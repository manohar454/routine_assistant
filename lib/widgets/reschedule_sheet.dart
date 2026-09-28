import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../engine/reschedule_engine.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

// ── Shared enum ──────────────────────────────────────────────────────────────

enum RescheduleChoice { snooze, useSlot, shiftAll, dismiss }

// ── Snooze duration helper ───────────────────────────────────────────────────

const int _kDefaultSnoozeMins = 10;

Future<int> getDefaultSnoozeMins() async {
  final raw = await DatabaseHelper.instance.getSetting('snooze_duration_minutes');
  return int.tryParse(raw ?? '') ?? _kDefaultSnoozeMins;
}

// ── Reusable function: show sheet + handle choice ────────────────────────────

/// Shows the reschedule bottom sheet for [task], handles the chosen action,
/// and reloads [todayTasks] via [onReload] when a change is applied.
///
/// [todayTasks] is used to find a free slot suggestion.
/// [onReload] is called after any DB update so the caller can refresh.
Future<void> showRescheduleSheet({
  required BuildContext context,
  required Task task,
  required List<Task> todayTasks,
  required Future<void> Function() onReload,
}) async {
  final engine       = RescheduleEngine();
  final slot         = engine.findFreeSlot(missedTask: task, todayTasks: todayTasks);
  final isDark       = Theme.of(context).brightness == Brightness.dark;
  final defaultMins  = await getDefaultSnoozeMins();

  if (!context.mounted) return;

  final result = await showModalBottomSheet<(RescheduleChoice, int)>(
    context: context,
    backgroundColor: isDark ? AppColors.darkCard : AppColors.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => MissedTaskSheet(
      task: task,
      suggestedSlot: slot,
      isDark: isDark,
      defaultSnoozeMins: defaultMins,
    ),
  );

  if (result == null || !context.mounted) return;
  final (choice, snoozeMins) = result;

  switch (choice) {
    case RescheduleChoice.useSlot:
      final initialTime = slot != null
          ? TimeOfDay(hour: slot.hour, minute: slot.minute)
          : TimeOfDay.now();

      if (!context.mounted) return;
      final picked = await showTimePicker(
        context: context,
        initialTime: initialTime,
        helpText: 'Choose new start time',
      );
      if (picked == null || !context.mounted) return;

      final now      = DateTime.now();
      final newStart = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      final confirmed = await _confirmDialog(
        context: context,
        title: 'Reschedule "${task.name}"?',
        body:
            'Move to ${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}?',
      );
      if (confirmed != true || !context.mounted) return;

      task.plannedStart = newStart;
      await DatabaseHelper.instance.updateTask(task);
      await onReload();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '"${task.name}" rescheduled to '
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
          ),
          duration: const Duration(seconds: 3),
        ));
      }

    case RescheduleChoice.shiftAll:
      if (!context.mounted) return;
      final confirmed = await _confirmDialog(
        context: context,
        title: 'Shift entire schedule?',
        body: 'All remaining flexible tasks will be pushed forward to fit the current time.',
      );
      if (confirmed != true || !context.mounted) return;

      final delayMinutes =
          DateTime.now().difference(task.plannedStart).inMinutes.clamp(1, 1440);
      await engine.applyDelay(delayedTask: task, delayMinutes: delayMinutes);
      task.plannedStart = DateTime.now();
      await DatabaseHelper.instance.updateTask(task);
      await onReload();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Schedule shifted to match current time'),
          duration: Duration(seconds: 3),
        ));
      }

    case RescheduleChoice.snooze:
      final newStart = DateTime.now().add(Duration(minutes: snoozeMins));
      task.plannedStart = newStart;
      // Compute new end explicitly — avoids race with stale getter if task
      // had already passed its original plannedEnd.
      final newEnd = newStart.add(Duration(minutes: task.estimatedDurationMinutes));
      await DatabaseHelper.instance.updateTask(task);
      await NotificationService.instance.scheduleVoiceCheckIn(
        taskId:         task.id,
        notificationId: (task.id.hashCode & 0x7fffffff) + 1,
        taskName:       task.name,
        checkInTime:    newEnd,
      );
      await onReload();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"${task.name}" snoozed $snoozeMins min'),
          duration: const Duration(seconds: 2),
        ));
      }

    case RescheduleChoice.dismiss:
      break;
  }
}

Future<bool?> _confirmDialog({
  required BuildContext context,
  required String title,
  required String body,
}) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

