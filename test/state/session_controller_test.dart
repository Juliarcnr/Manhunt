import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('create stores the code and exposes a session (R-LOBBY-02)', () async {
    final store = MemorySessionStore();
    final c = device('admin', store);
    expect(await c.read(sessionControllerProvider.future), isNull);

    await c
        .read(sessionControllerProvider.notifier)
        .create(name: 'Julia', settings: const GameSettings());

    final session = c.read(sessionControllerProvider).value!;
    expect(session.code, matches(RegExp(r'^\w{5}-\w{5}$')));
    expect(store.code, session.code);
  });

  test('second device joins with lower-case code without dash', () async {
    final admin = device('admin');
    await admin
        .read(sessionControllerProvider.notifier)
        .create(name: 'Julia', settings: const GameSettings());
    final code = admin.read(sessionControllerProvider).value!.code;

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
    final first = device('admin', store);
    await first
        .read(sessionControllerProvider.notifier)
        .create(name: 'Julia', settings: const GameSettings());

    final restarted = device('admin', store);
    final session = await restarted.read(sessionControllerProvider.future);
    expect(session!.code, store.code);
  });

  test('leave clears the stored code and own membership', () async {
    final store = MemorySessionStore();
    final admin = device('admin');
    await admin
        .read(sessionControllerProvider.notifier)
        .create(name: 'Julia', settings: const GameSettings());
    final code = admin.read(sessionControllerProvider).value!.code;

    final guest = device('guest', store);
    await guest.read(sessionControllerProvider.future);
    await guest
        .read(sessionControllerProvider.notifier)
        .join(code: code, name: 'Kim');
    await guest.read(sessionControllerProvider.notifier).leave();

    expect(store.code, isNull);
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
      final admin = device('admin', store);
      await admin
          .read(sessionControllerProvider.notifier)
          .create(name: 'Julia', settings: const GameSettings());

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
      expect(store.code, isNull);
      expect((await db.collection('games').get()).docs, isEmpty);
    },
  );

  test('app start keeps a recently used group', () async {
    final store = MemorySessionStore();
    final admin = device('admin', store);
    await admin
        .read(sessionControllerProvider.notifier)
        .create(name: 'Julia', settings: const GameSettings());

    final restarted = device('admin', store);
    expect(await restarted.read(sessionControllerProvider.future), isNotNull);
  });
}
