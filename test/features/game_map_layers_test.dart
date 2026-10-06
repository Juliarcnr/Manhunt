import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/features/game/game_map_layers.dart';

void main() {
  final positions = {
    'anna': LocationFix(
      point: const GeoPoint(52.52, 13.405),
      at: DateTime(2026, 10, 6, 14, 32),
    ),
  };
  const names = {'anna': 'Anna'};

  Future<void> pumpLayer(WidgetTester tester, MarkerLayer layer) =>
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
      await pumpLayer(
        tester,
        huntersLayer(positions: positions, names: names, colors: const {}),
      );
      expect(inPin(find.byIcon(Icons.location_on)), findsOneWidget);
      expect(inPin(find.byIcon(Icons.track_changes)), findsOneWidget);
      expect(inPin(find.text('Anna')), findsOneWidget);
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
          colors: const {},
          formatTime: (t) => '${t.hour}:${t.minute}',
        ),
      );
      expect(inPin(find.text('Anna · 14:32')), findsOneWidget);
      expect(inPin(find.byIcon(Icons.track_changes)), findsOneWidget);
    });
  });
}
