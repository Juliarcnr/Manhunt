import '../models/game_settings.dart';

enum GamePhase { notStarted, headStart, hunting, ended }

/// Deterministic timing of a running game, derived from [startAt] + [settings].
/// Every device computes the same schedule, so no server-side timer is needed.
class GameClock {
  const GameClock({
    required this.startAt,
    required this.settings,
    this.finishedAt,
    this.confirmedAt,
  });

  final DateTime startAt;
  final GameSettings settings;

  /// When the last player was caught and the hunters won (R-GAME-08); the
  /// round then counts as over as if the time were up.
  final DateTime? finishedAt;

  /// When someone still in the game confirmed, after the time was up, who
  /// else was caught (R-GAME-11). Only then is the result known.
  final DateTime? confirmedAt;

  /// Nobody confirmed for this long after the time was up: it counts as
  /// "nobody else was caught" (R-GAME-11).
  static const confirmTimeout = Duration(minutes: 10);

  /// Grace time after the round is over (time up or the hunters won) before
  /// a device ends it automatically (R-GAME-10): late pings and hunter
  /// positions still arrive (the end-of-game pings within seconds), then the
  /// round is saved to the history. 15 s is enough for that (2026-11-02).
  static const autoEndDelay = Duration(seconds: 15);

  DateTime get huntersReleaseAt => startAt.add(settings.headStart);

  /// End of the configured duration (R-GAME-01).
  DateTime get plannedEndAt => startAt.add(settings.duration);

  /// Actual end: the planned one, or earlier if the hunters won (R-GAME-08).
  DateTime get endAt => huntersWon ? finishedAt! : plannedEndAt;

  /// The time is up and someone confirmed this round who else was caught
  /// (R-GAME-11). A mark from before the end is a leftover of an earlier
  /// round and is ignored.
  bool get timeUpConfirmed =>
      !huntersWon &&
      confirmedAt != null &&
      !confirmedAt!.isBefore(plannedEndAt);

  /// From then on the result is known (R-GAME-09, R-GAME-11): the hunters'
  /// win, the confirmation after the time was up, or [confirmTimeout] after
  /// it without one.
  DateTime get decidedAt => huntersWon
      ? finishedAt!
      : timeUpConfirmed
      ? confirmedAt!
      : plannedEndAt.add(confirmTimeout);

  /// The time is up, but nobody has confirmed yet who else was caught
  /// (R-GAME-11).
  bool awaitingConfirmation(DateTime now) =>
      phaseAt(now) == GamePhase.ended && now.isBefore(decidedAt);

  /// From then on any device ends the round as if the host had (R-GAME-10).
  DateTime get autoEndAt => decidedAt.add(autoEndDelay);

  /// The hunters caught everyone before the time was up (R-GAME-08). A mark
  /// from before the start is a leftover of an earlier round (ended by an
  /// older app version that did not clear it) and is ignored.
  bool get huntersWon =>
      finishedAt != null &&
      !finishedAt!.isBefore(startAt) &&
      finishedAt!.isBefore(plannedEndAt);

  GamePhase phaseAt(DateTime now) {
    if (now.isBefore(startAt)) return GamePhase.notStarted;
    if (!now.isBefore(endAt)) return GamePhase.ended;
    if (now.isBefore(huntersReleaseAt)) return GamePhase.headStart;
    return GamePhase.hunting;
  }

  /// Regular ping times: every [GameSettings.pingInterval] after start,
  /// strictly before the end (R-PING-02).
  List<DateTime> regularPingTimes() {
    final times = <DateTime>[];
    for (
      var t = startAt.add(settings.pingInterval);
      t.isBefore(endAt);
      t = t.add(settings.pingInterval)
    ) {
      times.add(t);
    }
    return times;
  }

  /// First regular ping strictly after [now], or null if none is left.
  DateTime? nextRegularPing(DateTime now) {
    for (final t in regularPingTimes()) {
      if (t.isAfter(now)) return t;
    }
    return null;
  }
}

/// "mm:ss", or "h:mm:ss" from one hour on; negative counts as zero.
String formatCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = two(d.inMinutes % 60);
  final s = two(d.inSeconds % 60);
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
