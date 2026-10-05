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
}
