import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the workout session alive in the background.
///
/// Without this, Android can freeze or kill the app's Dart isolate once
/// it's backgrounded (screen off, app switched away, phone locked mid-set)
/// — the in-app Timer-based session/rest clocks would silently stop
/// counting and desync from real elapsed time. A foreground service with
/// a persistent notification is the standard, reliable fix: Android keeps
/// the process alive as long as that notification is showing.
///
/// This does NOT replace the session/rest timer logic already in
/// WorkoutSessionScreen — it just guarantees the process stays alive so
/// those timers keep ticking correctly while the screen is off or the
/// app is in the background.
class WorkoutForegroundService {
  WorkoutForegroundService._internal();
  static final WorkoutForegroundService instance =
      WorkoutForegroundService._internal();

  bool _initialized = false;

  void _ensureInit() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'workout_session_channel',
        channelName: 'Workout Session',
        channelDescription:
            'Keeps your workout session timer running in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        // No sound/vibration — this notification is purely a "stay alive"
        // anchor, not something that should interrupt you mid-set.
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  /// Starts the foreground service with a live-updating notification.
  /// Call this once when a workout session begins (or resumes).
  Future<void> start({required String templateName}) async {
    _ensureInit();

    final hasPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (hasPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // On Android 12+, starting a foreground service also needs this granted
    // — if the user never enabled it, start() below will simply no-op
    // rather than crash, and the in-app timers still work fine while the
    // app stays in the foreground (this only degrades background reliability,
    // never breaks the workout flow itself).
    await FlutterForegroundTask.startService(
      notificationTitle: templateName,
      notificationText: 'Workout in progress — 00:00',
      callback: _startCallback,
    );
  }

  /// Updates the persistent notification text — call this from the same
  /// periodic tick that already updates the on-screen session timer, so
  /// the notification and the in-app clock always show the same number.
  Future<void> updateElapsed(String formattedElapsed, {String? restLabel}) async {
    if (!_initialized) return;
    await FlutterForegroundTask.updateService(
      notificationText: restLabel != null
          ? 'Rest: $restLabel'
          : 'Workout in progress — $formattedElapsed',
    );
  }

  /// Stops the service — call this when the session finishes or is
  /// abandoned (leaving the screen without finishing should still stop
  /// it, since an orphaned "workout in progress" notification forever is
  /// worse than just letting the in-app draft-resume logic handle it).
  Future<void> stop() async {
    if (!_initialized) return;
    await FlutterForegroundTask.stopService();
  }
}

/// Entry point required by flutter_foreground_task — runs in a separate
/// isolate. Deliberately does almost nothing: the actual timer logic and
/// UI live in WorkoutSessionScreen; this isolate's only job is to exist,
/// which is what keeps Android from killing the process.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_WorkoutTaskHandler());
}

class _WorkoutTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  
  @override
  void onRepeatEvent(DateTime timestamp) {
    // Intentionally empty — WorkoutSessionScreen drives notification
    // content updates directly via updateElapsed(), not from here.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}