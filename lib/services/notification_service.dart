import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../engine/preference_learning_engine.dart';
import '../db/database_helper.dart';
import '../models/task.dart';
import '../models/routine_models.dart';
import '../screens/wake_alarm_screen.dart';
import '../screens/routine_confirm_screen.dart';
import 'tts_service.dart';

/// Global navigator key — allows notification taps to push routes
/// without a BuildContext.
final GlobalKey<NavigatorState> routineNavigatorKey =
    GlobalKey<NavigatorState>();

/// Top-level background callback — handles both notification taps and
/// action-button taps when the app is in the background or terminated.
@pragma('vm:entry-point')
void _onNotificationTapBackground(NotificationResponse response) {
  _handleTaskAction(response);
}

void _onNotificationTap(NotificationResponse response) {
  // Action button tapped (Done / Snooze) — handle without opening app.
  if (response.actionId != null) {
    _handleTaskAction(response);
    return;
  }
  _handleNotificationPayload(response.payload);
}

/// Handles Done / Snooze action buttons from task notifications.
/// Works both foreground and background (top-level function).
void _handleTaskAction(NotificationResponse response) {
  final actionId = response.actionId;
  final payload  = response.payload;
  if (actionId == null || payload == null) return;

  // Only handle task:id payloads here.
  if (!payload.startsWith('task:')) return;
  final taskId = payload.substring(5); // strip 'task:'

  if (actionId == 'done') {
    _markTaskDoneFromNotification(taskId);
  } else if (actionId == 'snooze') {
    _snoozeTaskFromNotification(taskId);
  }
}

/// Marks a task completed directly from a notification action.
Future<void> _markTaskDoneFromNotification(String taskId) async {
  final db = DatabaseHelper.instance;
  final tasks = await db.getTasksForDay(DateTime.now());
  final task = tasks.cast<Task?>().firstWhere(
    (t) => t?.id == taskId,
    orElse: () => null,
  );
  if (task == null) return;

  task.status    = TaskStatus.completed;
  task.actualEnd = DateTime.now();
  await db.updateTask(task);

  // Show a brief confirmation notification.
  await NotificationService.instance._showCompletionConfirm(task.name);

  // Speak feedback if app is in foreground — silently no-op if not.
  TtsService.instance.speak('Great job finishing ${task.name}!');
}

/// Snoozes a task from a notification action, using the stored default duration.
Future<void> _snoozeTaskFromNotification(String taskId) async {
  final db = DatabaseHelper.instance;
  final tasks = await db.getTasksForDay(DateTime.now());
  final task = tasks.cast<Task?>().firstWhere(
    (t) => t?.id == taskId,
    orElse: () => null,
  );
  if (task == null) return;

  final rawMins = await db.getSetting('snooze_duration_minutes');
  final snoozeMins = int.tryParse(rawMins ?? '') ?? 10;
  task.plannedStart = DateTime.now().add(Duration(minutes: snoozeMins));
  await db.updateTask(task);

  // Re-schedule the reminder for the new time.
  await NotificationService.instance.scheduleTaskReminderWithActions(
    taskId:        task.id,
    notificationId: task.id.hashCode & 0x7fffffff,
    title:         task.name,
    body:          task.voiceMessage ?? 'Time for ${task.name}',
    scheduledTime: task.plannedStart,
    taskCategory:  task.category,
  );
}

void _handleNotificationPayload(String? payload) {
  if (payload == null) return;

  // Voice check-in tap → trigger STT flow in foreground
  if (payload.startsWith('checkin:')) {
    final taskId = payload.substring(8);
    _triggerVoiceCheckInForTask(taskId);
    return;
  }

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

    if (isRoutine && typeName == 'wake') {
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

/// Looks up a task by id and starts the voice check-in flow.
/// Runs on the main isolate so TTS + STT work normally.
void _triggerVoiceCheckInForTask(String taskId) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final db    = DatabaseHelper.instance;
    final tasks = await db.getTasksForDay(DateTime.now());
    final task  = tasks.cast<Task?>().firstWhere(
      (t) => t?.id == taskId,
      orElse: () => null,
    );
    if (task == null || task.status == TaskStatus.completed) return;
    // Import is deferred to avoid a circular dep — accessed via dynamic call.
    // ignore: avoid_dynamic_calls
    await (VoiceCheckInServiceLocator.instance as dynamic).triggerCheckIn(task);
  });
}

