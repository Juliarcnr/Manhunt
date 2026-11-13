import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/app.dart';
import 'package:manhunt/core/groups/group_list.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/teams/team_assignment.dart';
import 'package:manhunt/data/game_repository.dart';
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
    FakeBotBackend? bots,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: deviceOverrides(
          db: db,
          userId: userId,
          store: MemorySessionStore.withGroup('ABCDE-FGHJK'),
          bots: bots,
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

  testWidgets('first app start asks for location permission (R-PERM-01)', (
    tester,
  ) async {
    final location = FakeLocationService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: deviceOverrides(
          db: FakeFirebaseFirestore(),
          userId: 'me',
          location: location,
        ),
        child: const ManhuntApp(locale: Locale('en')),
      ),
    );
    // Asked right away, already on the group overview (no group yet).
    expect(location.permissionRequests, 1);
    await tester.pumpAndSettle();
    expect(location.permissionRequests, 1);
  });

  testWidgets('lobby updates do not ask for permission again (R-PERM-01)', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
    await tester.runAsync(
      () =>
          deviceRepo(db)
              .createGame(me!, name: 'Julia', settings: defaultSettings),
    );
    final location = FakeLocationService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: deviceOverrides(
          db: db,
          userId: 'me',
          store: MemorySessionStore.withGroup('ABCDE-FGHJK'),
          location: location,
        ),
        child: const ManhuntApp(locale: Locale('en')),
      ),
    );
    await settleAsync(tester);

    expect(find.text('Lobby'), findsOneWidget);
    expect(location.permissionRequests, 1);
    // Rebuilds (member updates) do not ask again.
    await tester.runAsync(() => deviceRepo(db).renameGroup(me!, 'Crew'));
    await settleAsync(tester);
    expect(find.text('Crew'), findsOneWidget);
    expect(location.permissionRequests, 1);
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

  group('roles in the lobby (R-LOBBY-04, R-LOBBY-05, R-LOBBY-06, '
      'R-LOBBY-11, R-LOBBY-12, R-LOBBY-13, R-GM-02)', () {
    const square = [GeoPoint(52, 13), GeoPoint(52, 13.1), GeoPoint(52.1, 13.1)];
    late FakeFirebaseFirestore db;
    late GroupSession host;

    /// Host "me" and KIM, SAM, LOU – everyone unassigned after joining.
    Future<void> setUpGroup(WidgetTester tester) async {
      db = FakeFirebaseFirestore();
      host = (await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me')))!;
      await tester.runAsync(() async {
        await deviceRepo(db).createGame(
          host,
          name: 'Julia',
          settings: defaultSettings.copyWith(area: square),
        );
        for (final id in ['kim', 'sam', 'lou']) {
          await deviceRepo(db).joinGame(
            await testSession('ABCDE-FGHJK', id),
            name: id.toUpperCase(),
          );
        }
      });
    }

    Future<String?> role(WidgetTester tester, String id) async =>
        (await tester.runAsync(
              () => db
                  .collection('games')
                  .doc(host.groupId)
                  .collection('members')
                  .doc(id)
                  .get(),
            ))!.data()?['role']
            as String?;

    Future<void> assign(WidgetTester tester, Map<String, Role> roles) =>
        tester.runAsync(() async {
          final members = await deviceRepo(db).watchMembers(host).first;
          await deviceRepo(db).setRoles(host, [
            for (final m in members) m.copyWith(role: roles[m.id] ?? m.role),
          ]);
        });

    Future<void> scrollTo(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('newcomers are unassigned; the hint says they do not play; '
        'four sections and the drag hint for the host, no add button', (
      tester,
    ) async {
      await setUpGroup(tester);
      await pumpAppWithSession(tester, db: db, userId: 'me');
      await scrollTo(tester, find.byKey(const Key('dragHint')));
      expect(find.byKey(const Key('dragHint')), findsOneWidget);
      for (final key in [
        'unassignedSection',
        'playerSection',
        'hunterSection',
        'gameMasterSection',
      ]) {
        await scrollTo(tester, find.byKey(Key(key)));
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      await scrollTo(tester, find.byKey(const Key('unassignedHint')));
      expect(find.text('Anyone here does not play.'), findsOneWidget);
      expect(find.byKey(const Key('addGameMasterButton')), findsNothing);
      expect(await role(tester, 'kim'), 'unassigned');
    });

    testWidgets('tapping a person opens the role menu', (tester) async {
      await setUpGroup(tester);
      await pumpAppWithSession(tester, db: db, userId: 'me');
      await scrollTo(tester, find.text('KIM'));
      await tester.tap(find.text('KIM'));
      await tester.pumpAndSettle();
      expect(find.text('Role of KIM'), findsOneWidget);
      await tester.tap(find.byKey(const Key('roleOption_gameMaster')));
      await settleAsync(tester);
      expect(await role(tester, 'kim'), 'gameMaster');
    });

    testWidgets('a person is dragged into another section', (tester) async {
      await setUpGroup(tester);
      await assign(tester, {'me': Role.hunter, 'kim': Role.player});
      await pumpAppWithSession(tester, db: db, userId: 'me');
      await scrollTo(tester, find.byKey(const Key('hunterSection')));
      final from = tester.getCenter(find.byKey(const Key('drag_kim')));
      final to = tester.getCenter(find.byKey(const Key('hunterSection')));
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await settleAsync(tester);
      expect(await role(tester, 'kim'), 'hunter');
    });

    testWidgets('the sit-out button sends a person back to unassigned; not '
        'for the host themself', (tester) async {
      await setUpGroup(tester);
      await assign(tester, {'me': Role.hunter, 'kim': Role.player});
      await pumpAppWithSession(tester, db: db, userId: 'me');
      expect(find.byKey(const Key('unassign_me')), findsNothing);
      // Already unassigned: no button.
      expect(find.byKey(const Key('unassign_sam')), findsNothing);
      await scrollTo(tester, find.byKey(const Key('unassign_kim')));
      await tester.tap(find.byKey(const Key('unassign_kim')));
      await settleAsync(tester);
      expect(await role(tester, 'kim'), 'unassigned');
    });

    testWidgets('dice rolls everybody, also game masters and unassigned '
        'members, 30/70', (tester) async {
      await setUpGroup(tester);
      await assign(tester, {'me': Role.gameMaster, 'kim': Role.hunter});
      await pumpAppWithSession(tester, db: db, userId: 'me');
      await scrollTo(tester, find.byKey(const Key('randomButton')));
      await tester.tap(find.byKey(const Key('randomButton')));
      await settleAsync(tester);
      final roles = [
        for (final id in ['me', 'kim', 'sam', 'lou']) await role(tester, id),
      ];
      expect(roles.where((r) => r == 'hunter'), hasLength(1));
      expect(roles.where((r) => r == 'player'), hasLength(3));
    });

    testWidgets('an unassigned host cannot start', (tester) async {
      await setUpGroup(tester);
      await assign(tester, {'kim': Role.hunter, 'sam': Role.player});
      await pumpAppWithSession(tester, db: db, userId: 'me');
      final start = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('startButton')),
      );
      expect(start.onPressed, isNull);
      await scrollTo(tester, find.textContaining('You are still under'));
      expect(find.textContaining('You are still under'), findsOneWidget);
    });

    testWidgets('start shows who plays and who sits out; only the '
        'confirmation starts the round', (tester) async {
      await setUpGroup(tester);
      await assign(tester, {
        'me': Role.gameMaster,
        'kim': Role.hunter,
        'sam': Role.player,
      });
      await pumpAppWithSession(tester, db: db, userId: 'me');
      Future<String?> status() async =>
          (await tester.runAsync(
                () => db.collection('games').doc(host.groupId).get(),
              ))!.data()?['status']
              as String?;

      await tester.tap(find.byKey(const Key('startButton')));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const Key('startConfirmDialog'));
      expect(dialog, findsOneWidget);
      for (final (key, name) in [
        ('startConfirm_player', 'SAM'),
        ('startConfirm_hunter', 'KIM'),
        ('startConfirm_gameMaster', 'Julia'),
      ]) {
        expect(
          find.descendant(of: find.byKey(Key(key)), matching: find.text(name)),
          findsOneWidget,
          reason: key,
        );
      }
      expect(find.text('1 person does not play'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('LOU')),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await settleAsync(tester);
      expect(await status(), 'lobby');

      await tester.tap(find.byKey(const Key('startButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startConfirmButton')));
      await settleAsync(tester);
      expect(await status(), 'running');
    });

    testWidgets('during a round, unassigned members see the lobby as if no '
        'game were on (R-LOBBY-11)', (tester) async {
      await setUpGroup(tester);
      await assign(tester, {'me': Role.hunter, 'kim': Role.player});
      await tester.runAsync(() => deviceRepo(db).startGame(host));
      await pumpAppWithSession(tester, db: db, userId: 'lou');
      expect(find.text('Lobby'), findsOneWidget);
      expect(find.text('Waiting for the host to start…'), findsOneWidget);
      // Nothing to change until the round is over.
      final edit = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('editAreaButton')),
      );
      expect(edit.onPressed, isNull);
      expect(find.byKey(const Key('endRoundButton')), findsNothing);
    });
  });

  testWidgets('host is told before the start when hunters will see each '
      'other only every 15 s and watchers every 30 s (R-QUOTA-02)', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
    // 3 h, 3 hunters, 6 players, 1 game master: ≈ 45k reads with 5 s.
    final roles = {
      'me': Role.hunter,
      'h1': Role.hunter,
      'h2': Role.hunter,
      for (var i = 0; i < 6; i++) 'p$i': Role.player,
      'gm': Role.gameMaster,
    };
    Future<void> assign(Map<String, Role> roles) => tester.runAsync(() async {
      final members = await deviceRepo(db).watchMembers(me!).first;
      await deviceRepo(db).setRoles(me, [
        for (final m in members) m.copyWith(role: roles[m.id] ?? Role.player),
      ]);
    });
    await tester.runAsync(() async {
      await deviceRepo(db)
          .createGame(me!, name: 'Julia', settings: defaultSettings);
      for (final id in roles.keys.skip(1)) {
        await deviceRepo(db)
            .joinGame(await testSession('ABCDE-FGHJK', id), name: id);
      }
    });
    await assign(roles);
    await pumpAppWithSession(tester, db: db, userId: 'me');
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hunterLiveThrottledHint')), findsOneWidget);
    expect(find.textContaining('estimated 40 %'), findsOneWidget);

    // With only the hunters assigned so far it fits.
    await assign({
      for (final e in roles.entries)
        e.key: e.value == Role.hunter ? Role.hunter : Role.unassigned,
    });
    await settleAsync(tester);
    expect(find.byKey(const Key('hunterLiveThrottledHint')), findsNothing);
  });

  testWidgets('guests see the game master section only when it is taken '
      '(R-GM-01)', (tester) async {
    final db = FakeFirebaseFirestore();
    final admin = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'a'));
    final guest = await tester.runAsync(
      () => testSession('ABCDE-FGHJK', 'guest'),
    );
    await tester.runAsync(() async {
      await deviceRepo(db)
          .createGame(admin!, name: 'Julia', settings: defaultSettings);
      await deviceRepo(db).joinGame(guest!, name: 'Kim');
    });
    await pumpAppWithSession(tester, db: db, userId: 'guest');
    Future<void> toBottom() async {
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
    }

    await toBottom();
    expect(find.byKey(const Key('gameMasterSection')), findsNothing);

    await tester.runAsync(() async {
      final members = await deviceRepo(db).watchMembers(admin!).first;
      await deviceRepo(db)
          .setRoles(admin, setRole(members, 'a', Role.gameMaster));
    });
    await settleAsync(tester);
    await toBottom();
    expect(find.byKey(const Key('gameMasterSection')), findsOneWidget);
    // Guests cannot move anyone (R-LOBBY-05).
    expect(find.byKey(const Key('dragHint')), findsNothing);
    expect(find.byKey(const Key('drag_guest')), findsNothing);
  });

  testWidgets('members change their own name in the lobby (R-LOBBY-10)', (
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
    await pumpAppWithSession(tester, db: db, userId: 'guest');

    // Only one pencil: next to the own name, not next to the host.
    expect(find.byKey(const Key('renameMeButton')), findsOneWidget);
    // The pencil marks the own name, no extra "You" badge.
    expect(find.text('You'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('renameMeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('renameMeButton')));
    await tester.pumpAndSettle();
    expect(find.text('Change your name'), findsOneWidget);

    // Empty names are rejected.
    await tester.enterText(find.byKey(const Key('nameField')), '  ');
    await tester.tap(find.byKey(const Key('renameSave')));
    await tester.pumpAndSettle();
    expect(find.text('Change your name'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('nameField')), ' Kimi ');
    await tester.tap(find.byKey(const Key('renameSave')));
    await settleAsync(tester);
    expect(find.text('Kimi'), findsOneWidget);
    expect(find.text('Kim'), findsNothing);
    expect(find.text('Julia'), findsOneWidget);
  });

  testWidgets('computer players join unassigned, keep their role and are '
      'rolled like people (R-BOT-02, R-BOT-03, R-LOBBY-04)', (tester) async {
    final db = FakeFirebaseFirestore();
    final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
    final guest = await tester.runAsync(
      () => testSession('ABCDE-FGHJK', 'guest'),
    );
    await tester.runAsync(() async {
      await deviceRepo(db).createGame(
        me!,
        name: 'Julia',
        settings: defaultSettings.copyWith(botCount: 2),
      );
      await deviceRepo(db).joinGame(guest!, name: 'Kim');
    });
    await pumpAppWithSession(
      tester,
      db: db,
      userId: 'me',
      bots: FakeBotBackend(db, owner: 'me'),
    );

    Future<String?> role(String id) async =>
        (await tester.runAsync(
              () => db
                  .collection('games')
                  .doc(me!.groupId)
                  .collection('members')
                  .doc(id)
                  .get(),
            ))!.data()?['role']
            as String?;

    // The host's phone adds them, unassigned.
    expect(await role('bot-1-me'), 'unassigned');
    expect(await role('bot-2-me'), 'unassigned');

    // The host moves one like a person; game master is not offered.
    await tester.scrollUntilVisible(
      find.text('🤖 Adelgunde'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Clear of the start button at the bottom.
    await tester.ensureVisible(find.text('🤖 Adelgunde'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🤖 Adelgunde'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('roleOption_gameMaster')), findsNothing);
    await tester.tap(find.byKey(const Key('roleOption_hunter')));
    await settleAsync(tester);
    expect(await role('bot-1-me'), 'hunter');
    // It stays a hunter, nothing changes it back.
    await settleAsync(tester);
    expect(await role('bot-1-me'), 'hunter');

    // Random teams: 4 members → 1 hunter, 3 players, bots included.
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('randomButton')));
    await settleAsync(tester);
    final roles = [
      for (final id in ['me', 'guest', 'bot-1-me', 'bot-2-me']) await role(id),
    ];
    expect(roles.where((r) => r == 'hunter'), hasLength(1));
    expect(roles.where((r) => r == 'player'), hasLength(3));
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

  group('everyone sees the settings, only the host edits (R-SET-14)', () {
    Future<GroupSession> setUpGroup(
      WidgetTester tester,
      FakeFirebaseFirestore db,
    ) async {
      final admin = await tester.runAsync(
        () => testSession('ABCDE-FGHJK', 'a'),
      );
      final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
      await tester.runAsync(() async {
        await deviceRepo(db)
            .createGame(admin!, name: 'Alex', settings: defaultSettings);
        await deviceRepo(db).joinGame(me!, name: 'Kim');
      });
      return admin!;
    }

    testWidgets('guest sees the settings read-only and kept up to date', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      final admin = await setUpGroup(tester, db);
      await pumpAppWithSession(tester, db: db, userId: 'me');

      await tester.tap(find.byKey(const Key('settingsButton')));
      await tester.pumpAndSettle();

      expect(find.text('Game settings'), findsOneWidget);
      expect(find.byKey(const Key('settingsReadOnlyHint')), findsOneWidget);
      expect(find.byKey(const Key('saveSettings')), findsNothing);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      final joker = tester.widget<SwitchListTile>(
        find.byKey(const Key('playerJokerSwitch')),
      );
      expect(joker.onChanged, isNull);
      expect(find.text('20 min'), findsOneWidget);

      await tester.runAsync(
        () => deviceRepo(db).updateSettings(
          admin,
          defaultSettings.copyWith(pingInterval: const Duration(minutes: 35)),
        ),
      );
      await settleAsync(tester);
      expect(find.text('35 min'), findsOneWidget);
    });

    testWidgets('host can edit the settings', (tester) async {
      final db = FakeFirebaseFirestore();
      final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
      await tester.runAsync(
        () =>
            deviceRepo(db)
                .createGame(me!, name: 'Julia', settings: defaultSettings),
      );
      await pumpAppWithSession(tester, db: db, userId: 'me');

      await tester.tap(find.byKey(const Key('settingsButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settingsReadOnlyHint')), findsNothing);
      expect(find.byKey(const Key('saveSettings')), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsWidgets);
    });
  });

  testWidgets('settings show the full group name on top (R-SET-20)', (
    tester,
  ) async {
    const long = 'The very long name of our Friday evening running crew';
    final db = FakeFirebaseFirestore();
    final me = await tester.runAsync(() => testSession('ABCDE-FGHJK', 'me'));
    await tester.runAsync(
      () => deviceRepo(db).createGame(
        me!,
        name: 'Julia',
        settings: defaultSettings,
        groupName: long,
      ),
    );
    await pumpAppWithSession(tester, db: db, userId: 'me');

    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pumpAndSettle();

    final name = tester.widget<Text>(
      find.byKey(const Key('settingsGroupName')),
    );
    expect(name.data, long);
    expect(name.overflow, isNull); // wraps instead of "…"
  });
}
