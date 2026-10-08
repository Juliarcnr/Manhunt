import '../geo/polygon.dart';
import '../models/geo_point.dart';
import 'ping_schedule.dart';

/// Leaving the play area (R-OUT-01 … R-OUT-05). GPS scatters by 20–30 m and
/// sometimes jumps much further, and a wrongly shared live location would
/// spoil the game – so a player only counts as outside when it is certain.

/// A position counts as outside only this far beyond the edge, plus
/// [accuracyFactor] times its own reported inaccuracy (R-OUT-02).
const outsideBufferM = 30.0;

/// The reported accuracy is a 68 % radius (Android; iOS similar) and too
/// optimistic next to buildings – doubled, it is about a 95 % radius.
const accuracyFactor = 2.0;

/// Positions less accurate than this (or without accuracy) never count as
/// outside (R-OUT-02).
const maxOutsideAccuracyM = 30.0;

/// How long a player must be clearly outside, without interruption, before
/// the hunters see the live location (R-OUT-03).
const outsideGrace = Duration(seconds: 30);

/// At least this many clearly-outside positions during [outsideGrace].
const minOutsideFixes = 5;

/// Without a position for this long, a warning is dropped: "continuously
/// outside" can no longer be confirmed.
const maxOutsideFixGap = Duration(seconds: 15);

/// The hunters still see the live location this long after the player is
/// back inside (R-OUT-04).
const outsideAfterglow = Duration(seconds: 60);

enum FixSide {
  /// Inside the play area.
  inside,

  /// Certainly outside: beyond the edge by the buffer plus twice the
  /// inaccuracy.
  outside,

  /// Just outside, or too inaccurate to tell – changes nothing.
  unclear,
}

FixSide classifyFix(LocationFix fix, List<GeoPoint> area) {
  final distance = distanceOutsideM(fix.point, area);
  if (distance == null) return FixSide.unclear;
  if (distance <= 0) return FixSide.inside;
  final accuracy = fix.accuracyM;
  if (accuracy == null || accuracy > maxOutsideAccuracyM) {
    return FixSide.unclear;
  }
  return distance >= outsideThresholdM(accuracy)
      ? FixSide.outside
      : FixSide.unclear;
}

/// How far beyond the edge a position with [accuracyM] must be to count as
/// outside (R-OUT-02).
double outsideThresholdM(double accuracyM) =>
    outsideBufferM + accuracyFactor * accuracyM;

/// One position for the debug log, to calibrate the thresholds in the field:
/// "48 m out, ±9 m, needs 48 m" (R-OUT-07).
String describeFix(LocationFix fix, List<GeoPoint> area) {
  final distance = distanceOutsideM(fix.point, area);
  if (distance == null) return 'no area';
  final where = distance <= 0
      ? '${(-distance).round()} m in'
      : '${distance.round()} m out';
  final accuracy = fix.accuracyM;
  if (accuracy == null) return '$where, accuracy unknown';
  return '$where, ±${accuracy.round()} m, '
      'needs ${outsideThresholdM(accuracy).round()} m';
}

enum BoundaryPhase {
  /// Nothing to do (also: inside, or too unclear to say).
  inside,

  /// Clearly outside, but not long enough yet: only the player is warned.
  warning,

  /// The hunters see the live location.
  live,

  /// Back inside; the hunters still see the location until
  /// [BoundaryState.afterglowUntil].
  afterglow,
}

/// Where this player stands relative to the play area. Lives on the device;
/// only [BoundaryPhase.live] and [BoundaryPhase.afterglow] share anything.
class BoundaryState {
  const BoundaryState({
    this.phase = BoundaryPhase.inside,
    this.outsideSince,
    this.outsideFixes = 0,
    this.lastFixAt,
    this.afterglowUntil,
  });

  final BoundaryPhase phase;

  /// First clearly-outside position of the current warning.
  final DateTime? outsideSince;
  final int outsideFixes;
  final DateTime? lastFixAt;
  final DateTime? afterglowUntil;

  /// Whether the hunters see the live location right now.
  bool get sharing =>
      phase == BoundaryPhase.live || phase == BoundaryPhase.afterglow;

  /// During a warning: when the live location starts if nothing changes.
  DateTime? get liveAt =>
      phase == BoundaryPhase.warning ? outsideSince?.add(outsideGrace) : null;

  @override
  bool operator ==(Object other) =>
      other is BoundaryState &&
      other.phase == phase &&
      other.outsideSince == outsideSince &&
      other.outsideFixes == outsideFixes &&
      other.lastFixAt == lastFixAt &&
      other.afterglowUntil == afterglowUntil;

  @override
  int get hashCode =>
      Object.hash(phase, outsideSince, outsideFixes, lastFixAt, afterglowUntil);

  @override
  String toString() => 'BoundaryState(${phase.name})';
}

/// Next state after a new position [fix] (received at [now]) or, without
/// [fix], after time passed. Times are the device clock at arrival, not the
/// GPS timestamps.
BoundaryState boundaryStep(
  BoundaryState state, {
  required List<GeoPoint> area,
  required DateTime now,
  LocationFix? fix,
}) {
  if (area.length < 3) return const BoundaryState();
  var s = state;
  // Time passing alone.
  switch (s.phase) {
    case BoundaryPhase.warning:
      final last = s.lastFixAt;
      if (last == null || now.difference(last) > maxOutsideFixGap) {
        s = const BoundaryState();
      }
    case BoundaryPhase.afterglow:
      if (!now.isBefore(s.afterglowUntil!)) s = const BoundaryState();
    case BoundaryPhase.inside:
    case BoundaryPhase.live:
      break;
  }
  if (fix == null) return s;

  final side = classifyFix(fix, area);
  switch (s.phase) {
    case BoundaryPhase.inside:
      return side == FixSide.outside
          ? BoundaryState(
              phase: BoundaryPhase.warning,
              outsideSince: now,
              outsideFixes: 1,
              lastFixAt: now,
            )
          : s;
    case BoundaryPhase.warning:
      // Anything but a clearly-outside position ends the warning: a single
      // doubtful position is enough to not share anything.
      if (side != FixSide.outside) return const BoundaryState();
      final fixes = s.outsideFixes + 1;
      final since = s.outsideSince!;
      if (now.difference(since) >= outsideGrace && fixes >= minOutsideFixes) {
        return BoundaryState(phase: BoundaryPhase.live, lastFixAt: now);
      }
      return BoundaryState(
        phase: BoundaryPhase.warning,
        outsideSince: since,
        outsideFixes: fixes,
        lastFixAt: now,
      );
    case BoundaryPhase.live:
      return side == FixSide.inside
          ? BoundaryState(
              phase: BoundaryPhase.afterglow,
              lastFixAt: now,
              afterglowUntil: now.add(outsideAfterglow),
            )
          : BoundaryState(phase: BoundaryPhase.live, lastFixAt: now);
    case BoundaryPhase.afterglow:
      return side == FixSide.outside
          ? BoundaryState(phase: BoundaryPhase.live, lastFixAt: now)
          : BoundaryState(
              phase: BoundaryPhase.afterglow,
              lastFixAt: now,
              afterglowUntil: s.afterglowUntil,
            );
  }
}

/// Leaving the play area, as announced to the player (R-OUT-06).
enum BoundaryEvent {
  /// Clearly outside: back within [outsideGrace], or the hunters see you.
  warning,

  /// The hunters see the live location now.
  live,

  /// The live location is no longer shared.
  ended,
}
