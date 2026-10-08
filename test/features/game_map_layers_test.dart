import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/features/game/game_map_layers.dart';
import 'package:manhunt/theme/app_theme.dart';

void main() {
  final positions = {
    'anna': LocationFix(
      point: const GeoPoint(52.52, 13.405),
      at: DateTime(2026, 10, 6, 14, 32),
    ),
  };
  const names = {'anna': 'Anna'};

  Future<void> pumpLayer(WidgetTester tester, Widget layer) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(52.52, 13.405),
                initialZoom: 16,
              ),
              children: [layer],
            ),
          ),
        ),
      );

  Finder inPin(Finder matching) => find.descendant(
    of: find.byKey(const Key('hunter_anna')),
    matching: matching,
  );

  group('hunter pins (R-HUNT-02, R-PLAY-02)', () {
    testWidgets('live: location pin, hunter symbol before the name, no time', (
      tester,
    ) async {
      await pumpLayer(tester, huntersLayer(positions: positions, names: names));
      expect(inPin(find.byIcon(Icons.location_on)), findsOneWidget);
      expect(inPin(find.byIcon(Icons.track_changes)), findsOneWidget);
      expect(inPin(find.text('Anna')), findsOneWidget);
      // All hunters share the one hunter colour.
      expect(
        tester.widget<Icon>(inPin(find.byIcon(Icons.location_on))).color,
        AppColors.hunter,
      );
      expect(
        tester.getCenter(inPin(find.byIcon(Icons.track_changes))).dx,
        lessThan(tester.getCenter(inPin(find.text('Anna'))).dx),
      );
    });

    testWidgets('joker snapshot keeps the time of the position', (
      tester,
    ) async {
      await pumpLayer(
        tester,
        huntersLayer(
          positions: positions,
          names: names,
          formatTime: (t) => '${t.hour}:${t.minute}',
        ),
      );
      expect(inPin(find.text('Anna · 14:32')), findsOneWidget);
      expect(inPin(find.byIcon(Icons.track_changes)), findsOneWidget);
    });
  });

  group('speedhunt pings (R-HUNT-07)', () {
    PingRecord sh(String player, int n, int minute) => PingRecord(
      playerId: player,
      kind: PingKind.speedhunt,
      slotId: 'speedhunt_1_$n',
      fix: LocationFix(
        point: const GeoPoint(52.52, 13.405),
        at: DateTime(2026, 10, 6, 14, minute),
      ),
    );
    Finder pinIn(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byIcon(Icons.location_on),
    );

    testWidgets('only the latest per player gets a location pin', (
      tester,
    ) async {
      await pumpLayer(
        tester,
        speedhuntPingsLayer(
          pings: [sh('anna', 1, 30), sh('anna', 2, 35), sh('ben', 1, 20)],
          colors: const {'anna': Colors.pink},
          names: const {'anna': 'Anna', 'ben': 'Ben'},
        ),
      );
      // Older pings: bolt and number only; the latest also has the name.
      expect(find.text('⚡1'), findsOneWidget);
      expect(find.text('⚡2 Anna'), findsOneWidget);
      expect(find.text('⚡1 Ben'), findsOneWidget);
      expect(find.text('⚡2'), findsNothing);
      expect(pinIn('speedhunt_anna_speedhunt_1_1'), findsNothing);
      expect(pinIn('speedhunt_anna_speedhunt_1_2'), findsOneWidget);
      expect(pinIn('speedhunt_ben_speedhunt_1_1'), findsOneWidget);
      expect(
        tester.widget<Icon>(pinIn('speedhunt_anna_speedhunt_1_2')).color,
        Colors.pink,
      );
    });

    testWidgets('the named badge is only as wide as its text', (tester) async {
      await pumpLayer(
        tester,
        speedhuntPingsLayer(
          pings: [sh('anna', 1, 30)],
          colors: const {},
          names: const {'anna': 'Al'},
        ),
      );
      final badge = find
          .ancestor(of: find.text('⚡1 Al'), matching: find.byType(Container))
          .first;
      final text = tester.getSize(find.text('⚡1 Al')).width;
      // Text plus padding and border – not the full marker width.
      expect(tester.getSize(badge).width, lessThan(text + 30));
    });
  });

  group('live positions glide instead of jumping (R-MAP-04)', () {
    LocationFix fix(double lat) => LocationFix(
      point: GeoPoint(lat, 13.405),
      at: DateTime(2026, 10, 6, 14, 32),
    );
    double latOf(WidgetTester tester, String key) => tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .expand((l) => l.markers)
        .singleWhere((m) => m.key == Key(key))
        .point
        .latitude;

    testWidgets('own dot moves smoothly to the next fix', (tester) async {
      await pumpLayer(tester, selfLayer(fix(52.520)));
      expect(latOf(tester, 'self'), 52.520);

      await pumpLayer(tester, selfLayer(fix(52.521)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(latOf(tester, 'self'), closeTo(52.5205, 1e-6));

      // A new fix mid-move continues from where the dot is.
      await pumpLayer(tester, selfLayer(fix(52.5215)));
      await tester.pump();
      expect(latOf(tester, 'self'), closeTo(52.5205, 1e-6));
      await tester.pumpAndSettle();
      expect(latOf(tester, 'self'), 52.5215);
    });

    testWidgets('hunters glide, joker snapshots do not move', (tester) async {
      await pumpLayer(
        tester,
        huntersLayer(positions: {'anna': fix(52.520)}, names: names),
      );
      await pumpLayer(
        tester,
        huntersLayer(positions: {'anna': fix(52.522)}, names: names),
      );
      await tester.pump(const Duration(seconds: 1));
      final mid = latOf(tester, 'hunter_anna');
      expect(mid, greaterThan(52.520));
      expect(mid, lessThan(52.522));
      await tester.pumpAndSettle();
      expect(latOf(tester, 'hunter_anna'), 52.522);

      expect(
        huntersLayer(
          positions: {'anna': fix(52.522)},
          names: names,
          formatTime: (t) => '',
        ),
        isA<MarkerLayer>(),
      );
    });
  });
}
