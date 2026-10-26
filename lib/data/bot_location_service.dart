import 'dart:async';
import 'dart:math';

import '../core/bots/bot_walk.dart';
import '../core/models/geo_point.dart';
import '../core/round/ping_schedule.dart';
import 'location_service.dart';

/// Simulated GPS of a computer member (R-BOT-04): walks within [botRadiusM]
/// around its carrier's current position ([anchor]). Keeps the last known
/// anchor when the carrier's position is gone (e.g. caught).
class BotLocationService implements LocationService {
  BotLocationService({
    required this.anchor,
    Random? random,
    this.interval = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _random = random ?? Random(),
       _now = now ?? DateTime.now {
    _walk = BotWalk.random(_random);
  }

  final LocationFix? Function() anchor;
  final Duration interval;
  final Random _random;
  final DateTime Function() _now;
  late BotWalk _walk;
  GeoPoint? _lastAnchor;

  LocationFix? _fix() {
    final point = anchor()?.point ?? _lastAnchor;
    if (point == null) return null;
    _lastAnchor = point;
    return LocationFix(
      point: _walk.at(point),
      at: _now().toUtc(),
      accuracyM: 5,
    );
  }

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<GeoPoint?> currentPosition() async => _fix()?.point;

  @override
  Future<LocationFix?> currentFix() async => _fix();

  @override
  Stream<LocationFix> track(TrackingNotice notice) {
    Timer? timer;
    late StreamController<LocationFix> c;
    c = StreamController<LocationFix>(
      onListen: () => timer = Timer.periodic(interval, (_) {
        _walk = _walk.step(interval, _random);
        final fix = _fix();
        if (fix != null) c.add(fix);
      }),
      onCancel: () => timer?.cancel(),
    );
    return c.stream;
  }
}
