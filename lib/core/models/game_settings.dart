import 'geo_point.dart';

/// All configurable rules of a game (R-SET-02 … R-SET-07, R-SET-09, R-SET-11,
/// R-SET-12, R-SET-13, R-SET-15).
class GameSettings {
  const GameSettings({
    this.duration = const Duration(hours: 3),
    this.headStart = const Duration(minutes: 15),
    this.pingInterval = const Duration(minutes: 20),
    this.speedhuntCount = 2,
    this.speedhuntPings = 3,
    this.speedhuntInterval = const Duration(minutes: 5),
    this.speedhuntEarliest = const Duration(minutes: 60),
    this.speedhuntFirstDelay = Duration.zero,
    this.hunterCount = 1,
    this.jokerEnabled = true,
    this.playerJokerEnabled = true,
    this.sharedPings = false,
    this.area = const [],
  });

  final Duration duration;
  final Duration headStart;
  final Duration pingInterval;
  final int speedhuntCount;
  final int speedhuntPings;
  final Duration speedhuntInterval;

  /// Earliest time after the round start for the first speedhunt (R-SET-11).
  final Duration speedhuntEarliest;

  /// Delay between triggering a speedhunt and its first ping (R-SET-13).
  final Duration speedhuntFirstDelay;
  final int hunterCount;

  /// Joker "hunter positions": each player may see the hunters once
  /// (R-PLAY-02, R-SET-09).
  final bool jokerEnabled;

  /// Joker "player positions": each player may see all other players once
  /// (R-PLAY-03, R-SET-12).
  final bool playerJokerEnabled;

  /// Regular pings go to all players, not only to the hunters (R-SET-15).
  /// Replaces the joker "player positions".
  final bool sharedPings;

  /// The joker "player positions" is only offered without [sharedPings].
  bool get playerJokerAvailable => playerJokerEnabled && !sharedPings;

  /// Polygon of the play area; empty until drawn.
  final List<GeoPoint> area;

  /// Human-readable problems; empty when the settings are playable.
  List<SettingsError> validate({int? memberCount}) {
    final errors = <SettingsError>[];
    if (duration <= Duration.zero) errors.add(SettingsError.durationTooShort);
    if (headStart < Duration.zero || headStart >= duration) {
      errors.add(SettingsError.headStartInvalid);
    }
    if (pingInterval < const Duration(minutes: 1)) {
      errors.add(SettingsError.pingIntervalTooShort);
    }
    if (speedhuntCount < 0) errors.add(SettingsError.speedhuntCountInvalid);
    if (speedhuntEarliest < Duration.zero ||
        speedhuntFirstDelay < Duration.zero) {
      errors.add(SettingsError.speedhuntCountInvalid);
    }
    if (speedhuntPings < 1) errors.add(SettingsError.speedhuntPingsInvalid);
    if (speedhuntInterval < const Duration(minutes: 1)) {
      errors.add(SettingsError.speedhuntIntervalTooShort);
    }
    if (hunterCount < 1) errors.add(SettingsError.hunterCountInvalid);
    if (memberCount != null && hunterCount >= memberCount) {
      errors.add(SettingsError.notEnoughPlayers);
    }
    if (area.length < 3) errors.add(SettingsError.areaMissing);
    return errors;
  }

  GameSettings copyWith({
    Duration? duration,
    Duration? headStart,
    Duration? pingInterval,
    int? speedhuntCount,
    int? speedhuntPings,
    Duration? speedhuntInterval,
    Duration? speedhuntEarliest,
    Duration? speedhuntFirstDelay,
    int? hunterCount,
    bool? jokerEnabled,
    bool? playerJokerEnabled,
    bool? sharedPings,
    List<GeoPoint>? area,
  }) => GameSettings(
    duration: duration ?? this.duration,
    headStart: headStart ?? this.headStart,
    pingInterval: pingInterval ?? this.pingInterval,
    speedhuntCount: speedhuntCount ?? this.speedhuntCount,
    speedhuntPings: speedhuntPings ?? this.speedhuntPings,
    speedhuntInterval: speedhuntInterval ?? this.speedhuntInterval,
    speedhuntEarliest: speedhuntEarliest ?? this.speedhuntEarliest,
    speedhuntFirstDelay: speedhuntFirstDelay ?? this.speedhuntFirstDelay,
    hunterCount: hunterCount ?? this.hunterCount,
    jokerEnabled: jokerEnabled ?? this.jokerEnabled,
    playerJokerEnabled: playerJokerEnabled ?? this.playerJokerEnabled,
    sharedPings: sharedPings ?? this.sharedPings,
    area: area ?? this.area,
  );

  Map<String, Object?> toJson() => {
    'durationSec': duration.inSeconds,
    'headStartSec': headStart.inSeconds,
    'pingIntervalSec': pingInterval.inSeconds,
    'speedhuntCount': speedhuntCount,
    'speedhuntPings': speedhuntPings,
    'speedhuntIntervalSec': speedhuntInterval.inSeconds,
    'speedhuntEarliestSec': speedhuntEarliest.inSeconds,
    'speedhuntFirstDelaySec': speedhuntFirstDelay.inSeconds,
    'hunterCount': hunterCount,
    'jokerEnabled': jokerEnabled,
    'playerJokerEnabled': playerJokerEnabled,
    'sharedPings': sharedPings,
    'area': [for (final p in area) p.toJson()],
  };

  factory GameSettings.fromJson(Map<String, Object?> json) => GameSettings(
    duration: Duration(seconds: json['durationSec']! as int),
    headStart: Duration(seconds: json['headStartSec']! as int),
    pingInterval: Duration(seconds: json['pingIntervalSec']! as int),
    speedhuntCount: json['speedhuntCount']! as int,
    speedhuntPings: json['speedhuntPings']! as int,
    speedhuntInterval: Duration(seconds: json['speedhuntIntervalSec']! as int),
    speedhuntEarliest: Duration(
      seconds: json['speedhuntEarliestSec'] as int? ?? 3600,
    ),
    speedhuntFirstDelay: Duration(
      seconds: json['speedhuntFirstDelaySec'] as int? ?? 0,
    ),
    hunterCount: json['hunterCount']! as int,
    jokerEnabled: json['jokerEnabled'] as bool? ?? true,
    playerJokerEnabled: json['playerJokerEnabled'] as bool? ?? true,
    sharedPings: json['sharedPings'] as bool? ?? false,
    area: [
      for (final p in json['area']! as List<Object?>)
        GeoPoint.fromJson(p! as Map<String, Object?>),
    ],
  );
}

enum SettingsError {
  durationTooShort,
  headStartInvalid,
  pingIntervalTooShort,
  speedhuntCountInvalid,
  speedhuntPingsInvalid,
  speedhuntIntervalTooShort,
  hunterCountInvalid,
  notEnoughPlayers,
  areaMissing,
}
