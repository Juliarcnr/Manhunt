import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/groups/group_list.dart';

/// Persists this device's groups (join codes) and which one is open.
/// The codes are the groups' encryption secrets, so they live in the OS
/// keystore only (R-GROUPS-01).
abstract interface class SessionStore {
  Future<GroupList> loadGroups();
  Future<void> saveGroups(GroupList groups);

  /// Code of the group shown on app start; null = group overview.
  Future<String?> loadActive();
  Future<void> saveActive(String? code);
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _groupsKey = 'groups';
  static const _activeKey = 'active_group';

  /// Single group of app versions before R-GROUPS-01.
  static const _legacyKey = 'group_code';

  final FlutterSecureStorage _storage;

  Future<void>? _migration;

  /// Moves the single group of older versions into the list, once.
  Future<void> _migrate() => _migration ??= () async {
    final legacy = await _storage.read(key: _legacyKey);
    if (legacy == null) return;
    if (await _storage.read(key: _groupsKey) == null) {
      await saveGroups(GroupList([SavedGroup(code: legacy)]));
      await _storage.write(key: _activeKey, value: legacy);
    }
    await _storage.delete(key: _legacyKey);
  }();

  @override
  Future<GroupList> loadGroups() async {
    await _migrate();
    final raw = await _storage.read(key: _groupsKey);
    if (raw == null) return const GroupList();
    return GroupList.fromJson(jsonDecode(raw) as List<Object?>);
  }

  @override
  Future<void> saveGroups(GroupList groups) =>
      _storage.write(key: _groupsKey, value: jsonEncode(groups.toJson()));

  @override
  Future<String?> loadActive() async {
    await _migrate();
    return _storage.read(key: _activeKey);
  }

  @override
  Future<void> saveActive(String? code) => code == null
      ? _storage.delete(key: _activeKey)
      : _storage.write(key: _activeKey, value: code);
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore();

  /// A device that already belongs to (and has open) the group [code].
  MemorySessionStore.withGroup(String code)
    : groups = GroupList([SavedGroup(code: code)]),
      active = code;

  var groups = const GroupList();
  String? active;

  @override
  Future<GroupList> loadGroups() async => groups;

  @override
  Future<void> saveGroups(GroupList groups) async => this.groups = groups;

  @override
  Future<String?> loadActive() async => active;

  @override
  Future<void> saveActive(String? code) async => active = code;
}
