import '../models/game_settings.dart';

enum GamePhase { notStarted, headStart, hunting, ended }

/// Deterministic timing of a running game, derived from [startAt] + [settings].
/// Every device computes the same schedule, so no server-side timer is needed.
class GameClock {
  const GameClock({
    required this.startAt,
    required this.settings,
    this.finishedAt,
  });

  final DateTime startAt;
  final GameSettings settings;

  /// When the last player was caught and the hunters won (R-GAME-08); the
  /// round then counts as over as if the time were up.
  final DateTime? finishedAt;

  /// How long a round stays open for looking at the locations once it is
  /// over, if the host does not end it (R-GAME-10).
  static const autoEndDelay = Duration(hours: 3);

  DateTime get huntersReleaseAt => startAt.add(settings.headStart);

  /// End of the configured duration (R-GAME-01).
  DateTime get plannedEndAt => startAt.add(settings.duration);

  /// Actual end: the planned one, or earlier if the hunters won (R-GAME-08).
  DateTime get endAt => huntersWon ? finishedAt! : plannedEndAt;

  /// From then on any device ends the round as if the host had (R-GAME-10).
  DateTime get autoEndAt => endAt.add(autoEndDelay);

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
