import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the join code of the current group on this device only.
/// The code is the group's encryption secret, so it lives in the OS keystore.
abstract interface class SessionStore {
  Future<String?> loadCode();
  Future<void> saveCode(String code);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'group_code';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> loadCode() => _storage.read(key: _key);

  @override
  Future<void> saveCode(String code) => _storage.write(key: _key, value: code);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemorySessionStore implements SessionStore {
  String? code;

  @override
  Future<String?> loadCode() async => code;

  @override
  Future<void> saveCode(String code) async => this.code = code;

  @override
  Future<void> clear() async => code = null;
}
