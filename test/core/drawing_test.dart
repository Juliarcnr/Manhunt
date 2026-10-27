import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/drawing/stroke.dart';
import 'package:manhunt/core/drawing/stroke_geometry.dart';
import 'package:manhunt/core/models/geo_point.dart';

void main() {
  // 1 m east at 52.5° ≈ 1 / 67690 °lng; 1 m north ≈ 1 / 111195 °lat.
  const lat = 52.5;
  const lng = 13.4;
  GeoPoint east(double m) => GeoPoint(lat, lng + m / 67690);
  GeoPoint at(double eastM, double northM) =>
      GeoPoint(lat + northM / 111195, lng + eastM / 67690);

  // A straight 100 m line from west to east, two points only.
  final line = [east(0), east(100)];

  group('erasing parts of a stroke (R-DRAW-04)', () {
    test('erasing the middle leaves two pieces', () {
      final pieces = eraseFromStroke(line, [at(50, -20), at(50, 20)], 5)!;
      expect(pieces, hasLength(2));
      expect(pieces.first.first, east(0));
      expect(pieces.last.last, east(100));
      // The cut is around 45 m / 55 m.
      expect(pieces.first.last.lng, lessThan(east(46).lng));
      expect(pieces.last.first.lng, greaterThan(east(54).lng));
    });

    test('erasing an end leaves one piece', () {
      final pieces = eraseFromStroke(line, [east(100)], 10)!;
      expect(pieces, hasLength(1));
      expect(pieces.single.first, east(0));
      expect(pieces.single.last.lng, lessThan(east(91).lng));
    });

    test('erasing everything leaves nothing', () {
      expect(eraseFromStroke(line, [east(-10), east(110)], 5), isEmpty);
    });

    test('an eraser path far away does not touch the stroke', () {
      expect(eraseFromStroke(line, [at(0, 50), at(100, 50)], 5), isNull);
    });

    test('pieces keep only the original corners plus the cut ends', () {
      final zigzag = [at(0, 0), at(50, 30), at(100, 0)];
      final pieces = eraseFromStroke(zigzag, [at(100, 0)], 10)!;
      expect(pieces.single.first, at(0, 0));
      expect(pieces.single, contains(at(50, 30)));
      expect(pieces.single, hasLength(3));
    });
  });

  group('compact strokes (R-DRAW-06)', () {
    test('points closer than the minimum distance are dropped', () {
      final slow = [for (var m = 0.0; m <= 10; m += 0.5) east(m)];
      final simple = simplifyStroke(slow, 2);
      expect(simple.first, east(0));
      expect(simple.last, east(10));
      expect(simple.length, inInclusiveRange(5, 6));
    });

    test('a tap stays a short stroke', () {
      expect(simplifyStroke([east(0), east(0.1)], 2), [east(0), east(0.1)]);
    });

    test('long strokes are split into connected pieces', () {
      final long = [for (var i = 0; i < 10; i++) east(i.toDouble())];
      final pieces = splitLongStroke(long, 4);
      expect(pieces.map((p) => p.length), [4, 4, 4]);
      expect(pieces[0].last, pieces[1].first);
      expect(pieces.last.last, long.last);
      expect(splitLongStroke(long, 10), [long]);
    });
  });

  group('stroke payload (R-DRAW-03, R-DRAW-07)', () {
    test('round trip keeps colour and points', () {
      final stroke = Stroke(
        id: 'a',
        uid: 'u',
        color: StrokeColor.green,
        points: [const GeoPoint(52.123456, 13.654321), east(5)],
      );
      final back = Stroke.fromJson(stroke.toJson(), id: 'a', uid: 'u');
      expect(back.color, StrokeColor.green);
      expect(back.points.first, const GeoPoint(52.123456, 13.654321));
      expect(back.points.last.lng, closeTo(east(5).lng, 1e-6));
    });

    test('unknown colours fall back to red', () {
      final back = Stroke.fromJson(
        {
          'c': 'purple',
          'p': [1, 2, 3, 4],
        },
        id: 'a',
        uid: 'u',
      );
      expect(back.color, StrokeColor.red);
      expect(back.points, [const GeoPoint(1, 2), const GeoPoint(3, 4)]);
    });
  });
}
