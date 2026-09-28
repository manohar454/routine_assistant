import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../db/database_helper.dart';
import '../models/task.dart';
import '../widgets/reschedule_sheet.dart';
import 'tts_service.dart';
import 'notification_service.dart';

/// Fires at a task's plannedEnd:
///   1. TTS asks "Did you finish <task>?"
///   2. Listens via STT for up to 10 s
///   3. "yes/done/finish/completed" → marks task complete + TTS confirmation
///   4. "no/not yet/still"          → snoozes 10 min silently, re-fires same check-in
///   5. No response / timeout       → falls back to the notification with action buttons
class VoiceCheckInService {
  VoiceCheckInService._();
  static final VoiceCheckInService instance = VoiceCheckInService._();

  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;

  /// Must be called once at app startup (e.g. from main or after NotificationService.init).
  Future<void> init() async {
    _sttReady = await _stt.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
  }

  /// Called when a task's plannedEnd is reached (triggered by the check-in notification
  /// scheduler or from home_screen after loading today's tasks).
  ///
  /// Returns true if the check-in was handled (completed or snoozed).
  /// Returns false if the app fell back to the notification.
  Future<bool> triggerCheckIn(Task task) async {
    // Step 1 — TTS question
    await TtsService.instance.speak('Did you finish ${task.name}?');

    // Small gap so TTS audio doesn't bleed into STT
    await Future.delayed(const Duration(milliseconds: 600));

    if (!_sttReady) {
      // No microphone / permission → fall back to notification immediately
      await _scheduleImmediateFallbackNotification(task);
      return false;
    }

    // Step 2 — listen for up to 10 seconds
    final completer = Completer<String>();
    Timer? timeout;

    timeout = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        _stt.stop();
        completer.complete('');
      }
    });

    await _stt.listen(
      onResult: (result) {
        if (result.finalResult && !completer.isCompleted) {
          timeout?.cancel();
          completer.complete(result.recognizedWords.toLowerCase());
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      partialResults: false,
      cancelOnError: true,
    );

    final heard = await completer.future;

    // Step 3 — interpret
    if (_isYes(heard)) {
      await _markDone(task);
      return true;
    } else if (_isNo(heard)) {
      await _openRescheduleSheet(task);
      return true;
    } else {
      // No response or unintelligible → notification fallback
      await _scheduleImmediateFallbackNotification(task);
      return false;
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  bool _isYes(String s) {
    if (s.isEmpty) return false;
    const yesWords = ['yes', 'done', 'finish', 'finished', 'complete', 'completed', 'yeah', 'yep', 'yup'];
    return yesWords.any((w) => s.contains(w));
  }

  bool _isNo(String s) {
    if (s.isEmpty) return false;
    const noWords = ['no', 'not yet', 'still', 'nope', 'nah', 'not done', 'not finished'];
    return noWords.any((w) => s.contains(w));
  }

  Future<void> _markDone(Task task) async {
    task.status    = TaskStatus.completed;
    task.actualEnd = DateTime.now();
    await DatabaseHelper.instance.updateTask(task);
    await TtsService.instance.speak('Great job finishing ${task.name}!');
  }

  /// Opens the reschedule bottom sheet via the global navigator key.
  Future<void> _openRescheduleSheet(Task task) async {
    await TtsService.instance.speak('Okay, let me open the reschedule options for you.');
    await Future.delayed(const Duration(milliseconds: 800));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = routineNavigatorKey.currentState;
      if (navigator == null) return;
      navigator.push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          barrierColor: Colors.black54,
          pageBuilder: (ctx, _, __) => _RescheduleSheetPage(task: task),
        ),
      );
    });
  }

  Future<void> _scheduleImmediateFallbackNotification(Task task) async {
    // Fire the Done/Snooze notification right now (5 s in future so it's schedulable)
    final fireAt = DateTime.now().add(const Duration(seconds: 5));
    await NotificationService.instance.scheduleTaskReminderWithActions(
      taskId:         task.id,
      notificationId: (task.id.hashCode & 0x7fffffff) + 2,
      title:          'Check in: ${task.name}',
      body:           'Did you finish? Tap Done ✓ or Snooze.',
      scheduledTime:  fireAt,
      taskCategory:   task.category,
    );
  }
}

// ── Full-screen transparent route that hosts the reschedule sheet ─────────────

class _RescheduleSheetPage extends StatefulWidget {
  final Task task;
  const _RescheduleSheetPage({required this.task});

  @override
  State<_RescheduleSheetPage> createState() => _RescheduleSheetPageState();
}

class _RescheduleSheetPageState extends State<_RescheduleSheetPage> {
  @override
  void initState() {
    super.initState();
    // Open the sheet on the first frame so it appears immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final db         = DatabaseHelper.instance;
    final todayTasks = await db.getTasksForDay(DateTime.now());

    if (!mounted) return;
    await showRescheduleSheet(
      context: context,
      task: widget.task,
      todayTasks: todayTasks,
      onReload: () async {
        // No home_screen reload here — home_screen will pick up changes
        // on next _loadToday tick or when the user returns to it.
      },
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox.shrink(); // transparent scaffold — sheet appears over current route
}
