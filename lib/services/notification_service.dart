// lib/services/notification_service.dart
// Wraps flutter_local_notifications.
// Call [init] once at startup.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  int _idCounter = 0;

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );
    await _plugin.initialize(initSettings);
  }

  Future<void> show(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'photovault_channel',
      'PhotoVault',
      channelDescription: 'PhotoVault notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(_idCounter++, title, body, details);
  }
}
