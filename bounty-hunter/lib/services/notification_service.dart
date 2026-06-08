import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'bh_alerts';
  static const _channelName = 'Bounty Alerts';
  static const _channelDesc = 'Hospital exit and travel landing alerts';

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onTap,
    );
    _initialized = true;
  }

  void _onTap(NotificationResponse response) {
    // Payload is the target URL — handled by global navigator
    NotificationService.lastPayload = response.payload;
    pendingLaunch?.call(response.payload);
  }

  static String? lastPayload;
  static void Function(String?)? pendingLaunch;

  Future<bool> requestPermission() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return false;
    final granted = await androidPlugin.requestNotificationsPermission();
    return granted ?? false;
  }

  Future<bool> isPermissionGranted() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return false;
    return await androidPlugin.areNotificationsEnabled() ?? false;
  }

  Future<void> scheduleHospitalAlert({
    required int notifId,
    required String targetName,
    required int targetId,
    required int hospUntilSec,
    required int? reward,
    required double? ff,
    required bool? revivable,
  }) async {
    final alertAtSec = hospUntilSec - 60;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (alertAtSec < nowSec - 10) return;

    final scheduledDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.local,
      alertAtSec * 1000,
    );

    final parts = <String>[];
    if (reward != null) parts.add('\$${_fmt(reward)}');
    if (ff != null) parts.add('FF ${ff.toStringAsFixed(2)}');
    if (revivable == true) parts.add('💚 Revivable');
    final body = parts.join(' · ');

    await _plugin.zonedSchedule(
      notifId,
      '🏥 $targetName exits hospital soon',
      body.isEmpty ? 'Tap to attack' : body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          vibrationPattern: Int64List.fromList(const [0, 400, 150, 400, 150, 600]),
          playSound: true,
          ticker: '$targetName exits hospital',
        ),
      ),
      payload: 'https://www.torn.com/profiles.php?XID=$targetId',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> scheduleTravelAlert({
    required int notifId,
    required String targetName,
    required int targetId,
    required int landingTs,
  }) async {
    final alertAtSec = landingTs - 60;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (alertAtSec < nowSec - 10) return;

    final scheduledDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.local,
      alertAtSec * 1000,
    );

    await _plugin.zonedSchedule(
      notifId,
      '✈️ $targetName landing soon',
      'Marked target returning to Torn',
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
        ),
      ),
      payload: 'https://www.torn.com/profiles.php?XID=$targetId',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelNotification(int id) => _plugin.cancel(id);

  Future<void> cancelAll() => _plugin.cancelAll();

  static String _fmt(int n) {
    if (n >= 1000000000) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1000000) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1e3).toStringAsFixed(0)}K';
    return n.toString();
  }
}

