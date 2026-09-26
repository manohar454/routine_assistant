import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onCheckIn;

  const TaskCard({super.key, required this.task, required this.onCheckIn});

  String get _startLabel {
    final h = task.plannedStart.hour.toString().padLeft(2, '0');
    final m = task.plannedStart.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _endLabel {
    final h = task.plannedEnd.hour.toString().padLeft(2, '0');
    final m = task.plannedEnd.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool get _isNow {
    final now = DateTime.now();
    return now.isAfter(task.plannedStart) &&
        now.isBefore(task.plannedEnd) &&
        task.status != TaskStatus.completed;
  }

  bool get _isPast =>
      DateTime.now().isAfter(task.plannedEnd) &&
      task.status != TaskStatus.completed;

  Color _categoryColor(bool isDark) {
    switch (task.category.toLowerCase()) {
      case 'health':
      case 'fitness':
      case 'workout':
        return isDark ? AppColors.darkMoss : AppColors.moss;
      case 'work':
      case 'study':
        return isDark ? AppColors.darkDeep : AppColors.deep;
      case 'meal':
      case 'food':
        return isDark ? AppColors.darkAmber : AppColors.amber;
      default:
        return isDark ? AppColors.darkDeep : AppColors.deepLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final isDone = task.status == TaskStatus.completed;
    final isNow = _isNow;
    final isPast = _isPast;

    final borderColor = isNow
        ? (isDark ? AppColors.darkMoss : AppColors.moss)
        : (isDark ? AppColors.darkBorder : AppColors.mist);

    final bgColor = isDone
        ? (isDark
            ? AppColors.darkSurface.withValues(alpha: 0.5)
            : AppColors.canvas)
        : isNow
            ? (isDark
                ? const Color(0xFF1A2E1E)
                : const Color(0xFFF2FAF3))
            : (isDark ? AppColors.darkCard : AppColors.cardSurface);

    final catColor = _categoryColor(isDark);

    return GestureDetector(
      onLongPress: isDone
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onCheckIn();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
            width: isNow ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time column
            SizedBox(
              width: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _startLabel,
                    style: context.text.titleSmall?.copyWith(
                      color: isDone
                          ? (isDark
                              ? AppColors.darkInkSubtle
                              : AppColors.inkSubtle)
                          : (isDark
                              ? AppColors.darkInk
                              : AppColors.ink),
                      decoration:
                          isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _endLabel,
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            // Category accent bar
            Container(
              width: 3,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isDone
                    ? catColor.withValues(alpha: 0.3)
                    : catColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Task info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isNow)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkMoss
                                : AppColors.moss,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          task.name,
                          style: context.text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : null,
                            color: isDone
                                ? (isDark
                                    ? AppColors.darkInkSubtle
                                    : AppColors.inkSubtle)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _FlexTag(
                          flexibility: task.flexibility,
                          isDark: isDark),
                      const SizedBox(width: 8),
                      Text(
                        '${task.estimatedDurationMinutes} min',
                        style: context.text.bodySmall,
                      ),
                      if (isPast && !isDone) ...[
                        const SizedBox(width: 8),
                        Text(
                          'overdue',
                          style: context.text.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkClay
                                : AppColors.clay,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Check button
            GestureDetector(
              onTap: isDone ? null : onCheckIn,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? (isDark ? AppColors.darkMoss : AppColors.moss)
                      : Colors.transparent,
                  border: Border.all(
                    color: isDone
                        ? (isDark
                            ? AppColors.darkMoss
                            : AppColors.moss)
                        : (isDark
                            ? AppColors.darkBorder
                            : AppColors.mist),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  isDone ? Icons.check_rounded : Icons.check_rounded,
                  size: 16,
                  color: isDone
                      ? Colors.white
                      : (isDark
                          ? AppColors.darkInkSubtle
                          : AppColors.mistDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlexTag extends StatelessWidget {
  final TaskFlexibility flexibility;
  final bool isDark;

  const _FlexTag({required this.flexibility, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isFixed = flexibility == TaskFlexibility.fixed;
    final bg = isFixed
        ? AppColors.taskFixed(isDark)
        : AppColors.taskFlexible(isDark);
    final color = isFixed
        ? (isDark ? AppColors.darkAmber : AppColors.amber)
        : (isDark ? AppColors.darkMoss : AppColors.moss);

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        isFixed ? 'FIXED' : 'FLEXIBLE',
        style: context.text.labelSmall?.copyWith(
          color: color,
          fontSize: 9,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
