import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/group_crypto.dart';
import '../core/groups/group_list.dart';
import '../core/join_code.dart';
import '../core/models/game_settings.dart';
import '../data/game_repository.dart';
import 'providers.dart';

class InvalidCodeException implements Exception {
  const InvalidCodeException();
}

/// The group currently open on this device, or null = group overview
/// (R-LOBBY-01 … 03, R-GROUPS-01 … 03). The device may belong to up to
/// [GroupList.maxGroups] groups; they are listed by [groupListProvider].
class SessionController extends AsyncNotifier<GroupSession?> {
  @override
  Future<GroupSession?> build() async {
    final code = await ref.read(sessionStoreProvider).loadActive();
    if (code == null) return null;
    return _activate(code);
  }

  /// Opens [code], extending its lifetime. Returns null (and forgets the
  /// group) if it expired.
  Future<GroupSession?> _activate(String code) async {
    final session = await _open(code);
    // Housekeeping without a server (R-PRIV-05): opening the group extends its
    // lifetime; whoever opens it after 180 days of silence deletes it.
    try {
      if (!await ref.read(gameRepositoryProvider).checkIn(session)) {
        await _remove(code, notify: false);
        return null;
      }
    } on Exception {
      // Offline etc.: keep the session; the gate shows the group as usual.
    }
    await _updateGroups(
      (g) => g.update(code, groupId: session.groupId),
      notify: false,
    );
    await ref.read(sessionStoreProvider).saveActive(code);
    return session;
  }

  Future<GroupSession> _open(String code) async {
    final userId = await ref.read(userIdProvider)();
    final crypto = await ref.read(cryptoFactoryProvider)(code);
    return GroupSession(code: code, crypto: crypto, userId: userId);
  }

  /// Saves a change to the group list and reloads [groupListProvider] – unless
  /// [notify] is false: other providers must not be touched during [build].
  Future<void> _updateGroups(
    GroupList Function(GroupList) change, {
    bool notify = true,
  }) async {
    final store = ref.read(sessionStoreProvider);
    await store.saveGroups(change(await store.loadGroups()));
    if (notify) ref.invalidate(groupListProvider);
  }

  /// Throws [GroupLimitException] if this device has no room for one more.
  Future<void> _checkRoom(String? code) async {
    final groups = await ref.read(sessionStoreProvider).loadGroups();
    if (groups.isFull && (code == null || groups.find(code) == null)) {
      throw const GroupLimitException();
    }
  }

  /// Opens one of this device's groups from the overview (R-GROUPS-03).
  /// Returns false (and forgets it) if the group no longer exists.
  Future<bool> select(String code) async {
    final session = await _activate(code);
    ref.invalidate(groupListProvider);
    if (session == null) return false;
    state = AsyncData(session);
    return true;
  }

  /// Back to the group overview; the group stays in the list (R-GROUPS-03).
  Future<void> close() async {
    await ref.read(sessionStoreProvider).saveActive(null);
    state = const AsyncData(null);
  }

  /// Throws [GroupLimitException] (R-GROUPS-02).
  Future<void> create({
    required String name,
    required String groupName,
    required GameSettings settings,
  }) async {
    await _checkRoom(null);
    final session = await _open(JoinCode.generate());
    await ref
        .read(gameRepositoryProvider)
        .createGame(
          session,
          name: name,
          settings: settings,
          groupName: groupName,
        );
    await _remember(
      SavedGroup(
        code: session.code,
        groupId: session.groupId,
        name: groupName,
        isHost: true,
      ),
    );
    state = AsyncData(session);
  }

  /// Throws [InvalidCodeException], [GroupLimitException] or
  /// [GroupNotFoundException]. Joining a known group again only renames.
  Future<void> join({required String code, required String name}) async {
    final normalized = JoinCode.normalize(code);
    if (normalized == null) throw const InvalidCodeException();
    await _checkRoom(normalized);
    final session = await _open(normalized);
    await ref.read(gameRepositoryProvider).joinGame(session, name: name);
    final known = (await ref.read(sessionStoreProvider).loadGroups()).find(
      normalized,
    );
    await _remember(
      (known ?? SavedGroup(code: normalized)).copyWith(
        groupId: session.groupId,
      ),
    );
    state = AsyncData(session);
  }

  Future<void> _remember(SavedGroup group) async {
    await _updateGroups((g) => g.add(group));
    await ref.read(sessionStoreProvider).saveActive(group.code);
  }

  /// Keeps the overview's copy of the group's name and host flag up to date.
  Future<void> rememberInfo(GameInfo game) async {
    final session = state.value;
    if (session == null) return;
    final known = (await ref.read(sessionStoreProvider).loadGroups()).find(
      session.code,
    );
    final isHost = game.adminId == session.userId;
    if (known == null || (known.name == game.name && known.isHost == isHost)) {
      return;
    }
    await _updateGroups(
      (g) => g.update(session.code, name: game.name, isHost: isHost),
    );
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

  /// Drops the open group from this device, e.g. when the admin deleted it.
  Future<void> forget() => _forget();

  /// Drops a group from the overview without opening it, e.g. one that was
  /// deleted meanwhile.
  Future<void> forgetGroup(String code) async {
    if (state.value?.code == code) return _forget();
    await _updateGroups((g) => g.remove(code));
  }

  Future<void> _forget() async {
    final session = state.value;
    if (session != null) await _remove(session.code);
    await ref.read(sessionStoreProvider).saveActive(null);
    state = const AsyncData(null);
  }

  Future<void> _remove(String code, {bool notify = true}) async {
    await _updateGroups((g) => g.remove(code), notify: notify);
    await ref.read(sessionStoreProvider).saveActive(null);
  }
}

typedef CryptoFactory = Future<GroupCrypto> Function(String code);
