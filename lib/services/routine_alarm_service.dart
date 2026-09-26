import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:timezone/timezone.dart' as tz;
import '../db/database_helper.dart';
import '../models/routine_models.dart';
import 'tts_service.dart';

/// AI Voice Companion — schedules and orchestrates all daily routine reminders.
///
/// Each [RoutineEntry] in the DB becomes a daily repeating notification.
/// For wake-up entries the notification launches the [WakeAlarmScreen]
/// (via a special notification channel + payload) and also starts local
/// music playback.
///
/// IDs: notifications use the range 3000–3999 to avoid collisions with
/// the existing task-reminder range (1000–1999) and check-in range (2000–2999).
class RoutineAlarmService {
  RoutineAlarmService._internal();
  static final RoutineAlarmService instance = RoutineAlarmService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Notification channel IDs
  static const _routineChannelId = 'routine_companion';
  static const _wakeChannelId    = 'routine_wake_alarm';

  // Notification ID base
  static const _baseId = 3000;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Call after DB is ready to reschedule all enabled routine entries
  /// for the next 24 hours. Safe to call daily (cancels & rewrites).
  Future<void> scheduleAll() async {
    final entries = await _db.getRoutineEntriesForToday();
    // Cancel existing routine notifications first.
    await _cancelAllRoutineNotifications();
    for (int i = 0; i < entries.length; i++) {
      await _schedule(entries[i], notifId: _baseId + i);
    }
  }

  /// Reschedule everything — call this after the user edits the timetable.
  Future<void> rescheduleAll() => scheduleAll();

  /// Cancel all routine notifications (IDs 3000–3999).
  Future<void> cancelAll() => _cancelAllRoutineNotifications();

  /// Speak a routine entry's message via TTS immediately.
  /// Used by the WakeAlarmScreen or confirmation dialogs.
  Future<void> speakEntry(RoutineEntry entry) async {
    await TtsService.instance.speak(entry.message);
  }

  /// Play a local music file for the wake-up event.
  Future<AudioPlayer?> playWakeMusic(String filePath) async {
    try {
      final player = AudioPlayer();
      await player.setFilePath(filePath);
      await player.play();
      return player;
    } catch (_) {
      return null;
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<void> _cancelAllRoutineNotifications() async {
    for (int i = 0; i < 200; i++) {
      await _plugin.cancel(_baseId + i);
    }
  }

  Future<void> _schedule(RoutineEntry entry, {required int notifId}) async {
    final fireAt = _nextFireTime(entry.timeOfDayMinutes);
    final isWake = entry.type == RoutineEntryType.wakeUp;

    final androidDetails = AndroidNotificationDetails(
      isWake ? _wakeChannelId : _routineChannelId,
      isWake ? 'Wake Alarm' : 'Routine Companion',
      channelDescription: isWake
          ? 'Hard-to-dismiss morning wake-up alarm'
          : 'Daily routine voice reminders',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: isWake,
      playSound: true,
      enableVibration: true,
      // High visibility for lock screen
      visibility: NotificationVisibility.public,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Payload: entry id so the app can look it up on tap.
    final payload = 'routine:${entry.id}:${entry.type.name}';

    final tzTime = tz.TZDateTime.from(fireAt, tz.local);

    try {
      await _plugin.zonedSchedule(
        notifId,
        '${entry.type.emoji} ${entry.label}',
        entry.message.length > 80
            ? '${entry.message.substring(0, 80)}…'
            : entry.message,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.time, // repeats daily
      );
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        // Fall back to inexact — still repeating daily.
        await _plugin.zonedSchedule(
          notifId,
          '${entry.type.emoji} ${entry.label}',
          entry.message.length > 80
              ? '${entry.message.substring(0, 80)}…'
              : entry.message,
          tzTime,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    }
  }

  /// Returns the next DateTime at [minutesSinceMidnight].
  /// If that time has already passed today, returns tomorrow's.
  DateTime _nextFireTime(int minutesSinceMidnight) {
    final now = DateTime.now();
    var candidate = DateTime(
      now.year,
      now.month,
      now.day,
      minutesSinceMidnight ~/ 60,
      minutesSinceMidnight % 60,
    );
    if (candidate.isBefore(now.add(const Duration(seconds: 30)))) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}
