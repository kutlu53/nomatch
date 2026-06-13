import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data' show Int64List;
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification types for the app
enum NomatchNotificationType {
  /// Purple: Public mode pair request received
  pairRequest,

  /// Lime/Green: Radar mode heading match (pairing success)
  radarMatch,
}

/// Silent visual notification service — no text, no sound.
/// Only vibration + app icon banner when app is in background.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Bildirime tap edildiğinde yayınlanan stream (public moda yönlendirme için)
  final _tapController = StreamController<NomatchNotificationType>.broadcast();
  Stream<NomatchNotificationType> get onTap => _tapController.stream;

  // Android notification channel IDs
  static const _channelId = 'nomatch_pairing';
  static const _channelName = 'Nomatch Pairing';

  // Vibration patterns (ms): [wait, vibrate, wait, vibrate, ...]
  // Short double-tap for pair request
  static const _vibrationRequest = <int>[0, 200, 100, 200];
  // Long single pulse for radar match
  static const _vibrationMatch = <int>[0, 400, 200, 400];

  /// Initialize the notification plugin (call once at app startup)
  Future<void> initialize() async {
    if (_initialized) return;

    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings — no sound, request permission for alerts + badges
    const iosSettings = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        final type = NomatchNotificationType.values
            .where((t) => t.name == details.payload)
            .firstOrNull;
        if (type != null) {
          dev.log('[NOTIF] 👆 Notification tapped: $type');
          _tapController.add(type);
        }
      },
    );

    // Create Android notification channel (silent + vibration)
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
          showBadge: true,
        ),
      );
    }

    // Request iOS notification permissions
    final iosPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: false,
      );
    }

    _initialized = true;
    dev.log('[NOTIF] ✅ NotificationService initialized');
  }

  /// Show a silent notification (no text, no sound — only vibration + banner)
  Future<void> notify(NomatchNotificationType type) async {
    if (!_initialized) {
      dev.log('[NOTIF] ⚠️ Not initialized, skipping notification');
      return;
    }

    dev.log('[NOTIF] 📳 Triggering notification: $type');

    final vibration = switch (type) {
      NomatchNotificationType.pairRequest => _vibrationRequest,
      NomatchNotificationType.radarMatch => _vibrationMatch,
    };

    // Android color (ARGB int)
    final color = switch (type) {
      NomatchNotificationType.pairRequest => 0xFF9C27B0, // Purple
      NomatchNotificationType.radarMatch => 0xFF76FF03, // Lime
    };

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(vibration),
      color: Color(color),
      colorized: true,
      // Minimal content — Android requires title but space is invisible
      ticker: null,
      showWhen: false,
      autoCancel: true,
      // Silent
      silent: false, // false = allow vibration, true = suppress everything
    );

    const iosDetails = DarwinNotificationDetails(
      presentSound: false,
      presentBadge: true,
      presentBanner: true,
      presentList: false,
      // interruptionLevel on iOS 15+: active = shows banner silently
      interruptionLevel: InterruptionLevel.active,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Notification ID: use type index to replace previous same-type notification
    final id = type.index;

    // Title/body: single space (invisible but required for banner to show)
    await _plugin.show(
      id,
      ' ', // invisible title
      null, // no body
      details,
      payload: type.name, // bildirime tap edilince hangi tip olduğunu bilmek için
    );

    dev.log('[NOTIF] ✅ Notification shown: $type');
  }

  /// Cancel all notifications (e.g., when app comes to foreground)
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
