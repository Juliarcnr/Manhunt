import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// System notifications (R-NOTIF-01). Sound follows the phone's settings: the
/// OS plays it only when the phone is not muted (R-NOTIF-05).
abstract interface class NotificationService {
  /// Requests permission (Android 13+, iOS). Safe to call repeatedly.
  Future<void> init();

  /// [foreground]: the app is open and shows its own banner, so the
  /// notification is only used for the sound – no pop-up, gone after a few
  /// seconds. Otherwise a normal notification with sound/vibration as the
  /// phone is set.
  Future<void> show({
    required String title,
    required String body,
    bool foreground = false,
  });
}

class LocalNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  var _initialized = false;
  var _nextId = 0;

  static const _channelId = 'game_events';

  /// Separate channel (Android channels cannot change later): default
  /// importance = sound but no heads-up pop-up; vibration is done by the app.
  static const _foregroundChannelId = 'game_events_sound';

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

  static const _background = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Manhunt',
      channelDescription: 'Catches, speedhunts and your pings',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
    ),
    iOS: DarwinNotificationDetails(presentSound: true),
  );

  static const _foreground = NotificationDetails(
    android: AndroidNotificationDetails(
      _foregroundChannelId,
      'Manhunt (app open)',
      channelDescription: 'Sound for game events while the app is open',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      enableVibration: false,
      timeoutAfter: 5000,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: false,
      presentBanner: false,
      presentList: false,
      presentSound: true,
    ),
  );

  @override
  Future<void> show({
    required String title,
    required String body,
    bool foreground = false,
  }) async {
    await init();
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: foreground ? _foreground : _background,
    );
  }
}

/// Records instead of showing – for tests and platforms without
/// notifications.
class SilentNotificationService implements NotificationService {
  final shown = <({String title, String body, bool foreground})>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> show({
    required String title,
    required String body,
    bool foreground = false,
  }) async => shown.add((title: title, body: body, foreground: foreground));
}
