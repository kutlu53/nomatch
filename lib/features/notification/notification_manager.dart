import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:developer' as dev;
import 'dart:typed_data';

/// Bildirim yöneticisi - Emoji-only bildirimleri yönetir
class NotificationManager {
  static final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  static bool _initialized = false;

  /// Initialize notification system
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(initSettings);
      _initialized = true;
      dev.log('NOTIFICATION: Initialized');
    } catch (e) {
      dev.log('NOTIFICATION: Init failed - $e');
    }
  }

  /// Eşleşme bildirimi gönder (sadece emoji)
  static Future<void> showMatchNotification() async {
    if (!_initialized) {
      dev.log('NOTIFICATION: Not initialized, skipping');
      return;
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        'match_channel',
        'Match Notifications',
        channelDescription: 'Notifications when a match is found',
        importance: Importance.high,
        priority: Priority.high,
        playSound: false, // Sessiz uygulama
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 300, 200, 300, 200, 300]), // 3x titreşim
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        1, // Notification ID
        '🎉', // Title (sadece emoji)
        '✨', // Body (sadece emoji)
        details,
      );

      dev.log('NOTIFICATION: Match notification sent 🎉');
    } catch (e) {
      dev.log('NOTIFICATION: Failed to show - $e');
    }
  }

  /// İzin kontrolü (iOS için)
  static Future<bool> hasPermission() async {
    if (!_initialized) return false;

    try {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: false,
            sound: false,
          );

      return result ?? true; // Android için true (permission gerektirmez)
    } catch (e) {
      dev.log('NOTIFICATION: Permission check failed - $e');
      return false;
    }
  }

  /// Tüm bildirimleri temizle
  static Future<void> cancelAll() async {
    try {
      await _notifications.cancelAll();
      dev.log('NOTIFICATION: All cancelled');
    } catch (e) {
      dev.log('NOTIFICATION: Cancel failed - $e');
    }
  }
}
