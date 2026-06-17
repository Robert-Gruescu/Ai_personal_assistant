import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Notification Service for local notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initialize the notification service
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Initialize timezone
      tz_data.initializeTimeZones();

      // Android settings
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      // iOS settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final result = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Request permissions on Android 13+
      await _requestPermissions();

      _isInitialized = result ?? false;
      print('✅ Notification service initialized: $_isInitialized');
      return _isInitialized;
    } catch (e) {
      print('❌ Failed to initialize notifications: $e');
      return false;
    }
  }

  Future<void> _requestPermissions() async {
    try {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        await androidPlugin.requestExactAlarmsPermission();
      }
    } catch (e) {
      print('⚠️ Permission request error: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    print('🔔 Notification tapped: ${response.payload}');
    // Could navigate to meeting or open Meet link
  }

  /// Schedule a meeting reminder notification
  Future<bool> scheduleMeetingReminder({
    required int id,
    required String title,
    required String meetLink,
    required DateTime meetingTime,
    int minutesBefore = 30,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final reminderTime = meetingTime.subtract(
        Duration(minutes: minutesBefore),
      );

      // Don't schedule if reminder time is in the past
      if (reminderTime.isBefore(DateTime.now())) {
        print('⚠️ Reminder time is in the past, skipping');
        return false;
      }

      final scheduledDate = tz.TZDateTime.from(reminderTime, tz.local);

      const androidDetails = AndroidNotificationDetails(
        'meeting_reminders',
        'Întâlniri',
        channelDescription: 'Notificări pentru întâlniri programate',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.zonedSchedule(
        id,
        '📅 Întâlnire în $minutesBefore minute',
        '$title\nApasă pentru a intra în Meet',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: meetLink,
      );

      print(
        '✅ Reminder scheduled for $scheduledDate ($minutesBefore min before)',
      );
      return true;
    } catch (e) {
      print('❌ Failed to schedule reminder: $e');
      return false;
    }
  }

  /// Schedule a notification at the exact meeting time
  Future<bool> scheduleMeetingStartNotification({
    required int id,
    required String title,
    required String meetLink,
    required DateTime meetingTime,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Don't schedule if meeting time is in the past
      if (meetingTime.isBefore(DateTime.now())) {
        print('⚠️ Meeting time is in the past, skipping');
        return false;
      }

      final scheduledDate = tz.TZDateTime.from(meetingTime, tz.local);

      const androidDetails = AndroidNotificationDetails(
        'meeting_start',
        'Începere Întâlniri',
        channelDescription: 'Notificări când începe o întâlnire',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.zonedSchedule(
        id + 1000, // Different ID for start notification
        '🚨 Întâlnirea începe ACUM!',
        '$title\nApasă pentru a intra în Meet',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: meetLink,
      );

      print('✅ Meeting start notification scheduled for $scheduledDate');
      return true;
    } catch (e) {
      print('❌ Failed to schedule meeting start notification: $e');
      return false;
    }
  }

  /// Schedule a reminder for a task that has a due date/time.
  /// Notifică cu `minutesBefore` minute înainte de termen (implicit 10).
  Future<bool> scheduleTaskReminder({
    required int id,
    required String title,
    required DateTime taskTime,
    int minutesBefore = 10,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final reminderTime = taskTime.subtract(Duration(minutes: minutesBefore));

      // Nu programa dacă momentul reminderului e deja trecut.
      if (reminderTime.isBefore(DateTime.now())) {
        print('⚠️ Task reminder time is in the past, skipping');
        return false;
      }

      final scheduledDate = tz.TZDateTime.from(reminderTime, tz.local);

      const androidDetails = AndroidNotificationDetails(
        'task_reminders',
        'Reminder task-uri',
        channelDescription: 'Notificări pentru task-uri cu termen',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.zonedSchedule(
        id,
        '🔔 Task în $minutesBefore minute',
        title,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      print(
        '✅ Task reminder scheduled for $scheduledDate ($minutesBefore min before)',
      );
      return true;
    } catch (e) {
      print('❌ Failed to schedule task reminder: $e');
      return false;
    }
  }

  /// Cancel a scheduled notification
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
    await _notifications.cancel(id + 1000); // Cancel both reminder and start
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Show immediate notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    const androidDetails = AndroidNotificationDetails(
      'general',
      'General',
      channelDescription: 'Notificări generale',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(id, title, body, details, payload: payload);
  }
}
