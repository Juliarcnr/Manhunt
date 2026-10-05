import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/group_crypto.dart';
import '../core/join_code.dart';
import '../core/models/game_settings.dart';
import '../data/game_repository.dart';
import 'providers.dart';

class InvalidCodeException implements Exception {
  const InvalidCodeException();
}

/// The group this device currently belongs to, or null (R-LOBBY-01 … 03).
class SessionController extends AsyncNotifier<GroupSession?> {
  @override
  Future<GroupSession?> build() async {
    final code = await ref.read(sessionStoreProvider).loadCode();
    if (code == null) return null;
    final session = await _open(code);
    // Housekeeping without a server (R-PRIV-05): opening the group extends its
    // lifetime; whoever opens it after 180 days of silence deletes it.
    try {
      if (!await ref.read(gameRepositoryProvider).checkIn(session)) {
        await ref.read(sessionStoreProvider).clear();
        return null;
      }
    } on Exception {
      // Offline etc.: keep the session; the gate shows the group as usual.
    }
    return session;
  }

  Future<GroupSession> _open(String code) async {
    final userId = await ref.read(userIdProvider)();
    final crypto = await ref.read(cryptoFactoryProvider)(code);
    return GroupSession(code: code, crypto: crypto, userId: userId);
  }

  Future<void> create({
    required String name,
    required GameSettings settings,
  }) async {
    final session = await _open(JoinCode.generate());
    await ref
        .read(gameRepositoryProvider)
        .createGame(session, name: name, settings: settings);
    await ref.read(sessionStoreProvider).saveCode(session.code);
    state = AsyncData(session);
  }

  /// Throws [InvalidCodeException] or [GroupNotFoundException].
  Future<void> join({required String code, required String name}) async {
    final normalized = JoinCode.normalize(code);
    if (normalized == null) throw const InvalidCodeException();
    final session = await _open(normalized);
    await ref.read(gameRepositoryProvider).joinGame(session, name: name);
    await ref.read(sessionStoreProvider).saveCode(session.code);
    state = AsyncData(session);
  }

  /// Leaves the group on this device and removes the own member entry.
  Future<void> leave() async {
    final session = state.value;
    if (session != null) {
      try {
        await ref
            .read(gameRepositoryProvider)
            .removeMember(session, session.userId);
      } on Exception {
        // Group may already be gone; leaving locally is what matters.
      }
    }
    await _forget();
  }

  /// Admin only: deletes the whole group for everyone (R-PRIV-03).
  Future<void> deleteGroup() async {
    final session = state.value;
    if (session != null) {
      await ref.read(gameRepositoryProvider).deleteGame(session);
    }
    await _forget();
  }

  /// Drops the local session, e.g. when the group was deleted by the admin.
  Future<void> forget() => _forget();

  Future<void> _forget() async {
    await ref.read(sessionStoreProvider).clear();
    state = const AsyncData(null);
  }
}

typedef CryptoFactory = Future<GroupCrypto> Function(String code);
