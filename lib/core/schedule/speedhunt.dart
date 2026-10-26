import '../history/round_summary.dart';
import '../models/game_settings.dart';
import '../models/member.dart';
import 'game_clock.dart';

/// A speedhunt triggered by a hunter on one player (R-SPEED-02).
class Speedhunt {
  const Speedhunt({
    required this.targetId,
    required this.startedAt,
    required this.pings,
    required this.interval,
    this.firstDelay = Duration.zero,
    this.endedAt,
  });

  factory Speedhunt.fromSettings({
    required String targetId,
    required DateTime startedAt,
    required GameSettings settings,
  }) => Speedhunt(
    targetId: targetId,
    startedAt: startedAt,
    pings: settings.speedhuntPings,
    interval: settings.speedhuntInterval,
    firstDelay: settings.speedhuntFirstDelay,
  );

  final String targetId;
  final DateTime startedAt;
  final int pings;
  final Duration interval;

  /// Time from triggering to the first ping (R-SET-13). Frozen at trigger
  /// time, so all devices agree even if the settings change afterwards.
  final Duration firstDelay;

  /// Set when the target was caught during the speedhunt: it ends right then,
  /// without further pings (R-SPEED-10). Derived from the catch, never stored
  /// with the speedhunt.
  final DateTime? endedAt;

  Speedhunt endAt(DateTime at) => Speedhunt(
    targetId: targetId,
    startedAt: startedAt,
    pings: pings,
    interval: interval,
    firstDelay: firstDelay,
    endedAt: at,
  );

  /// First ping after [firstDelay] (default: immediately), then one every
  /// [interval] (R-SPEED-03). None from [endedAt] on (R-SPEED-10).
  List<DateTime> pingTimes() =>
      [for (var i = 0; i < pings; i++) startedAt.add(firstDelay + interval * i)]
          .where((t) => endedAt == null || t.isBefore(endedAt!))
          .toList();

  DateTime get endsAt {
    final planned = startedAt.add(firstDelay + interval * (pings - 1));
    final ended = endedAt;
    return ended != null && ended.isBefore(planned) ? ended : planned;
  }

  /// Active from trigger until the last ping has been sent or the target was
  /// caught (R-SPEED-10).
  bool isActiveAt(DateTime now) =>
      !now.isBefore(startedAt) &&
      !now.isAfter(endsAt) &&
      (endedAt == null || now.isBefore(endedAt!));

  Map<String, Object?> toJson() => {
    'targetId': targetId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'pings': pings,
    'intervalSec': interval.inSeconds,
    'firstDelaySec': firstDelay.inSeconds,
  };

  factory Speedhunt.fromJson(Map<String, Object?> json) => Speedhunt(
    targetId: json['targetId']! as String,
    startedAt: DateTime.parse(json['startedAt']! as String),
    pings: json['pings']! as int,
    interval: Duration(seconds: json['intervalSec']! as int),
    firstDelay: Duration(seconds: json['firstDelaySec'] as int? ?? 0),
  );
}

/// [all] with [Speedhunt.endedAt] set where a catch ended them (R-SPEED-10).
/// Only whoever reports a catch knows the target, so the catch names the
/// speedhunt it ends ([CatchRecord.endsSpeedhunt]).
List<Speedhunt> applyCatches(List<Speedhunt> all, List<CatchRecord> catches) {
  final endedAt = <DateTime, DateTime>{
    for (final c in catches)
      if (c.endsSpeedhunt case final start?) start.toUtc(): c.at,
  };
  return [
    for (final s in all)
      if (endedAt[s.startedAt.toUtc()] case final at?) s.endAt(at) else s,
  ];
}

/// Start of the speedhunt among [onTarget] (all on the caught player) that a
/// catch at [at] ends, or null if none is running then (R-SPEED-10).
DateTime? speedhuntEndedByCatch(List<Speedhunt> onTarget, DateTime at) {
  for (final s in onTarget) {
    if (s.isActiveAt(at)) return s.startedAt;
  }
  return null;
}

