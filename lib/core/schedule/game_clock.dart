import '../models/game_settings.dart';

enum GamePhase { notStarted, headStart, hunting, ended }

/// Deterministic timing of a running game, derived from [startAt] + [settings].
/// Every device computes the same schedule, so no server-side timer is needed.
class GameClock {
  const GameClock({required this.startAt, required this.settings});

  final DateTime startAt;
  final GameSettings settings;

  DateTime get huntersReleaseAt => startAt.add(settings.headStart);
  DateTime get endAt => startAt.add(settings.duration);

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
