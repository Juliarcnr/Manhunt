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

/// Device location access.
abstract interface class LocationService {
  /// Current position, or null if permission was denied / location is off.
  Future<GeoPoint?> currentPosition();

  /// Continuous positions while a round runs, also in the background
  /// (R-PING-03): Android foreground service with a permanent notification,
  /// iOS background location mode. Cancel the subscription to stop (R-PRIV-04).
  /// Emits nothing if permission is missing.
  Stream<LocationFix> track(TrackingNotice notice);
}

class GeolocatorLocationService implements LocationService {
  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  @override
  Future<GeoPoint?> currentPosition() async {
    if (!await _ensurePermission()) return null;
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return GeoPoint(pos.latitude, pos.longitude);
  }

  @override
  Stream<LocationFix> track(TrackingNotice notice) async* {
    if (!await _ensurePermission()) return;
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
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 10),
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
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }
}
