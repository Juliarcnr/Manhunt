import 'dart:math';

import '../models/geo_point.dart';

const _earthRadiusM = 6371000.0;

/// Local flat plane in metres around [lat0] (equirectangular). Strokes span
/// at most a few km, so this is accurate enough.
Point<double> _project(GeoPoint p, double lat0) => Point(
  _earthRadiusM * p.lng * pi / 180 * cos(lat0 * pi / 180),
  _earthRadiusM * p.lat * pi / 180,
);

/// Distance in metres between two nearby points.
double geoDistanceM(GeoPoint a, GeoPoint b) =>
    _project(a, a.lat).distanceTo(_project(b, a.lat));

double _distanceToSegment(Point<double> p, Point<double> a, Point<double> b) {
  final ab = b - a;
  final lengthSq = ab.x * ab.x + ab.y * ab.y;
  if (lengthSq == 0) return p.distanceTo(a);
  final t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSq;
  final c = t.clamp(0.0, 1.0);
  return p.distanceTo(Point(a.x + ab.x * c, a.y + ab.y * c));
}

/// Drops points closer than [minDistanceM] to the previously kept one, so a
/// slow finger doesn't produce hundreds of points. The last point is kept.
List<GeoPoint> simplifyStroke(List<GeoPoint> points, double minDistanceM) {
  if (points.length < 3) return List.of(points);
  final kept = [points.first];
  for (final p in points.skip(1).take(points.length - 2)) {
    if (geoDistanceM(kept.last, p) >= minDistanceM) kept.add(p);
  }
  final last = points.last;
  if (kept.length > 1 && geoDistanceM(kept.last, last) < minDistanceM) {
    kept.removeLast();
  }
  return kept..add(last);
}

/// Splits a long stroke into pieces of at most [maxPoints] points that share
/// their end points, so each fits into one document.
List<List<GeoPoint>> splitLongStroke(List<GeoPoint> points, int maxPoints) {
  assert(maxPoints >= 2);
  if (points.length <= maxPoints) return [points];
  return [
    for (var i = 0; i < points.length - 1; i += maxPoints - 1)
      points.sublist(i, min(i + maxPoints, points.length)),
  ];
}

/// Erases everything within [radiusM] of the eraser path from a stroke
/// (R-DRAW-04). Returns the remaining pieces (each with at least two points),
/// or null if the eraser didn't touch the stroke.
List<List<GeoPoint>>? eraseFromStroke(
  List<GeoPoint> points,
  List<GeoPoint> eraserPath,
  double radiusM,
) {
  if (points.isEmpty || eraserPath.isEmpty) return null;
  final lat0 = points.first.lat;
  final eraser = [for (final p in eraserPath) _project(p, lat0)];
  bool erased(GeoPoint p) {
    final q = _project(p, lat0);
    if (eraser.length == 1) return q.distanceTo(eraser.single) <= radiusM;
    for (var i = 0; i + 1 < eraser.length; i++) {
      if (_distanceToSegment(q, eraser[i], eraser[i + 1]) <= radiusM) {
        return true;
      }
    }
    return false;
  }

  // Densify so the eraser can cut long straight segments in the middle;
  // added points are only kept where they end a remaining piece.
  final step = max(radiusM / 2, 0.01);
  final dense = <({GeoPoint point, bool original})>[];
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    if (i > 0) {
      final a = points[i - 1];
      final n = (geoDistanceM(a, p) / step).ceil();
      for (var k = 1; k < n; k++) {
        final t = k / n;
        dense.add((
          point: GeoPoint(
            a.lat + (p.lat - a.lat) * t,
            a.lng + (p.lng - a.lng) * t,
          ),
          original: false,
        ));
      }
    }
    dense.add((point: p, original: true));
  }

  final keep = [for (final d in dense) !erased(d.point)];
  if (keep.every((k) => k)) return null;

  final pieces = <List<GeoPoint>>[];
  var run = <({GeoPoint point, bool original})>[];
  void flush() {
    if (run.length >= 2) {
      pieces.add([
        for (var i = 0; i < run.length; i++)
          if (run[i].original || i == 0 || i == run.length - 1) run[i].point,
      ]);
    }
    run = [];
  }

  for (var i = 0; i < dense.length; i++) {
    if (keep[i]) {
      run.add(dense[i]);
    } else {
      flush();
    }
  }
  flush();
  return pieces;
}