// ── Sheet widget (public so voice_checkin_service can use it) ─────────────────

class MissedTaskSheet extends StatefulWidget {
  final Task task;
  final DateTime? suggestedSlot;
  final bool isDark;
  final int defaultSnoozeMins;

  const MissedTaskSheet({
    super.key,
    required this.task,
    required this.suggestedSlot,
    required this.isDark,
    this.defaultSnoozeMins = _kDefaultSnoozeMins,
  });

  @override
  State<MissedTaskSheet> createState() => _MissedTaskSheetState();
}

class _MissedTaskSheetState extends State<MissedTaskSheet> {
  static const _chips = [5, 10, 15, 20];
  late int _snoozeMins;

  @override
  void initState() {
    super.initState();
    // Snap to nearest chip value, else use default
    _snoozeMins = _chips.contains(widget.defaultSnoozeMins)
        ? widget.defaultSnoozeMins
        : _kDefaultSnoozeMins;
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final text        = context.text;
    final isDark      = widget.isDark;
    final accentColor = isDark ? AppColors.darkAmber : AppColors.amber;
    final inkColor    = isDark ? AppColors.darkInk : AppColors.ink;
    final subtleColor = isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBorder : AppColors.mist,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // task header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.schedule_rounded, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Missed task',
                        style: text.labelSmall?.copyWith(color: subtleColor)),
                    Text(widget.task.name,
                        style: text.titleMedium?.copyWith(
                            color: inkColor, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Scheduled ${_fmt(widget.task.plannedStart)} – ${_fmt(widget.task.plannedEnd)}. '
            'What would you like to do?',
            style: text.bodyMedium?.copyWith(color: subtleColor),
          ),
          const SizedBox(height: 20),

          // ── Snooze duration chips ─────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.snooze_rounded, size: 14, color: subtleColor),
              const SizedBox(width: 6),
              Text('Snooze for', style: text.labelSmall?.copyWith(color: subtleColor)),
              const SizedBox(width: 10),
              ..._chips.map((mins) {
                final selected = mins == _snoozeMins;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _snoozeMins = mins),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: selected
                            ? accentColor
                            : (isDark ? AppColors.darkSurface : AppColors.canvas),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? accentColor
                              : (isDark ? AppColors.darkBorder : AppColors.mist),
                        ),
                      ),
                      child: Text(
                        '${mins}m',
                        style: text.labelSmall?.copyWith(
                          color: selected
                              ? Colors.white
                              : (isDark ? AppColors.darkInk : AppColors.ink),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          // ── Action options ────────────────────────────────────────────────
          RescheduleSheetOption(
            isDark: isDark,
            icon: Icons.snooze_rounded,
            label: 'Snooze $_snoozeMins min',
            sublabel: 'Come back to it shortly — check-in re-fires',
            onTap: () => Navigator.pop(context, (RescheduleChoice.snooze, _snoozeMins)),
          ),
          const SizedBox(height: 10),
          RescheduleSheetOption(
            isDark: isDark,
            icon: Icons.access_time_rounded,
            label: 'Choose a time',
            sublabel: widget.suggestedSlot != null
                ? 'Next free slot: ${_fmt(widget.suggestedSlot!)} — or pick your own'
                : 'Pick any time from the clock',
            onTap: () => Navigator.pop(context, (RescheduleChoice.useSlot, _snoozeMins)),
          ),
          const SizedBox(height: 10),
          RescheduleSheetOption(
            isDark: isDark,
            icon: Icons.update_rounded,
            label: 'Shift whole schedule',
            sublabel: 'Push all remaining flexible tasks forward',
            onTap: () => Navigator.pop(context, (RescheduleChoice.shiftAll, _snoozeMins)),
          ),
          const SizedBox(height: 10),
          RescheduleSheetOption(
            isDark: isDark,
            icon: Icons.close_rounded,
            label: 'Skip this task',
            sublabel: 'Leave schedule as-is',
            onTap: () => Navigator.pop(context, (RescheduleChoice.dismiss, _snoozeMins)),
          ),
        ],
      ),
    );
  }
}

class RescheduleSheetOption extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const RescheduleSheetOption({
    super.key,
    required this.isDark,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.mist,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkInk : AppColors.ink)),
                  Text(sublabel, style: text.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18,
                color: isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
          ],
        ),
      ),
    );
  }
}