/// Speedhunts whose first ping is due by [now], oldest first. Players get one
/// chip each – at the same moment the hunters' chip appears, and the same for
/// every player, so it reveals no target (R-SPEED-09).
List<Speedhunt> speedhuntsWithFirstPing(List<Speedhunt> all, DateTime now) => [
  for (final s in all)
    if (s.pingTimes() case [final first, ...] when !first.isAfter(now)) s,
]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

/// Earliest time for the next speedhunt: not during the head start, not
/// before the configured minute after the round start (R-SET-11), nor within
/// the cooldown after the end of any previous one (R-SET-18). A catch ends a
/// speedhunt early, so [previous] should have [applyCatches] applied.
DateTime nextSpeedhuntAt(GameClock clock, List<Speedhunt> previous) {
  var at = clock.startAt.add(clock.settings.speedhuntEarliest);
  if (clock.huntersReleaseAt.isAfter(at)) at = clock.huntersReleaseAt;
  for (final s in previous) {
    final ready = s.endsAt.add(clock.settings.speedhuntCooldown);
    if (ready.isAfter(at)) at = ready;
  }
  return at;
}

/// Why a player cannot be the target of the next speedhunt (R-SET-19).
class TargetBlock {
  const TargetBlock({this.until});

  /// End of the per-player cooldown; null without repeats: the target of the
  /// last speedhunt is out until another player was targeted.
  final DateTime? until;
}

/// Whether [targetId] is blocked as the next speedhunt target (R-SET-19).
/// [previous] must carry the targets (hunters only). Without repeats the
/// target of the last speedhunt is blocked; with repeats a player is blocked
/// until [GameSettings.speedhuntRepeatCooldown] after the end of the last
/// speedhunt on them – even with other speedhunts in between.
TargetBlock? speedhuntTargetBlock({
  required GameSettings settings,
  required List<Speedhunt> previous,
  required String targetId,
  required DateTime now,
}) {
  if (previous.isEmpty) return null;
  if (!settings.speedhuntRepeatTarget) {
    final last = previous.reduce(
      (a, b) => b.startedAt.isAfter(a.startedAt) ? b : a,
    );
    return last.targetId == targetId ? const TargetBlock() : null;
  }
  DateTime? until;
  for (final s in previous) {
    if (s.targetId != targetId) continue;
    final end = s.endsAt.add(settings.speedhuntRepeatCooldown);
    if (until == null || end.isAfter(until)) until = end;
  }
  return until != null && until.isAfter(now) ? TargetBlock(until: until) : null;
}

enum SpeedhuntDenial {
  notHunting,
  tooEarly,
  coolingDown,
  noneLeft,
  alreadyRunning,
  invalidTarget,
  sameTarget,
  targetCoolingDown,
}

/// Checks whether a hunter may start a speedhunt on [target] right now.
/// Returns null if allowed. [targeted] are the previous speedhunts with their
/// targets, for the per-player rules (R-SET-19); empty skips those.
SpeedhuntDenial? canStartSpeedhunt({
  required GameClock clock,
  required DateTime now,
  required List<Speedhunt> previous,
  required Member target,
  List<Speedhunt> targeted = const [],
}) {
  // The head start counts as "not yet", with a countdown (R-SPEED-11).
  if (clock.phaseAt(now) case GamePhase.notStarted || GamePhase.ended) {
    return SpeedhuntDenial.notHunting;
  }
  if (previous.length >= clock.settings.speedhuntCount) {
    return SpeedhuntDenial.noneLeft;
  }
  if (previous.any((s) => s.isActiveAt(now))) {
    return SpeedhuntDenial.alreadyRunning;
  }
  // R-SET-11: not before the configured minute after the round start;
  // R-SET-18: not within the cooldown after the previous one.
  if (now.isBefore(nextSpeedhuntAt(clock, previous))) {
    return previous.isEmpty
        ? SpeedhuntDenial.tooEarly
        : SpeedhuntDenial.coolingDown;
  }
  if (!target.isPlayer || target.caught) return SpeedhuntDenial.invalidTarget;
  return switch (speedhuntTargetBlock(
    settings: clock.settings,
    previous: targeted,
    targetId: target.id,
    now: now,
  )) {
    null => null,
    TargetBlock(until: null) => SpeedhuntDenial.sameTarget,
    TargetBlock() => SpeedhuntDenial.targetCoolingDown,
  };
}
