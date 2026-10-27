import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:manhunt/core/drawing/stroke.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/data/firestore_game_repository.dart';
import 'package:manhunt/data/firestore_round_repository.dart';
import 'package:manhunt/data/game_repository.dart';
import 'package:manhunt/data/session_store.dart';
import 'package:manhunt/features/game/game_screen.dart';
import 'package:manhunt/l10n/app_localizations.dart';
import 'package:manhunt/theme/app_theme.dart';

import '../helpers.dart';

/// Round with hunters Alex (host) and Tom, players Kim and Sam.
void main() {
  const code = 'ABCDE-FGHJK';
  final start = DateTime.utc(2026, 10, 4, 14);
  const area = [
    GeoPoint(52.50, 13.40),
    GeoPoint(52.50, 13.41),
    GeoPoint(52.51, 13.41),
    GeoPoint(52.51, 13.40),
  ];
  const settings = GameSettings(area: area, anonymousPlayers: false);

  late FakeFirebaseFirestore db;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  Future<GroupSession> session(WidgetTester tester, String uid) async =>
      (await tester.runAsync(() => testSession(code, uid)))!;

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      final games = FirestoreGameRepository(db);
      final alex = await testSession(code, 'alex');
      await games.createGame(alex, name: 'Alex', settings: settings);
      for (final uid in ['tom', 'kim', 'sam']) {
        await games.joinGame(await testSession(code, uid), name: uid);
      }
      final members = await games.watchMembers(alex).first;
      await games.setRoles(alex, [
        for (final m in members)
          m.copyWith(
            role: {'alex', 'tom'}.contains(m.id) ? Role.hunter : Role.player,
          ),
      ]);
      await games.startGame(alex);
    });
  }

  Future<void> pumpAs(WidgetTester tester, String userId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: deviceOverrides(
          db: db,
          userId: userId,
          store: MemorySessionStore.withGroup(code),
        ),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GameScreen(
            session: await session(tester, userId),
            game: GameInfo(
              adminId: 'alex',
              status: GameStatus.running,
              settings: settings,
              startAt: start,
            ),
            now: () => start.add(const Duration(minutes: 30)),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<List<Stroke>> stored(WidgetTester tester) async =>
      (await tester.runAsync(
        () async =>
            FirestoreRoundRepository(db)
                .watchDrawings(await testSession(code, 'tom'))
                .first,
      ))!;

  /// Global screen position of a map coordinate.
  Offset onScreen(WidgetTester tester, GeoPoint p) {
    final layer = find.byType(PolylineLayer).first;
    final camera = MapCamera.of(tester.element(layer));
    return tester.getTopLeft(find.byType(FlutterMap)) +
        camera.latLngToScreenOffset(LatLng(p.lat, p.lng));
  }

  Offset mapCenter(WidgetTester tester) =>
      tester.getCenter(find.byType(FlutterMap));

  Future<void> toggleDrawMode(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('drawModeButton')));
    await tester.pump();
  }

  /// One finger draws a line through the map centre.
  Future<void> drawLine(WidgetTester tester, {Offset? from}) async {
    final start = from ?? mapCenter(tester) - const Offset(80, 0);
    final g = await tester.startGesture(start);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(start + Offset(20.0 * i, 5.0 * i));
      await tester.pump();
    }
    await g.up();
    await settle(tester);
  }

  setUp(() => db = FakeFirebaseFirestore());

  group('drawing mode (R-DRAW-01, R-DRAW-02, R-DRAW-03)', () {
    testWidgets('only hunters get the drawing button', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'kim');
      expect(find.byKey(const Key('drawModeButton')), findsNothing);
      await pumpAs(tester, 'alex');
      expect(find.byKey(const Key('drawModeButton')), findsOneWidget);
      expect(find.byKey(const Key('drawEraserButton')), findsNothing);
    });

    testWidgets('one finger draws a red line that is stored encrypted', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      await toggleDrawMode(tester);
      expect(find.byKey(const Key('drawColor_red')), findsOneWidget);
      await drawLine(tester);

      final strokes = await stored(tester);
      expect(strokes, hasLength(1));
      expect(strokes.single.uid, 'alex');
      expect(strokes.single.color, StrokeColor.red);
      expect(strokes.single.points.length, greaterThan(2));
      // Within the play area around the centre.
      expect(strokes.single.points.first.lat, closeTo(52.505, 0.01));
    });

    testWidgets('a picked colour is used for the next line', (tester) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      await toggleDrawMode(tester);
      await tester.tap(find.byKey(const Key('drawColor_green')));
      await tester.pump();
      await drawLine(tester);
      expect((await stored(tester)).single.color, StrokeColor.green);
    });

    testWidgets('without drawing mode a drag moves the map, nothing is drawn', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      await drawLine(tester);
      expect(await stored(tester), isEmpty);
    });

    testWidgets('a second finger cancels the line (pinch zoom)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      await toggleDrawMode(tester);
      final c = mapCenter(tester);
      final a = await tester.startGesture(c - const Offset(40, 0), pointer: 1);
      await a.moveBy(const Offset(-10, 0));
      await tester.pump();
      final b = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
      for (var i = 0; i < 5; i++) {
        await a.moveBy(const Offset(-10, 0));
        await b.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await settle(tester);
      expect(await stored(tester), isEmpty);
    });
  });

  group('erase and clear (R-DRAW-04, R-DRAW-05, R-DRAW-06)', () {
    final line = [
      const GeoPoint(52.505, 13.401),
      const GeoPoint(52.505, 13.409),
    ];

    Future<void> seedStroke(WidgetTester tester) => tester.runAsync(
      () async => FirestoreRoundRepository(db).addStrokes(
        await testSession(code, 'tom'),
        [Stroke(id: '', uid: '', color: StrokeColor.blue, points: line)],
      ),
    );

    testWidgets('another hunter\'s line shows up, also outside drawing mode', (
      tester,
    ) async {
      await seed(tester);
      await seedStroke(tester);
      await pumpAs(tester, 'alex');
      final polylines = tester
          .widgetList<PolylineLayer>(find.byType(PolylineLayer))
          .expand((l) => l.polylines)
          .where((p) => p.color == AppColors.drawBlue);
      expect(polylines, hasLength(1));
    });

    testWidgets('players never see the drawings', (tester) async {
      await seed(tester);
      await seedStroke(tester);
      await pumpAs(tester, 'kim');
      final polylines = tester
          .widgetList<PolylineLayer>(find.byType(PolylineLayer))
          .expand((l) => l.polylines)
          .where((p) => p.color == AppColors.drawBlue);
      expect(polylines, isEmpty);
    });

    testWidgets('the eraser cuts the middle out of another hunter\'s line', (
      tester,
    ) async {
      await seed(tester);
      await seedStroke(tester);
      await pumpAs(tester, 'alex');
      await toggleDrawMode(tester);
      await tester.tap(find.byKey(const Key('drawEraserButton')));
      await tester.pump();

      final middle = onScreen(tester, const GeoPoint(52.505, 13.405));
      final g = await tester.startGesture(middle - const Offset(0, 40));
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(middle + Offset(0, -40.0 + 10 * i));
        await tester.pump();
      }
      await g.up();
      await settle(tester);

      final pieces = await stored(tester);
      expect(pieces, hasLength(2));
      expect(pieces.every((s) => s.color == StrokeColor.blue), isTrue);
      final ends = pieces.expand((s) => s.points).map((p) => p.lng);
      expect(ends, containsAll([13.401, 13.409]));
    });

    testWidgets('the trash can deletes all lines of all hunters at once', (
      tester,
    ) async {
      await seed(tester);
      await seedStroke(tester); // Tom's
      await pumpAs(tester, 'alex');
      await toggleDrawMode(tester);
      await drawLine(tester); // Alex's
      expect(await stored(tester), hasLength(2));

      await tester.tap(find.byKey(const Key('drawClearButton')));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(await stored(tester), isEmpty);
    });

    testWidgets('leaving drawing mode keeps the lines and hides the tools', (
      tester,
    ) async {
      await seed(tester);
      await pumpAs(tester, 'alex');
      await toggleDrawMode(tester);
      await drawLine(tester);
      await toggleDrawMode(tester);
      expect(find.byKey(const Key('drawClearButton')), findsNothing);
      await settle(tester);
      expect(await stored(tester), hasLength(1));
      final red = tester
          .widgetList<PolylineLayer>(find.byType(PolylineLayer))
          .expand((l) => l.polylines)
          .where((p) => p.color == AppColors.drawRed);
      expect(red, hasLength(1));
    });
  });
}
