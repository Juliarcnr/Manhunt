import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption for one group (R-PRIV-02).
///
/// The join code never leaves the device. From it we derive (PBKDF2):
/// - [groupId]: the public document id in the backend,
/// - a 256-bit AES-GCM key for all sensitive payloads (locations, area).
/// Both come from the same slow derivation, so guessing codes via the
/// public group id is as expensive as guessing the key itself.
class GroupCrypto {
  GroupCrypto._(this.groupId, this._key);

  /// ~1 s in pure Dart; with a ≈48-bit code, brute force stays infeasible.
  static const defaultIterations = 50000;
  static final _salt = utf8.encode('manhunt-app/group-key/v1');
  static final _aes = AesGcm.with256bits();

  final String groupId;
  final SecretKey _key;

  /// Runs the slow derivation in a background isolate to keep the UI smooth.
  static Future<GroupCrypto> derive(
    String joinCode, {
    int iterations = defaultIterations,
  }) async {
    final bytes = await Isolate.run(() => _deriveBytes(joinCode, iterations));
    final id = bytes
        .sublist(32, 48)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return GroupCrypto._(id, SecretKey(bytes.sublist(0, 32)));
  }

  static Future<List<int>> _deriveBytes(String joinCode, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 512,
    );
    final derived = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(joinCode)),
      nonce: _salt,
    );
    return derived.extractBytes();
  }

  /// Encrypts a JSON-serializable value to a base64 string (nonce|ciphertext|mac).
  Future<String> encryptJson(Object? value) async {
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: _key,
    );
    return base64Encode(box.concatenation());
  }

  /// Throws [SecretBoxAuthenticationError] if the data was tampered with
  /// or encrypted with another group's key.
  Future<Object?> decryptJson(String encoded) async {
    final box = SecretBox.fromConcatenation(
      base64Decode(encoded),
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    final clear = await _aes.decrypt(box, secretKey: _key);
    return jsonDecode(utf8.decode(clear));
  }
}
