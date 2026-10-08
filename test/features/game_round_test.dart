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
  const settings = GameSettings(area: area);

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
      expect(find.text('Speedhunt (1)'), findsOneWidget);
      expect(find.text('Speedhunt started!'), findsOneWidget); // notice
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

      expect(find.textContaining('You were caught'), findsOneWidget);
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
      now = start.add(settings.duration + const Duration(minutes: 5));
      await pumpAs(tester, 'alex');

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
  });
}
