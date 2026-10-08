import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../core/models/geo_point.dart';
import '../core/round/ping_schedule.dart';

/// Text of the permanent Android notification while tracking (localized by
/// the caller; the service has no BuildContext).
class TrackingNotice {
  const TrackingNotice({required this.title, required this.text});

  final String title;
  final String text;
}

/// Location access is not granted (or location services are off).
class LocationPermissionMissing implements Exception {
  const LocationPermissionMissing();
}

/// Device location access.
abstract interface class LocationService {
  /// Asks for location permission if needed. Concurrent calls share one
  /// request: Android aborts a second permission dialog while one is open.
  Future<bool> ensurePermission();

  /// Current position, or null if permission was denied / location is off.
  Future<GeoPoint?> currentPosition();

  /// Like [currentPosition], with the reported accuracy – needed to tell
  /// whether a player left the play area (R-OUT-02).
  Future<LocationFix?> currentFix();

  /// Continuous positions while a round runs, also in the background
  /// (R-PING-03): Android foreground service with a permanent notification,
  /// iOS background location mode. Cancel the subscription to stop (R-PRIV-04).
  /// Fails with [LocationPermissionMissing] if access is not granted.
  Stream<LocationFix> track(TrackingNotice notice);
}

class GeolocatorLocationService implements LocationService {
  Future<bool>? _pending;

  @override
  Future<bool> ensurePermission() =>
      _pending ??= _requestPermission().whenComplete(() => _pending = null);

  Future<bool> _requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  @override
  Future<GeoPoint?> currentPosition() async => (await currentFix())?.point;

  @override
  Future<LocationFix?> currentFix() async {
    if (!await ensurePermission()) return null;
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return LocationFix(
      point: GeoPoint(pos.latitude, pos.longitude),
      at: pos.timestamp.toUtc(),
      accuracyM: pos.accuracy,
    );
  }

  @override
  Stream<LocationFix> track(TrackingNotice notice) async* {
    if (!await ensurePermission()) throw const LocationPermissionMissing();
    yield* Geolocator.getPositionStream(locationSettings: _settings(notice))
        .map(
          (p) => LocationFix(
            point: GeoPoint(p.latitude, p.longitude),
            at: p.timestamp.toUtc(),
            accuracyM: p.accuracy,
          ),
        );
  }

  LocationSettings _settings(TrackingNotice notice) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        // No distance filter: also deliver updates while standing still, so a
        // fresh position is available at every ping.
        distanceFilter: 0,
        // About one fix per second keeps the own dot moving smoothly
        // (R-MAP-04). GPS is on anyway; uploads stay throttled by the engine.
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: notice.title,
          notificationText: notice.text,
          notificationChannelName: 'Manhunt',
          setOngoing: true,
          enableWakeLock: true,
        ),
      );
    }
    if (Platform.isIOS) {
      // Started in the foreground with "while in use" permission, iOS keeps
      // delivering updates in the background (blue status bar indicator).
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.fitness,
        // Every update (about one per second) for a smoothly moving own dot
        // (R-MAP-04); uploads stay throttled by the engine.
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }
}
