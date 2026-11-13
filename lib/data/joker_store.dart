import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/round/ping_schedule.dart';

/// One use of the hunter joker: when and where the hunters were (R-PLAY-02).
typedef HunterReveal = ({DateTime at, Map<String, LocationFix> positions});

/// Joker results and own ⚡ pings of the current round, kept on this device so
/// they can be shown again any time – also after an app restart (R-PLAY-04,
/// R-SPEED-09). Also whether the caught player accepted the live view
/// (R-GM-08).
class SavedJokers {
  const SavedJokers({
    required this.roundStart,
    this.hunters = const [],
    this.players,
    this.speedhuntPings = const {},
    this.liveViewAccepted = false,
  });

  /// Results belong to one round; another round start means "nothing saved".
  final DateTime roundStart;

  /// Hunter jokers, oldest first (several per round, R-SET-09): the positions
  /// themselves – the hunters' live positions are readable only for 2 minutes
  /// after using one (security rules).
  final List<HunterReveal> hunters;

  /// Player joker: the request id – the answers stay readable for the asking
  /// player until the round ends.
  final ({DateTime at, String requestId})? players;

  /// Own position at each speedhunt ping time, by slot id (R-SPEED-09).
  final Map<String, LocationFix> speedhuntPings;

  /// The caught player confirmed not to pass on what they see live
  /// (R-GM-08); asked once per round.
  final bool liveViewAccepted;

  SavedJokers copyWith({
    List<HunterReveal>? hunters,
    ({DateTime at, String requestId})? players,
    Map<String, LocationFix>? speedhuntPings,
    bool? liveViewAccepted,
  }) => SavedJokers(
    roundStart: roundStart,
    hunters: hunters ?? this.hunters,
    players: players ?? this.players,
    speedhuntPings: speedhuntPings ?? this.speedhuntPings,
    liveViewAccepted: liveViewAccepted ?? this.liveViewAccepted,
  );

  Map<String, Object?> toJson() => {
    'roundStart': roundStart.toUtc().toIso8601String(),
    if (hunters.isNotEmpty)
      'hunterReveals': [for (final h in hunters) _revealToJson(h)],
    if (players case final p?)
      'players': {
        'at': p.at.toUtc().toIso8601String(),
        'requestId': p.requestId,
      },
    if (speedhuntPings.isNotEmpty)
      'speedhuntPings': {
        for (final e in speedhuntPings.entries) e.key: e.value.toJson(),
      },
    if (liveViewAccepted) 'liveViewAccepted': true,
  };

  factory SavedJokers.fromJson(Map<String, Object?> json) {
    // Saved before several hunter jokers existed: a single one.
    final legacy = json['hunters'] as Map<String, Object?>?;
    final h = json['hunterReveals'] as List<Object?>? ?? [?legacy];
    final p = json['players'] as Map<String, Object?>?;
    final s = json['speedhuntPings'] as Map<String, Object?>? ?? const {};
    return SavedJokers(
      speedhuntPings: {
        for (final e in s.entries)
          e.key: LocationFix.fromJson(e.value! as Map<String, Object?>),
      },
      roundStart: DateTime.parse(json['roundStart']! as String),
      liveViewAccepted: json['liveViewAccepted'] as bool? ?? false,
      hunters: [for (final r in h) _revealFromJson(r! as Map<String, Object?>)],
      players: p == null
          ? null
          : (
              at: DateTime.parse(p['at']! as String),
              requestId: p['requestId']! as String,
            ),
    );
  }

  static Map<String, Object?> _revealToJson(HunterReveal r) => {
    'at': r.at.toUtc().toIso8601String(),
    'positions': {for (final e in r.positions.entries) e.key: e.value.toJson()},
  };

  static HunterReveal _revealFromJson(Map<String, Object?> json) => (
    at: DateTime.parse(json['at']! as String),
    positions: {
      for (final e in (json['positions']! as Map<String, Object?>).entries)
        e.key: LocationFix.fromJson(e.value! as Map<String, Object?>),
    },
  );
}

abstract interface class JokerStore {
  /// Saved results of the round that started at [roundStart], or null.
  Future<SavedJokers?> load(String groupId, DateTime roundStart);

  Future<void> save(String groupId, SavedJokers jokers);
}

/// In the OS keystore: hunter positions are sensitive.
class SecureJokerStore implements JokerStore {
  SecureJokerStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String groupId) => 'jokers_$groupId';

  @override
  Future<SavedJokers?> load(String groupId, DateTime roundStart) async {
    final raw = await _storage.read(key: _key(groupId));
    if (raw == null) return null;
    final saved = SavedJokers.fromJson(jsonDecode(raw) as Map<String, Object?>);
    return saved.roundStart.isAtSameMomentAs(roundStart) ? saved : null;
  }

  @override
  Future<void> save(String groupId, SavedJokers jokers) =>
      _storage.write(key: _key(groupId), value: jsonEncode(jokers.toJson()));
}

class MemoryJokerStore implements JokerStore {
  final _data = <String, String>{};

  @override
  Future<SavedJokers?> load(String groupId, DateTime roundStart) async {
    final raw = _data[groupId];
    if (raw == null) return null;
    final saved = SavedJokers.fromJson(jsonDecode(raw) as Map<String, Object?>);
    return saved.roundStart.isAtSameMomentAs(roundStart) ? saved : null;
  }

  @override
  Future<void> save(String groupId, SavedJokers jokers) async =>
      _data[groupId] = jsonEncode(jokers.toJson());
}
