import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/core/schedule/speedhunt.dart';
import 'package:manhunt/core/schedule/start_time.dart';
import 'package:manhunt/data/firestore_game_repository.dart';
import 'package:manhunt/data/firestore_round_repository.dart';
import 'package:manhunt/data/game_repository.dart';
import 'package:manhunt/data/joker_store.dart';
import 'package:manhunt/data/notification_service.dart';
import 'package:manhunt/data/session_store.dart';
import 'package:manhunt/features/game/game_screen.dart';
import 'package:manhunt/features/map/base_map.dart';
import 'package:manhunt/l10n/app_localizations.dart';
import 'package:manhunt/theme/app_theme.dart';

import '../helpers.dart';

/// Round with host Alex (hunter), Kim and Sam (players), started at [start].
void main() {
  const code = 'ABCDE-FGHJK';
  final start = DateTime.utc(2026, 10, 4, 14);
  const area = [
    GeoPoint(52.50, 13.40),
    GeoPoint(52.50, 13.41),
    GeoPoint(52.51, 13.41),
  ];
  // Real names for the hunters, so the tests can find them; anonymous players
  // have their own group (R-ANON-*).
  const settings = GameSettings(area: area, anonymousPlayers: false);

  late FakeFirebaseFirestore db;
  late FakeLocationService location;
  late SilentNotificationService notifications;
  late MemoryJokerStore jokers;
  late DateTime now;

  /// Lets real async work (fake Firestore, isolates) finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  Future<void> seed(
    WidgetTester tester, {
    GameSettings gameSettings = settings,
  }) async {
    await tester.runAsync(() async {
      final games = FirestoreGameRepository(db);
      final alex = await testSession(code, 'alex');
      await games.createGame(alex, name: 'Alex', settings: gameSettings);
      await games.joinGame(await testSession(code, 'kim'), name: 'Kim');
      await games.joinGame(await testSession(code, 'sam'), name: 'Sam');
      final members = await games.watchMembers(alex).first;
      await games.setRoles(alex, [
        for (final m in members)
          m.copyWith(role: m.id == 'alex' ? Role.hunter : Role.player),
      ]);
      await games.startGame(alex);
    });
  }

  Future<void> pumpAs(
    WidgetTester tester,
    String userId, {
    GameSettings gameSettings = settings,
    DateTime? finishedAt,
    DateTime? confirmedAt,
    Duration hunterLive = const Duration(seconds: 5),
  }) async {
    final session = (await tester.runAsync(() => testSession(code, userId)))!;
    // Anonymous numbers as shuffled by the host at the start (R-ANON-01).
    final aliases = (await tester.runAsync(
      () => FirestoreGameRepository(db).watchGame(session).first,
    ))?.aliases;
    await tester.pumpWidget(
      ProviderScope(
        overrides: deviceOverrides(
          db: db,
          userId: userId,
          now: () => now,
          store: MemorySessionStore.withGroup(code),
          location: location,
          notifications: notifications,
          jokers: jokers,
        ),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GameScreen(
            session: session,
            game: GameInfo(
              adminId: 'alex',
              status: GameStatus.running,
              settings: gameSettings,
              startAt: start,
              finishedAt: finishedAt,
              confirmedAt: confirmedAt,
              aliases: aliases ?? const {},
              hunterLiveInterval: hunterLive,
            ),
            now: () => now,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    location = FakeLocationService();
    notifications = SilentNotificationService();
    jokers = MemoryJokerStore();
    now = start.add(const Duration(minutes: 30));
  });

  group('countdown before the official start (R-START-01, R-START-03 … '
      'R-START-05)', () {
    final timed = settings.copyWith(startTime: const Duration(hours: 14));
    String countdown(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('startCountdownText'))).data!;

    testWidgets('hunter: big countdown over the map, no buttons, no '
        'tracking', (tester) async {
      now = start.subtract(const Duration(seconds: 90));
      await seed(tester, gameSettings: timed);
      await pumpAs(tester, 'alex', gameSettings: timed);
      // Only over the map, not in the header (R-START-05).
      expect(find.text('COUNTDOWN'), findsOneWidget);
      expect(find.byKey(const Key('gameCountdown')), findsNothing);
      expect(find.text('THE GAME STARTS IN'), findsOneWidget);
      expect(countdown(tester), '01:30');
      expect(find.byKey(const Key('catchButton')), findsNothing);
      expect(find.byKey(const Key('speedhuntButton')), findsNothing);
      expect(location.isTracking, isFalse);

      // Under a minute: only the seconds.
      now = start.subtract(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(countdown(tester), '3');

      // At the official start the head start begins (R-GAME-04) and "GO!"
      // shows briefly.
      now = start;
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(countdown(tester), 'GO!');
      expect(find.text('HEAD START'), findsOneWidget);
      expect(find.byKey(const Key('catchButton')), findsOneWidget);
      // Everyone is told that it starts now (R-START-04).
      expect(find.text('The game has officially started!'), findsOneWidget);
      expect(
        find.text('The players have a 15 min head start.'),
        findsOneWidget,
      );
      expect(
        notifications.shown.map((n) => n.title),
        contains('The game has officially started!'),
      );

      // Then the map is free again.
      now = start.add(startFlash);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('startCountdown')), findsNothing);
    });

    testWidgets('player: no joker or self-catch before the start', (
      tester,
    ) async {
      now = start.subtract(const Duration(seconds: 30));
      await seed(tester, gameSettings: timed);
      await pumpAs(tester, 'kim', gameSettings: timed);
      expect(countdown(tester), '30');
      expect(find.byKey(const Key('jokerButton')), findsNothing);
      expect(find.byKey(const Key('selfCatchButton')), findsNothing);

      now = start;
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('Your head start: 15 min – go!'), findsOneWidget);
      expect(find.byKey(const Key('selfCatchButton')), findsOneWidget);
    });

    testWidgets('without a start time: the same countdown and notice', (
      tester,
    ) async {
      now = start.subtract(const Duration(seconds: 2));
      await seed(tester);
      await pumpAs(tester, 'kim');
      expect(countdown(tester), '2');
      now = start;
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(
        notifications.shown.map((n) => n.title),
        contains('The game has officially started!'),
      );
    });
  });

  group('hunter (R-HUNT-*, R-SPEED-*)', () {
    testWidgets('sees catch and speedhunt buttons, not the player ones', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      expect(find.byKey(const Key('catchButton')), findsOneWidget);
      // Minute 30: greyed out until minute 60 (R-SET-11, R-SPEED-11).
      expect(find.text('Speedhunt (2) · 30:00'), findsOneWidget);
      expect(find.byKey(const Key('jokerButton')), findsNothing);
      expect(location.isTracking, isTrue);
    });

    testWidgets('sees when the next pings arrive, above the filters '
        '(R-HUNT-10)', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      expect(find.text('Next pings in 10:00'), findsOneWidget);
      expect(find.textContaining('Next ping in'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Next pings in 10:00')).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('filterBar'))).dy),
      );
    });

    testWidgets('no "next pings" after the last regular ping (R-HUNT-10)', (
      tester,
    ) async {
      now = start.add(settings.duration - const Duration(seconds: 1));
      await seed(tester);
      await pumpAs(tester, 'alex');
      expect(find.textContaining('Next pings'), findsNothing);
    });

    testWidgets('starting a speedhunt shows the banner for everyone', (
      tester,
    ) async {
      now = start.add(const Duration(minutes: 70)); // after R-SET-11
      await seed(tester);
      await pumpAs(tester, 'alex');
      await tester.tap(find.byKey(const Key('speedhuntButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('not on whom'), findsOneWidget);
      await tester.tap(find.byKey(const Key('speedhuntPlayer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kim').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmSpeedhunt')));
      await settle(tester);

      expect(find.byKey(const Key('speedhuntBanner')), findsOneWidget);
      // 1st ping goes out immediately, so the countdown shows the 2nd one.
      expect(find.text('Speedhunt active · ping 2/3 in 05:00'), findsOneWidget);
      // Ends at minute 80, then 30 min pause (R-SET-18, R-SPEED-11).
      expect(find.text('Speedhunt (1) · 40:00'), findsOneWidget);
      expect(find.text('Speedhunt started!'), findsOneWidget); // notice
      // Hunters know the target, so no "whom is unclear" hint (R-NOTIF-06).
      expect(find.textContaining('Nobody knows whom'), findsNothing);
      // App open: sound via the system (follows mute switch), no pop-up
      // (R-NOTIF-05).
      expect(notifications.shown.single.title, 'Speedhunt started!');
      expect(notifications.shown.single.foreground, isTrue);
    });

    testWidgets('speedhunt before minute 60 is refused (R-SET-11)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex'); // minute 30
      await tester.tap(find.byKey(const Key('speedhuntButton')));
      await tester.pumpAndSettle();
      expect(
        find.text('The next speedhunt is possible in 30:00 min.'),
        findsOne,
      );
      expect(find.byKey(const Key('speedhuntPlayer')), findsNothing);
    });

    Future<void> catchSam(WidgetTester tester) => tester.runAsync(
      () async => FirestoreGameRepository(db).recordCatch(
        await testSession(code, 'alex'),
        CatchRecord(
          playerId: 'sam',
          at: start.add(const Duration(minutes: 20)),
        ),
      ),
    );

    testWidgets('caught players cannot be picked for a speedhunt '
        '(R-SPEED-02)', (tester) async {
      now = start.add(const Duration(minutes: 70)); // after R-SET-11
      await seed(tester);
      await catchSam(tester);
      await pumpAs(tester, 'alex');
      await tester.tap(find.byKey(const Key('speedhuntButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speedhuntPlayer')));
      await tester.pumpAndSettle();

      Finder option(String id) => find.byWidgetPredicate(
        (w) => w is DropdownMenuItem<String> && w.value == id,
      );
      expect(option('kim'), findsWidgets);
      expect(option('sam'), findsNothing);
    });

    testWidgets('host undoes a catch via the overview, nobody is removed '
        'during a round (R-CATCH-04, R-LOBBY-09)', (tester) async {
      await seed(tester);
      await catchSam(tester);
      await pumpAs(tester, 'alex');
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overviewRemove_kim')), findsNothing);
      // Only caught players can be taken back.
      expect(find.byKey(const Key('overviewUndoCatch_kim')), findsNothing);
      await tester.tap(find.byKey(const Key('overviewUndoCatch_sam')));
      await tester.pumpAndSettle();
      expect(find.text('Undo the catch of Sam?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmUndoCatch')));
      await settle(tester);

      final session = (await tester.runAsync(() => testSession(code, 'alex')))!;
      final repo = FirestoreGameRepository(db);
      final members = await tester.runAsync(
        () => repo.watchMembers(session).first,
      );
      expect(members!.firstWhere((m) => m.id == 'sam').caught, isFalse);
      final catches = await tester.runAsync(
        () => repo.watchCatches(session).first,
      );
      expect(catches, isEmpty);
      expect(find.text('Sam is back in the game'), findsOneWidget);
    });

    Future<void> undoSam(WidgetTester tester) async {
      await tester.runAsync(
        () async =>
            FirestoreGameRepository(db)
                .undoCatch(await testSession(code, 'alex'), 'sam'),
      );
      await settle(tester);
    }

    testWidgets('the player is told they are back in the game (R-CATCH-05)', (
      tester,
    ) async {
      await seed(tester);
      await catchSam(tester);
      await pumpAs(tester, 'sam');
      expect(find.byKey(const Key('selfCatchButton')), findsNothing);
      await undoSam(tester);
      expect(find.text('You are back in the game'), findsOneWidget);
      expect(
        notifications.shown.map((n) => n.title),
        contains('You are back in the game'),
      );
      expect(find.byKey(const Key('selfCatchButton')), findsOneWidget);
    });

    testWidgets('other players are told by real name (R-CATCH-05)', (
      tester,
    ) async {
      await seed(tester);
      await catchSam(tester);
      await pumpAs(tester, 'kim');
      await undoSam(tester);
      expect(find.text('Sam is back in the game'), findsOneWidget);
    });

    testWidgets('ending the round is no "back in the game" (R-CATCH-05)', (
      tester,
    ) async {
      await seed(tester);
      await catchSam(tester);
      await pumpAs(tester, 'kim');
      await tester.runAsync(
        () async =>
            FirestoreGameRepository(db)
                .endRound(await testSession(code, 'alex')),
      );
      await settle(tester);
      expect(find.textContaining('back in the game'), findsNothing);
      expect(
        notifications.shown.map((n) => n.title),
        isNot(contains('Sam is back in the game')),
      );
    });

    testWidgets('the automatic end deletes the catches before the lobby: no '
        '"back in the game" either (R-CATCH-05, R-GAME-10)', (tester) async {
      await seed(tester);
      await catchSam(tester);
      now = start.add(settings.duration + const Duration(seconds: 5));
      await pumpAs(tester, 'kim');
      // As autoEndRound: round data first, the lobby only afterwards.
      await tester.runAsync(() async {
        final events = await db
            .collection('games')
            .doc((await testSession(code, 'kim')).groupId)
            .collection('events')
            .get();
        for (final d in events.docs) {
          await d.reference.delete();
        }
      });
      await settle(tester);
      expect(find.textContaining('back in the game'), findsNothing);
      expect(
        notifications.shown.map((n) => n.title),
        isNot(contains('Sam is back in the game')),
      );
    });

    testWidgets('players cannot undo a catch (R-CATCH-04)', (tester) async {
      await seed(tester);
      await catchSam(tester);
      await pumpAs(tester, 'kim');
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overviewUndoCatch_sam')), findsNothing);
    });

    testWidgets('speedhunt during head start is refused', (tester) async {
      now = start.add(const Duration(minutes: 5));
      await seed(tester);
      await pumpAs(tester, 'alex');
      await tester.tap(find.byKey(const Key('speedhuntButton')));
      await tester.pumpAndSettle();
      // Counts down to minute 60 already during the head start (R-SPEED-11).
      expect(
        find.text('The next speedhunt is possible in 55:00 min.'),
        findsOne,
      );
      expect(find.byKey(const Key('speedhuntPlayer')), findsNothing);
    });

    group('pauses between speedhunts (R-SET-18, R-SET-19, R-SPEED-11, '
        'R-SPEED-12)', () {
      /// Speedhunt on Sam from minute 60 to 70.
      Future<void> speedhuntOnSam(WidgetTester tester) => tester.runAsync(
        () async => FirestoreRoundRepository(db).startSpeedhunt(
          await testSession(code, 'alex'),
          Speedhunt.fromSettings(
            targetId: 'sam',
            startedAt: start.add(const Duration(minutes: 60)),
            settings: settings,
          ),
        ),
      );

      Future<void> openPlayerList(WidgetTester tester) async {
        await tester.tap(find.byKey(const Key('speedhuntButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('speedhuntPlayer')));
        await tester.pumpAndSettle();
      }

      bool canConfirm(WidgetTester tester) =>
          tester
              .widget<FilledButton>(find.byKey(const Key('confirmSpeedhunt')))
              .onPressed !=
          null;

      testWidgets('button greyed out with countdown; tapping tells how long', (
        tester,
      ) async {
        now = start.add(const Duration(minutes: 80));
        await seed(tester);
        await speedhuntOnSam(tester);
        await pumpAs(tester, 'alex');
        // Ended at minute 70 + 30 min pause.
        expect(find.text('Speedhunt (1) · 20:00'), findsOneWidget);
        final button = tester.widget<OutlinedButton>(
          find.byKey(const Key('speedhuntButton')),
        );
        expect(button.style?.foregroundColor?.resolve({}), AppColors.textMuted);
        await tester.tap(find.byKey(const Key('speedhuntButton')));
        await tester.pumpAndSettle();
        expect(
          find.text('The next speedhunt is possible in 20:00 min.'),
          findsOne,
        );
        expect(find.byKey(const Key('speedhuntPlayer')), findsNothing);
      });

      testWidgets('catching the target starts the pause right then '
          '(R-SPEED-10)', (tester) async {
        now = start.add(const Duration(minutes: 63));
        await seed(tester);
        await speedhuntOnSam(tester);
        await pumpAs(tester, 'alex');
        // Running until minute 70, then 30 min pause.
        expect(find.text('Speedhunt (1) · 37:00'), findsOneWidget);

        await tester.tap(find.byKey(const Key('catchButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('catchPlayer')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sam').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmCatch')));
        await settle(tester);

        expect(find.text('Speedhunt (1) · 30:00'), findsOneWidget);
      });

      testWidgets('same player again only after their own pause', (
        tester,
      ) async {
        const longer = GameSettings(
          area: area,
          anonymousPlayers: false,
          speedhuntRepeatCooldown: Duration(minutes: 60),
        );
        now = start.add(const Duration(minutes: 110));
        await seed(tester, gameSettings: longer);
        await speedhuntOnSam(tester);
        await pumpAs(tester, 'alex', gameSettings: longer);
        expect(find.text('Speedhunt (1)'), findsOneWidget);
        await openPlayerList(tester);
        // Sam's pause: until minute 70 + 60. It counts down in the open
        // menu, too.
        expect(find.text('Sam · 20:00'), findsWidgets);
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Sam · 19:59'), findsWidgets);
        now = now.subtract(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Sam · 20:00').last);
        await tester.pumpAndSettle();
        expect(
          find.text('A speedhunt on Sam is possible again in 20:00 min.'),
          findsOne,
        );
        expect(canConfirm(tester), isFalse);

        await tester.tap(find.byKey(const Key('speedhuntPlayer')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kim').last);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('speedhuntBlocked')), findsNothing);
        expect(canConfirm(tester), isTrue);
      });

      testWidgets('once the pause runs out in the open menu, the player is '
          'normal and can be picked', (tester) async {
        // General pause over at minute 80, Sam's only at minute 100.
        const shortPause = GameSettings(
          area: area,
          anonymousPlayers: false,
          speedhuntCooldown: Duration(minutes: 10),
        );
        now = start.add(const Duration(minutes: 99, seconds: 58));
        await seed(tester, gameSettings: shortPause);
        await speedhuntOnSam(tester);
        await pumpAs(tester, 'alex', gameSettings: shortPause);
        await openPlayerList(tester);
        expect(find.text('Sam · 00:02'), findsWidgets);
        now = start.add(const Duration(minutes: 100));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Sam · 00:02'), findsNothing);
        await tester.tap(find.text('Sam').last);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('speedhuntBlocked')), findsNothing);
        expect(canConfirm(tester), isTrue);
      });

      testWidgets('without repeats the last target is blocked', (tester) async {
        const noRepeat = GameSettings(
          area: area,
          anonymousPlayers: false,
          speedhuntRepeatTarget: false,
        );
        now = start.add(const Duration(minutes: 150));
        await seed(tester, gameSettings: noRepeat);
        await speedhuntOnSam(tester);
        await pumpAs(tester, 'alex', gameSettings: noRepeat);
        await openPlayerList(tester);
        final sam = tester.widget<Text>(find.text('Sam').last);
        expect(sam.style?.color, AppColors.textMuted);
        await tester.tap(find.text('Sam').last);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Several speedhunts in a row on the same player are not allowed.',
          ),
          findsOne,
        );
        expect(canConfirm(tester), isFalse);
      });
    });

    testWidgets('reporting a catch notifies and marks the player', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      await tester.tap(find.byKey(const Key('catchButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catchPlayer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sam').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmCatch')));
      await settle(tester);

      expect(find.text('Sam was caught'), findsOneWidget);
      final members = await tester.runAsync(
        () async =>
            FirestoreGameRepository(db)
                .watchMembers(await testSession(code, 'alex'))
                .first,
      );
      expect(members!.firstWhere((m) => m.id == 'sam').caught, isTrue);
    });

    testWidgets('overview tells hunters whom the speedhunt is on '
        '(R-OVER-04)', (tester) async {
      now = start.add(const Duration(minutes: 72));
      await seed(tester);
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).startSpeedhunt(
          await testSession(code, 'alex'),
          Speedhunt.fromSettings(
            targetId: 'sam',
            startedAt: start.add(const Duration(minutes: 70)),
            settings: settings,
          ),
        ),
      );
      await pumpAs(tester, 'alex');
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('overviewSpeedhunt')),
          matching: find.text('Speedhunt on Sam'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('catching the speedhunt target ends the speedhunt '
        '(R-SPEED-10)', (tester) async {
      now = start.add(const Duration(minutes: 72));
      await seed(tester);
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).startSpeedhunt(
          await testSession(code, 'alex'),
          Speedhunt.fromSettings(
            targetId: 'sam',
            startedAt: start.add(const Duration(minutes: 70)),
            settings: settings,
          ),
        ),
      );
      await pumpAs(tester, 'alex');
      expect(find.byKey(const Key('speedhuntBanner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('catchButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catchPlayer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sam').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmCatch')));
      await settle(tester);

      expect(find.byKey(const Key('speedhuntBanner')), findsNothing);
      final catches = await tester.runAsync(
        () async =>
            FirestoreGameRepository(db)
                .watchCatches(await testSession(code, 'kim'))
                .first,
      );
      expect(
        catches!.single.endsSpeedhunt,
        start.add(const Duration(minutes: 70)),
      );
    });

    testWidgets('catching someone else keeps the speedhunt (R-SPEED-10)', (
      tester,
    ) async {
      now = start.add(const Duration(minutes: 72));
      await seed(tester);
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).startSpeedhunt(
          await testSession(code, 'alex'),
          Speedhunt.fromSettings(
            targetId: 'sam',
            startedAt: start.add(const Duration(minutes: 70)),
            settings: settings,
          ),
        ),
      );
      await pumpAs(tester, 'alex');
      await tester.tap(find.byKey(const Key('catchButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catchPlayer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kim').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmCatch')));
      await settle(tester);

      expect(find.byKey(const Key('speedhuntBanner')), findsOneWidget);
    });

    testWidgets('each player has an own pin colour (R-HUNT-03)', (
      tester,
    ) async {
      await seed(tester);
      await tester.runAsync(() async {
        final rounds = FirestoreRoundRepository(db);
        for (final (id, lat) in [('kim', 52.505), ('sam', 52.506)]) {
          await rounds.sendPing(
            await testSession(code, id),
            PingSlot(
              id: 'regular_1',
              kind: PingKind.regular,
              at: start.add(const Duration(minutes: 20)),
            ),
            LocationFix(
              point: GeoPoint(lat, 13.405),
              at: start.add(const Duration(minutes: 20)),
            ),
          );
        }
      });
      await pumpAs(tester, 'alex');
      Color pinColor(String id) => tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(Key('lastPing_$id')),
              matching: find.byIcon(Icons.location_on),
            ),
          )
          .color!;
      expect(pinColor('kim'), isNot(pinColor('sam')));
    });

    testWidgets('sees the last ping of each player with name (R-HUNT-03)', (
      tester,
    ) async {
      await seed(tester);
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).sendPing(
          await testSession(code, 'kim'),
          PingSlot(
            id: 'regular_1',
            kind: PingKind.regular,
            at: start.add(const Duration(minutes: 20)),
          ),
          LocationFix(
            point: const GeoPoint(52.505, 13.405),
            at: start.add(const Duration(minutes: 20)),
          ),
        ),
      );
      await pumpAs(tester, 'alex');
      expect(find.byKey(const Key('lastPing_kim')), findsOneWidget);
      expect(find.text('Kim'), findsWidgets);
    });
  });

  testWidgets('hunters are told when they see each other only every 15 s '
      '(R-QUOTA-02)', (tester) async {
    await seed(tester);
    await pumpAs(tester, 'alex', hunterLive: const Duration(seconds: 15));
    expect(
      find.text('Hunter positions every 15 s this round (Firebase quota)'),
      findsOneWidget,
    );
    await pumpAs(tester, 'alex');
    expect(find.textContaining('every 15 s this round'), findsNothing);
    await pumpAs(tester, 'kim', hunterLive: const Duration(seconds: 15));
    expect(find.textContaining('every 15 s this round'), findsNothing);
  });

  group('player (R-PLAY-*, R-PING-*)', () {
    testWidgets('sees next ping countdown and joker/self-catch buttons', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      expect(find.text('Next ping in 10:00'), findsOneWidget);
      expect(find.byKey(const Key('jokerButton')), findsOneWidget);
      expect(find.byKey(const Key('selfCatchButton')), findsOneWidget);
      expect(find.byKey(const Key('speedhuntButton')), findsNothing);
      expect(location.isTracking, isTrue);
    });

    testWidgets('"next ping" sits above the filter bar (R-MAP-01)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      expect(
        tester.getTopLeft(find.text('Next ping in 10:00')).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('filterBar'))).dy),
      );
    });

    testWidgets('hunter joker reveals hunters once (R-PLAY-02)', (
      tester,
    ) async {
      await seed(tester);
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).updateHunterLocation(
          await testSession(code, 'alex'),
          LocationFix(point: const GeoPoint(52.506, 13.406), at: now),
        ),
      );
      await pumpAs(tester, 'kim');
      await tester.tap(find.byKey(const Key('jokerButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joker_hunters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmJoker')));
      await settle(tester);

      expect(find.byKey(const Key('hunter_alex')), findsOneWidget);
      // Each pin shows the time of the position ("Alex · 14:30").
      expect(find.textContaining('Alex · '), findsOneWidget);
      // Joker result is a filter chip with the time, switched on (R-PLAY-04).
      expect(find.byKey(const Key('filter_hunterJoker')), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('filter_hunterJoker')))
            .selected,
        isTrue,
      );

      // Used up: still listed, but disabled.
      await tester.tap(find.byKey(const Key('jokerButton')));
      await tester.pumpAndSettle();
      expect(find.text('Already used'), findsOneWidget);
      final option = tester.widget<ListTile>(
        find.byKey(const Key('joker_hunters')),
      );
      expect(option.enabled, isFalse);
    });

    testWidgets('player joker shows the answers of other players '
        '(R-PLAY-03)', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      await tester.tap(find.byKey(const Key('jokerButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joker_players')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmJoker')));
      await settle(tester);
      expect(find.byKey(const Key('filter_playerJoker')), findsOneWidget);

      // Sam's device answers (its engine does this automatically).
      await tester.runAsync(() async {
        final rounds = FirestoreRoundRepository(db);
        final sam = await testSession(code, 'sam');
        final request = (await rounds.watchJokerRequests(sam).first).single;
        expect(request.requesterId, 'kim');
        await rounds.answerJokerRequest(
          sam,
          request,
          LocationFix(point: const GeoPoint(52.507, 13.407), at: now),
        );
      });
      await settle(tester);
      expect(find.byKey(const Key('player_sam')), findsOneWidget);
      expect(find.textContaining('Sam · '), findsOneWidget);
    });

    testWidgets('only enabled jokers are offered (R-SET-09, R-SET-12)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(
        tester,
        'kim',
        gameSettings: settings.copyWith(jokerEnabled: false),
      );
      await tester.tap(find.byKey(const Key('jokerButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('joker_hunters')), findsNothing);
      expect(find.byKey(const Key('joker_players')), findsOneWidget);
    });

    testWidgets('no joker button when both jokers are off', (tester) async {
      await seed(tester);
      await pumpAs(
        tester,
        'kim',
        gameSettings: settings.copyWith(
          jokerEnabled: false,
          playerJokerEnabled: false,
        ),
      );
      expect(find.byKey(const Key('jokerButton')), findsNothing);
    });

    testWidgets('status line shows GPS state (no silent failures)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      expect(find.text('Waiting for GPS signal …'), findsOneWidget);
      location.emit(
        LocationFix(point: const GeoPoint(52.505, 13.405), at: now),
      );
      await settle(tester);
      // Once GPS works, the line disappears (only problems are shown).
      expect(find.byKey(const Key('trackingStatus')), findsNothing);
    });

    testWidgets('"my location" jumps to the own position', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      location.emit(
        LocationFix(point: const GeoPoint(48.137, 11.575), at: now),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('myLocationButton')));
      await tester.pumpAndSettle();
      final camera = MapCamera.of(
        tester.element(find.byType(MarkerLayer).first),
      );
      expect(camera.center.latitude, closeTo(48.137, 1e-6));
      expect(camera.center.longitude, closeTo(11.575, 1e-6));

      await tester.tap(find.byKey(const Key('fitAreaButton')));
      await tester.pumpAndSettle();
      final back = MapCamera.of(tester.element(find.byType(MarkerLayer).first));
      expect(back.center.latitude, closeTo(52.505, 0.01));
    });

    testWidgets('missing location access is shown with a retry button', (
      tester,
    ) async {
      location.permissionGranted = false;
      await seed(tester);
      await pumpAs(tester, 'kim');
      expect(find.textContaining('No location access'), findsOneWidget);
      location.permissionGranted = true;
      await tester.tap(find.byKey(const Key('trackingRetry')));
      await settle(tester);
      expect(find.text('Waiting for GPS signal …'), findsOneWidget);
    });

    testWidgets('header shows phase + countdown, not the app name', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'kim'); // minute 30 of 3 h
      expect(find.text('HUNT IS ON'), findsOneWidget);
      expect(find.text('2:30:00'), findsOneWidget);
      expect(find.text('Manhunt'), findsNothing);
      // History is for the lobby; during the game there is the overview.
      expect(find.byKey(const Key('historyButton')), findsNothing);
      expect(find.byKey(const Key('overviewButton')), findsOneWidget);
      // North always up: no rotation gesture (R-MAP-02).
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.interactionOptions.flags & InteractiveFlag.rotate, 0);
      expect(
        map.options.interactionOptions.flags & InteractiveFlag.pinchZoom,
        isNot(0),
      );
    });

    testWidgets('overview lists hunters and players, caught struck through '
        '(R-OVER-01 … 03)', (tester) async {
      await seed(tester);
      await tester.runAsync(
        () async => FirestoreGameRepository(db).recordCatch(
          await testSession(code, 'alex'),
          CatchRecord(playerId: 'sam', at: now),
        ),
      );
      await pumpAs(tester, 'kim');
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsOneWidget);
      expect(find.textContaining('HUNTERS · 1'), findsOneWidget);
      expect(find.textContaining('1 OF 2 FREE'), findsOneWidget);
      expect(find.text('No speedhunt running'), findsOneWidget);
      final sam = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('overview_sam')),
          matching: find.text('Sam'),
        ),
      );
      expect(sam.style!.decoration, TextDecoration.lineThrough);
      final kim = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('overview_kim')),
          matching: find.text('Kim (You)'),
        ),
      );
      expect(kim.style!.decoration, isNull);
    });

    testWidgets('every player sees the speedhunt countdown, not the target '
        '(R-SPEED-05, R-SPEED-08)', (tester) async {
      now = start.add(const Duration(minutes: 72));
      await seed(tester);
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).startSpeedhunt(
          await testSession(code, 'alex'),
          Speedhunt.fromSettings(
            targetId: 'sam',
            startedAt: start.add(const Duration(minutes: 70)),
            settings: settings,
          ),
        ),
      );
      await pumpAs(tester, 'kim');
      expect(find.text('Speedhunt active · ping 2/3 in 03:00'), findsOneWidget);
      expect(find.textContaining('Sam'), findsNothing);

      // Nor in the overview (R-OVER-04).
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('overviewSpeedhunt')),
          matching: find.text('Speedhunt active'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Speedhunt on'), findsNothing);
    });

    testWidgets('players see the speedhunt end when its target is caught '
        '(R-SPEED-10)', (tester) async {
      now = start.add(const Duration(minutes: 72));
      await seed(tester);
      final startedAt = start.add(const Duration(minutes: 70));
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).startSpeedhunt(
          await testSession(code, 'alex'),
          Speedhunt.fromSettings(
            targetId: 'sam',
            startedAt: startedAt,
            settings: settings,
          ),
        ),
      );
      await pumpAs(tester, 'kim');
      expect(find.byKey(const Key('speedhuntBanner')), findsOneWidget);

      await tester.runAsync(
        () async => FirestoreGameRepository(db).recordCatch(
          await testSession(code, 'sam'),
          CatchRecord(playerId: 'sam', at: now, endsSpeedhunt: startedAt),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('speedhuntBanner')), findsNothing);
    });

    testWidgets('player banner explains the ⚡ pings and stays 15 s '
        '(R-NOTIF-06)', (tester) async {
      now = start.add(const Duration(minutes: 72));
      await seed(tester);
      await pumpAs(tester, 'kim');
      await settle(tester);
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).startSpeedhunt(
          await testSession(code, 'alex'),
          Speedhunt.fromSettings(
            targetId: 'sam',
            startedAt: start.add(const Duration(minutes: 71)),
            settings: settings,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Speedhunt started!'), findsOneWidget);
      expect(find.textContaining('Nobody knows whom'), findsOneWidget);
      expect(
        notifications.shown.last.body,
        contains("that doesn't mean it's you"),
      );
      await tester.pump(const Duration(seconds: 14));
      expect(find.text('Speedhunt started!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Speedhunt started!'), findsNothing);
    });

    testWidgets('caught players get no speedhunt notice (R-NOTIF-07)', (
      tester,
    ) async {
      now = start.add(const Duration(minutes: 72));
      await seed(tester);
      await tester.runAsync(
        () async => FirestoreGameRepository(db).recordCatch(
          await testSession(code, 'alex'),
          CatchRecord(playerId: 'kim', at: now),
        ),
      );
      await pumpAs(tester, 'kim');
      await tester.tap(find.byKey(const Key('liveViewOk')));
      await settle(tester);
      final shownBefore = notifications.shown.length;
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).startSpeedhunt(
          await testSession(code, 'alex'),
          Speedhunt.fromSettings(
            targetId: 'sam',
            startedAt: start.add(const Duration(minutes: 71)),
            settings: settings,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Speedhunt started!'), findsNothing);
      expect(
        notifications.shown.skip(shownBefore).map((n) => n.title),
        isNot(contains('Speedhunt started!')),
      );
      await tester.pump(const Duration(seconds: 16));
    });

    for (final who in ['kim', 'alex']) {
      testWidgets('$who: below the filters the same gap as above them: '
          '"next ping(s)" (R-MAP-01, R-HUNT-10)', (tester) async {
        now = start.add(const Duration(minutes: 72));
        await seed(tester);
        await tester.runAsync(
          () async => FirestoreRoundRepository(db).startSpeedhunt(
            await testSession(code, 'alex'),
            Speedhunt.fromSettings(
              targetId: 'sam',
              startedAt: start.add(const Duration(minutes: 70)),
              settings: settings,
            ),
          ),
        );
        await pumpAs(tester, who);
        // The visible chip, without its invisible tap-target margin.
        final chip = tester.getRect(
          find
              .descendant(
                of: find.byType(FilterChip).first,
                matching: find.byType(Material),
              )
              .first,
        );
        final above = tester
            .getRect(
              find
                  .ancestor(
                    of: find.textContaining('Next ping'),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .bottom;
        final gapAbove = chip.top - above;
        double gapTo(Finder below) => tester.getRect(below).top - chip.bottom;

        // GPS still waiting: the status line follows the filters …
        expect(
          gapTo(find.byKey(const Key('trackingStatus'))),
          gapAbove,
          reason: who,
        );
        // … once GPS works, the speedhunt banner takes its place.
        location.emit(
          LocationFix(point: const GeoPoint(52.505, 13.405), at: now),
        );
        await settle(tester);
        expect(find.byKey(const Key('trackingStatus')), findsNothing);
        expect(
          gapTo(find.byKey(const Key('speedhuntBanner'))),
          gapAbove,
          reason: who,
        );
      });
    }

    testWidgets('self catch stops sharing the location (R-CATCH-01)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      await tester.tap(find.byKey(const Key('selfCatchButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmSelfCatch')));
      await settle(tester);

      // First the warning about the live view (R-GM-08).
      expect(find.byKey(const Key('liveViewDialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('liveViewOk')));
      await settle(tester);
      // The header says it instead of an info line (R-CATCH-06).
      expect(find.text('CAUGHT'), findsOneWidget);
      expect(find.byKey(const Key('gameCountdown')), findsOneWidget);
      expect(find.textContaining('You were caught'), findsNothing);
      expect(find.text('Kim was caught'), findsOneWidget);
      expect(find.byKey(const Key('selfCatchButton')), findsNothing);
      expect(location.isTracking, isFalse);
    });
  });

  group('map filters (phase 6)', () {
    /// Sends a ping of [player] (regular or speedhunt) [minute] after start.
    Future<void> ping(
      WidgetTester tester,
      String player,
      String slot,
      double lat,
      int minute, {
      PingKind kind = PingKind.regular,
    }) => tester.runAsync(
      () async => FirestoreRoundRepository(db).sendPing(
        await testSession(code, player),
        PingSlot(
          id: slot,
          kind: kind,
          at: start.add(Duration(minutes: minute)),
        ),
        LocationFix(
          point: GeoPoint(lat, 13.405),
          at: start.add(Duration(minutes: minute)),
        ),
      ),
    );

    Future<void> tapFilter(WidgetTester tester, String id) async {
      await tester.ensureVisible(find.byKey(Key('filter_$id')));
      await tester.tap(find.byKey(Key('filter_$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('hunters get filter chips incl. one per player (R-HUNT-01)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      for (final id in ['hunters', 'lastPings', 'player_kim', 'player_sam']) {
        expect(find.byKey(Key('filter_$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const Key('filter_myPings')), findsNothing);
      // No "lines" chip any more (the player chip does it, R-HUNT-05) and
      // speedhunt chips only once there is a speedhunt (R-HUNT-07).
      expect(find.byKey(const Key('filter_lines')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('filter_speedhunt'),
        ),
        findsNothing,
      );
    });

    testWidgets('"last pings" can be switched off and on (R-HUNT-03)', (
      tester,
    ) async {
      await seed(tester);
      await ping(tester, 'kim', 'regular_1', 52.505, 20);
      await pumpAs(tester, 'alex');
      expect(find.byKey(const Key('lastPing_kim')), findsOneWidget);
      await tapFilter(tester, 'lastPings');
      expect(find.byKey(const Key('lastPing_kim')), findsNothing);
      await tapFilter(tester, 'lastPings');
      expect(find.byKey(const Key('lastPing_kim')), findsOneWidget);
    });

    testWidgets('new regular pings switch "last pings" back on (R-HUNT-08)', (
      tester,
    ) async {
      await seed(tester);
      await ping(tester, 'kim', 'regular_1', 52.505, 20);
      await pumpAs(tester, 'alex');
      await tapFilter(tester, 'lastPings');
      expect(find.byKey(const Key('lastPing_kim')), findsNothing);

      // A speedhunt ping does not switch it on …
      await ping(
        tester,
        'sam',
        'speedhunt_1791228604799_1',
        52.501,
        30,
        kind: PingKind.speedhunt,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filterCheck_lastPings')), findsNothing);

      // … a regular one does.
      await ping(tester, 'sam', 'regular_2', 52.502, 40);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filterCheck_lastPings')), findsOneWidget);
      expect(find.byKey(const Key('lastPing_sam')), findsOneWidget);
    });

    testWidgets('"last pings" ignore speedhunt pings (R-HUNT-03)', (
      tester,
    ) async {
      await seed(tester);
      await ping(tester, 'kim', 'regular_1', 52.505, 20);
      await ping(
        tester,
        'kim',
        'speedhunt_1791228604799_1',
        52.509,
        70,
        kind: PingKind.speedhunt,
      );
      await ping(
        tester,
        'sam',
        'speedhunt_1791228604799_1',
        52.501,
        70,
        kind: PingKind.speedhunt,
      );
      await pumpAs(tester, 'alex');
      final kim = tester
          .widgetList<MarkerLayer>(find.byType(MarkerLayer))
          .expand((l) => l.markers)
          .singleWhere((m) => m.key == const Key('lastPing_kim'));
      expect(kim.point.latitude, 52.505);
      expect(find.byKey(const Key('lastPing_sam')), findsNothing);
    });

    testWidgets('chips are dark; selected ones get a check mark (R-HUNT-01)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      final chip = tester.widget<FilterChip>(
        find.byKey(const Key('filter_lastPings')),
      );
      expect(chip.selectedColor, chip.backgroundColor);
      expect(find.byKey(const Key('filterCheck_lastPings')), findsOneWidget);
      expect(find.byKey(const Key('filterCheck_player_kim')), findsNothing);
      await tapFilter(tester, 'lastPings');
      expect(find.byKey(const Key('filterCheck_lastPings')), findsNothing);
    });

    testWidgets('player chip cycles: history → with lines → off '
        '(R-HUNT-04, R-HUNT-05)', (tester) async {
      await seed(tester);
      await ping(tester, 'kim', 'regular_1', 52.501, 20);
      await ping(tester, 'kim', 'regular_2', 52.503, 40);
      await ping(tester, 'kim', 'regular_3', 52.506, 60);
      await pumpAs(tester, 'alex');
      Finder lineIcon() => find.descendant(
        of: find.byKey(const Key('filter_player_kim')),
        matching: find.byIcon(Icons.timeline),
      );
      expect(find.byKey(const Key('history_kim_1')), findsNothing);

      // 1st tap: numbered points only.
      await tapFilter(tester, 'player_kim');
      expect(find.byKey(const Key('history_kim_1')), findsOneWidget);
      expect(find.byKey(const Key('history_kim_3')), findsOneWidget);
      expect(find.byKey(const Key('arrow_kim_0')), findsNothing);
      expect(lineIcon(), findsNothing);
      // The last ping is part of the history – no duplicate pin.
      expect(find.byKey(const Key('lastPing_kim')), findsNothing);

      // 2nd tap: with lines and arrows; the chip shows a line icon.
      await tapFilter(tester, 'player_kim');
      expect(find.byKey(const Key('history_kim_1')), findsOneWidget);
      expect(find.byKey(const Key('arrow_kim_0')), findsOneWidget);
      expect(find.byKey(const Key('arrow_kim_1')), findsOneWidget);
      expect(lineIcon(), findsOneWidget);

      // 3rd tap: off.
      await tapFilter(tester, 'player_kim');
      expect(find.byKey(const Key('history_kim_1')), findsNothing);
      expect(find.byKey(const Key('arrow_kim_0')), findsNothing);
      expect(lineIcon(), findsNothing);
      expect(find.byKey(const Key('filterCheck_player_kim')), findsNothing);
      expect(find.byKey(const Key('lastPing_kim')), findsOneWidget);
    });

    testWidgets('history numbers only regular pings, speedhunt pings stay '
        'separate (R-HUNT-04, R-HUNT-07)', (tester) async {
      await seed(tester);
      final sh = start.add(const Duration(minutes: 25)).millisecondsSinceEpoch;
      await ping(
        tester,
        'kim',
        'speedhunt_${sh}_1',
        52.5011,
        25,
        kind: PingKind.speedhunt,
      );
      await ping(
        tester,
        'kim',
        'speedhunt_${sh}_2',
        52.5012,
        30,
        kind: PingKind.speedhunt,
      );
      await ping(tester, 'kim', 'regular_1', 52.503, 40);
      await ping(tester, 'kim', 'regular_2', 52.506, 60);
      await pumpAs(tester, 'alex');
      await tapFilter(tester, 'player_kim');
      await tapFilter(tester, 'player_kim');

      Marker marker(String key) => tester
          .widgetList<MarkerLayer>(find.byType(MarkerLayer))
          .expand((l) => l.markers)
          .singleWhere((m) => m.key == Key(key));
      // Same numbers as on the player's phone: 1 and 2 are the regular pings.
      expect(marker('history_kim_1').point.latitude, 52.503);
      expect(marker('history_kim_2').point.latitude, 52.506);
      expect(find.byKey(const Key('history_kim_3')), findsNothing);
      // Lines connect the regular pings only: one arrow between 1 and 2.
      expect(find.byKey(const Key('arrow_kim_0')), findsOneWidget);
      expect(find.byKey(const Key('arrow_kim_1')), findsNothing);
      // The speedhunt pings are still shown with their own numbering.
      expect(find.text('⚡1'), findsOneWidget);
      expect(find.text('⚡2 Kim'), findsOneWidget);
    });

    testWidgets('one chip per speedhunt with name and start time, '
        'toggleable on its own (R-HUNT-07)', (tester) async {
      await seed(tester);
      final first = start.add(const Duration(minutes: 70));
      final second = start.add(const Duration(minutes: 100));
      for (final (i, lat) in [52.501, 52.502, 52.503].indexed) {
        await ping(
          tester,
          'sam',
          'speedhunt_${first.millisecondsSinceEpoch}_${i + 1}',
          lat,
          70 + i * 5,
          kind: PingKind.speedhunt,
        );
      }
      await ping(
        tester,
        'kim',
        'speedhunt_${second.millisecondsSinceEpoch}_1',
        52.507,
        100,
        kind: PingKind.speedhunt,
      );
      await pumpAs(tester, 'alex');
      final samChip = 'speedhunt_sam_${first.millisecondsSinceEpoch}';
      final kimChip = 'speedhunt_kim_${second.millisecondsSinceEpoch}';
      final hm = DateFormat.Hm('en');
      expect(
        find.descendant(
          of: find.byKey(Key('filter_$samChip')),
          matching: find.text('Sam ${hm.format(first.toLocal())}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(Key('filter_$kimChip')),
          matching: find.text('Kim ${hm.format(second.toLocal())}'),
        ),
        findsOneWidget,
      );
      // Oldest speedhunt first.
      expect(
        tester.getRect(find.byKey(Key('filter_$samChip'))).left,
        lessThan(tester.getRect(find.byKey(Key('filter_$kimChip'))).left),
      );

      expect(find.text('⚡1'), findsOneWidget);
      expect(find.text('⚡2'), findsOneWidget);
      // The latest one also carries the player's name.
      expect(find.text('⚡3 Sam'), findsOneWidget);
      expect(find.text('⚡1 Kim'), findsOneWidget);
      // No yellow badge – the bolt would vanish on it.
      final badge = tester.widget<Container>(
        find.ancestor(of: find.text('⚡1'), matching: find.byType(Container)),
      );
      expect(
        (badge.decoration! as BoxDecoration).color,
        isNot(AppColors.speedhunt),
      );

      // Sam's speedhunt off: Kim's stays.
      await tapFilter(tester, samChip);
      expect(find.text('⚡3 Sam'), findsNothing);
      expect(find.text('⚡1'), findsNothing);
      expect(find.text('⚡1 Kim'), findsOneWidget);
      await tapFilter(tester, samChip);
      expect(find.text('⚡3 Sam'), findsOneWidget);
    });

    testWidgets('a new speedhunt ping switches its chip back on (R-HUNT-08)', (
      tester,
    ) async {
      await seed(tester);
      final sh = start.add(const Duration(minutes: 70)).millisecondsSinceEpoch;
      await ping(
        tester,
        'sam',
        'speedhunt_${sh}_1',
        52.501,
        70,
        kind: PingKind.speedhunt,
      );
      await pumpAs(tester, 'alex');
      final chip = 'speedhunt_sam_$sh';
      await tapFilter(tester, chip);
      expect(find.byKey(Key('filterCheck_$chip')), findsNothing);
      expect(find.text('⚡1 Sam'), findsNothing);

      // A regular ping does not switch it on …
      await ping(tester, 'sam', 'regular_4', 52.502, 80);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('filterCheck_$chip')), findsNothing);

      // … the next ping of the speedhunt does.
      await ping(
        tester,
        'sam',
        'speedhunt_${sh}_2',
        52.503,
        75,
        kind: PingKind.speedhunt,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(Key('filterCheck_$chip')), findsOneWidget);
      expect(find.text('⚡2 Sam'), findsOneWidget);
    });

    testWidgets('caught players lose their chips; one "caught" chip shows '
        'their history and speedhunt pings (R-HUNT-09)', (tester) async {
      await seed(tester);
      final sh = start.add(const Duration(minutes: 70)).millisecondsSinceEpoch;
      await ping(tester, 'sam', 'regular_1', 52.501, 20);
      await ping(tester, 'sam', 'regular_2', 52.502, 40);
      await ping(
        tester,
        'sam',
        'speedhunt_${sh}_1',
        52.503,
        70,
        kind: PingKind.speedhunt,
      );
      await ping(tester, 'kim', 'regular_1', 52.506, 20);
      await pumpAs(tester, 'alex');
      expect(find.byKey(const Key('filter_caught')), findsNothing);
      expect(find.byKey(Key('filter_speedhunt_sam_$sh')), findsOneWidget);
      // Sam's history was on before the catch – it must not stay on.
      await tapFilter(tester, 'player_sam');
      expect(find.byKey(const Key('history_sam_1')), findsOneWidget);

      await tester.runAsync(
        () async => FirestoreGameRepository(db).recordCatch(
          await testSession(code, 'alex'),
          CatchRecord(
            playerId: 'sam',
            at: start.add(const Duration(minutes: 80)),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const Key('filter_player_sam')), findsNothing);
      expect(find.byKey(Key('filter_speedhunt_sam_$sh')), findsNothing);
      expect(find.byKey(const Key('filter_player_kim')), findsOneWidget);
      // The chip starts off: no history, no speedhunt pings of Sam.
      expect(find.byKey(const Key('filterCheck_caught')), findsNothing);
      expect(find.byKey(const Key('history_sam_1')), findsNothing);
      expect(find.text('⚡1 Sam'), findsNothing);

      // Nothing switches it on by itself (unlike R-HUNT-08): not new regular
      // pings, not a late speedhunt ping of Sam, not another catch.
      await ping(tester, 'kim', 'regular_2', 52.507, 85);
      await ping(
        tester,
        'sam',
        'speedhunt_${sh}_2',
        52.504,
        75,
        kind: PingKind.speedhunt,
      );
      await tester.runAsync(
        () async => FirestoreGameRepository(db).recordCatch(
          await testSession(code, 'alex'),
          CatchRecord(
            playerId: 'kim',
            at: start.add(const Duration(minutes: 90)),
          ),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('filterCheck_caught')), findsNothing);
      expect(find.byKey(const Key('history_sam_1')), findsNothing);
      expect(find.byKey(const Key('history_kim_1')), findsNothing);
      expect(find.text('⚡2 Sam'), findsNothing);
      expect(find.byKey(const Key('filter_player_kim')), findsNothing);

      await tapFilter(tester, 'caught');
      expect(find.byKey(const Key('history_sam_1')), findsOneWidget);
      expect(find.byKey(const Key('history_sam_2')), findsOneWidget);
      expect(find.text('⚡1'), findsOneWidget);
      expect(find.text('⚡2 Sam'), findsOneWidget);
      // Kim is caught now too.
      expect(find.byKey(const Key('history_kim_2')), findsOneWidget);
      // The last ping is part of the history – no duplicate pin.
      expect(find.byKey(const Key('lastPing_sam')), findsNothing);

      await tapFilter(tester, 'caught');
      expect(find.byKey(const Key('history_sam_1')), findsNothing);
      expect(find.text('⚡2 Sam'), findsNothing);
      // Caught players appear only under "caught", not under "last pings".
      expect(find.byKey(const Key('filterCheck_lastPings')), findsOneWidget);
      expect(find.byKey(const Key('lastPing_sam')), findsNothing);
    });

    testWidgets('a caught player\'s ping leaves "last pings" right away '
        '(R-HUNT-03, R-HUNT-09)', (tester) async {
      await seed(tester);
      await ping(tester, 'sam', 'regular_1', 52.501, 20);
      await ping(tester, 'kim', 'regular_1', 52.506, 20);
      await pumpAs(tester, 'alex');
      expect(find.byKey(const Key('lastPing_sam')), findsOneWidget);
      await tester.runAsync(
        () async => FirestoreGameRepository(db).recordCatch(
          await testSession(code, 'alex'),
          CatchRecord(playerId: 'sam', at: now),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('lastPing_sam')), findsNothing);
      expect(find.byKey(const Key('lastPing_kim')), findsOneWidget);
    });

    testWidgets('time up, not ended yet: caught players are split up again '
        '(R-HUNT-11)', (tester) async {
      final sh = start.add(const Duration(minutes: 70)).millisecondsSinceEpoch;
      await seed(tester);
      await ping(tester, 'sam', 'regular_1', 52.501, 20);
      await ping(
        tester,
        'sam',
        'speedhunt_${sh}_1',
        52.503,
        70,
        kind: PingKind.speedhunt,
      );
      await tester.runAsync(
        () async => FirestoreGameRepository(db).recordCatch(
          await testSession(code, 'alex'),
          CatchRecord(
            playerId: 'sam',
            at: start.add(const Duration(minutes: 80)),
          ),
        ),
      );
      now = start.add(settings.duration + const Duration(seconds: 30));
      // Someone confirmed who else was caught (R-GAME-11).
      await pumpAs(tester, 'alex', confirmedAt: now);

      expect(find.byKey(const Key('filter_caught')), findsNothing);
      expect(find.byKey(const Key('filter_player_sam')), findsOneWidget);
      expect(find.byKey(Key('filter_speedhunt_sam_$sh')), findsOneWidget);
      expect(find.text('⚡1 Sam'), findsOneWidget);
      // Back under "last pings", in Sam's colour, not grey.
      expect(find.byKey(const Key('lastPing_sam')), findsOneWidget);
      final pin = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('lastPing_sam')),
          matching: find.byIcon(Icons.location_on),
        ),
      );
      expect(pin.color, isNot(AppColors.textMuted));
      await tapFilter(tester, 'player_sam');
      expect(find.byKey(const Key('history_sam_1')), findsOneWidget);
    });

    group('speedhunt chips for players (R-SPEED-09)', () {
      Future<int> startSpeedhunt(
        WidgetTester tester, {
        Duration delay = Duration.zero,
      }) async {
        final startedAt = start.add(const Duration(minutes: 70));
        await tester.runAsync(
          () async => FirestoreRoundRepository(db).startSpeedhunt(
            await testSession(code, 'alex'),
            Speedhunt.fromSettings(
              targetId: 'sam',
              startedAt: startedAt,
              settings: settings.copyWith(speedhuntFirstDelay: delay),
            ),
          ),
        );
        return startedAt.millisecondsSinceEpoch;
      }

      /// Lets the engine tick (every 5 s) at the current [now].
      Future<void> tick(WidgetTester tester) async {
        await tester.pump(const Duration(seconds: 5));
        await settle(tester);
      }

      for (final who in ['kim', 'sam']) {
        testWidgets('$who sees own ⚡ pings under "⚡ time", target or not; '
            'hidden until the next ping switches the chip on', (tester) async {
          now = start.add(const Duration(minutes: 70, seconds: 30));
          location.position = const GeoPoint(52.505, 13.405);
          await seed(tester);
          final sh = await startSpeedhunt(tester);
          await pumpAs(tester, who);
          await tick(tester);
          final id = '${who}_$sh';
          final chip = find.byKey(Key('filter_speedhunt_$id'));
          expect(chip, findsOneWidget);
          final time = DateFormat.Hm('en')
              .format(DateTime.fromMillisecondsSinceEpoch(sh));
          expect(
            find.descendant(of: chip, matching: find.text(time)),
            findsOneWidget,
          );
          // No target name on the chip.
          expect(
            find.descendant(of: chip, matching: find.textContaining('Sam')),
            findsNothing,
          );
          final name = who == 'kim' ? 'Kim' : 'Sam';
          expect(find.text('⚡1 $name'), findsOneWidget);
          expect(find.byKey(Key('filterCheck_speedhunt_$id')), findsOneWidget);

          // Hidden with the chip …
          await tapFilter(tester, 'speedhunt_$id');
          expect(find.text('⚡1 $name'), findsNothing);
          expect(find.byKey(Key('filterCheck_speedhunt_$id')), findsNothing);

          // … until the next ping: chip on, all its pings shown again.
          now = start.add(const Duration(minutes: 75, seconds: 1));
          location.position = const GeoPoint(52.507, 13.405);
          await tick(tester);
          expect(find.byKey(Key('filterCheck_speedhunt_$id')), findsOneWidget);
          expect(find.text('⚡1'), findsOneWidget);
          expect(find.text('⚡2 $name'), findsOneWidget);
        });
      }

      testWidgets('chip appears with the first ping, like for the hunters; '
          'own ⚡ pings survive an app restart', (tester) async {
        now = start.add(const Duration(minutes: 71));
        location.position = const GeoPoint(52.505, 13.405);
        await seed(tester);
        final sh = await startSpeedhunt(
          tester,
          delay: const Duration(minutes: 2),
        );
        await pumpAs(tester, 'kim');
        expect(find.byKey(Key('filter_speedhunt_kim_$sh')), findsNothing);
        now = start.add(const Duration(minutes: 72));
        await tick(tester);
        expect(find.byKey(Key('filter_speedhunt_kim_$sh')), findsOneWidget);
        expect(find.text('⚡1 Kim'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        location.position = null; // no new position needed
        await pumpAs(tester, 'kim');
        expect(find.text('⚡1 Kim'), findsOneWidget);
      });

      testWidgets('hunters still see only the target\'s pings', (tester) async {
        now = start.add(const Duration(minutes: 70, seconds: 30));
        location.position = const GeoPoint(52.505, 13.405);
        await seed(tester);
        await startSpeedhunt(tester);
        await pumpAs(tester, 'alex');
        await tick(tester);
        expect(find.textContaining('⚡1'), findsNothing);
      });
    });

    group('regular pings to all players (R-PLAY-05)', () {
      const shared = GameSettings(area: area, sharedPings: true);

      testWidgets('without the setting players get no such chip', (
        tester,
      ) async {
        await seed(tester);
        await pumpAs(tester, 'kim');
        expect(find.byKey(const Key('filter_sharedPings')), findsNothing);
      });

      testWidgets('players see only the latest regular ping of the others; '
          'caught ones grey until newer pings', (tester) async {
        await seed(tester);
        await ping(tester, 'kim', 'regular_1', 52.506, 20);
        await ping(tester, 'sam', 'regular_1', 52.501, 20);
        await ping(tester, 'sam', 'regular_2', 52.502, 40);
        await ping(
          tester,
          'sam',
          'speedhunt_1791228604799_1',
          52.509,
          45,
          kind: PingKind.speedhunt,
        );
        await pumpAs(tester, 'kim', gameSettings: shared);
        expect(
          find.byKey(const Key('filterCheck_sharedPings')),
          findsOneWidget,
        );
        Marker marker(String key) => tester
            .widgetList<MarkerLayer>(find.byType(MarkerLayer))
            .expand((l) => l.markers)
            .singleWhere((m) => m.key == Key(key));
        // Latest regular ping only – no history, no speedhunt ping.
        expect(marker('lastPing_sam').point.latitude, 52.502);
        expect(find.text('⚡1 Sam'), findsNothing);
        // The own ping is under "my pings".
        expect(find.byKey(const Key('lastPing_kim')), findsNothing);

        await tester.runAsync(
          () async => FirestoreGameRepository(db).recordCatch(
            await testSession(code, 'sam'),
            CatchRecord(playerId: 'sam', at: now),
          ),
        );
        await settle(tester);
        final pin = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('lastPing_sam')),
            matching: find.byIcon(Icons.location_on),
          ),
        );
        expect(pin.color, AppColors.textMuted);

        // Can be switched off; new pings switch it back on (like R-HUNT-08).
        await tapFilter(tester, 'sharedPings');
        expect(find.byKey(const Key('lastPing_sam')), findsNothing);
        await ping(tester, 'kim', 'regular_3', 52.507, 60);
        await settle(tester);
        expect(
          find.byKey(const Key('filterCheck_sharedPings')),
          findsOneWidget,
        );
        // Newer pings exist: the caught player's old pin is gone.
        expect(find.byKey(const Key('lastPing_sam')), findsNothing);
      });

      testWidgets('switched off: another player\'s new ping switches the '
          'chip back on and shows it (R-PLAY-05)', (tester) async {
        await seed(tester);
        await ping(tester, 'sam', 'regular_1', 52.501, 20);
        await pumpAs(tester, 'kim', gameSettings: shared);
        await tapFilter(tester, 'sharedPings');
        expect(find.byKey(const Key('filterCheck_sharedPings')), findsNothing);
        expect(find.byKey(const Key('lastPing_sam')), findsNothing);

        await ping(tester, 'sam', 'regular_2', 52.502, 40);
        await settle(tester);
        expect(
          find.byKey(const Key('filterCheck_sharedPings')),
          findsOneWidget,
        );
        final sam = tester
            .widgetList<MarkerLayer>(find.byType(MarkerLayer))
            .expand((l) => l.markers)
            .singleWhere((m) => m.key == const Key('lastPing_sam'));
        expect(sam.point.latitude, 52.502);
      });

      testWidgets('replaces the player joker (R-SET-15)', (tester) async {
        await seed(tester);
        await pumpAs(tester, 'kim', gameSettings: shared);
        await tester.tap(find.byKey(const Key('jokerButton')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('joker_players')), findsNothing);
        expect(find.byKey(const Key('joker_hunters')), findsOneWidget);
      });
    });

    testWidgets('map can switch to satellite images and back (R-MAP-03)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      expect(find.byIcon(Icons.satellite_alt), findsOneWidget);
      await tester.tap(find.byKey(const Key('mapStyleButton')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      expect(MapStyle.satellite.tileUrl, contains('/hybrid/'));
      await tester.tap(find.byKey(const Key('mapStyleButton')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.satellite_alt), findsOneWidget);
    });

    testWidgets('player: own pings can be hidden (R-PLAY-01)', (tester) async {
      await seed(tester);
      await ping(tester, 'kim', 'regular_1', 52.505, 20);
      await pumpAs(tester, 'kim');
      expect(find.byKey(const Key('history_1')), findsOneWidget);
      await tapFilter(tester, 'myPings');
      expect(find.byKey(const Key('history_1')), findsNothing);
    });

    testWidgets('joker result: chip on after use, toggleable, kept after an '
        'app restart (R-PLAY-04)', (tester) async {
      await seed(tester);
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).updateHunterLocation(
          await testSession(code, 'alex'),
          LocationFix(point: const GeoPoint(52.506, 13.406), at: now),
        ),
      );
      await pumpAs(tester, 'kim');
      expect(find.byKey(const Key('filter_hunterJoker')), findsNothing);
      await tester.tap(find.byKey(const Key('jokerButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joker_hunters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmJoker')));
      await settle(tester);
      expect(find.byKey(const Key('hunter_alex')), findsOneWidget);

      await tapFilter(tester, 'hunterJoker');
      expect(find.byKey(const Key('hunter_alex')), findsNothing);
      await tapFilter(tester, 'hunterJoker');
      expect(find.byKey(const Key('hunter_alex')), findsOneWidget);

      // "Restart": a fresh app, same device storage.
      await tester.pumpWidget(const SizedBox());
      await pumpAs(tester, 'kim');
      expect(find.byKey(const Key('filter_hunterJoker')), findsOneWidget);
      expect(find.byKey(const Key('hunter_alex')), findsOneWidget);
    });

    group('anonymous players (R-ANON-01 … R-ANON-04)', () {
      // Default: anonymous (R-SET-16).
      const anon = GameSettings(area: area);

      /// Numbers shuffled by the host at the start.
      Future<Map<String, int>> aliases(WidgetTester tester) async =>
          (await tester.runAsync(
            () async =>
                FirestoreGameRepository(db)
                    .watchGame(await testSession(code, 'alex'))
                    .first,
          ))!.aliases;

      Finder label(String key, String text) =>
          find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

      testWidgets('the overview names the speedhunt target by number '
          '(R-OVER-04)', (tester) async {
        now = start.add(const Duration(minutes: 72));
        await seed(tester, gameSettings: anon);
        final numbers = await aliases(tester);
        await tester.runAsync(
          () async => FirestoreRoundRepository(db).startSpeedhunt(
            await testSession(code, 'alex'),
            Speedhunt.fromSettings(
              targetId: 'sam',
              startedAt: start.add(const Duration(minutes: 70)),
              settings: anon,
            ),
          ),
        );
        await pumpAs(tester, 'alex', gameSettings: anon);
        await tester.tap(find.byKey(const Key('overviewButton')));
        await tester.pumpAndSettle();

        expect(
          label('overviewSpeedhunt', 'Speedhunt on Player ${numbers['sam']}'),
          findsOneWidget,
        );
      });

      testWidgets('hunters see "Player n" on pins and chips, ordered and '
          'coloured by number (R-ANON-01)', (tester) async {
        final sh = start
            .add(const Duration(minutes: 70))
            .millisecondsSinceEpoch;
        await seed(tester, gameSettings: anon);
        final numbers = await aliases(tester);
        expect(numbers.keys, unorderedEquals(['kim', 'sam']));
        expect(numbers.values, unorderedEquals([1, 2]));
        final kim = 'Player ${numbers['kim']}';
        final sam = 'Player ${numbers['sam']}';
        await ping(tester, 'kim', 'regular_1', 52.505, 20);
        await ping(tester, 'sam', 'regular_1', 52.506, 20);
        await ping(
          tester,
          'sam',
          'speedhunt_${sh}_1',
          52.503,
          70,
          kind: PingKind.speedhunt,
        );
        await pumpAs(tester, 'alex', gameSettings: anon);

        expect(label('lastPing_kim', kim), findsOneWidget);
        expect(label('lastPing_sam', sam), findsOneWidget);
        expect(label('filter_player_kim', kim), findsOneWidget);
        expect(label('filter_player_sam', sam), findsOneWidget);
        expect(find.text('⚡1 $sam'), findsOneWidget);
        final hm = DateFormat.Hm('en');
        expect(
          label(
            'filter_speedhunt_sam_$sh',
            '$sam ${hm.format(DateTime.fromMillisecondsSinceEpoch(sh))}',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Kim'), findsNothing);
        expect(find.textContaining('Sam'), findsNothing);
        // The hunters' own names stay.
        expect(label('filter_hunters', 'Hunters'), findsOneWidget);

        // Player 1 first and in the first colour – the join order (Kim
        // before Sam) gives nobody away.
        final first = numbers['kim'] == 1 ? 'kim' : 'sam';
        final second = first == 'kim' ? 'sam' : 'kim';
        expect(
          tester.getRect(find.byKey(Key('filter_player_$first'))).left,
          lessThan(
            tester.getRect(find.byKey(Key('filter_player_$second'))).left,
          ),
        );
        final pin = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(Key('lastPing_$first')),
            matching: find.byIcon(Icons.location_on),
          ),
        );
        expect(pin.color, AppColors.playerPalette[0]);
      });

      testWidgets('speedhunt is picked by number (R-ANON-01)', (tester) async {
        now = start.add(const Duration(minutes: 70)); // after R-SET-11
        await seed(tester, gameSettings: anon);
        final numbers = await aliases(tester);
        await pumpAs(tester, 'alex', gameSettings: anon);
        await tester.tap(find.byKey(const Key('speedhuntButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('speedhuntPlayer')));
        await tester.pumpAndSettle();
        expect(find.text('Kim'), findsNothing);
        expect(find.text('Sam'), findsNothing);
        await tester.tap(find.text('Player ${numbers['sam']}').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmSpeedhunt')));
        await settle(tester);

        final targets = await tester.runAsync(
          () => db
              .collection('games')
              .get()
              .then(
                (games) => games.docs.single.reference
                    .collection('speedhuntTargets')
                    .get(),
              ),
        );
        expect(targets!.docs.single.data()['uid'], 'sam');
      });

      testWidgets('catch is reported by real name and announced with it; '
          'the caught player stays anonymous under "caught" (R-ANON-01)', (
        tester,
      ) async {
        await seed(tester, gameSettings: anon);
        final sam = 'Player ${(await aliases(tester))['sam']}';
        await ping(tester, 'sam', 'regular_1', 52.506, 20);
        await pumpAs(tester, 'alex', gameSettings: anon);
        await tester.tap(find.byKey(const Key('catchButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('catchPlayer')));
        await tester.pumpAndSettle();
        // The hunter knows whom they caught: real names in the list.
        Finder item(String text) => find.descendant(
          of: find.byType(DropdownMenuItem<String>),
          matching: find.text(text),
        );
        expect(item('Sam'), findsWidgets);
        expect(item(sam), findsNothing);
        await tester.tap(find.text('Sam').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmCatch')));
        await settle(tester);

        expect(find.text('Sam was caught'), findsOneWidget);
        expect(notifications.shown.single.title, 'Sam was caught');
        expect(find.byKey(const Key('filter_player_sam')), findsNothing);
        await tapFilter(tester, 'caught');
        expect(find.byKey(const Key('history_sam_1')), findsOneWidget);
        expect(find.text('Sam'), findsNothing);
      });

      testWidgets('hunters are told by real name when a catch is undone '
          '(R-CATCH-05)', (tester) async {
        await seed(tester, gameSettings: anon);
        final games = FirestoreGameRepository(db);
        final alex = (await tester.runAsync(() => testSession(code, 'alex')))!;
        await tester.runAsync(
          () =>
              games.recordCatch(alex, CatchRecord(playerId: 'sam', at: start)),
        );
        await pumpAs(tester, 'alex', gameSettings: anon);
        await tester.runAsync(() => games.undoCatch(alex, 'sam'));
        await settle(tester);
        expect(find.text('Sam is back in the game'), findsOneWidget);
      });

      testWidgets('real names once the time is up (R-ANON-02)', (tester) async {
        await seed(tester, gameSettings: anon);
        await ping(tester, 'kim', 'regular_1', 52.505, 20);
        now = start.add(anon.duration + const Duration(minutes: 5));
        await pumpAs(tester, 'alex', gameSettings: anon);
        expect(label('lastPing_kim', 'Kim'), findsOneWidget);
        expect(label('filter_player_kim', 'Kim'), findsOneWidget);
        expect(find.textContaining('Player '), findsNothing);
      });

      testWidgets('players see real names (R-ANON-03)', (tester) async {
        const shared = GameSettings(area: area, sharedPings: true);
        await seed(tester, gameSettings: shared);
        await ping(tester, 'sam', 'regular_1', 52.506, 20);
        await pumpAs(tester, 'kim', gameSettings: shared);
        expect(label('lastPing_sam', 'Sam'), findsOneWidget);
        expect(find.textContaining('Player '), findsNothing);
      });

      testWidgets('players see their own number in the overview, hunters '
          'none (R-ANON-04)', (tester) async {
        await seed(tester, gameSettings: anon);
        final kim = (await aliases(tester))['kim'];
        await pumpAs(tester, 'kim', gameSettings: anon);
        await tester.tap(find.byKey(const Key('overviewButton')));
        await tester.pumpAndSettle();
        expect(find.text('Hunters see you as Player $kim'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await pumpAs(tester, 'alex', gameSettings: anon);
        await tester.tap(find.byKey(const Key('overviewButton')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('overviewMyAlias')), findsNothing);
      });

      testWidgets('without the setting nobody gets a number', (tester) async {
        await seed(tester);
        expect(await aliases(tester), isEmpty);
        await pumpAs(tester, 'kim');
        await tester.tap(find.byKey(const Key('overviewButton')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('overviewMyAlias')), findsNothing);
      });
    });
  });

  group('leaving the play area (R-OUT-05, R-OUT-06)', () {
    // ~170 m east of the triangular [area] (still on screen) / inside it.
    const outside = GeoPoint(52.505, 13.4125);
    const inside = GeoPoint(52.502, 13.409);

    Future<void> shareOutside(WidgetTester tester, String userId) =>
        tester.runAsync(() async {
          await FirestoreRoundRepository(db).updateOutsideLocation(
            await testSession(code, userId),
            LocationFix(point: outside, at: now, accuracyM: 10),
          );
        });

    Finder label(String key, String text) =>
        find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

    testWidgets('hunters see the live pin and are told, anonymously '
        '(R-ANON-01)', (tester) async {
      const anon = GameSettings(area: area);
      await seed(tester, gameSettings: anon);
      final number = (await tester.runAsync(
        () async =>
            FirestoreGameRepository(db)
                .watchGame(await testSession(code, 'alex'))
                .first,
      ))!.aliases['kim'];
      await shareOutside(tester, 'kim');
      await pumpAs(tester, 'alex', gameSettings: anon);

      expect(label('outside_kim', 'Player $number'), findsOneWidget);
      expect(
        notifications.shown.map((n) => n.title),
        contains('Player $number left the play area'),
      );
      expect(find.textContaining('Kim'), findsNothing);
    });

    testWidgets('without anonymous players: real name', (tester) async {
      await seed(tester);
      await shareOutside(tester, 'kim');
      await pumpAs(tester, 'alex');
      expect(label('outside_kim', 'Kim'), findsOneWidget);
      // Red "LIVE" badge instead of a symbol before the name.
      expect(label('outside_kim', 'LIVE'), findsOneWidget);
      expect(find.text('Kim left the play area'), findsOneWidget);
    });

    testWidgets('players never see others outside', (tester) async {
      await seed(tester);
      await shareOutside(tester, 'sam');
      await pumpAs(tester, 'kim');
      expect(find.byKey(const Key('outside_sam')), findsNothing);
    });

    testWidgets('the player is told the whole time their live location is '
        'shared (R-OUT-06)', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      Future<void> walk(GeoPoint p, int seconds) async {
        for (var i = 0; i < seconds; i++) {
          now = now.add(const Duration(seconds: 1));
          location.emit(LocationFix(point: p, at: now, accuracyM: 10));
          await tester.pump(const Duration(seconds: 1));
        }
      }

      await walk(inside, 3);
      expect(find.byKey(const Key('outsideBanner_inside')), findsNothing);
      expect(find.textContaining('live location'), findsNothing);

      await walk(outside, 10);
      expect(find.byKey(const Key('outsideBanner_warning')), findsOneWidget);
      expect(find.textContaining('go back within 00:21'), findsOneWidget);
      expect(notifications.shown.last.title, 'You left the play area');

      await walk(outside, 21);
      expect(find.byKey(const Key('outsideBanner_live')), findsOneWidget);
      expect(
        notifications.shown.last.title,
        'The hunters see your live location',
      );

      await walk(inside, 1);
      expect(find.byKey(const Key('outsideBanner_afterglow')), findsOneWidget);
      expect(find.textContaining('for 01:00'), findsOneWidget);

      await walk(inside, 60);
      expect(find.textContaining('live location'), findsNothing);
      expect(
        notifications.shown.last.title,
        'Your live location is no longer shared',
      );
      await settle(tester);
    });
  });

  group('round over: everyone sees all positions (R-GAME-06, R-GAME-08)', () {
    const timeUpHint = 'The round is over and will be saved in a moment.';

    Future<void> regularPing(WidgetTester tester, String player) =>
        tester.runAsync(
          () async => FirestoreRoundRepository(db).sendPing(
            await testSession(code, player),
            PingSlot(
              id: 'regular_1',
              kind: PingKind.regular,
              at: start.add(const Duration(minutes: 20)),
            ),
            LocationFix(
              point: const GeoPoint(52.505, 13.405),
              at: start.add(const Duration(minutes: 20)),
            ),
          ),
        );

    Future<void> catchByRepo(WidgetTester tester, String player) =>
        tester.runAsync(
          () async => FirestoreGameRepository(db).recordCatch(
            await testSession(code, 'alex'),
            CatchRecord(
              playerId: player,
              at: start.add(const Duration(minutes: 25)),
            ),
          ),
        );

    /// [userId] confirms after the time is up who else was caught
    /// (R-GAME-11), at the end of the time like the dialog.
    Future<void> confirmByRepo(
      WidgetTester tester,
      String userId, [
      List<String> caught = const [],
    ]) => tester.runAsync(
      () async => FirestoreGameRepository(db)
          .confirmTimeUp(await testSession(code, userId), [
            for (final id in caught)
              CatchRecord(playerId: id, at: start.add(settings.duration)),
          ]),
    );

    Future<Map<String, dynamic>> gameDoc(WidgetTester tester) async {
      final session = (await tester.runAsync(() => testSession(code, 'alex')))!;
      final snap = await tester.runAsync(
        () => db.collection('games').doc(session.groupId).get(),
      );
      return snap!.data()!;
    }

    Future<bool> caught(WidgetTester tester, String player) async {
      final members = await tester.runAsync(
        () async =>
            FirestoreGameRepository(db)
                .watchMembers(await testSession(code, 'alex'))
                .first,
      );
      return members!.firstWhere((m) => m.id == player).caught;
    }

    Future<void> hunterCatches(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('catchButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catchPlayer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmCatch')));
      await tester.pumpAndSettle();
    }

    testWidgets('time up: players get the hunter view and the hint '
        '(R-GAME-06)', (tester) async {
      await seed(tester);
      await regularPing(tester, 'sam');
      now = start.add(settings.duration + const Duration(seconds: 30));
      await pumpAs(tester, 'kim');

      for (final id in ['hunters', 'lastPings', 'player_kim', 'player_sam']) {
        expect(find.byKey(Key('filter_$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const Key('filter_myPings')), findsNothing);
      // Sam's ping, which Kim could not see during the game.
      expect(find.byKey(const Key('lastPing_sam')), findsOneWidget);
      // No info line: the banner says it (R-GAME-09).
      expect(find.textContaining(timeUpHint), findsNothing);
      expect(find.byKey(const Key('jokerButton')), findsNothing);
    });

    testWidgets('15 s after the end the game screen ends the round by itself '
        'and saves its map, on any phone (R-GAME-10, R-HIST-04)', (
      tester,
    ) async {
      await seed(tester);
      await regularPing(tester, 'sam');
      // Confirmed right at the end who else was caught (R-GAME-11).
      final confirmedAt = start.add(settings.duration);
      final autoEndAt = confirmedAt.add(const Duration(seconds: 15));
      // Fake Firestore stores serverTimestamp as real time; pin it.
      final groupId = (await tester.runAsync(() => testSession(code, 'kim')))!
          .groupId;
      await tester.runAsync(
        () => db.collection('games').doc(groupId).update({
          'startAt': Timestamp.fromDate(start),
          'confirmedAt': Timestamp.fromDate(confirmedAt),
        }),
      );
      now = autoEndAt.subtract(const Duration(seconds: 2));
      await pumpAs(tester, 'kim', confirmedAt: confirmedAt);
      expect(find.text('PLAYERS WIN'), findsOneWidget);
      expect((await gameDoc(tester))['status'], 'running');

      now = autoEndAt;
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      final game = await gameDoc(tester);
      expect(game['status'], 'lobby');
      expect(game['startAt'], isNull);
      final pings = await tester.runAsync(
        () => db.collection('games').doc(groupId).collection('pings').get(),
      );
      expect(pings!.docs, isEmpty);
      final maps = await tester.runAsync(
        () =>
            db.collection('games').doc(groupId).collection('historyMaps').get(),
      );
      expect(maps!.docs, hasLength(1));
    });

    testWidgets('while the game is on players keep their own view', (
      tester,
    ) async {
      await seed(tester);
      await regularPing(tester, 'sam');
      await pumpAs(tester, 'kim');
      expect(find.byKey(const Key('filter_myPings')), findsOneWidget);
      expect(find.byKey(const Key('filter_player_sam')), findsNothing);
      expect(find.byKey(const Key('lastPing_sam')), findsNothing);
    });

    testWidgets('catching a player who is not the last needs no extra '
        'confirmation (R-GAME-08)', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      await hunterCatches(tester, 'Sam');
      expect(find.byKey(const Key('confirmLastCatch')), findsNothing);
      await settle(tester);
      expect(await caught(tester, 'sam'), isTrue);
      expect((await gameDoc(tester))['finishedAt'], isNull);
    });

    testWidgets('hunter catches the last player: confirmation, then the '
        'hunters won (R-GAME-08)', (tester) async {
      await seed(tester);
      await catchByRepo(tester, 'kim');
      await pumpAs(tester, 'alex');

      // Cancel: no catch at all.
      await hunterCatches(tester, 'Sam');
      expect(find.text('Last player – hunters win'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.textContaining('every player can look'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(await caught(tester, 'sam'), isFalse);
      expect((await gameDoc(tester))['finishedAt'], isNull);

      await hunterCatches(tester, 'Sam');
      await tester.tap(find.byKey(const Key('confirmLastCatch')));
      await settle(tester);
      expect(await caught(tester, 'sam'), isTrue);
      expect((await gameDoc(tester))['finishedAt'], isNotNull);
    });

    testWidgets('the last player reports their own catch: confirmation, then '
        'the hunters won (R-GAME-08)', (tester) async {
      await seed(tester);
      await catchByRepo(tester, 'kim');
      await pumpAs(tester, 'sam');
      await tester.tap(find.byKey(const Key('selfCatchButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmSelfCatch')));
      await tester.pumpAndSettle();
      expect(find.text('Last player – hunters win'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmLastCatch')));
      await settle(tester);
      expect(await caught(tester, 'sam'), isTrue);
      expect((await gameDoc(tester))['finishedAt'], isNotNull);
    });

    testWidgets('after the hunters won it is like time up for everyone '
        '(R-GAME-08)', (tester) async {
      await seed(tester);
      await regularPing(tester, 'sam');
      await catchByRepo(tester, 'kim');
      await catchByRepo(tester, 'sam');
      await pumpAs(
        tester,
        'kim',
        finishedAt: now.subtract(const Duration(seconds: 30)),
      );
      expect(find.text('HUNTERS WON'), findsOneWidget);
      // Kim was caught, but now the header with the winner is enough.
      expect(find.text('CAUGHT'), findsNothing);
      // Caught players split up again, like after the time (R-HUNT-11).
      expect(find.byKey(const Key('filter_caught')), findsNothing);
      expect(find.byKey(const Key('filter_player_sam')), findsOneWidget);
      expect(find.byKey(const Key('lastPing_sam')), findsOneWidget);
    });

    testWidgets('time up: a banner names the players who won until the '
        'round is saved; the overview keeps it (R-GAME-09)', (tester) async {
      await seed(tester);
      await catchByRepo(tester, 'kim');
      await pumpAs(tester, 'alex');
      const banner = 'Time is up – Sam has won!';
      expect(find.text(banner), findsNothing);

      now = start.add(settings.duration);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      // First the hunter confirms that nobody else was caught (R-GAME-11).
      expect(find.text(banner), findsNothing);
      await tester.tap(find.byKey(const Key('timeUpNobody')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmTimeUp')));
      await settle(tester);
      // The confirmation arrives with the game document.
      await pumpAs(tester, 'alex', confirmedAt: now);
      expect(find.text(banner), findsOneWidget);
      expect(notifications.shown.map((n) => n.title), contains(banner));
      // Header: no names, they are in the overview.
      expect(find.text('PLAYER WINS'), findsOneWidget);
      // 15 s – until the round is saved and everyone is back in the lobby.
      await tester.pump(const Duration(seconds: 14));
      expect(find.text(banner), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(banner), findsNothing);

      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('overviewWinner')),
          matching: find.text('Sam was never caught and has won'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('overviewWinner_sam')), findsOneWidget);
      expect(find.byKey(const Key('overviewWinner_kim')), findsNothing);
      expect(find.byKey(const Key('overviewWinner_alex')), findsNothing);
    });

    testWidgets('the last catch arrives: banner "hunters won" for everyone '
        '(R-GAME-08, R-GAME-09)', (tester) async {
      await seed(tester);
      await catchByRepo(tester, 'kim');
      await pumpAs(tester, 'kim');
      await catchByRepo(tester, 'sam');
      // The game document now carries finishedAt.
      await pumpAs(tester, 'kim', finishedAt: now);
      expect(
        notifications.shown.map((n) => n.title),
        contains('All players caught – the hunters won!'),
      );
      expect(find.text('HUNTERS WON'), findsOneWidget);
    });

    testWidgets('caught while others are still in the game: "caught" in the '
        'header and the overview, no positions before the warning '
        '(R-GAME-06, R-CATCH-01, R-CATCH-06)', (tester) async {
      await seed(tester);
      await regularPing(tester, 'sam');
      await catchByRepo(tester, 'kim');
      await pumpAs(tester, 'kim');
      expect(find.text('CAUGHT'), findsOneWidget);
      expect(find.text('HUNT IS ON'), findsNothing);
      // No info line over the map any more.
      expect(
        find.text('You were caught – your location is no longer shared.'),
        findsNothing,
      );
      expect(find.textContaining(timeUpHint), findsNothing);
      // Until the warning is confirmed nothing else is shown (R-GM-08).
      expect(find.byKey(const Key('liveViewDialog')), findsOneWidget);
      for (final id in ['hunters', 'lastPings', 'player_sam']) {
        expect(find.byKey(Key('filter_$id')), findsNothing, reason: id);
      }
      expect(find.byKey(const Key('lastPing_sam')), findsNothing);
      expect(find.byKey(const Key('selfCatchButton')), findsNothing);

      // The overview says it, including not to pass anything on.
      await tester.tap(find.byKey(const Key('liveViewOk')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      final hint = tester.widget<Text>(
        find.byKey(const Key('overviewCaughtSelf')),
      );
      expect(hint.data, contains('your location is no longer shared'));
      expect(hint.data, contains('you must not share these locations'));
    });

    testWidgets('time up with several players left: all are named '
        '(R-GAME-09)', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      now = start.add(settings.duration);
      await tester.pump(const Duration(seconds: 1));
      await confirmByRepo(tester, 'alex');
      await pumpAs(tester, 'kim', confirmedAt: now);
      expect(
        notifications.shown.last.title,
        'Time is up – Kim and Sam have won!',
      );
      expect(find.text('PLAYERS WIN'), findsOneWidget);
    });

    testWidgets('time up with everyone caught: the hunters won (R-GAME-09)', (
      tester,
    ) async {
      await seed(tester);
      await catchByRepo(tester, 'kim');
      await catchByRepo(tester, 'sam');
      await pumpAs(tester, 'sam');
      // Caught while the round ran: the live view warning first (R-GM-08).
      await tester.tap(find.byKey(const Key('liveViewOk')));
      await tester.pumpAndSettle();
      now = start.add(settings.duration);
      await tester.pump(const Duration(seconds: 1));
      // Sam is caught: no question, only "time is up" (R-GAME-11).
      expect(find.byKey(const Key('confirmTimeUp')), findsNothing);
      expect(find.text('TIME IS UP'), findsOneWidget);
      await confirmByRepo(tester, 'alex');
      await pumpAs(tester, 'sam', confirmedAt: now);
      expect(
        notifications.shown.last.title,
        'All players caught – the hunters won!',
      );
      expect(find.text('HUNTERS WON'), findsOneWidget);
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(
        find.text('The hunters won – all players were caught'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('overviewWinner_alex')), findsOneWidget);
    });

    testWidgets('time up: a player still in the game reports who else was '
        'caught; the result follows (R-GAME-11)', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'sam');
      now = start.add(settings.duration);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Header without a winner; the dialog asks, nothing chosen yet.
      expect(find.text('TIME IS UP'), findsOneWidget);
      expect(find.text('Time is up'), findsOneWidget);
      expect(
        notifications.shown.map((n) => n.title),
        contains('Time is up – was anyone else caught?'),
      );
      FilledButton confirm() =>
          tester.widget<FilledButton>(find.byKey(const Key('confirmTimeUp')));
      expect(confirm().onPressed, isNull);
      // Real names, also the player's own (R-ANON-02).
      expect(find.byKey(const Key('timeUpCaught_kim')), findsOneWidget);
      expect(find.byKey(const Key('timeUpCaught_sam')), findsOneWidget);
      expect(find.byKey(const Key('timeUpCaught_alex')), findsNothing);

      // "Nobody" and players exclude each other.
      await tester.tap(find.byKey(const Key('timeUpNobody')));
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('timeUpCaught_kim')));
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('timeUpNobody')))
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('confirmTimeUp')));
      // Encrypting the catch takes a moment.
      await settle(tester);
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmTimeUp')), findsNothing);
      expect((await gameDoc(tester))['confirmedAt'], isNotNull);
      expect(await caught(tester, 'kim'), isTrue);
      expect(await caught(tester, 'sam'), isFalse);

      await pumpAs(tester, 'sam', confirmedAt: now);
      expect(find.text('Time is up – Sam has won!'), findsOneWidget);
      expect(find.text('PLAYER WINS'), findsOneWidget);
    });

    testWidgets('the dialog closes when someone else confirmed (R-GAME-11)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      now = start.add(settings.duration);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmTimeUp')), findsOneWidget);

      await confirmByRepo(tester, 'alex', ['sam']);
      await pumpAs(tester, 'kim', confirmedAt: now);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmTimeUp')), findsNothing);
      expect(find.text('Time is up – Kim has won!'), findsOneWidget);
    });

    testWidgets('nobody confirms: after 10 min "nobody else" (R-GAME-11)', (
      tester,
    ) async {
      await seed(tester);
      now = start.add(settings.duration + const Duration(minutes: 9));
      await pumpAs(tester, 'alex');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmTimeUp')), findsOneWidget);
      now = start.add(settings.duration + const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmTimeUp')), findsNothing);
      expect(find.text('PLAYERS WIN'), findsOneWidget);
    });

    testWidgets('no winner in the overview while the game is on '
        '(R-GAME-09)', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overviewWinner')), findsNothing);
      expect(find.byIcon(Icons.emoji_events), findsNothing);
    });

    testWidgets('opening the app after the end: no banner again, but the '
        'overview tells who won (R-GAME-09)', (tester) async {
      await seed(tester);
      now = start.add(settings.duration + const Duration(seconds: 30));
      await pumpAs(
        tester,
        'sam',
        confirmedAt: now.subtract(const Duration(seconds: 10)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('have won!'), findsNothing);
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(find.text('Kim and Sam were never caught and have won'), findsOne);
    });

    testWidgets('after the hunters won the host cannot undo catches '
        '(R-CATCH-04, R-GAME-08)', (tester) async {
      await seed(tester);
      await catchByRepo(tester, 'kim');
      await catchByRepo(tester, 'sam');
      await pumpAs(
        tester,
        'alex',
        finishedAt: now.subtract(const Duration(minutes: 1)),
      );
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overviewUndoCatch_sam')), findsNothing);
      expect(find.byKey(const Key('overviewUndoCatch_kim')), findsNothing);
    });
  });

  group('game master and caught players watch live (R-GM-01 … R-GM-09)', () {
    LocationFix live(double lat) =>
        LocationFix(point: GeoPoint(lat, 13.405), at: now);

    /// Like [seed], plus Gil as game master; anonymous players on, so the
    /// real names show that only hunters get numbers (R-GM-03).
    Future<void> seedWithGameMaster(WidgetTester tester) async {
      await seed(
        tester,
        gameSettings: settings.copyWith(anonymousPlayers: true),
      );
      await tester.runAsync(() async {
        final games = FirestoreGameRepository(db);
        final alex = await testSession(code, 'alex');
        await games.joinGame(await testSession(code, 'gil'), name: 'Gil');
        final members = await games.watchMembers(alex).first;
        await games.setRoles(alex, [
          for (final m in members)
            m.id == 'gil' ? m.copyWith(role: Role.gameMaster) : m,
        ]);
        final rounds = FirestoreRoundRepository(db);
        await rounds.updateHunterLocation(alex, live(52.501));
        await rounds.updatePlayerLocation(
          await testSession(code, 'kim'),
          live(52.502),
        );
        await rounds.updatePlayerLocation(
          await testSession(code, 'sam'),
          live(52.503),
        );
      });
    }

    Future<void> pumpGameMaster(WidgetTester tester, String userId) => pumpAs(
      tester,
      userId,
      gameSettings: settings.copyWith(anonymousPlayers: true),
    );

    Future<void> catchPlayer(WidgetTester tester, String id) async {
      await tester.runAsync(
        () async => FirestoreGameRepository(db).recordCatch(
          await testSession(code, 'alex'),
          CatchRecord(playerId: id, at: now),
        ),
      );
      await settle(tester);
    }

    testWidgets('game master sees hunters and players live with real names, '
        'no drawing or game buttons', (tester) async {
      await seedWithGameMaster(tester);
      await pumpGameMaster(tester, 'gil');
      for (final id in ['hunters', 'lastPings', 'live_kim', 'live_sam']) {
        expect(find.byKey(Key('filter_$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const Key('filter_player_kim')), findsNothing);
      expect(find.byKey(const Key('live_kim')), findsOneWidget);
      expect(find.byKey(const Key('live_sam')), findsOneWidget);
      expect(find.byKey(const Key('hunter_alex')), findsOneWidget);
      expect(find.text('Kim'), findsWidgets);
      expect(find.textContaining('Player 1'), findsNothing);
      expect(
        find.text('Game master – you see everyone live (every 15 s).'),
        findsOneWidget,
      );
      for (final key in [
        'drawModeButton',
        'catchButton',
        'speedhuntButton',
        'jokerButton',
        'selfCatchButton',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      // Game masters do not take part: no tracking (R-GM-01).
      expect(location.isTracking, isFalse);

      // A live chip switches that player off.
      await tester.tap(find.byKey(const Key('filter_live_kim')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live_kim')), findsNothing);
      expect(find.byKey(const Key('live_sam')), findsOneWidget);
    });

    testWidgets('a caught player loses their live pin and chip; their pings '
        'go under "caught"', (tester) async {
      await seedWithGameMaster(tester);
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).sendPing(
          await testSession(code, 'sam'),
          PingSlot(
            id: 'regular_1',
            kind: PingKind.regular,
            at: start.add(const Duration(minutes: 20)),
          ),
          live(52.509),
        ),
      );
      await pumpGameMaster(tester, 'gil');
      expect(find.byKey(const Key('lastPing_sam')), findsOneWidget);

      await catchPlayer(tester, 'sam');
      expect(find.byKey(const Key('filter_live_sam')), findsNothing);
      // Sam's device deletes it; an old one must not show meanwhile.
      expect(find.byKey(const Key('live_sam')), findsNothing);
      expect(find.byKey(const Key('lastPing_sam')), findsNothing);
      await tester.tap(find.byKey(const Key('filter_caught')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_sam_1')), findsOneWidget);
    });

    testWidgets('caught player: warning first, live view only after "OK", '
        'asked once per round (R-GM-07, R-GM-08)', (tester) async {
      await seedWithGameMaster(tester);
      await catchPlayer(tester, 'kim');
      await pumpAs(tester, 'kim');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('liveViewDialog')), findsOneWidget);
      expect(find.byKey(const Key('live_sam')), findsNothing);
      // Not dismissible by tapping outside.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('liveViewDialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('liveViewOk')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('liveViewDialog')), findsNothing);
      // The dialog was the warning; no extra info line afterwards.
      expect(find.textContaining('You see everyone live'), findsNothing);
      expect(find.byKey(const Key('live_sam')), findsOneWidget);
      expect(find.byKey(const Key('hunter_alex')), findsOneWidget);
      expect(find.byKey(const Key('filter_live_sam')), findsOneWidget);
      expect(find.byKey(const Key('filter_live_kim')), findsNothing);
      expect(find.byKey(const Key('drawModeButton')), findsNothing);
      final saved = await tester.runAsync(
        () async =>
            jokers.load((await testSession(code, 'kim')).groupId, start),
      );
      expect(saved?.liveViewAccepted, isTrue);

      // After an app restart: not asked again.
      await tester.pumpWidget(const SizedBox());
      await pumpAs(tester, 'kim');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('liveViewDialog')), findsNothing);
      expect(find.byKey(const Key('live_sam')), findsOneWidget);
    });

    testWidgets('game master: info line only for 15 s, the overview tells the '
        'role (R-GM-03, R-GM-11)', (tester) async {
      await seedWithGameMaster(tester);
      await pumpGameMaster(tester, 'gil');
      const info = 'Game master – you see everyone live (every 15 s).';
      expect(find.text(info), findsOneWidget);
      now = now.add(const Duration(seconds: 16));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(info), findsNothing);

      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overviewGameMaster')), findsOneWidget);
      expect(find.text('GAME MASTER · 1'), findsOneWidget);
      expect(find.text('Gil (You)'), findsOneWidget);
    });

    testWidgets('others see the game master in the overview, without the '
        'own-role line (R-GM-11)', (tester) async {
      await seedWithGameMaster(tester);
      await pumpGameMaster(tester, 'kim');
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview_gil')), findsOneWidget);
      expect(find.byKey(const Key('overviewGameMaster')), findsNothing);
    });

    testWidgets('game master has the speedhunt chips like the hunters '
        '(R-GM-10)', (tester) async {
      await seedWithGameMaster(tester);
      final sh = start.add(const Duration(minutes: 25)).millisecondsSinceEpoch;
      await tester.runAsync(
        () async => FirestoreRoundRepository(db).sendPing(
          await testSession(code, 'sam'),
          PingSlot(
            id: 'speedhunt_${sh}_1',
            kind: PingKind.speedhunt,
            at: start.add(const Duration(minutes: 25)),
          ),
          live(52.508),
        ),
      );
      await pumpGameMaster(tester, 'gil');
      final chip = find.byKey(Key('filter_speedhunt_sam_$sh'));
      expect(chip, findsOneWidget);
      expect(find.text('⚡1 Sam'), findsOneWidget);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text('⚡1 Sam'), findsNothing);

      // Caught: the speedhunt goes under "caught", like for the hunters.
      await catchPlayer(tester, 'sam');
      expect(chip, findsNothing);
      await tester.ensureVisible(find.byKey(const Key('filter_caught')));
      await tester.tap(find.byKey(const Key('filter_caught')));
      await tester.pumpAndSettle();
      expect(find.textContaining('⚡1'), findsOneWidget);
    });

    testWidgets('players still in the game and hunters get no live view', (
      tester,
    ) async {
      await seedWithGameMaster(tester);
      for (final id in ['sam', 'alex']) {
        await pumpGameMaster(tester, id);
        expect(find.byKey(const Key('liveViewDialog')), findsNothing);
        expect(find.byKey(const Key('live_kim')), findsNothing, reason: id);
        expect(find.byKey(const Key('filter_live_kim')), findsNothing);
      }
    });

    testWidgets('once the time is up, the game master gets the usual end '
        'view, nothing live (R-GM-09)', (tester) async {
      await seedWithGameMaster(tester);
      now = start.add(const Duration(hours: 3, minutes: 1));
      await pumpGameMaster(tester, 'gil');
      expect(find.byKey(const Key('live_kim')), findsNothing);
      expect(find.byKey(const Key('filter_live_kim')), findsNothing);
      expect(find.byKey(const Key('filter_player_kim')), findsOneWidget);
      // Not asked who else was caught; until then only "time is up"
      // (R-GAME-11).
      expect(find.byKey(const Key('confirmTimeUp')), findsNothing);
      expect(find.text('TIME IS UP'), findsOneWidget);
    });
  });
}
