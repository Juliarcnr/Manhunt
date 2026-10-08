import 'dart:math';

import '../models/geo_point.dart';

const _earthRadiusM = 6371000.0;

/// Ray-casting point-in-polygon test; fine for play areas of a few km.
bool isInsidePolygon(GeoPoint p, List<GeoPoint> polygon) {
  if (polygon.length < 3) return false;
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    final crosses =
        (a.lat > p.lat) != (b.lat > p.lat) &&
        p.lng < (b.lng - a.lng) * (p.lat - a.lat) / (b.lat - a.lat) + a.lng;
    if (crosses) inside = !inside;
  }
  return inside;
}

/// Projection to a local flat plane in metres (equirectangular around the
/// polygon's mean latitude). Accurate enough for areas of a few km.
Point<double> Function(GeoPoint) _projection(List<GeoPoint> polygon) {
  final lat0 =
      polygon.map((p) => p.lat).reduce((a, b) => a + b) / polygon.length;
  final cosLat = cos(lat0 * pi / 180);
  return (p) => Point(
    _earthRadiusM * p.lng * pi / 180 * cosLat,
    _earthRadiusM * p.lat * pi / 180,
  );
}

List<Point<double>> _toMetres(List<GeoPoint> polygon) {
  final project = _projection(polygon);
  return [for (final p in polygon) project(p)];
}

/// Signed distance in metres from [p] to the edge of [polygon]: positive
/// outside, negative inside (R-OUT-01). Null without a valid polygon.
double? distanceOutsideM(GeoPoint p, List<GeoPoint> polygon) {
  if (polygon.length < 3) return null;
  final project = _projection(polygon);
  final pts = [for (final v in polygon) project(v)];
  final q = project(p);
  var nearest = double.infinity;
  for (var i = 0; i < pts.length; i++) {
    final edge = _distanceToSegment(q, pts[i], pts[(i + 1) % pts.length]);
    nearest = min(nearest, edge);
  }
  return isInsidePolygon(p, polygon) ? -nearest : nearest;
}

double _distanceToSegment(Point<double> p, Point<double> a, Point<double> b) {
  final ab = b - a;
  final lengthSq = ab.x * ab.x + ab.y * ab.y;
  if (lengthSq == 0) return p.distanceTo(a);
  final t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSq;
  final c = t.clamp(0.0, 1.0);
  return p.distanceTo(Point(a.x + ab.x * c, a.y + ab.y * c));
}

/// Area of the play area in km² (shown while drawing, R-SET-06).
double polygonAreaKm2(List<GeoPoint> polygon) {
  if (polygon.length < 3) return 0;
  final pts = _toMetres(polygon);
  var sum = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2 / 1e6;
}

/// Width (east–west) and height (north–south) of the bounding box in km.
({double widthKm, double heightKm}) polygonExtentKm(List<GeoPoint> polygon) {
  if (polygon.length < 2) return (widthKm: 0, heightKm: 0);
  final pts = _toMetres(polygon);
  final xs = pts.map((p) => p.x);
  final ys = pts.map((p) => p.y);
  return (
    widthKm: (xs.reduce(max) - xs.reduce(min)) / 1000,
    heightKm: (ys.reduce(max) - ys.reduce(min)) / 1000,
  );
}

/// True if no two edges cross (a "bow tie" shape is not a valid play area).
bool isSimplePolygon(List<GeoPoint> polygon) {
  final n = polygon.length;
  if (n < 4) return n == 3;
  final pts = _toMetres(polygon);
  for (var i = 0; i < n; i++) {
    final a1 = pts[i];
    final a2 = pts[(i + 1) % n];
    for (var j = i + 1; j < n; j++) {
      // Skip neighbouring edges, they share a vertex.
      if (j == i || (j + 1) % n == i || (i + 1) % n == j) continue;
      if (_segmentsCross(a1, a2, pts[j], pts[(j + 1) % n])) return false;
    }
  }
  return true;
}

bool _segmentsCross(
  Point<double> p1,
  Point<double> p2,
  Point<double> q1,
  Point<double> q2,
) {
  double orient(Point<double> a, Point<double> b, Point<double> c) =>
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  final d1 = orient(q1, q2, p1);
  final d2 = orient(q1, q2, p2);
  final d3 = orient(p1, p2, q1);
  final d4 = orient(p1, p2, q2);
  return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
}
