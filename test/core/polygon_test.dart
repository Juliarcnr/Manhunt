import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/geo/polygon.dart';
import 'package:manhunt/core/models/geo_point.dart';

void main() {
  // ~1 km (east–west) × ~2 km (north–south) rectangle near Berlin.
  // 1° lat ≈ 111.19 km; 1° lng at 52.5° ≈ 67.69 km.
  const lat = 52.5;
  const dLat = 2 / 111.195;
  const dLng = 1 / 67.69;
  const rect = [
    GeoPoint(lat, 13.4),
    GeoPoint(lat, 13.4 + dLng),
    GeoPoint(lat + dLat, 13.4 + dLng),
    GeoPoint(lat + dLat, 13.4),
  ];

  group('area & extent (R-SET-06)', () {
    test('1 km × 2 km rectangle ≈ 2 km²', () {
      expect(polygonAreaKm2(rect), closeTo(2.0, 0.03));
    });

    test('orientation does not matter', () {
      expect(
        polygonAreaKm2(rect.reversed.toList()),
        closeTo(polygonAreaKm2(rect), 1e-9),
      );
    });

    test('extent in km', () {
      final e = polygonExtentKm(rect);
      expect(e.widthKm, closeTo(1.0, 0.02));
      expect(e.heightKm, closeTo(2.0, 0.02));
    });

    test('fewer than 3 points have no area', () {
      expect(polygonAreaKm2(rect.take(2).toList()), 0);
    });
  });

  group('isSimplePolygon', () {
    test('rectangle is simple', () {
      expect(isSimplePolygon(rect), isTrue);
    });

    test('triangle is simple', () {
      expect(isSimplePolygon(rect.take(3).toList()), isTrue);
    });

    test('bow tie (crossing edges) is not simple', () {
      final bowTie = [rect[0], rect[2], rect[1], rect[3]];
      expect(isSimplePolygon(bowTie), isFalse);
    });

    test('concave L-shape is simple', () {
      const l = [
        GeoPoint(0, 0),
        GeoPoint(0, 2),
        GeoPoint(1, 2),
        GeoPoint(1, 1),
        GeoPoint(2, 1),
        GeoPoint(2, 0),
      ];
      expect(isSimplePolygon(l), isTrue);
    });

    test('too few points', () {
      expect(isSimplePolygon(rect.take(2).toList()), isFalse);
    });
  });

  group('isInsidePolygon', () {
    test('inside / outside', () {
      expect(
        isInsidePolygon(GeoPoint(lat + dLat / 2, 13.4 + dLng / 2), rect),
        isTrue,
      );
      expect(isInsidePolygon(const GeoPoint(lat - 0.01, 13.4), rect), isFalse);
    });
  });

  group('distance to the edge (R-OUT-01)', () {
    // Metres east of the rectangle's east edge, at mid-height.
    GeoPoint east(double m) =>
        GeoPoint(lat + dLat / 2, 13.4 + dLng + m / 67690);

    test('positive outside, negative inside, in metres', () {
      expect(distanceOutsideM(east(50), rect), closeTo(50, 1));
      expect(distanceOutsideM(east(-20), rect), closeTo(-20, 1));
    });

    test('inside: distance to the nearest edge', () {
      // Centre: 500 m to the long east and west edges.
      final centre = GeoPoint(lat + dLat / 2, 13.4 + dLng / 2);
      expect(distanceOutsideM(centre, rect), closeTo(-500, 10));
    });

    test('beyond a corner: distance to the corner', () {
      // 30 m east and 40 m north of the north-east corner → 50 m.
      final p = GeoPoint(lat + dLat + 40 / 111195, 13.4 + dLng + 30 / 67690);
      expect(distanceOutsideM(p, rect), closeTo(50, 1));
    });

    test('on the edge ≈ 0', () {
      expect(distanceOutsideM(east(0), rect)!.abs(), lessThan(0.5));
    });

    test('no area → null', () {
      expect(distanceOutsideM(east(50), rect.take(2).toList()), isNull);
    });
  });
}
