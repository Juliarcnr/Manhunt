import '../models/geo_point.dart';

/// The four pen colours of the hunters' drawing mode (R-DRAW-03).
enum StrokeColor { red, blue, green, black }

/// One freehand line drawn by a hunter on the map (R-DRAW-01).
class Stroke {
  const Stroke({
    required this.id,
    required this.uid,
    required this.color,
    required this.points,
  });

  /// Document id; empty for a stroke not yet stored.
  final String id;

  /// The hunter who drew it.
  final String uid;
  final StrokeColor color;
  final List<GeoPoint> points;

  /// Encrypted payload: colour and points as a flat `[lat, lng, …]` list,
  /// rounded to ~10 cm to keep documents small.
  Map<String, Object?> toJson() => {
    'c': color.name,
    'p': [
      for (final p in points) ...[_round(p.lat), _round(p.lng)],
    ],
  };

  factory Stroke.fromJson(
    Map<String, Object?> json, {
    required String id,
    required String uid,
  }) {
    final flat = (json['p']! as List).cast<num>();
    return Stroke(
      id: id,
      uid: uid,
      color: StrokeColor.values.asNameMap()[json['c']] ?? StrokeColor.red,
      points: [
        for (var i = 0; i + 1 < flat.length; i += 2)
          GeoPoint(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
    );
  }

  static double _round(double v) => (v * 1e6).roundToDouble() / 1e6;
}
