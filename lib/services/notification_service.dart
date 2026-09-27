import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../engine/preference_learning_engine.dart';
import '../db/database_helper.dart';
import '../models/routine_models.dart';
import '../screens/wake_alarm_screen.dart';
import '../screens/routine_confirm_screen.dart';

/// Global navigator key — allows notification taps to push routes
/// without a BuildContext.
final GlobalKey<NavigatorState> routineNavigatorKey =
    GlobalKey<NavigatorState>();

/// Top-level background callback (must be a top-level function).
@pragma('vm:entry-point')
void _onNotificationTapBackground(NotificationResponse response) {
  // Background taps: store payload for app to handle on next launch.
  // The foreground handler covers most real-world cases.
}

void _onNotificationTap(NotificationResponse response) {
  _handleNotificationPayload(response.payload);
}

void _handleNotificationPayload(String? payload) {
  if (payload == null) return;
  // Accept both 'routine:' and 'missed:' prefixes
  final isRoutine = payload.startsWith('routine:');
  final isMissed  = payload.startsWith('missed:');
  if (!isRoutine && !isMissed) return;

  final parts = payload.split(':');
  if (parts.length < 3) return;

  final entryId  = parts[1];
  final typeName = parts[2];

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final navigator = routineNavigatorKey.currentState;
    if (navigator == null) return;

    if (isRoutine && typeName == 'wakeUp') {
      final entry = await DatabaseHelper.instance.getRoutineEntry(entryId);
      navigator.push(MaterialPageRoute(
        builder: (_) => WakeAlarmScreen(entry: entry),
      ));
    } else {
      // All other routine + all missed payloads → confirm screen
      final entry = await DatabaseHelper.instance.getRoutineEntry(entryId);
      if (entry != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => RoutineConfirmScreen(entry: entry),
          fullscreenDialog: true,
        ));
      }
    }
  });
}

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

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapBackground,
    );

    // Explicitly create all notification channels used by this app.
    // Android 8+ silently drops notifications on unregistered channels.
    await _createAndroidChannels();

    await _requestAndroidPermissions();
  }

  Future<void> _createAndroidChannels() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    const channels = [
      AndroidNotificationChannel(
        'routine_channel',
        'Routine Reminders',
        description: 'Voice-linked task reminders',
        importance: Importance.max,
      ),
      AndroidNotificationChannel(
        'routine_companion',
        'Routine Companion',
        description: 'Daily routine voice reminders',
        importance: Importance.max,
      ),
      AndroidNotificationChannel(
        'routine_wake_alarm',
        'Wake Alarm',
        description: 'Hard-to-dismiss morning wake-up alarm',
        importance: Importance.max,
      ),
      AndroidNotificationChannel(
        'routine_missed',
        'Missed Routine Reminders',
        description: 'Alerts for unconfirmed routine tasks',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'routine_rescheduled',
        'Rescheduled Routine',
        description: 'Your rescheduled routine reminders',
        importance: Importance.high,
      ),
    ];

    for (final ch in channels) {
      await androidPlugin.createNotificationChannel(ch);
    }
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

  // ── Routine Confirmation Notifications ─────────────────────────────────────

  /// Show a "you missed this" notification for an unconfirmed routine entry.
  Future<void> showMissedRoutineNotification(RoutineEntry entry) async {
    const androidDetails = AndroidNotificationDetails(
      'routine_missed',
      'Missed Routine Reminders',
      channelDescription: 'Alerts for unconfirmed routine tasks',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const details = NotificationDetails(android: androidDetails);
    // Use stable ID derived from entry.id string to avoid hashCode collisions.
    final notifId = 4000 + entry.id.hashCode.abs() % 1000;
    await _plugin.show(
      notifId,
      '${entry.type.emoji} Missed: ${entry.label}',
      'Tap to confirm, reschedule, or skip.',
      details,
      payload: 'missed:${entry.id}:${entry.type.name}',
    );
  }

  /// Schedule a one-shot reminder when the user reschedules an entry.
  Future<void> scheduleRescheduledReminder(
      RoutineEntry entry, int minutesSinceMidnight) async {
    final now = DateTime.now();
    final fireAt = DateTime(
      now.year, now.month, now.day,
      minutesSinceMidnight ~/ 60,
      minutesSinceMidnight % 60,
    );
    if (fireAt.isBefore(now)) return;

    final tzTime = tz.TZDateTime.from(fireAt, tz.local);
    const androidDetails = AndroidNotificationDetails(
      'routine_rescheduled',
      'Rescheduled Routine',
      channelDescription: 'Your rescheduled routine reminders',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    final notifId = 5000 + entry.id.hashCode.abs() % 1000;

    try {
      await _plugin.zonedSchedule(
        notifId,
        '${entry.type.emoji} ${entry.label} (rescheduled)',
        entry.message.length > 80
            ? '${entry.message.substring(0, 80)}…'
            : entry.message,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'routine:${entry.id}:${entry.type.name}',
      );
    } on PlatformException {
      await _plugin.zonedSchedule(
        notifId,
        '${entry.type.emoji} ${entry.label} (rescheduled)',
        entry.message.length > 80
            ? '${entry.message.substring(0, 80)}…'
            : entry.message,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'routine:${entry.id}:${entry.type.name}',
      );
    }
  }
}