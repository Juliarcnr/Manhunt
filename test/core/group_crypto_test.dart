import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/crypto/group_crypto.dart';

void main() {
  // Low iteration count keeps tests fast; production uses defaultIterations.
  Future<GroupCrypto> derive(String code) =>
      GroupCrypto.derive(code, iterations: 1000);

  group('GroupCrypto (R-PRIV-02)', () {
    test('same code → same group id, different code → different id', () async {
      final a1 = await derive('ABCDE-FGHJK');
      final a2 = await derive('ABCDE-FGHJK');
      final b = await derive('ABCDE-FGHJM');
      expect(a1.groupId, a2.groupId);
      expect(a1.groupId, isNot(b.groupId));
      expect(a1.groupId, hasLength(32));
      expect(a1.groupId, isNot(contains('ABCDE')));
    });

    test('roundtrip between devices of the same group', () async {
      final sender = await derive('ABCDE-FGHJK');
      final receiver = await derive('ABCDE-FGHJK');
      final payload = {
        'lat': 52.52,
        'lng': 13.405,
        't': '2026-10-04T14:20:00Z',
      };
      final cipher = await sender.encryptJson(payload);
      expect(cipher, isNot(contains('52.52')));
      expect(await receiver.decryptJson(cipher), payload);
    });

    test('random nonce: same payload encrypts differently', () async {
      final c = await derive('ABCDE-FGHJK');
      expect(await c.encryptJson(1), isNot(await c.encryptJson(1)));
    });

    test('other group cannot decrypt', () async {
      final a = await derive('ABCDE-FGHJK');
      final b = await derive('ABCDE-FGHJM');
      final cipher = await a.encryptJson('secret');
      expect(
        b.decryptJson(cipher),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
