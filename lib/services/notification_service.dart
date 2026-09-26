import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../engine/preference_learning_engine.dart';

/// This is the RELIABILITY layer.
///
/// Its job is to make sure notifications are scheduled as reliably as
/// possible, regardless of whether other "smart" scheduling logic works.
class NotificationService {
  NotificationService._internal();

  static final NotificationService instance =
      NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Initializes:
  /// - timezone database
  /// - device timezone
  /// - Android notification settings
  /// - iOS notification settings
  /// - Android notification permissions
  /// - Android exact-alarm permission
  Future<void> init() async {
    tzdata.initializeTimeZones();

    // CRITICAL:
    // Without this, tz.local can silently default to UTC.
    // That would cause scheduled notifications to fire at the wrong time.
    final String deviceTimeZone =
        await FlutterTimezone.getLocalTimezone();

    tz.setLocalLocation(
      tz.getLocation(deviceTimeZone),
    );

    const androidSettings =
        AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);

    await _requestAndroidPermissions();
  }

  /// Android 13+ requires runtime notification permission.
  ///
  /// Android 12+ can require exact-alarm permission for precise alarms.
  ///
  /// On some OEM devices such as Vivo, Realme and Oppo, the permission
  /// dialog may not appear reliably. The user may need to manually enable
  /// "Alarms & reminders" from Android Settings.
  Future<void> _requestAndroidPermissions() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) {
      return;
    }

    await androidPlugin.requestNotificationsPermission();

    await androidPlugin.requestExactAlarmsPermission();
  }

  /// Returns whether exact-alarm scheduling is currently available.
  Future<bool> canScheduleExactAlarms() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) {
      // Not Android.
      return true;
    }

    return await androidPlugin.canScheduleExactNotifications() ??
        false;
  }

  /// Schedules a one-time notification.
  ///
  /// First tries exact scheduling.
  ///
  /// If exact-alarm permission isn't available, falls back to
  /// inexact scheduling rather than breaking the Save flow.
  ///
  /// If [taskCategory] is provided, applies two per-category learned preferences:
  /// - lead-time: fires N minutes before [scheduledTime] (default 0 = at task start)
  /// - voice-disable: sets notification to silent if user has disabled voice for that category
  Future<void> scheduleTaskReminder({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? taskCategory,
  }) async {
    // Apply per-category preference rules.
    DateTime fireAt = scheduledTime;
    bool silent = false;
    if (taskCategory != null) {
      final engine = PreferenceLearningEngine.instance;
      final leadMinutes = await engine.getLeadTimeMinutes(taskCategory);
      if (leadMinutes > 0) {
        fireAt = scheduledTime.subtract(Duration(minutes: leadMinutes));
        // Never fire in the past — clamp to now + 5s.
        final earliest = DateTime.now().add(const Duration(seconds: 5));
        if (fireAt.isBefore(earliest)) fireAt = earliest;
      }
      silent = await engine.isVoiceDisabled(taskCategory);
    }

    final tzTime = tz.TZDateTime.from(
      fireAt,
      tz.local,
    );

    final androidDetails = AndroidNotificationDetails(
      'routine_channel',
      'Routine Reminders',
      channelDescription:
          'Voice-linked task reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: !silent,
      enableVibration: !silent,
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode:
            AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException catch (e) {
      // Exact alarms aren't allowed.
      // Fall back to inexact scheduling.
      if (e.code == 'exact_alarms_not_permitted') {
        await _plugin.zonedSchedule(
          notificationId,
          title,
          body,
          tzTime,
          details,
          androidScheduleMode:
              AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } else {
        rethrow;
      }
    }
  }

  /// Schedules a check-in notification for a task.
  Future<void> scheduleCheckIn({
    required int notificationId,
    required String taskName,
    required DateTime checkInTime,
  }) async {
    await scheduleTaskReminder(
      notificationId: notificationId,
      title: 'Check-in',
      body:
          'Is "$taskName" done? Open the app to confirm or reschedule.',
      scheduledTime: checkInTime,
    );
  }

  /// Shows an immediate notification.
  ///
  /// This is useful for diagnostics.
  ///
  /// If this notification appears:
  /// notification permissions and the channel are working.
  ///
  /// If this appears but scheduled notifications don't:
  /// the problem is specifically related to scheduling, Doze,
  /// exact-alarm permissions, or OEM background restrictions.
  Future<void> showTestNotificationNow() async {
    const androidDetails =
        AndroidNotificationDetails(
      'routine_channel',
      'Routine Reminders',
      channelDescription:
          'Voice-linked task reminders',
      importance: Importance.max,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      999999,
      'Test notification',
      'If you see this, notification permission + channel are working.',
      details,
    );
  }

  /// Returns the notifications currently scheduled with the OS.
  ///
  /// Useful for debugging.
  Future<List<PendingNotificationRequest>>
      getPendingNotifications() async {
    return await _plugin.pendingNotificationRequests();
  }

  /// Schedules a test notification 60 seconds from now.
  ///
  /// Useful for testing whether the operating system actually delivers
  /// scheduled notifications.
  Future<void> scheduleNearTermTest() async {
    final target =
        DateTime.now().add(const Duration(seconds: 60));

    await scheduleTaskReminder(
      notificationId: 888888,
      title: 'Scheduled test (1 min)',
      body:
          'If you see this ~60 seconds after tapping the test button, scheduling works.',
      scheduledTime: target,
    );
  }

  /// Cancels a scheduled notification.
  Future<void> cancel(int notificationId) async {
    await _plugin.cancel(notificationId);
  }
}