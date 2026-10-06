import 'dart:math';

import '../models/geo_point.dart';

/// Direction marker for a path: placed at the middle of a segment, pointing
/// from its start to its end (R-HUNT-05).
class PathArrow {
  const PathArrow({required this.at, required this.bearingRad});

  final GeoPoint at;

  /// Clockwise from north, in radians – the map is always north-up (R-MAP-02),
  /// so this is also the angle on screen.
  final double bearingRad;
}

/// One arrow per segment of [path] (chronological points). Segments without
/// movement get no arrow.
List<PathArrow> pathArrows(List<GeoPoint> path) => [
  for (var i = 0; i + 1 < path.length; i++)
    if (path[i] != path[i + 1])
      PathArrow(
        at: GeoPoint(
          (path[i].lat + path[i + 1].lat) / 2,
          (path[i].lng + path[i + 1].lng) / 2,
        ),
        bearingRad: _bearing(path[i], path[i + 1]),
      ),
];

/// Bearing on a local flat projection (fine for a few km).
double _bearing(GeoPoint a, GeoPoint b) {
  final meanLat = (a.lat + b.lat) / 2 * pi / 180;
  final dx = (b.lng - a.lng) * cos(meanLat);
  final dy = b.lat - a.lat;
  return atan2(dx, dy);
}
