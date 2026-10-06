import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/round/ping_schedule.dart';

/// Joker results of the current round, kept on this device so they can be
/// shown again any time – also after an app restart (R-PLAY-04).
class SavedJokers {
  const SavedJokers({required this.roundStart, this.hunters, this.players});

  /// Results belong to one round; another round start means "nothing saved".
  final DateTime roundStart;

  /// Hunter joker: the positions themselves – the hunters' live positions are
  /// readable only for 2 minutes after using it (security rules).
  final ({DateTime at, Map<String, LocationFix> positions})? hunters;

  /// Player joker: the request id – the answers stay readable for the asking
  /// player until the round ends.
  final ({DateTime at, String requestId})? players;

  SavedJokers copyWith({
    ({DateTime at, Map<String, LocationFix> positions})? hunters,
    ({DateTime at, String requestId})? players,
  }) => SavedJokers(
    roundStart: roundStart,
    hunters: hunters ?? this.hunters,
    players: players ?? this.players,
  );

  Map<String, Object?> toJson() => {
    'roundStart': roundStart.toUtc().toIso8601String(),
    if (hunters case final h?)
      'hunters': {
        'at': h.at.toUtc().toIso8601String(),
        'positions': {
          for (final e in h.positions.entries) e.key: e.value.toJson(),
        },
      },
    if (players case final p?)
      'players': {
        'at': p.at.toUtc().toIso8601String(),
        'requestId': p.requestId,
      },
  };

  factory SavedJokers.fromJson(Map<String, Object?> json) {
    final h = json['hunters'] as Map<String, Object?>?;
    final p = json['players'] as Map<String, Object?>?;
    return SavedJokers(
      roundStart: DateTime.parse(json['roundStart']! as String),
      hunters: h == null
          ? null
          : (
              at: DateTime.parse(h['at']! as String),
              positions: {
                for (final e
                    in (h['positions']! as Map<String, Object?>).entries)
                  e.key: LocationFix.fromJson(e.value! as Map<String, Object?>),
              },
            ),
      players: p == null
          ? null
          : (
              at: DateTime.parse(p['at']! as String),
              requestId: p['requestId']! as String,
            ),
    );
  }
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
