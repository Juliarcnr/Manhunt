import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/groups/group_list.dart';
import 'package:manhunt/data/session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureSessionStore (R-GROUPS-01)', () {
    test('keeps groups and the open group', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      expect((await store.loadGroups()).isEmpty, isTrue);
      expect(await store.loadActive(), isNull);

      await store.saveGroups(
        const GroupList([
          SavedGroup(code: 'ABCDE-FGHJK', groupId: 'g1', name: 'Crew'),
        ]),
      );
      await store.saveActive('ABCDE-FGHJK');

      final again = SecureSessionStore();
      expect((await again.loadGroups()).find('ABCDE-FGHJK')!.name, 'Crew');
      expect(await again.loadActive(), 'ABCDE-FGHJK');

      await again.saveActive(null);
      expect(await SecureSessionStore().loadActive(), isNull);
    });

    test('takes over the single group of older app versions', () async {
      FlutterSecureStorage.setMockInitialValues({'group_code': 'ABCDE-FGHJK'});
      final store = SecureSessionStore();

      final groups = await store.loadGroups();
      expect(groups.groups.map((g) => g.code), ['ABCDE-FGHJK']);
      expect(groups.groups.single.groupId, isNull);
      expect(await store.loadActive(), 'ABCDE-FGHJK');
      expect(
        await const FlutterSecureStorage().read(key: 'group_code'),
        isNull,
      );

      // Only once: a later restart does not bring the group back.
      await store.saveGroups(const GroupList());
      expect((await SecureSessionStore().loadGroups()).isEmpty, isTrue);
    });
  });
}
