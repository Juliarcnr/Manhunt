import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:manhunt/core/crypto/group_crypto.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/data/firestore_game_repository.dart';
import 'package:manhunt/data/firestore_round_repository.dart';
import 'package:manhunt/data/game_repository.dart';
import 'package:manhunt/data/location_service.dart';
import 'package:manhunt/data/notification_service.dart';
import 'package:manhunt/data/session_store.dart';
import 'package:manhunt/state/providers.dart';

/// Fast key derivation for tests.
Future<GroupCrypto> testCrypto(String code) =>
    GroupCrypto.derive(code, iterations: 10);

Future<GroupSession> testSession(String code, String userId) async =>
    GroupSession(code: code, crypto: await testCrypto(code), userId: userId);

const defaultSettings = GameSettings();

FirestoreGameRepository deviceRepo(FakeFirebaseFirestore db) =>
    FirestoreGameRepository(db);

/// Provider overrides for one simulated device sharing [db] with others.
List<Override> deviceOverrides({
  required FakeFirebaseFirestore db,
  required String userId,
  SessionStore? store,
  DateTime Function()? now,
  LocationService? location,
  NotificationService? notifications,
}) => [
  gameRepositoryProvider.overrideWithValue(
    FirestoreGameRepository(db, now: now),
  ),
  sessionStoreProvider.overrideWithValue(store ?? MemorySessionStore()),
  userIdProvider.overrideWithValue(() async => userId),
  cryptoFactoryProvider.overrideWithValue(testCrypto),
  locationServiceProvider.overrideWithValue(location ?? FakeLocationService()),
  roundRepositoryProvider.overrideWithValue(FirestoreRoundRepository(db)),
  notificationServiceProvider.overrideWithValue(
    notifications ?? SilentNotificationService(),
  ),
];

/// Controllable location: [position] for one-off lookups, [emit] to feed the
/// tracking stream. Records whether tracking is active.
class FakeLocationService implements LocationService {
  FakeLocationService({this.position});

  GeoPoint? position;
  var permissionGranted = true;
  var currentCalls = 0;
  var trackCalls = 0;
  final _fixes = StreamController<LocationFix>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  var trackingListeners = 0;
  TrackingNotice? lastNotice;

  bool get isTracking => trackingListeners > 0;

  void emit(LocationFix fix) => _fixes.add(fix);

  /// Simulates the GPS stream failing (e.g. a platform exception).
  void fail(Object error) => _errors.add(error);

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Future<GeoPoint?> currentPosition() async {
    currentCalls++;
    return permissionGranted ? position : null;
  }

  @override
  Stream<LocationFix> track(TrackingNotice notice) {
    lastNotice = notice;
    trackCalls++;
    if (!permissionGranted) {
      return Stream.error(const LocationPermissionMissing());
    }
    late StreamController<LocationFix> c;
    final subs = <StreamSubscription<Object>>[];
    c = StreamController<LocationFix>(
      onListen: () {
        trackingListeners++;
        subs
          ..add(_fixes.stream.listen(c.add))
          ..add(_errors.stream.listen(c.addError));
      },
      onCancel: () async {
        trackingListeners--;
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return c.stream;
  }
}
