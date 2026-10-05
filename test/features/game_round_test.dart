import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/core/schedule/speedhunt.dart';
import 'package:manhunt/data/firestore_game_repository.dart';
import 'package:manhunt/data/firestore_round_repository.dart';
import 'package:manhunt/data/game_repository.dart';
import 'package:manhunt/data/session_store.dart';
import 'package:manhunt/features/game/game_screen.dart';
import 'package:manhunt/l10n/app_localizations.dart';

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
  const settings = GameSettings(area: area);

  late FakeFirebaseFirestore db;
  late FakeLocationService location;
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

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      final games = FirestoreGameRepository(db);
      final alex = await testSession(code, 'alex');
      await games.createGame(alex, name: 'Alex', settings: settings);
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
  }) async {
    final session = (await tester.runAsync(() => testSession(code, userId)))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: deviceOverrides(
          db: db,
          userId: userId,
          store: MemorySessionStore()..code = code,
          location: location,
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
    now = start.add(const Duration(minutes: 30));
  });

  group('hunter (R-HUNT-*, R-SPEED-*)', () {
    testWidgets('sees catch and speedhunt buttons, not the player ones', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      expect(find.byKey(const Key('catchButton')), findsOneWidget);
      expect(find.text('Speedhunt (2)'), findsOneWidget);
      expect(find.byKey(const Key('jokerButton')), findsNothing);
      expect(location.isTracking, isTrue);
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
      expect(find.text('Speedhunt (1)'), findsOneWidget);
      expect(find.text('Speedhunt started!'), findsOneWidget); // notice
    });

    testWidgets('speedhunt before minute 60 is refused (R-SET-11)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex'); // minute 30
      await tester.tap(find.byKey(const Key('speedhuntButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('60 min after the start'), findsOne);
      expect(find.byKey(const Key('speedhuntPlayer')), findsNothing);
    });

    testWidgets('host removes someone via the overview (R-LOBBY-09)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overviewRemove_alex')), findsNothing);
      await tester.tap(find.byKey(const Key('overviewRemove_sam')));
      await tester.pumpAndSettle();
      expect(find.text('Remove Sam?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmRemove')));
      await settle(tester);

      final members = await tester.runAsync(
        () async =>
            FirestoreGameRepository(db)
                .watchMembers(await testSession(code, 'alex'))
                .first,
      );
      expect(members!.map((m) => m.id), isNot(contains('sam')));
    });

    testWidgets('players cannot remove anyone', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      await tester.tap(find.byKey(const Key('overviewButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overviewRemove_sam')), findsNothing);
    });

    testWidgets('speedhunt during head start is refused', (tester) async {
      now = start.add(const Duration(minutes: 5));
      await seed(tester);
      await pumpAs(tester, 'alex');
      await tester.tap(find.byKey(const Key('speedhuntButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('once the hunters are released'), findsOne);
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
      expect(find.textContaining('Hunters at'), findsOneWidget);

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
      expect(find.textContaining('Players at'), findsOneWidget);

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
    });

    testWidgets('self catch stops sharing the location (R-CATCH-01)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      await tester.tap(find.byKey(const Key('selfCatchButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmSelfCatch')));
      await settle(tester);

      expect(find.textContaining('You were caught'), findsOneWidget);
      expect(find.text('Kim was caught'), findsOneWidget);
      expect(find.byKey(const Key('selfCatchButton')), findsNothing);
      expect(location.isTracking, isFalse);
    });
  });
}
