import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/data/location_service.dart';
import 'package:manhunt/features/map/area_editor_screen.dart';
import 'package:manhunt/l10n/app_localizations.dart';
import 'package:manhunt/state/providers.dart';

import '../helpers.dart';

void main() {
  const square = [
    GeoPoint(52.50, 13.40),
    GeoPoint(52.50, 13.41),
    GeoPoint(52.51, 13.41),
    GeoPoint(52.51, 13.40),
  ];

  /// Pumps a host page that opens the editor and records its result.
  Future<List<GeoPoint>? Function()> open(
    WidgetTester tester, {
    List<GeoPoint> initial = const [],
    LocationService? location,
  }) async {
    List<GeoPoint>? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(
            location ?? FakeLocationService(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.of(context)
                  .push<List<GeoPoint>>(
                    MaterialPageRoute(
                      builder: (_) => AreaEditorScreen(initial: initial),
                    ),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  /// Taps the map at an offset from its center (single taps wait for the
  /// double-tap timeout).
  Future<void> tapMap(WidgetTester tester, Offset fromCenter) async {
    final center = tester.getCenter(find.byType(FlutterMap));
    await tester.tapAt(center + fromCenter);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  Finder status() => find.byKey(const Key('areaStatus'));
  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('areaSave')))
          .onPressed !=
      null;

  testWidgets('tapping sets corners; save from 3 corners (R-SET-06)', (
    tester,
  ) async {
    final result = await open(tester);
    expect(tester.widget<Text>(status()).data, 'Mindestens 3 Eckpunkte setzen');
    expect(saveEnabled(tester), isFalse);

    await tapMap(tester, const Offset(-60, -60));
    await tapMap(tester, const Offset(60, -60));
    expect(find.byKey(const Key('areaCorner1')), findsOneWidget);
    expect(saveEnabled(tester), isFalse);

    await tapMap(tester, const Offset(60, 60));
    expect(tester.widget<Text>(status()).data, startsWith('3 Eckpunkte · ≈'));
    expect(saveEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('areaSave')));
    await tester.pumpAndSettle();
    expect(result(), hasLength(3));
  });

  testWidgets('existing area is shown and can be extended via "+"', (
    tester,
  ) async {
    final result = await open(tester, initial: square);
    expect(find.byKey(const Key('areaCorner3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('areaInsert0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('areaCorner4')), findsOneWidget);
    await tester.tap(find.byKey(const Key('areaSave')));
    await tester.pumpAndSettle();
    expect(result()![1].lat, closeTo(52.50, 1e-9));
    expect(result()![1].lng, closeTo(13.405, 1e-9));
  });

  testWidgets('long-press deletes a corner, undo restores it', (tester) async {
    await open(tester, initial: square);
    await tester.longPress(find.byKey(const Key('areaCorner0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('areaCorner3')), findsNothing);
    await tester.tap(find.byKey(const Key('areaUndo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('areaCorner3')), findsOneWidget);
  });

  testWidgets('dragging a corner moves it', (tester) async {
    final result = await open(tester, initial: square);
    await tester.drag(
      find.byKey(const Key('areaCorner0')),
      const Offset(-40, 40),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('areaSave')));
    await tester.pumpAndSettle();
    final moved = result()!.first;
    expect(moved.lat, lessThan(52.50));
    expect(moved.lng, lessThan(13.40));
  });

  testWidgets('crossing edges block saving', (tester) async {
    await open(tester, initial: [square[0], square[2], square[1], square[3]]);
    expect(tester.widget<Text>(status()).data, contains('überkreuzen'));
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('cancel returns nothing', (tester) async {
    final result = await open(tester, initial: square);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });

  testWidgets('new area centers on my location; unavailable shows hint', (
    tester,
  ) async {
    final location = FakeLocationService();
    await open(tester, location: location);
    expect(location.currentCalls, 1); // automatic, quiet
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byIcon(Icons.my_location));
    await tester.pumpAndSettle();
    expect(location.currentCalls, 2);
    expect(find.textContaining('Standort nicht verfügbar'), findsOneWidget);
  });
}
