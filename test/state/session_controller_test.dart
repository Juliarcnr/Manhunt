import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/groups/group_list.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/data/game_repository.dart';
import 'package:manhunt/data/session_store.dart';
import 'package:manhunt/state/providers.dart';
import 'package:manhunt/state/session_controller.dart';

import '../helpers.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  ProviderContainer device(String userId, [SessionStore? store]) {
    final c = ProviderContainer(
      overrides: deviceOverrides(db: db, userId: userId, store: store),
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<String> create(
    ProviderContainer c, [
    String groupName = 'Crew',
  ]) async {
    await c
        .read(sessionControllerProvider.notifier)
        .create(
          name: 'Julia',
          groupName: groupName,
          settings: const GameSettings(),
        );
    return c.read(sessionControllerProvider).value!.code;
  }

  test('create stores the code and exposes a session (R-LOBBY-02)', () async {
    final store = MemorySessionStore();
    final c = device('admin', store);
    expect(await c.read(sessionControllerProvider.future), isNull);

    final code = await create(c);

    final session = c.read(sessionControllerProvider).value!;
    expect(code, matches(RegExp(r'^\w{5}-\w{5}$')));
    expect(store.active, code);
    final saved = store.groups.find(code)!;
    expect(saved.name, 'Crew');
    expect(saved.isHost, isTrue);
    expect(saved.groupId, session.groupId);
  });

  test('second device joins with lower-case code without dash', () async {
    final admin = device('admin');
    final code = await create(admin);

    final guest = device('guest');
    await guest.read(sessionControllerProvider.future);
    await guest
        .read(sessionControllerProvider.notifier)
        .join(code: code.replaceAll('-', '').toLowerCase(), name: 'Kim');

    expect(
      guest.read(sessionControllerProvider).value!.groupId,
      admin.read(sessionControllerProvider).value!.groupId,
    );
  });

  test('invalid code is rejected before any network call', () async {
    final c = device('guest');
    await c.read(sessionControllerProvider.future);
    expect(
      () => c
          .read(sessionControllerProvider.notifier)
          .join(code: 'abc', name: 'Kim'),
      throwsA(isA<InvalidCodeException>()),
    );
  });

  test('unknown group surfaces GroupNotFoundException', () async {
    final c = device('guest');
    await c.read(sessionControllerProvider.future);
    expect(
      () => c
          .read(sessionControllerProvider.notifier)
          .join(code: 'ABCDE-FGHJK', name: 'Kim'),
      throwsA(isA<GroupNotFoundException>()),
    );
  });

  test('session is restored after app restart', () async {
    final store = MemorySessionStore();
    final code = await create(device('admin', store));

    final restarted = device('admin', store);
    final session = await restarted.read(sessionControllerProvider.future);
    expect(session!.code, code);
  });

  test('leave forgets the group and removes own membership', () async {
    final store = MemorySessionStore();
    final admin = device('admin');
    final code = await create(admin);

    final guest = device('guest', store);
    await guest.read(sessionControllerProvider.future);
    await guest
        .read(sessionControllerProvider.notifier)
        .join(code: code, name: 'Kim');
    await guest.read(sessionControllerProvider.notifier).leave();

    expect(store.active, isNull);
    expect(store.groups.isEmpty, isTrue);
    expect(guest.read(sessionControllerProvider).value, isNull);
    final members = await deviceRepo(db)
        .watchMembers(admin.read(sessionControllerProvider).value!)
        .first;
    expect(members.map((m) => m.id), ['admin']);
  });

  test(
    'app start deletes a group nobody opened for 180 days (R-PRIV-05)',
    () async {
      final store = MemorySessionStore();
      await create(device('admin', store));

      final later = ProviderContainer(
        overrides: deviceOverrides(
          db: db,
          userId: 'admin',
          store: store,
          now: () => DateTime.now().add(const Duration(days: 181)),
        ),
      );
      addTearDown(later.dispose);

      expect(await later.read(sessionControllerProvider.future), isNull);
      expect(store.active, isNull);
      expect(store.groups.isEmpty, isTrue);
      expect((await db.collection('games').get()).docs, isEmpty);
    },
  );

  test('app start keeps a recently used group', () async {
    final store = MemorySessionStore();
    await create(device('admin', store));

    final restarted = device('admin', store);
    expect(await restarted.read(sessionControllerProvider.future), isNotNull);
  });

  group('several groups (R-GROUPS-01 … R-GROUPS-03)', () {
    test('create and join add up; close keeps them, select reopens', () async {
      final other = device('other');
      final joined = await create(other, 'Other crew');

      final store = MemorySessionStore();
      final me = device('me', store);
      final controller = me.read(sessionControllerProvider.notifier);
      await me.read(sessionControllerProvider.future);
      final own = await create(me, 'Mine');
      await controller.join(code: joined, name: 'Julia');

      expect(store.groups.groups.map((g) => g.code), [own, joined]);
      expect(store.groups.find(joined)!.isHost, isFalse);
      expect(me.read(sessionControllerProvider).value!.code, joined);

      await controller.close();
      expect(me.read(sessionControllerProvider).value, isNull);
      expect(store.active, isNull);
      expect(store.groups.groups, hasLength(2));
      expect((await me.read(groupListProvider.future)).groups, hasLength(2));

      expect(await controller.select(own), isTrue);
      expect(me.read(sessionControllerProvider).value!.code, own);
      expect(store.active, own);

      // App restart opens the last group again.
      final restarted = device('me', store);
      expect(
        (await restarted.read(sessionControllerProvider.future))!.code,
        own,
      );
    });

    test('at most 5 groups, created or joined (R-GROUPS-02)', () async {
      final other = device('other');
      final extra = await create(other, 'Extra');

      final store = MemorySessionStore();
      final me = device('me', store);
      await me.read(sessionControllerProvider.future);
      final codes = [
        for (var i = 0; i < GroupList.maxGroups; i++) await create(me, 'G$i'),
      ];
      expect(store.groups.isFull, isTrue);

      final controller = me.read(sessionControllerProvider.notifier);
      await expectLater(
        controller.create(
          name: 'Julia',
          groupName: 'Too many',
          settings: const GameSettings(),
        ),
        throwsA(isA<GroupLimitException>()),
      );
      await expectLater(
        controller.join(code: extra, name: 'Julia'),
        throwsA(isA<GroupLimitException>()),
      );
      // Nothing was written for the rejected groups.
      expect((await db.collection('games').get()).docs, hasLength(6));
      final extraSession = other.read(sessionControllerProvider).value!;
      final extraMembers = await deviceRepo(db)
          .watchMembers(extraSession)
          .first;
      expect(extraMembers.map((m) => m.id), ['other']);

      // Re-joining a known group is fine (no new slot needed).
      await controller.join(code: codes.first, name: 'Julia 2');
      expect(store.groups.groups, hasLength(GroupList.maxGroups));

      // Deleting one frees a slot.
      await controller.deleteGroup();
      await controller.join(code: extra, name: 'Julia');
      expect(store.groups.find(extra), isNotNull);
    });

    test('select forgets a group that was deleted meanwhile', () async {
      final store = MemorySessionStore();
      final me = device('me', store);
      await me.read(sessionControllerProvider.future);

      final admin = device('admin');
      final code = await create(admin);
      await me
          .read(sessionControllerProvider.notifier)
          .join(code: code, name: 'Kim');
      await me.read(sessionControllerProvider.notifier).close();
      await admin.read(sessionControllerProvider.notifier).deleteGroup();

      expect(
        await me.read(sessionControllerProvider.notifier).select(code),
        isFalse,
      );
      expect(me.read(sessionControllerProvider).value, isNull);
      expect(store.groups.isEmpty, isTrue);
    });

    test('rememberInfo keeps name and host flag current', () async {
      final store = MemorySessionStore();
      final me = device('me', store);
      final code = await create(me, 'Old');
      final session = me.read(sessionControllerProvider).value!;

      await deviceRepo(db).renameGroup(session, 'New');
      final game = await deviceRepo(db).watchGame(session).first;
      await me.read(sessionControllerProvider.notifier).rememberInfo(game!);

      expect(store.groups.find(code)!.name, 'New');
      expect((await me.read(groupListProvider.future)).find(code)!.name, 'New');
    });
  });
}
