import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _nameController = TextEditingController();
  final _durationController = TextEditingController(text: '30');
  final _voiceMessageController = TextEditingController();

  String _category = 'Health';
  TaskFlexibility _flexibility = TaskFlexibility.flexible;
  TimeOfDay _startTime = TimeOfDay.now();
  String? _moodTag;
  bool _saving = false;

  final List<String> _categories = const [
    'Health',
    'Work',
    'Personal',
  ];

  final List<String> _moodOptions = const [
    'None',
    'energetic',
    'calm',
    'focus',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _voiceMessageController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _startTime = picked;
    });
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty || _saving) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final now = DateTime.now();

    // Build today's date using the time selected by the user.
    var plannedStart = DateTime(
      now.year,
      now.month,
      now.day,
      _startTime.hour,
      _startTime.minute,
    );

    // If that time has already passed today, interpret the user's
    // selection as tomorrow at the same time.
    var scheduledForTomorrow = false;

    if (plannedStart.isBefore(now)) {
      plannedStart = plannedStart.add(
        const Duration(days: 1),
      );
      scheduledForTomorrow = true;
    }

    final task = Task(
      id: const Uuid().v4(),
      name: _nameController.text.trim(),
      category: _category,
      plannedStart: plannedStart,
      estimatedDurationMinutes:
          int.tryParse(_durationController.text.trim()) ?? 30,
      flexibility: _flexibility,
      voiceMessage: _voiceMessageController.text.trim().isEmpty
          ? null
          : _voiceMessageController.text.trim(),
      moodTag:
          (_moodTag == null || _moodTag == 'None') ? null : _moodTag,
    );

    String? schedulingWarning;

    try {
      // IMPORTANT:
      // Save the task first. Notification failure must never prevent
      // the task from being saved.
      await DatabaseHelper.instance.insertTask(task);

      final baseId = task.id.hashCode & 0x7fffffff;

      // Main task notification.
      await NotificationService.instance.scheduleTaskReminder(
        notificationId: baseId,
        title: task.name,
        body: task.voiceMessage ?? 'Time for ${task.name}',
        scheduledTime: task.plannedStart,
      );

      // Check-in notification after the task duration.
      await NotificationService.instance.scheduleCheckIn(
        notificationId: baseId + 1,
        taskName: task.name,
        checkInTime: task.plannedEnd,
      );

      // Check whether exact alarms are available.
      final exactAllowed =
          await NotificationService.instance.canScheduleExactAlarms();

      if (!exactAllowed) {
        schedulingWarning =
            'Task saved, but exact-alarm permission isn\'t granted yet. '
            'Reminders may fire a few minutes late. Enable '
            '"Alarms & reminders" for this app in your phone Settings '
            'for precise timing.';
      }
    } catch (e) {
      // The task was already saved before notification scheduling.
      // Do not allow notification errors to break the Save operation.
      schedulingWarning =
          'Task saved, but there was a problem scheduling the reminder.';
    }

    if (!mounted) {
      return;
    }

    // Store the messages before leaving this screen.
    final tomorrowMessage = scheduledForTomorrow
        ? 'That time has passed today — scheduled for tomorrow instead.'
        : null;

    final warningMessage = schedulingWarning;

    // Leave the Add Task screen.
    Navigator.pop(context);

    // NOTE:
    // Do not try to show a SnackBar using this screen's ScaffoldMessenger
    // after Navigator.pop(). The screen may already be disposed.
    //
    // The task and notification scheduling have already completed above.
    //
    // The important behavior is:
    //
    // selected 01:05 AM when it has already passed
    //          ↓
    // tomorrow 01:05 AM
    //
    // The calling screen can display a confirmation if desired.
    debugPrint(
      tomorrowMessage ?? '',
    );

    debugPrint(
      warningMessage ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            20,
            0,
            20,
            40,
          ),
          children: [
            Text(
              'New task',
              style: textTheme.displaySmall,
            ),

            const SizedBox(height: 24),

            _FieldLabel('Task name'),

            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'e.g. Evening walk',
              ),
            ),

            const SizedBox(height: 22),

            _FieldLabel('Category'),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in _categories)
                  _CategoryChip(
                    label: category,
                    selected: _category == category,
                    onTap: () {
                      setState(() {
                        _category = category;
                      });
                    },
                  ),
              ],
            ),

            const SizedBox(height: 22),

            _FieldLabel('Start time & duration'),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickTime,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                      ),
                      side: const BorderSide(
                        color: AppColors.mist,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _startTime.format(context),
                      style: const TextStyle(
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      suffixText: 'min',
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            _FieldLabel('Flexibility'),

            _FlexibilitySegment(
              value: _flexibility,
              onChanged: (value) {
                setState(() {
                  _flexibility = value;
                });
              },
            ),

            const SizedBox(height: 22),

            _FieldLabel('Music mood (optional)'),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mood in _moodOptions)
                  _CategoryChip(
                    label: mood,
                    selected: (_moodTag ?? 'None') == mood,
                    onTap: () {
                      setState(() {
                        _moodTag = mood;
                      });
                    },
                  ),
              ],
            ),

            const SizedBox(height: 6),

            Text(
              'Auto-plays a matching playlist when this task starts',
              style: textTheme.bodyMedium,
            ),

            const SizedBox(height: 22),

            _FieldLabel('Voice reminder (optional)'),

            TextField(
              controller: _voiceMessageController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Boss, time for your evening walk',
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Leave blank for a default message',
              style: textTheme.bodyMedium,
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save task'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.deep
              : AppColors.cardSurface,
          border: Border.all(
            color: selected
                ? AppColors.deep
                : AppColors.mist,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected
                ? AppColors.canvas
                : AppColors.deepLight,
          ),
        ),
      ),
    );
  }
}

class _FlexibilitySegment extends StatelessWidget {
  final TaskFlexibility value;
  final ValueChanged<TaskFlexibility> onChanged;

  const _FlexibilitySegment({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(
          color: AppColors.mist,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segmentButton(
              'Flexible',
              TaskFlexibility.flexible,
            ),
          ),
          Expanded(
            child: _segmentButton(
              'Fixed',
              TaskFlexibility.fixed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentButton(
    String label,
    TaskFlexibility flexibility,
  ) {
    final selected = value == flexibility;

    return GestureDetector(
      onTap: () => onChanged(flexibility),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.deep
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: selected
                ? AppColors.canvas
                : AppColors.deepLight,
          ),
        ),
      ),
    );
  }
}