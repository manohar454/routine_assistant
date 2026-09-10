import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';
import 'task_card.dart';

class DaySpineTimeline extends StatelessWidget {
  final List<Task> tasks;
  final void Function(Task task) onCheckIn;

  const DaySpineTimeline({
    super.key,
    required this.tasks,
    required this.onCheckIn,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('No tasks yet — add your first one.')),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Stack(
        children: [
          Positioned(
            left: 9,
            top: 6,
            bottom: 6,
            child: Container(width: 2, color: AppColors.mist),
          ),
          Column(
            children: [
              for (final task in tasks)
                _SpineNode(task: task, onCheckIn: () => onCheckIn(task)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpineNode extends StatelessWidget {
  final Task task;
  final VoidCallback onCheckIn;

  const _SpineNode({required this.task, required this.onCheckIn});

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == TaskStatus.completed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 26),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -30,
            top: 20,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? AppColors.moss : AppColors.cardSurface,
                border: Border.all(
                  color: isDone ? AppColors.moss : AppColors.deep,
                  width: 2,
                ),
              ),
            ),
          ),
          TaskCard(task: task, onCheckIn: onCheckIn),
        ],
      ),
    );
  }
}
