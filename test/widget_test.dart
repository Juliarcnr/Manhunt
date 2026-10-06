import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/app.dart';
import 'package:manhunt/core/groups/group_list.dart';
import 'package:manhunt/data/session_store.dart';

import 'helpers.dart';

void main() {
  Future<FakeFirebaseFirestore> pumpApp(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    FakeFirebaseFirestore? db,
    String userId = 'me',
    SessionStore? store,
  }) async {
    final firestore = db ?? FakeFirebaseFirestore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: deviceOverrides(db: firestore, userId: userId, store: store),
        child: ManhuntApp(locale: locale),
      ),
    );
    await tester.pumpAndSettle();
    return firestore;
  }

  /// App start for a device that already belongs to group ABCDE-FGHJK.
  Future<void> pumpAppWithSession(
    WidgetTester tester, {
    required FakeFirebaseFirestore db,
    required String userId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: deviceOverrides(
          db: db,
          userId: userId,
          store: MemorySessionStore.withGroup('ABCDE-FGHJK'),
        ),
        child: const ManhuntApp(locale: Locale('en')),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
  }

  /// Lets real async work (key derivation in an isolate, fake Firestore) finish.
  Future<void> settleAsync(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('home shows create/join in German (R-PLAT-02)', (tester) async {
    await pumpApp(tester, locale: const Locale('de'));
    expect(find.text('Gruppe erstellen'), findsOneWidget);
    expect(find.text('Mit Code beitreten'), findsOneWidget);
  });

  testWidgets('home shows create/join in English (R-PLAT-02)', (tester) async {
    await pumpApp(tester);
    expect(find.text('Create group'), findsOneWidget);
    expect(find.text('Join with code'), findsOneWidget);
  });

  testWidgets('app uses dark theme (R-UI-02)', (tester) async {
    await pumpApp(tester);
    final context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets('create group leads to lobby with code (R-SET-01, R-LOBBY-02)', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('createButton')));
    await tester.pumpAndSettle();

    // Name is required.
    await tester.tap(find.text('Create group').last);
    await tester.pumpAndSettle();
    expect(find.text('Please enter a name'), findsOneWidget);
    expect(find.text('Please enter a group name'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('groupNameField')), 'Crew');
    await tester.enterText(find.byKey(const Key('nameField')), 'Julia');
    await tester.tap(find.text('Create group').last);
    await settleAsync(tester);

    expect(find.text('Lobby'), findsOneWidget);
    expect(find.text('Crew'), findsOneWidget); // group name (R-GROUPS-04)
    expect(find.byKey(const Key('groupCode')), findsOneWidget);
    expect(find.text('Julia'), findsOneWidget);
    // No play area yet → start disabled (R-LOBBY-06).
    final start = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('startButton')),
    );
    expect(start.onPressed, isNull);
    await tester.scrollUntilVisible(
      find.text('Draw the play area first'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Draw the play area first'), findsOneWidget);
  });

  testWidgets('host draws the play area from the lobby (R-SET-06, R-SET-08)', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('createButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('groupNameField')), 'Crew');
    await tester.enterText(find.byKey(const Key('nameField')), 'Julia');
    await tester.tap(find.text('Create group').last);
    await settleAsync(tester);

    expect(find.text('Not drawn yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('editAreaButton')));
    await tester.pumpAndSettle();
    expect(find.text('Draw play area'), findsWidgets);

    final center = tester.getCenter(find.byType(FlutterMap));
    for (final offset in const [
      Offset(-80, -80),
      Offset(80, -80),
      Offset(80, 80),
      Offset(-80, 80),
    ]) {
      await tester.tapAt(center + offset);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('areaSave')));
    await settleAsync(tester);

    expect(find.text('Lobby'), findsOneWidget);
    expect(find.textContaining('4 corners'), findsOneWidget);
    expect(find.text('Edit play area'), findsOneWidget);
    expect(find.text('Draw the play area first'), findsNothing);
  });

  testWidgets('tapping outside a text field closes the keyboard', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('createButton')));
    await tester.pumpAndSettle();

    await tester.showKeyboard(find.byKey(const Key('nameField')));
    await tester.enterText(find.byKey(const Key('nameField')), 'Julia');
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('New group')); // app bar, outside the field
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('Julia'), findsOneWidget); // input is kept
  });
  testWidgets('join with unknown code shows error (R-LOBBY-01)', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('joinButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('codeField')), 'ABCDE-FGHJK');
    await tester.enterText(find.byKey(const Key('nameField')), 'Kim');
    await tester.tap(find.text('Join'));
    await settleAsync(tester);
    expect(find.text('No group with this code'), findsOneWidget);
  });

  testWidgets('guest sees lobby and waits for host (R-LOBBY-03)', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final admin = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'a'));
    await tester.runAsync(
      () =>
          deviceRepo(db)
              .createGame(admin!, name: 'Julia', settings: defaultSettings),
    );

    await pumpApp(tester, db: db, userId: 'guest');
    await tester.tap(find.byKey(const Key('joinButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('codeField')), 'abcde fghjk');
    await tester.enterText(find.byKey(const Key('nameField')), 'Kim');
    await tester.tap(find.text('Join'));
    await settleAsync(tester);

    expect(find.text('Lobby'), findsOneWidget);
    expect(find.text('Julia'), findsOneWidget);
    expect(find.text('Kim'), findsOneWidget);
    expect(find.text('Waiting for the host to start…'), findsOneWidget);
    expect(find.byKey(const Key('randomButton')), findsNothing);
    // Everyone may draw the play area (R-SET-10), only the host starts.
    expect(find.byKey(const Key('editAreaButton')), findsOneWidget);
    expect(find.byKey(const Key('startButton')), findsNothing);
  });

  testWidgets('host removes a member in the lobby (R-LOBBY-09)', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
    final guest = await tester.runAsync(
      () => testSession('ABCDE-FGHJK', 'guest'),
    );
    await tester.runAsync(() async {
      await deviceRepo(db)
          .createGame(me!, name: 'Julia', settings: defaultSettings);
      await deviceRepo(db).joinGame(guest!, name: 'Kim');
    });
    await pumpAppWithSession(tester, db: db, userId: 'me');

    expect(find.text('Kim'), findsOneWidget);
    expect(find.byKey(const Key('remove_me')), findsNothing); // not oneself
    await tester.ensureVisible(find.byKey(const Key('remove_guest')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove_guest')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Kim?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await settleAsync(tester);
    expect(find.text('Kim'), findsNothing);
  });

  testWidgets('removed member is told and can go back home (R-LOBBY-09)', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final admin = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'a'));
    final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
    await tester.runAsync(() async {
      await deviceRepo(db)
          .createGame(admin!, name: 'Julia', settings: defaultSettings);
      await deviceRepo(db).joinGame(me!, name: 'Kim');
    });
    await pumpAppWithSession(tester, db: db, userId: 'me');
    expect(find.text('Lobby'), findsOneWidget);

    await tester.runAsync(() => deviceRepo(db).removeMember(admin!, 'me'));
    await settleAsync(tester);
    expect(
      find.text('You were removed from the group by the host.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Back to my groups'));
    await settleAsync(tester);
    expect(find.byKey(const Key('createButton')), findsOneWidget);
  });

  group('group overview (R-GROUPS-01 … R-GROUPS-04)', () {
    testWidgets('lobby leads to the overview and back (R-GROUPS-03)', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('createButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('groupNameField')), 'Crew');
      await tester.enterText(find.byKey(const Key('nameField')), 'Julia');
      await tester.tap(find.text('Create group').last);
      await settleAsync(tester);
      expect(find.text('Lobby'), findsOneWidget);

      await tester.tap(find.byKey(const Key('groupsBackButton')));
      await settleAsync(tester);
      expect(find.text('Your groups'), findsOneWidget);
      expect(find.text('1 of 5'), findsOneWidget);
      expect(find.text('Crew'), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
      // Create and join stay available from the overview.
      expect(find.byKey(const Key('createButton')), findsOneWidget);
      expect(find.byKey(const Key('joinButton')), findsOneWidget);

      await tester.tap(find.text('Crew'));
      await settleAsync(tester);
      expect(find.text('Lobby'), findsOneWidget);

      // The system back gesture also returns to the overview.
      await tester.binding.handlePopRoute();
      await settleAsync(tester);
      expect(find.text('Your groups'), findsOneWidget);
    });

    testWidgets('with 5 groups, create and join are disabled (R-GROUPS-02)', (
      tester,
    ) async {
      final store = MemorySessionStore()
        ..groups = GroupList([
          for (var i = 0; i < GroupList.maxGroups; i++)
            SavedGroup(code: 'CODE$i', name: 'Group $i'),
        ]);
      await pumpApp(tester, store: store);

      expect(find.text('5 of 5'), findsOneWidget);
      expect(find.byKey(const Key('groupLimit')), findsOneWidget);
      for (final key in ['createButton', 'joinButton']) {
        final button = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
        expect(button.onPressed, isNull, reason: key);
      }
    });

    testWidgets('shows running and deleted groups; deleted ones vanish', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      final admin = await tester.runAsync(
        () => testSession('ABCDE-FGHJK', 'a'),
      );
      await tester.runAsync(() async {
        await deviceRepo(db).createGame(
          admin!,
          name: 'Alex',
          settings: defaultSettings,
          groupName: 'Running crew',
        );
        await deviceRepo(db).startGame(admin);
      });
      final store = MemorySessionStore()
        ..groups = GroupList([
          SavedGroup(
            code: 'ABCDE-FGHJK',
            groupId: admin!.groupId,
            name: 'Running crew',
          ),
          const SavedGroup(
            code: 'KLMNP-QRSTU',
            groupId: 'missing',
            name: 'Gone crew',
          ),
        ]);
      await pumpApp(tester, db: db, store: store);
      await settleAsync(tester);

      expect(find.text('Round running'), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);

      await tester.tap(find.text('Gone crew'));
      await settleAsync(tester);
      expect(find.text('This group no longer exists.'), findsOneWidget);
      expect(find.text('Gone crew'), findsNothing);
      expect(store.groups.groups.map((g) => g.code), ['ABCDE-FGHJK']);
    });

    testWidgets('host renames the group (R-GROUPS-04)', (tester) async {
      final db = FakeFirebaseFirestore();
      final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
      await tester.runAsync(
        () => deviceRepo(db).createGame(
          me!,
          name: 'Julia',
          settings: defaultSettings,
          groupName: 'Crew',
        ),
      );
      await pumpAppWithSession(tester, db: db, userId: 'me');
      expect(find.byKey(const Key('groupName')), findsOneWidget);
      expect(find.text('Crew'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lobbyMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('groupNameField')),
        'Night crew',
      );
      await tester.tap(find.byKey(const Key('renameSave')));
      await settleAsync(tester);

      expect(find.text('Night crew'), findsOneWidget);
    });

    testWidgets('guests cannot rename the group (R-GROUPS-04)', (tester) async {
      final db = FakeFirebaseFirestore();
      final admin = await tester.runAsync(
        () => testSession('ABCDE-FGHJK', 'a'),
      );
      final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
      await tester.runAsync(() async {
        await deviceRepo(db).createGame(
          admin!,
          name: 'Alex',
          settings: defaultSettings,
          groupName: 'Crew',
        );
        await deviceRepo(db).joinGame(me!, name: 'Kim');
      });
      await pumpAppWithSession(tester, db: db, userId: 'me');

      await tester.tap(find.byKey(const Key('lobbyMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Rename group'), findsNothing);
      expect(find.text('Leave group'), findsOneWidget);
    });
  });
}
