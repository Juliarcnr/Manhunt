import 'geo_point.dart';

/// All configurable rules of a game (R-SET-02 … R-SET-06, R-SET-09, R-SET-11,
/// R-SET-12, R-SET-13, R-SET-15, R-SET-16, R-SET-17, R-SET-18, R-SET-19,
/// R-SET-21, R-BOT-02, R-BOT-09).
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
    this.speedhuntCooldown = const Duration(minutes: 30),
    this.speedhuntRepeatTarget = true,
    this.speedhuntRepeatCooldown = const Duration(minutes: 30),
    this.hunterJokers = 1,
    this.playerJokerEnabled = true,
    this.sharedPings = false,
    this.anonymousPlayers = true,
    this.outsideLiveLocation = true,
    this.botCount = 0,
    this.area = const [],
    this.startTime,
    this.skipCountdown = false,
  });

  static const _keep = Object();

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

  /// Pause after the end of a speedhunt before the next one (R-SET-18).
  final Duration speedhuntCooldown;

  /// Whether two speedhunts in a row may target the same player (R-SET-19).
  final bool speedhuntRepeatTarget;

  /// With [speedhuntRepeatTarget]: pause after the end of a speedhunt on a
  /// player before the next one on them; never below [speedhuntCooldown]
  /// (R-SET-19).
  final Duration speedhuntRepeatCooldown;

  /// Joker "hunter positions": how often each player may see the hunters
  /// per round; 0 = no such joker (R-PLAY-02, R-SET-09).
  final int hunterJokers;

  /// Upper limit offered in the settings (R-SET-09).
  static const maxHunterJokers = 5;

  bool get jokerEnabled => hunterJokers > 0;

  /// Joker "player positions": each player may see all other players once
  /// (R-PLAY-03, R-SET-12).
  final bool playerJokerEnabled;

  /// Regular pings go to all players, not only to the hunters (R-SET-15).
  /// Replaces the joker "player positions".
  final bool sharedPings;

  /// Hunters see "Player 1 … n" instead of the players' names until the time
  /// is up (R-SET-16, R-ANON-01).
  final bool anonymousPlayers;

  /// Hunters see the live location of a player who left the play area
  /// (R-SET-17, R-OUT-01).
  final bool outsideLiveLocation;

  /// Computer members for testing with few phones (R-BOT-02); only offered
  /// in debug builds. Older groups had hunters and players separately.
  final int botCount;

  /// Time of day (since midnight, local) of the official start; null = a
  /// short countdown from pressing "start" (R-SET-21, R-START-01).
  final Duration? startTime;

  /// Testing only: the round starts right away, without a countdown and
  /// regardless of [startTime] (R-BOT-09).
  final bool skipCountdown;

  /// The joker "player positions" is only offered without [sharedPings].
  bool get playerJokerAvailable => playerJokerEnabled && !sharedPings;

  /// Polygon of the play area; empty until drawn.
  final List<GeoPoint> area;

  /// Human-readable problems; empty when the settings are playable.
  List<SettingsError> validate() {
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
    if (speedhuntCooldown < Duration.zero) {
      errors.add(SettingsError.speedhuntCountInvalid);
    }
    if (speedhuntRepeatTarget && speedhuntRepeatCooldown < speedhuntCooldown) {
      errors.add(SettingsError.speedhuntRepeatCooldownTooShort);
    }
    if (speedhuntPings < 1) errors.add(SettingsError.speedhuntPingsInvalid);
    if (speedhuntInterval < const Duration(minutes: 1)) {
      errors.add(SettingsError.speedhuntIntervalTooShort);
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
    Duration? speedhuntCooldown,
    bool? speedhuntRepeatTarget,
    Duration? speedhuntRepeatCooldown,
    int? hunterJokers,
    bool? playerJokerEnabled,
    bool? sharedPings,
    bool? anonymousPlayers,
    bool? outsideLiveLocation,
    int? botCount,
    List<GeoPoint>? area,
    Object? startTime = _keep,
    bool? skipCountdown,
  }) => GameSettings(
    duration: duration ?? this.duration,
    headStart: headStart ?? this.headStart,
    pingInterval: pingInterval ?? this.pingInterval,
    speedhuntCount: speedhuntCount ?? this.speedhuntCount,
    speedhuntPings: speedhuntPings ?? this.speedhuntPings,
    speedhuntInterval: speedhuntInterval ?? this.speedhuntInterval,
    speedhuntEarliest: speedhuntEarliest ?? this.speedhuntEarliest,
    speedhuntFirstDelay: speedhuntFirstDelay ?? this.speedhuntFirstDelay,
    speedhuntCooldown: speedhuntCooldown ?? this.speedhuntCooldown,
    speedhuntRepeatTarget: speedhuntRepeatTarget ?? this.speedhuntRepeatTarget,
    speedhuntRepeatCooldown:
        speedhuntRepeatCooldown ?? this.speedhuntRepeatCooldown,
    hunterJokers: hunterJokers ?? this.hunterJokers,
    playerJokerEnabled: playerJokerEnabled ?? this.playerJokerEnabled,
    sharedPings: sharedPings ?? this.sharedPings,
    anonymousPlayers: anonymousPlayers ?? this.anonymousPlayers,
    outsideLiveLocation: outsideLiveLocation ?? this.outsideLiveLocation,
    botCount: botCount ?? this.botCount,
    area: area ?? this.area,
    // Pass null to clear it.
    startTime: identical(startTime, _keep)
        ? this.startTime
        : startTime as Duration?,
    skipCountdown: skipCountdown ?? this.skipCountdown,
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
    'speedhuntCooldownSec': speedhuntCooldown.inSeconds,
    'speedhuntRepeatTarget': speedhuntRepeatTarget,
    'speedhuntRepeatCooldownSec': speedhuntRepeatCooldown.inSeconds,
    // The roles are set in the lobby now (R-LOBBY-04); older app versions
    // still require the key when reading the settings.
    'hunterCount': 1,
    'hunterJokers': hunterJokers,
    // Older app versions only know the switch.
    'jokerEnabled': jokerEnabled,
    'playerJokerEnabled': playerJokerEnabled,
    'sharedPings': sharedPings,
    'anonymousPlayers': anonymousPlayers,
    'outsideLiveLocation': outsideLiveLocation,
    'botCount': botCount,
    'area': [for (final p in area) p.toJson()],
    'startTimeMin': startTime?.inMinutes,
    'skipCountdown': skipCountdown,
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
    speedhuntCooldown: Duration(
      seconds: json['speedhuntCooldownSec'] as int? ?? 1800,
    ),
    speedhuntRepeatTarget: json['speedhuntRepeatTarget'] as bool? ?? true,
    speedhuntRepeatCooldown: Duration(
      seconds: json['speedhuntRepeatCooldownSec'] as int? ?? 1800,
    ),
    hunterJokers:
        json['hunterJokers'] as int? ??
        (json['jokerEnabled'] as bool? ?? true ? 1 : 0),
    playerJokerEnabled: json['playerJokerEnabled'] as bool? ?? true,
    sharedPings: json['sharedPings'] as bool? ?? false,
    anonymousPlayers: json['anonymousPlayers'] as bool? ?? true,
    outsideLiveLocation: json['outsideLiveLocation'] as bool? ?? true,
    botCount:
        json['botCount'] as int? ??
        (json['botHunters'] as int? ?? 0) + (json['botPlayers'] as int? ?? 0),
    area: [
      for (final p in json['area']! as List<Object?>)
        GeoPoint.fromJson(p! as Map<String, Object?>),
    ],
    startTime: switch (json['startTimeMin'] as int?) {
      final min? => Duration(minutes: min),
      null => null,
    },
    skipCountdown: json['skipCountdown'] as bool? ?? false,
  );
}

enum SettingsError {
  durationTooShort,
  headStartInvalid,
  pingIntervalTooShort,
  speedhuntCountInvalid,
  speedhuntPingsInvalid,
  speedhuntIntervalTooShort,
  speedhuntRepeatCooldownTooShort,
  areaMissing,
}
