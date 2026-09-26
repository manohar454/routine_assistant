import '../db/database_helper.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../services/music_service.dart';
import 'dart:async';
import 'adaptive_learning_engine.dart';
import 'reasoning_trace_engine.dart';

class RescheduleResult {
  final List<Task> shiftedTasks;
  final Task? conflictedFixedTask;

  RescheduleResult({required this.shiftedTasks, this.conflictedFixedTask});
}

class RescheduleEngine {
  final DatabaseHelper db = DatabaseHelper.instance;
  final NotificationService notifications = NotificationService.instance;

  Future<RescheduleResult> applyDelay({
    required Task delayedTask,
    required int delayMinutes,
  }) async {
    final dayTasks = await db.getTasksForDay(delayedTask.plannedStart);

    final downstream = dayTasks
        .where((t) => t.plannedStart.isAfter(delayedTask.plannedStart))
        .toList()
      ..sort((a, b) => a.plannedStart.compareTo(b.plannedStart));

    final shifted = <Task>[];
    Task? conflict;

    for (final task in downstream) {
      if (task.flexibility == TaskFlexibility.fixed) {
        conflict = task;
        break;
      }

      task.plannedStart =
          task.plannedStart.add(Duration(minutes: delayMinutes));
      await db.updateTask(task);
      await _rescheduleNotificationsFor(task);
      shifted.add(task);
    }

    // Record the rescheduling decision for the reasoning trace.
    unawaited(ReasoningTraceEngine.instance.record(
      taskName: delayedTask.name,
      decisionType: 'rescheduled',
      context: {
        'delayMinutes': delayMinutes,
        'tasksShifted': shifted.length,
        if (conflict != null) 'blockedBy': conflict.name,
      },
    ));

    return RescheduleResult(
        shiftedTasks: shifted, conflictedFixedTask: conflict);
  }

  Future<void> _rescheduleNotificationsFor(Task task) async {
    final baseId = task.id.hashCode & 0x7fffffff;
    final now = DateTime.now();

    await notifications.cancel(baseId);
    await notifications.cancel(baseId + 1);

    // Guard: never schedule notifications in the past.
    if (task.plannedStart.isAfter(now)) {
      await notifications.scheduleTaskReminder(
        notificationId: baseId,
        title: task.name,
        body: task.voiceMessage ?? 'Time for ${task.name}',
        scheduledTime: task.plannedStart,
        taskCategory: task.category,
      );
    }

    if (task.plannedEnd.isAfter(now)) {
      await notifications.scheduleCheckIn(
        notificationId: baseId + 1,
        taskName: task.name,
        checkInTime: task.plannedEnd,
      );
    }
  }

  Future<void> markCompleted(Task task, {DateTime? actualEnd}) async {
    task.status = TaskStatus.completed;
    task.actualEnd = actualEnd ?? DateTime.now();
    await db.updateTask(task);

    if (task.moodTag != null) {
      await MusicService.instance.stopForTaskEnd();
    }

    // Phase 2: record the actual duration so the behavioral profile
    // learns from this completion. Only meaningful if we know when
    // the task actually started.
    if (task.actualStart != null) {
      final actualDurationMinutes =
          (task.actualEnd!).difference(task.actualStart!).inMinutes.toDouble();
      await AdaptiveLearningEngine.instance.recordTaskCompletion(
        taskCategory: task.category,
        actualDurationMinutes: actualDurationMinutes,
      );
    }

    unawaited(ReasoningTraceEngine.instance.record(
      taskName: task.name,
      decisionType: 'completed',
      context: {
        'category': task.category,
        if (task.actualStart != null)
          'durationMinutes':
              task.actualEnd!.difference(task.actualStart!).inMinutes,
      },
    ));
  }
}
