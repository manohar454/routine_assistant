import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onCheckIn;

  const TaskCard({super.key, required this.task, required this.onCheckIn});

  String get _timeLabel {
    final h = task.plannedStart.hour.toString().padLeft(2, '0');
    final m = task.plannedStart.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == TaskStatus.completed;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.mist),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(
              _timeLabel,
              style: textTheme.titleLarge?.copyWith(
                fontSize: 16,
                color: AppColors.deep,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: textTheme.bodyLarge?.copyWith(
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color:
                        isDone ? AppColors.ink.withValues(alpha: 0.4) : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _FlexibilityTag(flexibility: task.flexibility),
                    const SizedBox(width: 8),
                    Text('${task.estimatedDurationMinutes} min',
                        style: textTheme.bodyMedium),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: isDone ? null : onCheckIn,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? AppColors.moss : Colors.transparent,
                border: Border.all(
                  color: isDone ? AppColors.moss : AppColors.mist,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.check,
                size: 16,
                color: isDone ? Colors.white : AppColors.deep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlexibilityTag extends StatelessWidget {
  final TaskFlexibility flexibility;
  const _FlexibilityTag({required this.flexibility});

  @override
  Widget build(BuildContext context) {
    final isFixed = flexibility == TaskFlexibility.fixed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isFixed ? const Color(0xFFFBEFE3) : const Color(0xFFEFF3EE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isFixed ? 'FIXED' : 'FLEXIBLE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: isFixed ? AppColors.amber : AppColors.moss,
        ),
      ),
    );
  }
}