/// Thin locator so notification_service.dart can reference VoiceCheckInService
/// without a circular import (voice_checkin_service imports notification_service).
abstract class VoiceCheckInServiceLocator {
  static dynamic instance;
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
        'task_actions',
        'Task Reminders',
        description: 'Task reminders with Done and Snooze actions',
        importance: Importance.max,
      ),
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

  /// Schedules a task reminder with **Done ✓** and **Snooze 10 min** action
  /// buttons directly on the notification.
  ///
  /// Tapping "Done" marks the task completed without opening the app.
  /// Tapping "Snooze" reschedules the task 10 minutes from now.
  /// Tapping the notification body opens the app normally.
  ///
  /// Also speaks the task name + voiceMessage via TTS when the notification
  /// fires (foreground only — background TTS is silently skipped).
  Future<void> scheduleTaskReminderWithActions({
    required String taskId,
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? taskCategory,
  }) async {
    DateTime fireAt = scheduledTime;
    bool silent = false;

    if (taskCategory != null) {
      final engine = PreferenceLearningEngine.instance;
      final leadMinutes = await engine.getLeadTimeMinutes(taskCategory);
      if (leadMinutes > 0) {
        fireAt = scheduledTime.subtract(Duration(minutes: leadMinutes));
        final earliest = DateTime.now().add(const Duration(seconds: 5));
        if (fireAt.isBefore(earliest)) fireAt = earliest;
      }
      silent = await engine.isVoiceDisabled(taskCategory);
    }

    final tzTime = tz.TZDateTime.from(fireAt, tz.local);

    const doneAction = AndroidNotificationAction(
      'done',
      'Done ✓',
      showsUserInterface: false,
      cancelNotification: true,
    );
    const snoozeAction = AndroidNotificationAction(
      'snooze',
      'Snooze 10 min',
      showsUserInterface: false,
      cancelNotification: true,
    );

    final androidDetails = AndroidNotificationDetails(
      'task_actions',
      'Task Reminders',
      channelDescription: 'Task reminders with Done and Snooze actions',
      importance: Importance.max,
      priority: Priority.high,
      playSound: !silent,
      enableVibration: !silent,
      actions: const [doneAction, snoozeAction],
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        tzTime,
        details,
        payload: 'task:$taskId',
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        await _plugin.zonedSchedule(
          notificationId,
          title,
          body,
          tzTime,
          details,
          payload: 'task:$taskId',
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } else {
        rethrow;
      }
    }
  }

  /// Shows a brief "completed" confirmation notification.
  Future<void> _showCompletionConfirm(String taskName) async {
    const androidDetails = AndroidNotificationDetails(
      'task_actions',
      'Task Reminders',
      channelDescription: 'Task reminders with Done and Snooze actions',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
      enableVibration: false,
    );
    await _plugin.show(
      ('done_$taskName').hashCode & 0x7fffffff,
      '✓ $taskName',
      'Marked as done — great work!',
      const NotificationDetails(android: androidDetails),
    );
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

  /// Schedules the voice check-in notification for [taskId] at [checkInTime].
  ///
  /// When tapped (or when the app receives it in foreground), the app triggers
  /// [VoiceCheckInService.triggerCheckIn] for the STT flow.
  /// Payload format: `checkin:<taskId>` so the foreground handler can route it.
  Future<void> scheduleVoiceCheckIn({
    required String taskId,
    required int notificationId,
    required String taskName,
    required DateTime checkInTime,
  }) async {
    final tzTime = tz.TZDateTime.from(checkInTime, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'task_actions',
      'Task Reminders',
      channelDescription: 'Task reminders with Done and Snooze actions',
      importance: Importance.max,
      priority: Priority.high,
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.zonedSchedule(
        notificationId,
        'Time to check in',
        'Did you finish "$taskName"? Tap to answer.',
        tzTime,
        details,
        payload: 'checkin:$taskId',
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        await _plugin.zonedSchedule(
          notificationId,
          'Time to check in',
          'Did you finish "$taskName"? Tap to answer.',
          tzTime,
          details,
          payload: 'checkin:$taskId',
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } else {
        rethrow;
      }
    }
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
      'Missed: ${entry.label}',
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
        '${entry.label} (rescheduled)',
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
        '${entry.label} (rescheduled)',
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