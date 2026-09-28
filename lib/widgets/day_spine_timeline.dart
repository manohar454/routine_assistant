import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';
import 'task_card.dart';

class DaySpineTimeline extends StatelessWidget {
  final List<Task> tasks;
  final void Function(Task) onCheckIn;
  final void Function(Task)? onEdit;
  final void Function(Task)? onDelete;

  const DaySpineTimeline({
    super.key,
    required this.tasks,
    required this.onCheckIn,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    if (tasks.isEmpty) {
      return _EmptyState(isDark: isDark);
    }

    return Column(
      children: [
        for (int i = 0; i < tasks.length; i++)
          _SpineNode(
            task: tasks[i],
            isLast: i == tasks.length - 1,
            isDark: isDark,
            onCheckIn: () => onCheckIn(tasks[i]),
            onEdit: onEdit != null ? () => onEdit!(tasks[i]) : null,
            onDelete: onDelete != null ? () => onDelete!(tasks[i]) : null,
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.mist,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_today_outlined,
              color:
                  isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No tasks yet',
            style: context.text.titleMedium?.copyWith(
              color:
                  isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to add your first task for today.',
            style: context.text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SpineNode extends StatelessWidget {
  final Task task;
  final bool isLast;
  final bool isDark;
  final VoidCallback onCheckIn;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _SpineNode({
    required this.task,
    required this.isLast,
    required this.isDark,
    required this.onCheckIn,
    this.onEdit,
    this.onDelete,
  });

  bool get _isNow {
    final now = DateTime.now();
    return now.isAfter(task.plannedStart) &&
        now.isBefore(task.plannedEnd) &&
        task.status != TaskStatus.completed;
  }

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == TaskStatus.completed;
    final isNow = _isNow;

    final dotColor = isDone
        ? (isDark ? AppColors.darkMoss : AppColors.moss)
        : isNow
            ? (isDark ? AppColors.darkDeep : AppColors.deep)
            : (isDark ? AppColors.darkBorder : AppColors.mist);

    final dotBorder = isDone || isNow
        ? dotColor
        : (isDark ? AppColors.darkInkSubtle : AppColors.mistDark);

    final lineColor =
        isDark ? AppColors.darkBorder : AppColors.mist;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Spine column: dot + line
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Dot
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone || isNow ? dotColor : Colors.transparent,
                    border: Border.all(color: dotBorder, width: 2),
                  ),
                ),
                // Line to next node
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: lineColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Task card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: TaskCard(task: task, onCheckIn: onCheckIn, onEdit: onEdit, onDelete: onDelete),
            ),
          ),
        ],
      ),
    );
  }
}
