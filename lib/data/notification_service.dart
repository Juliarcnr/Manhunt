import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// System notifications with vibration for when the app is in the background
/// or the screen is off (R-NOTIF-01). In the foreground the game screen shows
/// an in-app banner instead.
abstract interface class NotificationService {
  /// Requests permission (Android 13+, iOS). Safe to call repeatedly.
  Future<void> init();

  Future<void> show({required String title, required String body});
}

class LocalNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  var _initialized = false;
  var _nextId = 0;

  static const _channelId = 'game_events';

  @override
  Future<void> init() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  @override
  Future<void> show({required String title, required String body}) async {
    await init();
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Manhunt',
          channelDescription: 'Catches, speedhunts and your pings',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
    );
  }
}

/// Does nothing – for tests and platforms without notifications.
class SilentNotificationService implements NotificationService {
  final shown = <(String, String)>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> show({required String title, required String body}) async =>
      shown.add((title, body));
}
