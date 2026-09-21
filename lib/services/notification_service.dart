import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int arrivalNotificationId = 1001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings);

    const channel = AndroidNotificationChannel(
      'ev_arrival',
      'EV Arrival',
      description: 'Notifications when the VIT EV buggy is arriving.',
      importance: Importance.high,
      playSound: true,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(channel);

    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> showEvArrival({required String blockName}) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'ev_arrival',
      'EV Arrival',
      channelDescription: 'Notifications when the VIT EV buggy is arriving.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      arrivalNotificationId,
      'EV ARRIVAL',
      'EV has arrived at your $blockName pickup point',
      details,
    );
  }

  Future<void> cancelEvArrival() async {
    if (!_initialized) return;
    await _plugin.cancel(arrivalNotificationId);
  }
}
