import 'dart:math';

import '../models/geo_point.dart';

/// How far a computer member walks from its carrier's position (R-BOT-04).
const botRadiusM = 100.0;

/// Random walk of a computer member around an anchor (its carrier's
/// position), in metres east/north of it. Never leaves [botRadiusM].
class BotWalk {
  const BotWalk({
    this.eastM = 0,
    this.northM = 0,
    this.heading = 0,
    this.pause = Duration.zero,
  });

  /// Starts somewhere within [radiusM], heading anywhere.
  factory BotWalk.random(Random random, {double radiusM = botRadiusM}) {
    final r = radiusM * sqrt(random.nextDouble());
    final a = random.nextDouble() * 2 * pi;
    return BotWalk(
      eastM: r * sin(a),
      northM: r * cos(a),
      heading: random.nextDouble() * 2 * pi,
    );
  }

  final double eastM;
  final double northM;

  /// Walking direction in radians, clockwise from north.
  final double heading;

  /// Standing still for this long.
  final Duration pause;

  double get distanceM => sqrt(eastM * eastM + northM * northM);

  /// About [speedMps] in a slowly changing direction, now and then standing
  /// still for a while; at the edge of [radiusM] it turns back inwards.
  BotWalk step(
    Duration dt,
    Random random, {
    double radiusM = botRadiusM,
    double speedMps = 1.3,
  }) {
    final seconds = dt.inMilliseconds / 1000;
    if (pause > Duration.zero) {
      final left = pause - dt;
      return BotWalk(
        eastM: eastM,
        northM: northM,
        heading: heading,
        pause: left > Duration.zero ? left : Duration.zero,
      );
    }
    if (random.nextDouble() < 0.02 * seconds) {
      return BotWalk(
        eastM: eastM,
        northM: northM,
        heading: heading,
        pause: Duration(seconds: 5 + random.nextInt(16)),
      );
    }
    var h = heading + (random.nextDouble() - 0.5) * 0.8 * seconds;
    var e = eastM + sin(h) * speedMps * seconds;
    var n = northM + cos(h) * speedMps * seconds;
    final d = sqrt(e * e + n * n);
    if (d > radiusM) {
      e = e / d * radiusM;
      n = n / d * radiusM;
      // Back towards the anchor, not exactly through it.
      h = atan2(-e, -n) + (random.nextDouble() - 0.5);
    }
    return BotWalk(eastM: e, northM: n, heading: h);
  }

  /// The position for the anchor's current location.
  GeoPoint at(GeoPoint anchor) {
    const metresPerDegree = 111320.0;
    return GeoPoint(
      anchor.lat + northM / metresPerDegree,
      anchor.lng + eastM / (metresPerDegree * cos(anchor.lat * pi / 180)),
    );
  }
}
