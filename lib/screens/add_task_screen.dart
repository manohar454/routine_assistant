import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/task.dart';
import '../engine/preference_learning_engine.dart';
import '../services/notification_service.dart';
import '../services/llm_service.dart';
import '../theme/app_theme.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _durationController = TextEditingController(text: '30');
  final _voiceMessageController = TextEditingController();
  final _nameFocus = FocusNode();

  String _category = 'Health';
  TaskFlexibility _flexibility = TaskFlexibility.flexible;
  TimeOfDay _startTime = TimeOfDay.now();
  String? _moodTag;
  bool _saving = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const List<String> _categories = [
    'Health',
    'Work',
    'Study',
    'Personal',
    'Meal',
    'Fitness',
  ];

  static const List<({String tag, String label, IconData icon})> _moodOptions =
      [
    (tag: 'energetic', label: 'Energetic', icon: Icons.bolt_rounded),
    (tag: 'calm', label: 'Calm', icon: Icons.spa_rounded),
    (tag: 'focus', label: 'Focus', icon: Icons.center_focus_strong_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _voiceMessageController.dispose();
    _nameFocus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _startTime = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _saving) return;

    HapticFeedback.lightImpact();
    setState(() => _saving = true);

    final now = DateTime.now();
    var plannedStart = DateTime(
      now.year,
      now.month,
      now.day,
      _startTime.hour,
      _startTime.minute,
    );

    if (plannedStart.isBefore(now)) {
      plannedStart = plannedStart.add(const Duration(days: 1));
    }

    final duration = int.tryParse(_durationController.text) ?? 30;
    final task = Task(
      id: const Uuid().v4(),
      name: name,
      category: _category,
      plannedStart: plannedStart,
      estimatedDurationMinutes: duration,
      flexibility: _flexibility,
      moodTag: _moodTag,
      voiceMessage:
          _voiceMessageController.text.trim().isNotEmpty
              ? _voiceMessageController.text.trim()
              : null,
    );

    await DatabaseHelper.instance.insertTask(task);

    // Preference extraction — two signals fired in parallel (fire-and-forget):
    // 1. Weak positive weight nudge for this category (rule-based, always runs).
    // 2. LLM-based extraction from task name — applies lead-time / voice-disable
    //    preferences if the model is loaded; silently skipped if not ready yet.
    unawaited(PreferenceLearningEngine.instance.observeTaskCreated(_category));
    unawaited(_extractLlmPreferences(task.name, _category));

    final baseId   = task.id.hashCode & 0x7fffffff;
    final plannedEnd = plannedStart.add(Duration(minutes: duration));

    if (plannedStart.isAfter(DateTime.now())) {
      await NotificationService.instance.scheduleTaskReminderWithActions(
        taskId: task.id,
        notificationId: baseId,
        title: task.name,
        body: task.voiceMessage ?? 'Time for ${task.name}',
        scheduledTime: plannedStart,
        taskCategory: _category,
      );
    }

    // Schedule voice check-in at plannedEnd regardless of whether start is future.
    if (plannedEnd.isAfter(DateTime.now())) {
      await NotificationService.instance.scheduleVoiceCheckIn(
        taskId:         task.id,
        notificationId: baseId + 1,
        taskName:       task.name,
        checkInTime:    plannedEnd,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// Fire-and-forget: asks the LLM to extract lead-time and voice-disable
  /// preferences from the task name. Silently no-ops if model isn't ready.
  Future<void> _extractLlmPreferences(
      String taskName, String category) async {
    final prefs =
        await LlmService.instance.extractPreferences(taskName, category);
    if (prefs.isEmpty) return;

    final engine = PreferenceLearningEngine.instance;

    final leadTimeStr = prefs['lead_time_minutes'];
    if (leadTimeStr != null) {
      final minutes = int.tryParse(leadTimeStr) ?? 0;
      if (minutes > 0) {
        await engine.setLeadTimeMinutes(category, minutes);
      }
    }

    final voiceDisabledStr = prefs['voice_disabled'];
    if (voiceDisabledStr != null) {
      await engine.setVoiceDisabled(
        category,
        disabled: voiceDisabledStr == 'true',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;

    return Scaffold(
      backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: dark ? AppColors.darkInk : AppColors.ink,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'New Task',
          style: context.text.titleLarge?.copyWith(
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: TextButton(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(
                backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(AppRadius.pill),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Save',
                      style: context.text.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Task name
              _Section(
                label: 'Task Name',
                child: _NameField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  dark: dark,
                  hint: 'e.g. Morning run, Deep work…',
                  onText: context.text,
                ),
              ),

              // Category
              _Section(
                label: 'Category',
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final cat = _categories[i];
                      return _CategoryChip(
                        label: cat,
                        selected: _category == cat,
                        dark: dark,
                        onText: context.text,
                        onTap: () => setState(() => _category = cat),
                      );
                    },
                  ),
                ),
              ),

              // Time + Duration row
              _Section(
                label: 'Time',
                child: Row(
                  children: [
                    Expanded(
                      child: _InfoTile(
                        icon: Icons.access_time_rounded,
                        label: 'Start time',
                        value: _startTime.format(context),
                        dark: dark,
                        onText: context.text,
                        onTap: _pickTime,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _DurationField(
                        controller: _durationController,
                        dark: dark,
                        onText: context.text,
                      ),
                    ),
                  ],
                ),
              ),

              // Flexibility
              _Section(
                label: 'Schedule Type',
                child: _FlexibilitySegment(
                  value: _flexibility,
                  dark: dark,
                  onText: context.text,
                  onChanged: (v) => setState(() => _flexibility = v),
                ),
              ),

              // Mood tag
              _Section(
                label: 'Mood Tag',
                sublabel: 'Links music & energy to this task',
                child: Row(
                  children: [
                    // "None" option
                    GestureDetector(
                      onTap: () => setState(() => _moodTag = null),
                      child: _MoodChip(
                        label: 'None',
                        icon: Icons.block_rounded,
                        selected: _moodTag == null,
                        color: dark ? AppColors.darkBorder : AppColors.mist,
                        dark: dark,
                        onText: context.text,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ..._moodOptions.map((m) => Padding(
                          padding:
                              const EdgeInsets.only(right: AppSpacing.sm),
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _moodTag = m.tag),
                            child: _MoodChip(
                              label: m.label,
                              icon: m.icon,
                              selected: _moodTag == m.tag,
                              color: AppColors.amber,
                              dark: dark,
                              onText: context.text,
                            ),
                          ),
                        )),
                  ],
                ),
              ),

              // Voice reminder
              _Section(
                label: 'Voice Reminder',
                sublabel: 'Spoken aloud when task starts',
                child: _VoiceField(
                  controller: _voiceMessageController,
                  dark: dark,
                  onText: context.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section wrapper ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String label;
  final String? sublabel;
  final Widget child;

  const _Section({
    required this.label,
    required this.child,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              sublabel!,
              style: context.text.labelSmall?.copyWith(
                color: (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)
                    .withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

// ─── Name field ─────────────────────────────────────────────────────────────

class _NameField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool dark;
  final String hint;
  final TextTheme onText;

  const _NameField({
    required this.controller,
    required this.focusNode,
    required this.dark,
    required this.hint,
    required this.onText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      style: onText.bodyLarge?.copyWith(
        color: dark ? AppColors.darkInk : AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: onText.bodyLarge?.copyWith(
          color: (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)
              .withValues(alpha: 0.5),
        ),
        filled: true,
        fillColor: dark ? AppColors.darkCard : AppColors.cardSurface,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          borderSide: BorderSide(
            color: dark ? AppColors.darkDeep : AppColors.deep,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
      ),
    );
  }
}

// ─── Info tile (tappable card) ───────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool dark;
  final TextTheme onText;
  final VoidCallback? onTap;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.dark,
    required this.onText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : AppColors.cardSurface,
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(
            color: dark ? AppColors.darkBorder : AppColors.mist,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: dark ? AppColors.darkDeep : AppColors.deep,
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: onText.labelSmall?.copyWith(
                    color: dark
                        ? AppColors.darkInkSubtle
                        : AppColors.inkSubtle,
                  ),
                ),
                Text(
                  value,
                  style: onText.labelLarge?.copyWith(
                    color: dark ? AppColors.darkInk : AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Duration field ──────────────────────────────────────────────────────────

class _DurationField extends StatelessWidget {
  final TextEditingController controller;
  final bool dark;
  final TextTheme onText;

  const _DurationField({
    required this.controller,
    required this.dark,
    required this.onText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.mist,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: dark ? AppColors.darkDeep : AppColors.deep,
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Duration',
                style: onText.labelSmall?.copyWith(
                  color:
                      dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                ),
              ),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  style: onText.labelLarge?.copyWith(
                    color: dark ? AppColors.darkInk : AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    suffix: Text(
                      ' min',
                      style: onText.labelSmall?.copyWith(
                        color: dark
                            ? AppColors.darkInkSubtle
                            : AppColors.inkSubtle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Category chip ───────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool dark;
  final TextTheme onText;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.dark,
    required this.onText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? (dark ? AppColors.darkDeep : AppColors.deep)
              : (dark ? AppColors.darkCard : AppColors.cardSurface),
          borderRadius: const BorderRadius.all(AppRadius.pill),
          border: Border.all(
            color: selected
                ? (dark ? AppColors.darkDeep : AppColors.deep)
                : (dark ? AppColors.darkBorder : AppColors.mist),
          ),
        ),
        child: Text(
          label,
          style: onText.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: selected
                ? Colors.white
                : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
          ),
        ),
      ),
    );
  }
}

// ─── Flexibility segment ─────────────────────────────────────────────────────

class _FlexibilitySegment extends StatelessWidget {
  final TaskFlexibility value;
  final bool dark;
  final TextTheme onText;
  final ValueChanged<TaskFlexibility> onChanged;

  const _FlexibilitySegment({
    required this.value,
    required this.dark,
    required this.onText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.mist,
        ),
      ),
      child: Row(
        children: TaskFlexibility.values.map((flex) {
          final selected = value == flex;
          final label =
              flex == TaskFlexibility.flexible ? 'Flexible' : 'Fixed';
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(flex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? (dark ? AppColors.darkDeep : AppColors.deep)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.all(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: onText.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : (dark
                            ? AppColors.darkInkSubtle
                            : AppColors.inkSubtle),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Mood chip ───────────────────────────────────────────────────────────────

class _MoodChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final bool dark;
  final TextTheme onText;

  const _MoodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.dark,
    required this.onText,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: 0.15)
            : (dark ? AppColors.darkCard : AppColors.cardSurface),
        borderRadius: const BorderRadius.all(AppRadius.pill),
        border: Border.all(
          color: selected
              ? color.withValues(alpha: 0.6)
              : (dark ? AppColors.darkBorder : AppColors.mist),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: selected
                ? color
                : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: onText.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: selected
                  ? color
                  : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Voice field ──────────────────────────────────────────────────────────────

class _VoiceField extends StatelessWidget {
  final TextEditingController controller;
  final bool dark;
  final TextTheme onText;

  const _VoiceField({
    required this.controller,
    required this.dark,
    required this.onText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 2,
      style: onText.bodyMedium?.copyWith(
        color: dark ? AppColors.darkInk : AppColors.ink,
      ),
      decoration: InputDecoration(
        hintText: 'Optional spoken reminder…',
        hintStyle: onText.bodyMedium?.copyWith(
          color: (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)
              .withValues(alpha: 0.5),
        ),
        prefixIcon: Icon(
          Icons.record_voice_over_rounded,
          color: dark ? AppColors.darkMoss : AppColors.moss,
          size: 18,
        ),
        filled: true,
        fillColor: dark ? AppColors.darkCard : AppColors.cardSurface,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(AppRadius.md),
          borderSide: BorderSide(
            color: dark ? AppColors.darkMoss : AppColors.moss,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
      ),
    );
  }
}
