import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/geo/area_draft.dart';
import 'package:manhunt/core/models/geo_point.dart';

void main() {
  const a = GeoPoint(52.0, 13.0);
  const b = GeoPoint(52.0, 13.1);
  const c = GeoPoint(52.1, 13.1);
  const d = GeoPoint(52.1, 13.0);

  AreaDraft square() => const AreaDraft([]).add(a).add(b).add(c).add(d);

  group('AreaDraft (R-SET-06)', () {
    test('tapping adds corners; valid from 3 points', () {
      var draft = const AreaDraft([]);
      expect(draft.isValid, isFalse);
      draft = draft.add(a).add(b);
      expect(draft.hasMinimumPoints, isFalse);
      draft = draft.add(c);
      expect(draft.isValid, isTrue);
      expect(draft.areaKm2, greaterThan(0));
    });

    test('undo steps back through every edit', () {
      var draft = square().remove(0);
      expect(draft.points, [b, c, d]);
      draft = draft.undo();
      expect(draft.points, [a, b, c, d]);
      draft = draft.undo();
      expect(draft.points, [a, b, c]);
    });

    test('undo on a fresh draft does nothing', () {
      const draft = AreaDraft([a]);
      expect(draft.canUndo, isFalse);
      expect(draft.undo().points, [a]);
    });

    test('insert a corner on an edge via its midpoint', () {
      final draft = square();
      final mid = draft.midpoint(0);
      expect(mid, const GeoPoint(52.0, 13.05));
      expect(draft.insertAfter(0, mid).points, [a, mid, b, c, d]);
      // Last edge closes the polygon back to the first corner.
      expect(draft.midpoint(3), const GeoPoint(52.05, 13.0));
    });

    test('a drag is a single undo step', () {
      var draft = square().beginMove();
      draft = draft.move(0, const GeoPoint(51.9, 12.9), record: false);
      draft = draft.move(0, const GeoPoint(51.8, 12.8), record: false);
      expect(draft.points.first, const GeoPoint(51.8, 12.8));
      expect(draft.undo().points.first, a);
    });

    test('crossing edges make the draft invalid', () {
      final bowTie = const AreaDraft([]).add(a).add(c).add(b).add(d);
      expect(bowTie.hasMinimumPoints, isTrue);
      expect(bowTie.isSimple, isFalse);
      expect(bowTie.isValid, isFalse);
    });

    test('clear removes everything but can be undone', () {
      final cleared = square().clear();
      expect(cleared.points, isEmpty);
      expect(cleared.undo().points, [a, b, c, d]);
    });
  });
}
