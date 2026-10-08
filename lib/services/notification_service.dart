import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles local notifications when an EV reaches a faculty pickup point.
/// Other code decides when an EV arrives; this class only shows or removes the alert.
class NotificationService {
  // Private constructor so the app uses the single shared instance below.
  NotificationService._();

  // One shared NotificationService is used throughout the app.
  static final NotificationService instance = NotificationService._();

  // One fixed ID makes a new alert replace the old one instead of creating duplicates.
  static const int arrivalNotificationId = 1001;

  // Flutter plugin used to set up and show local notifications.
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Call before showing notifications to prepare Android settings, create the
  /// `ev_arrival` channel, and request notification permission when needed.
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings);

    // Android channel for EV arrival alerts; high importance and sound help
    // the user notice when the EV is arriving.
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
  }

  /// Shows or updates the current EV arrival notification.
  /// The caller provides the block after checking the EV location and geofence.
  Future<void> showEvArrival({required String blockName}) async {
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

    // Reusing the fixed ID updates the current alert during repeated GPS updates.
    await _plugin.show(
      arrivalNotificationId,
      'EV ARRIVAL',
      'EV has arrived at your $blockName pickup point',
      details,
    );
  }

  /// Removes the current EV arrival alert when the EV leaves the pickup area
  /// or the caller decides the alert is no longer needed.
  Future<void> cancelEvArrival() async {
    await _plugin.cancel(arrivalNotificationId);
  }
}
