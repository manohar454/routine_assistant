import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/workout_models.dart';
import '../theme/app_theme.dart';

const _equipmentOptions = [
  'bodyweight', 'band', 'dumbbell', 'barbell', 'cable', 'machine', 'none'
];

class WorkoutTemplateEditorScreen extends StatefulWidget {
  final String templateId;
  const WorkoutTemplateEditorScreen({super.key, required this.templateId});

  @override
  State<WorkoutTemplateEditorScreen> createState() =>
      _WorkoutTemplateEditorScreenState();
}

class _WorkoutTemplateEditorScreenState
    extends State<WorkoutTemplateEditorScreen> {
  final db = DatabaseHelper.instance;
  WorkoutTemplate? _template;
  List<Exercise> _exercises = [];
  List<Exercise> _warmupExercises = [];
  bool _loading = true;

  late TextEditingController _nameController;
  late TextEditingController _restSetsController;
  late TextEditingController _restExercisesController;
  late TextEditingController _roundsController;
  late TextEditingController _restAfterRoundController;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final template = await db.getWorkoutTemplate(widget.templateId);
    if (template == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final exercises = await db.getExercisesForIds(template.exerciseIds);
    final warmup = await db.getExercisesForIds(template.warmupExerciseIds);
    if (!mounted) return;

    _nameController = TextEditingController(text: template.name);
    _restSetsController =
        TextEditingController(text: '${template.restBetweenSetsSeconds}');
    _restExercisesController =
        TextEditingController(text: '${template.restBetweenExercisesSeconds}');
    _roundsController = TextEditingController(text: '${template.circuitRounds}');
    _restAfterRoundController =
        TextEditingController(text: '${template.restAfterRoundSeconds}');

    setState(() {
      _template = template;
      _exercises = exercises;
      _warmupExercises = warmup;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final t = _template;
    if (t == null) return;
    t.name = _nameController.text.trim().isEmpty ? t.name : _nameController.text.trim();
    t.restBetweenSetsSeconds =
        int.tryParse(_restSetsController.text) ?? t.restBetweenSetsSeconds;
    t.restBetweenExercisesSeconds =
        int.tryParse(_restExercisesController.text) ?? t.restBetweenExercisesSeconds;
    t.circuitRounds = int.tryParse(_roundsController.text) ?? t.circuitRounds;
    t.restAfterRoundSeconds =
        int.tryParse(_restAfterRoundController.text) ?? t.restAfterRoundSeconds;
    t.exerciseIds = _exercises.map((e) => e.id).toList();
    t.warmupExerciseIds = _warmupExercises.map((e) => e.id).toList();
    await db.insertWorkoutTemplate(t);
    if (mounted) Navigator.pop(context);
  }

  // ── main exercises ──
  void _removeExercise(Exercise ex) => setState(() => _exercises.remove(ex));
  void _moveExercise(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _exercises.length) return;
    setState(() {
      final item = _exercises.removeAt(i);
      _exercises.insert(j, item);
    });
  }

  Future<void> _addExercise() async {
    final allExercises = await db.getUserCreatedExercises();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExercisePickerSheet(existing: allExercises),
    );
    if (picked == null) return;
    if (_exercises.any((e) => e.id == picked.id)) return;
    await _customizeForThisDay(picked, isWarmup: false);
    if (!mounted) return;
    setState(() => _exercises.add(picked));
  }

  // ── warmup exercises ──
  void _removeWarmup(Exercise ex) => setState(() => _warmupExercises.remove(ex));
  void _moveWarmup(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _warmupExercises.length) return;
    setState(() {
      final item = _warmupExercises.removeAt(i);
      _warmupExercises.insert(j, item);
    });
  }

  Future<void> _addWarmupExercise() async {
    final allExercises = await db.getUserCreatedExercises();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExercisePickerSheet(existing: allExercises),
    );
    if (picked == null) return;
    if (_warmupExercises.any((e) => e.id == picked.id)) return;
    await _customizeForThisDay(picked, isWarmup: true);
    if (!mounted) return;
    setState(() => _warmupExercises.add(picked));
  }

  Future<void> _customizeForThisDay(Exercise exercise, {required bool isWarmup}) async {
    final t = _template!;
    final dark = context.isDark;
    final setsController =
        TextEditingController(text: '${t.effectiveSets(exercise)}');
    final repsController = TextEditingController(text: t.effectiveReps(exercise));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? AppColors.darkSurface : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(AppRadius.lg)),
        title: Text(exercise.name,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              color: dark ? AppColors.darkInk : AppColors.ink,
            )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: dark
                    ? AppColors.darkDeep.withValues(alpha: 0.15)
                    : AppColors.deep.withValues(alpha: 0.07),
                borderRadius: const BorderRadius.all(AppRadius.sm),
              ),
              child: Text(
                'Customizes only "${t.name}"${isWarmup ? " warm-up" : ""} — '
                'other days using this exercise are unaffected.',
                style: TextStyle(
                  fontSize: 12,
                  color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _DialogField(
                    label: 'Sets',
                    controller: setsController,
                    dark: dark,
                    numeric: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DialogField(
                    label: 'Target',
                    controller: repsController,
                    dark: dark,
                    hint: 'e.g. 10, Max, 45s',
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(AppRadius.pill)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final newSets = int.tryParse(setsController.text) ?? exercise.targetSets;
    final newReps = repsController.text.trim().isEmpty
        ? exercise.repsTarget
        : repsController.text.trim();
    setState(() {
      if (newSets != exercise.targetSets) {
        t.setsOverrides[exercise.id] = newSets;
      } else {
        t.setsOverrides.remove(exercise.id);
      }
      if (newReps != exercise.repsTarget) {
        t.repsOverrides[exercise.id] = newReps;
      } else {
        t.repsOverrides.remove(exercise.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final text = context.text;

    if (_loading) {
      return Scaffold(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        body: Center(
          child: CircularProgressIndicator(
            color: dark ? AppColors.darkDeep : AppColors.deep,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (_template == null) {
      return Scaffold(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('Template not found.')),
      );
    }
    final t = _template!;

    return Scaffold(
      backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: dark ? AppColors.darkInk : AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Edit Day',
            style: text.titleMedium?.copyWith(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              color: dark ? AppColors.darkInk : AppColors.ink,
            )),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _save();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                decoration: BoxDecoration(
                  color: dark ? AppColors.darkDeep : AppColors.deep,
                  borderRadius: const BorderRadius.all(AppRadius.pill),
                ),
                child: Text('Save',
                    style: text.labelMedium?.copyWith(
                      color: dark ? AppColors.darkCanvas : AppColors.canvas,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              20, AppSpacing.md, 20, AppSpacing.xxl),
          children: [
            // Day name
            _SectionLabel('Day name', dark: dark, text: text),
            _StyledTextField(
                controller: _nameController, dark: dark, hint: 'e.g. Push Day'),
            const SizedBox(height: AppSpacing.lg),

            // Rest day toggle
            _RestDayToggle(
              value: t.isRestDay,
              dark: dark,
              text: text,
              onChanged: (v) => setState(() => t.isRestDay = v),
            ),

            if (!t.isRestDay) ...[
              const SizedBox(height: AppSpacing.lg),

              // ── Warm-up ──
              _SectionLabel('Warm-up', dark: dark, text: text),
              Text(
                'Runs before the main workout. Tap to customize for this day.',
                style: text.bodySmall
                    ?.copyWith(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (int i = 0; i < _warmupExercises.length; i++)
                _ExerciseRow(
                  exercise: _warmupExercises[i],
                  index: i,
                  count: _warmupExercises.length,
                  template: t,
                  dark: dark,
                  text: text,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _customizeForThisDay(_warmupExercises[i], isWarmup: true);
                  },
                  onMoveUp: () => _moveWarmup(i, -1),
                  onMoveDown: () => _moveWarmup(i, 1),
                  onRemove: () {
                    HapticFeedback.lightImpact();
                    _removeWarmup(_warmupExercises[i]);
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
              _AddExerciseButton(
                label: 'Add warm-up exercise',
                dark: dark,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _addWarmupExercise();
                },
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Session type ──
              _SectionLabel('Session type', dark: dark, text: text),
              Row(
                children: [
                  Expanded(
                    child: _SegButton(
                      label: 'Sequential',
                      selected: t.sessionType == SessionType.sequential,
                      dark: dark,
                      onTap: () =>
                          setState(() => t.sessionType = SessionType.sequential),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _SegButton(
                      label: 'Circuit',
                      selected: t.sessionType == SessionType.circuit,
                      dark: dark,
                      onTap: () =>
                          setState(() => t.sessionType = SessionType.circuit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Rest settings
              if (t.sessionType == SessionType.sequential)
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        label: 'Rest sets (s)',
                        controller: _restSetsController,
                        dark: dark,
                        text: text,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _NumberField(
                        label: 'Rest exercises (s)',
                        controller: _restExercisesController,
                        dark: dark,
                        text: text,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        label: 'Rounds',
                        controller: _roundsController,
                        dark: dark,
                        text: text,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _NumberField(
                        label: 'Rest after round (s)',
                        controller: _restAfterRoundController,
                        dark: dark,
                        text: text,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.xl),

              // ── Exercises ──
              _SectionLabel('Exercises', dark: dark, text: text),
              Text(
                'Tap to customize sets/reps for this day only.',
                style: text.bodySmall
                    ?.copyWith(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (int i = 0; i < _exercises.length; i++)
                _ExerciseRow(
                  exercise: _exercises[i],
                  index: i,
                  count: _exercises.length,
                  template: t,
                  dark: dark,
                  text: text,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _customizeForThisDay(_exercises[i], isWarmup: false);
                  },
                  onMoveUp: () => _moveExercise(i, -1),
                  onMoveDown: () => _moveExercise(i, 1),
                  onRemove: () {
                    HapticFeedback.lightImpact();
                    _removeExercise(_exercises[i]);
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
              _AddExerciseButton(
                label: 'Add exercise',
                dark: dark,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _addExercise();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool dark;
  final TextTheme text;
  const _SectionLabel(this.label, {required this.dark, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: text.labelSmall?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: (dark ? AppColors.darkDeep : AppColors.deep).withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final bool dark;
  final String? hint;
  final bool numeric;
  const _StyledTextField({
    required this.controller,
    required this.dark,
    this.hint,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      style: TextStyle(
        color: dark ? AppColors.darkInk : AppColors.ink,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
        filled: true,
        fillColor: dark
            ? AppColors.darkCard.withValues(alpha: 0.8)
            : AppColors.mist.withValues(alpha: 0.4),
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
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool dark;
  final String? hint;
  final bool numeric;
  const _DialogField({
    required this.label,
    required this.controller,
    required this.dark,
    this.hint,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: dark ? AppColors.darkInk : AppColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
        hintText: hint,
        hintStyle:
            TextStyle(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
        filled: true,
        fillColor: dark
            ? AppColors.darkCard.withValues(alpha: 0.8)
            : AppColors.mist.withValues(alpha: 0.3),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _RestDayToggle extends StatelessWidget {
  final bool value;
  final bool dark;
  final TextTheme text;
  final ValueChanged<bool> onChanged;
  const _RestDayToggle({
    required this.value,
    required this.dark,
    required this.text,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(
          color: dark ? AppColors.darkBorder.withValues(alpha: 0.5) : AppColors.mist,
        ),
      ),
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
        value: value,
        activeThumbColor: dark ? AppColors.darkAmber : AppColors.amber,
        onChanged: onChanged,
        title: Text('Rest day',
            style: text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: dark ? AppColors.darkInk : AppColors.ink,
            )),
        subtitle: Text('No exercises — recovery only',
            style: text.bodySmall
                ?.copyWith(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool dark;
  final TextTheme text;
  const _NumberField({
    required this.label,
    required this.controller,
    required this.dark,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label, dark: dark, text: text),
        _StyledTextField(controller: controller, dark: dark, numeric: true),
      ],
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  const _SegButton({
    required this.label,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = dark ? AppColors.darkDeep : AppColors.deep;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? activeColor
              : (dark ? AppColors.darkCard : AppColors.cardSurface),
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(
            color: selected
                ? activeColor
                : (dark
                    ? AppColors.darkBorder.withValues(alpha: 0.6)
                    : AppColors.mist),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected
                ? (dark ? AppColors.darkCanvas : AppColors.canvas)
                : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
          ),
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  final Exercise exercise;
  final int index;
  final int count;
  final WorkoutTemplate template;
  final bool dark;
  final TextTheme text;
  final VoidCallback onTap;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;
  const _ExerciseRow({
    required this.exercise,
    required this.index,
    required this.count,
    required this.template,
    required this.dark,
    required this.text,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasOverride = template.hasOverride(exercise.id);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : AppColors.cardSurface,
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(
            color: dark
                ? AppColors.darkBorder.withValues(alpha: 0.5)
                : AppColors.mist.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            // Reorder handle
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: index == 0 ? null : onMoveUp,
                  child: Icon(Icons.arrow_upward_rounded,
                      size: 16,
                      color: index == 0
                          ? (dark
                              ? AppColors.darkBorder
                              : AppColors.mist)
                          : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: index == count - 1 ? null : onMoveDown,
                  child: Icon(Icons.arrow_downward_rounded,
                      size: 16,
                      color: index == count - 1
                          ? (dark
                              ? AppColors.darkBorder
                              : AppColors.mist)
                          : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(exercise.name,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: dark ? AppColors.darkInk : AppColors.ink,
                            )),
                      ),
                      if (hasOverride) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs + 2, vertical: 2),
                          decoration: BoxDecoration(
                            color: dark
                                ? AppColors.darkAmber.withValues(alpha: 0.15)
                                : AppColors.amber.withValues(alpha: 0.12),
                            borderRadius: const BorderRadius.all(AppRadius.pill),
                          ),
                          child: Text(
                            'CUSTOM',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: dark
                                  ? AppColors.darkAmber
                                  : AppColors.amber,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${template.effectiveSets(exercise)}× ${template.effectiveReps(exercise)} · ${exercise.equipment}',
                    style: text.bodySmall?.copyWith(
                        color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
                  ),
                ],
              ),
            ),
            // Remove
            GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xs + 2),
                decoration: BoxDecoration(
                  color: AppColors.clay.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.all(AppRadius.sm),
                ),
                child: const Icon(Icons.close_rounded,
                    size: 16, color: AppColors.clay),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddExerciseButton extends StatelessWidget {
  final String label;
  final bool dark;
  final VoidCallback onTap;
  const _AddExerciseButton(
      {required this.label, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(
            color: dark ? AppColors.darkBorder : AppColors.mist,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                size: 18, color: dark ? AppColors.darkDeep : AppColors.deep),
            const SizedBox(width: AppSpacing.xs),
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: dark ? AppColors.darkDeep : AppColors.deep,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Exercise picker bottom sheet
// ─────────────────────────────────────────────

class _ExercisePickerSheet extends StatefulWidget {
  final List<Exercise> existing;
  const _ExercisePickerSheet({required this.existing});

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final db = DatabaseHelper.instance;
  String _search = '';
  bool _creatingNew = false;

  final _nameController = TextEditingController();
  final _setsController = TextEditingController(text: '3');
  final _repsController = TextEditingController(text: '10');
  final _durationValueController = TextEditingController(text: '30');
  String _equipment = 'bodyweight';
  bool _isDuration = false;
  String _durationUnit = 'sec';
  bool _showNameError = false;

  List<Exercise> get _nameSuggestions {
    final q = _nameController.text.trim().toLowerCase();
    if (q.isEmpty) return [];
    return widget.existing
        .where((e) => e.name.toLowerCase().contains(q))
        .take(5)
        .toList();
  }

  Future<void> _createAndReturn() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    final repsTarget = _isDuration
        ? '${_durationValueController.text.trim().isEmpty ? "30" : _durationValueController.text.trim()} $_durationUnit'
        : (_repsController.text.trim().isEmpty ? '10' : _repsController.text.trim());
    final exercise = Exercise(
      id: const Uuid().v4(),
      name: _nameController.text.trim(),
      equipment: _equipment,
      targetSets: int.tryParse(_setsController.text) ?? 3,
      repsTarget: repsTarget,
      isSeeded: false,
    );
    await db.insertExercise(exercise);
    if (mounted) Navigator.pop(context, exercise);
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final filtered = widget.existing
        .where((e) => e.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: const EdgeInsets.fromLTRB(
          20, AppSpacing.sm, 20, AppSpacing.lg),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkSurface : Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: AppRadius.xl),
      ),
      child: _creatingNew ? _buildCreateForm(dark) : _buildPicker(filtered, dark),
    );
  }

  Widget _buildPicker(List<Exercise> filtered, bool dark) {
    final text = context.text;
    return Column(
      children: [
        // handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: dark ? AppColors.darkBorder : AppColors.mist,
              borderRadius: const BorderRadius.all(AppRadius.pill),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Add Exercise',
            style: text.titleMedium?.copyWith(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              color: dark ? AppColors.darkInk : AppColors.ink,
            )),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Only exercises you\'ve created appear here.',
          style: text.bodySmall
              ?.copyWith(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          style: TextStyle(color: dark ? AppColors.darkInk : AppColors.ink),
          decoration: InputDecoration(
            hintText: 'Search your exercises…',
            hintStyle: TextStyle(
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            prefixIcon: Icon(Icons.search_rounded,
                size: 18,
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            filled: true,
            fillColor: dark
                ? AppColors.darkCard.withValues(alpha: 0.8)
                : AppColors.mist.withValues(alpha: 0.4),
            border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(AppRadius.md),
                borderSide: BorderSide.none),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fitness_center_rounded,
                            size: 32,
                            color: (dark ? AppColors.darkDeep : AppColors.deep)
                                .withValues(alpha: 0.35)),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _search.isEmpty
                              ? 'No exercises yet — create your first one below.'
                              : 'No results for "$_search".',
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(
                              color: dark
                                  ? AppColors.darkInkSubtle
                                  : AppColors.inkSubtle),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final e = filtered[i];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(context, e);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
                        decoration: BoxDecoration(
                          color: dark ? AppColors.darkCard : AppColors.mist.withValues(alpha: 0.35),
                          borderRadius: const BorderRadius.all(AppRadius.sm),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.name,
                                      style: text.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color:
                                            dark ? AppColors.darkInk : AppColors.ink,
                                      )),
                                  Text(
                                    '${e.targetSets}× ${e.repsTarget} · ${e.equipment}',
                                    style: text.bodySmall?.copyWith(
                                        color: dark
                                            ? AppColors.darkInkSubtle
                                            : AppColors.inkSubtle),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.add_circle_outline_rounded,
                                size: 18,
                                color: dark ? AppColors.darkDeep : AppColors.deep),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(AppRadius.md)),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _creatingNew = true);
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create new exercise'),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateForm(bool dark) {
    final text = context.text;
    final suggestions = _nameSuggestions;
    return ListView(
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _creatingNew = false),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: dark ? AppColors.darkInk : AppColors.ink),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('New Exercise',
                style: text.titleMedium?.copyWith(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w700,
                  color: dark ? AppColors.darkInk : AppColors.ink,
                )),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Name field
        TextField(
          controller: _nameController,
          style: TextStyle(color: dark ? AppColors.darkInk : AppColors.ink),
          onChanged: (_) {
            if (_showNameError) setState(() => _showNameError = false);
            setState(() {});
          },
          decoration: InputDecoration(
            hintText: 'Exercise name',
            hintStyle: TextStyle(
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            errorText: _showNameError ? 'Name is required' : null,
            filled: true,
            fillColor: dark
                ? AppColors.darkCard.withValues(alpha: 0.8)
                : AppColors.mist.withValues(alpha: 0.4),
            border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(AppRadius.md),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(AppRadius.md),
              borderSide: BorderSide(
                  color: dark ? AppColors.darkDeep : AppColors.deep, width: 1.5),
            ),
          ),
        ),

        // Suggestions
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
            color: dark ? AppColors.darkCard : AppColors.mist.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.all(AppRadius.md),
            ),
            child: Column(
              children: suggestions
                  .map((s) => ListTile(
                        dense: true,
                        leading: Icon(Icons.history_rounded,
                            size: 16,
                            color: dark
                                ? AppColors.darkInkSubtle
                                : AppColors.inkSubtle),
                        title: Text(s.name,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: dark ? AppColors.darkInk : AppColors.ink)),
                        subtitle: Text(
                            '${s.targetSets}× ${s.repsTarget} · ${s.equipment} — already exists',
                            style: TextStyle(
                                fontSize: 11,
                                color: dark
                                    ? AppColors.darkInkSubtle
                                    : AppColors.inkSubtle)),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context, s);
                        },
                      ))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),

        // Equipment chips
        _SectionLabel('Equipment', dark: dark, text: text),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: _equipmentOptions.map((eq) {
            final sel = _equipment == eq;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _equipment = eq);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                decoration: BoxDecoration(
                  color: sel
                      ? (dark ? AppColors.darkDeep : AppColors.deep)
                      : (dark
                          ? AppColors.darkCard
                          : AppColors.mist.withValues(alpha: 0.5)),
                  borderRadius: const BorderRadius.all(AppRadius.pill),
                ),
                child: Text(eq,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sel
                          ? (dark ? AppColors.darkCanvas : AppColors.canvas)
                          : (dark ? AppColors.darkInk : AppColors.ink),
                    )),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),

        // Target type toggle
        Row(
          children: [
            Expanded(
              child: _SegButton(
                label: 'Rep count',
                selected: !_isDuration,
                dark: dark,
                onTap: () => setState(() => _isDuration = false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _SegButton(
                label: 'Time-based',
                selected: _isDuration,
                dark: dark,
                onTap: () => setState(() => _isDuration = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        if (_isDuration)
          Row(
            children: [
              Expanded(
                child: _DialogField(
                  label: 'Duration',
                  controller: _durationValueController,
                  dark: dark,
                  hint: 'e.g. 30',
                  numeric: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _SegButton(
                        label: 'sec',
                        selected: _durationUnit == 'sec',
                        dark: dark,
                        onTap: () => setState(() => _durationUnit = 'sec'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _SegButton(
                        label: 'min',
                        selected: _durationUnit == 'min',
                        dark: dark,
                        onTap: () => setState(() => _durationUnit = 'min'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: _DialogField(
                  label: 'Sets',
                  controller: _setsController,
                  dark: dark,
                  hint: 'e.g. 3',
                  numeric: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _DialogField(
                  label: 'Reps',
                  controller: _repsController,
                  dark: dark,
                  hint: 'e.g. 10 or Max',
                ),
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(AppRadius.md)),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              _createAndReturn();
            },
            child: const Text('Add to day',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}
