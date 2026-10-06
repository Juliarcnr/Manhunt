import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/geo/arrows.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';

void main() {
  group('pathArrows (R-HUNT-05)', () {
    test('one arrow per segment, at its middle', () {
      final arrows = pathArrows(const [
        GeoPoint(52.0, 13.0),
        GeoPoint(52.1, 13.0),
        GeoPoint(52.1, 13.1),
      ]);
      expect(arrows, hasLength(2));
      expect(arrows.first.at.lat, closeTo(52.05, 1e-9));
    });

    test('directions: north = 0, east = 90°, south = 180°, west = -90°', () {
      double deg(GeoPoint a, GeoPoint b) =>
          pathArrows([a, b]).single.bearingRad * 180 / pi;
      const o = GeoPoint(52.0, 13.0);
      expect(deg(o, const GeoPoint(52.1, 13.0)), closeTo(0, 1e-6));
      expect(deg(o, const GeoPoint(52.0, 13.1)), closeTo(90, 1e-6));
      expect(deg(o, const GeoPoint(51.9, 13.0)).abs(), closeTo(180, 1e-6));
      expect(deg(o, const GeoPoint(52.0, 12.9)), closeTo(-90, 1e-6));
    });

    test('no arrow when standing still, none for a single point', () {
      expect(pathArrows(const [GeoPoint(52, 13), GeoPoint(52, 13)]), isEmpty);
      expect(pathArrows(const [GeoPoint(52, 13)]), isEmpty);
    });
  });

  test('speedhunt number from the slot id (R-HUNT-07)', () {
    PingRecord rec(PingKind kind, String? slot) => PingRecord(
      playerId: 'kim',
      kind: kind,
      fix: LocationFix(point: const GeoPoint(0, 0), at: DateTime.utc(2026)),
      slotId: slot,
    );
    expect(
      rec(PingKind.speedhunt, 'speedhunt_1791228604799_2').speedhuntNumber,
      2,
    );
    expect(rec(PingKind.regular, 'regular_3').speedhuntNumber, isNull);
    expect(rec(PingKind.speedhunt, null).speedhuntNumber, isNull);
  });
}
