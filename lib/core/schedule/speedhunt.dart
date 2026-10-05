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
  );

  final String targetId;
  final DateTime startedAt;
  final int pings;
  final Duration interval;

  /// The first ping fires immediately, then one every [interval] (R-SPEED-03).
  List<DateTime> pingTimes() => [
    for (var i = 0; i < pings; i++) startedAt.add(interval * i),
  ];

  DateTime get endsAt => startedAt.add(interval * (pings - 1));

  /// Active from trigger until the last ping has been sent.
  bool isActiveAt(DateTime now) =>
      !now.isBefore(startedAt) && !now.isAfter(endsAt);

  Map<String, Object?> toJson() => {
    'targetId': targetId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'pings': pings,
    'intervalSec': interval.inSeconds,
  };

  factory Speedhunt.fromJson(Map<String, Object?> json) => Speedhunt(
    targetId: json['targetId']! as String,
    startedAt: DateTime.parse(json['startedAt']! as String),
    pings: json['pings']! as int,
    interval: Duration(seconds: json['intervalSec']! as int),
  );
}

enum SpeedhuntDenial {
  notHunting,
  tooEarly,
  noneLeft,
  alreadyRunning,
  invalidTarget,
}

/// Checks whether a hunter may start a speedhunt on [target] right now.
/// Returns null if allowed.
SpeedhuntDenial? canStartSpeedhunt({
  required GameClock clock,
  required DateTime now,
  required List<Speedhunt> previous,
  required Member target,
}) {
  if (clock.phaseAt(now) != GamePhase.hunting) {
    return SpeedhuntDenial.notHunting;
  }
  // R-SET-11: not before the configured minute after the round start.
  if (now.isBefore(clock.startAt.add(clock.settings.speedhuntEarliest))) {
    return SpeedhuntDenial.tooEarly;
  }
  if (previous.length >= clock.settings.speedhuntCount) {
    return SpeedhuntDenial.noneLeft;
  }
  if (previous.any((s) => s.isActiveAt(now))) {
    return SpeedhuntDenial.alreadyRunning;
  }
  if (!target.isPlayer || target.caught) return SpeedhuntDenial.invalidTarget;
  return null;
}
