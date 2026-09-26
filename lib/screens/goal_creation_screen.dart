import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../engine/goal_decomposition_engine.dart';
import '../models/goal_models.dart';
import '../models/workout_models.dart';
import '../theme/app_theme.dart';

class GoalCreationScreen extends StatefulWidget {
  const GoalCreationScreen({super.key});

  @override
  State<GoalCreationScreen> createState() => _GoalCreationScreenState();
}

class _GoalCreationScreenState extends State<GoalCreationScreen> {
  final _nameController = TextEditingController();
  final _outcomeController = TextEditingController();
  final _baselineController = TextEditingController();
  final _targetController = TextEditingController();
  final _unitController = TextEditingController(text: 'reps');
  final _exerciseSearchController = TextEditingController();

  GoalDomain _domain = GoalDomain.workout;
  DateTime _targetDate = DateTime.now().add(const Duration(days: 42));
  bool _saving = false;
  String? _error;

  // Linked exercise
  Exercise? _linkedExercise;
  List<Exercise> _allExercises = [];
  List<Exercise> _filteredExercises = [];
  bool _showExercisePicker = false;
  bool _loadingExercises = false;

  @override
  void initState() {
    super.initState();
    _exerciseSearchController.addListener(_filterExercises);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _outcomeController.dispose();
    _baselineController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    _exerciseSearchController.dispose();
    super.dispose();
  }

  bool get _canLinkExercise =>
      _domain == GoalDomain.workout || _domain == GoalDomain.running;

  Future<void> _loadExercises() async {
    if (_allExercises.isNotEmpty) {
      setState(() => _showExercisePicker = true);
      return;
    }
    setState(() { _loadingExercises = true; _showExercisePicker = true; });
    final exercises = await DatabaseHelper.instance.getAllExercises();
    if (!mounted) return;
    setState(() {
      _allExercises = exercises;
      _filteredExercises = exercises;
      _loadingExercises = false;
    });
  }

  void _filterExercises() {
    final q = _exerciseSearchController.text.trim().toLowerCase();
    setState(() {
      _filteredExercises = q.isEmpty
          ? _allExercises
          : _allExercises
              .where((e) =>
                  e.name.toLowerCase().contains(q) ||
                  e.equipment.toLowerCase().contains(q))
              .toList();
    });
  }

  void _selectExercise(Exercise ex) {
    setState(() {
      _linkedExercise = ex;
      _showExercisePicker = false;
      _exerciseSearchController.clear();
    });
    // Pre-fill name and unit if empty
    if (_nameController.text.isEmpty) {
      _nameController.text = ex.name;
    }
    if (_unitController.text == 'reps' || _unitController.text.isEmpty) {
      _unitController.text = 'reps';
    }
  }

  Future<void> _pickDate() async {
    final dark = context.isDark;
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime.now().add(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: dark ? ThemeData.dark() : ThemeData.light(),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final outcome = _outcomeController.text.trim();
    final baseline = double.tryParse(_baselineController.text.trim());
    final target = double.tryParse(_targetController.text.trim());
    final unit = _unitController.text.trim();

    if (name.isEmpty || outcome.isEmpty || baseline == null ||
        target == null || unit.isEmpty) {
      setState(() => _error = 'Fill in all fields.');
      return;
    }
    if (target <= baseline) {
      setState(() => _error = 'Target must be higher than your current level.');
      return;
    }

    setState(() { _saving = true; _error = null; });

    final plan = GoalPlan(
      id: const Uuid().v4(),
      name: name,
      domain: _domain,
      status: GoalStatus.active,
      outcomeDescription: outcome,
      targetValue: target,
      unit: unit,
      baselineValue: baseline,
      startDate: DateTime.now(),
      targetDate: _targetDate,
      milestones: [],
      linkedExerciseId: _linkedExercise?.id,
    );

    await GoalDecompositionEngine.instance.createAndSimulate(plan: plan);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final text = context.text;
    final weeks = _targetDate.difference(DateTime.now()).inDays ~/ 7;

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
        title: Text(
          'New Goal',
          style: text.titleMedium?.copyWith(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.w700,
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, AppSpacing.md, 20, 80),
        children: [
          // Domain chips
          _Label('CATEGORY', dark: dark, text: text),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: GoalDomain.values.map((d) {
              final sel = _domain == d;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _domain = d;
                    // Clear linked exercise if switching away from workout/running
                    if (d != GoalDomain.workout && d != GoalDomain.running) {
                      _linkedExercise = null;
                      _showExercisePicker = false;
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                  decoration: BoxDecoration(
                    color: sel
                        ? (dark ? AppColors.darkDeep : AppColors.deep)
                        : (dark ? AppColors.darkCard : AppColors.cardSurface),
                    borderRadius: const BorderRadius.all(AppRadius.pill),
                    border: Border.all(
                      color: sel
                          ? Colors.transparent
                          : (dark ? AppColors.darkBorder : AppColors.mist),
                    ),
                  ),
                  child: Text(
                    _domainLabel(d),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sel
                          ? Colors.white
                          : (dark ? AppColors.darkInk : AppColors.ink),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          // ── Linked exercise (workout / running only) ──────────────────────
          if (_canLinkExercise) ...[
            const SizedBox(height: AppSpacing.lg),
            _Label('LINK TO EXERCISE (OPTIONAL)', dark: dark, text: text),
            if (_linkedExercise != null)
              _LinkedExerciseBadge(
                exercise: _linkedExercise!,
                dark: dark,
                text: text,
                onClear: () => setState(() => _linkedExercise = null),
              )
            else
              GestureDetector(
                onTap: _loadExercises,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: dark
                        ? AppColors.darkCard.withValues(alpha: 0.8)
                        : AppColors.mist.withValues(alpha: 0.4),
                    borderRadius: const BorderRadius.all(AppRadius.md),
                    border: Border.all(
                      color: dark
                          ? AppColors.darkBorder.withValues(alpha: 0.5)
                          : AppColors.mist,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.fitness_center_rounded,
                          size: 16,
                          color: dark
                              ? AppColors.darkDeep
                              : AppColors.deep),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Link an exercise for real data in simulations',
                        style: text.bodySmall?.copyWith(
                          color: dark
                              ? AppColors.darkInkSubtle
                              : AppColors.inkSubtle,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.add_rounded,
                          size: 18,
                          color: dark
                              ? AppColors.darkDeep
                              : AppColors.deep),
                    ],
                  ),
                ),
              ),

            // Exercise search picker
            if (_showExercisePicker) ...[
              const SizedBox(height: AppSpacing.sm),
              _ExercisePicker(
                searchController: _exerciseSearchController,
                exercises: _filteredExercises,
                loading: _loadingExercises,
                dark: dark,
                text: text,
                onSelect: _selectExercise,
                onDismiss: () => setState(() {
                  _showExercisePicker = false;
                  _exerciseSearchController.clear();
                }),
              ),
            ],
          ],

          const SizedBox(height: AppSpacing.lg),
          _Label('GOAL NAME', dark: dark, text: text),
          _Field(
            controller: _nameController,
            dark: dark,
            hint: 'e.g. Build pull-up strength',
          ),

          const SizedBox(height: AppSpacing.md),
          _Label('WHAT YOU WANT TO ACHIEVE', dark: dark, text: text),
          _Field(
            controller: _outcomeController,
            dark: dark,
            hint: 'e.g. Do 10 pull-ups in one set',
          ),

          const SizedBox(height: AppSpacing.md),
          _Label('UNIT', dark: dark, text: text),
          _Field(
            controller: _unitController,
            dark: dark,
            hint: 'reps / km / min / sessions',
          ),

          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('WHERE YOU ARE NOW', dark: dark, text: text),
                    _Field(
                      controller: _baselineController,
                      dark: dark,
                      hint: 'e.g. 3',
                      numeric: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('TARGET', dark: dark, text: text),
                    _Field(
                      controller: _targetController,
                      dark: dark,
                      hint: 'e.g. 10',
                      numeric: true,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),
          _Label('DEADLINE', dark: dark, text: text),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.md + 2),
              decoration: BoxDecoration(
                color: dark
                    ? AppColors.darkCard.withValues(alpha: 0.8)
                    : AppColors.mist.withValues(alpha: 0.4),
                borderRadius: const BorderRadius.all(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 16,
                      color: dark ? AppColors.darkDeep : AppColors.deep),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${_targetDate.day}/${_targetDate.month}/${_targetDate.year}  ·  $weeks week${weeks == 1 ? '' : 's'}',
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: dark ? AppColors.darkInk : AppColors.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18,
                      color: dark
                          ? AppColors.darkInkSubtle
                          : AppColors.inkSubtle),
                ],
              ),
            ),
          ),

          // Info card
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: (dark ? AppColors.darkDeep : AppColors.deep)
                  .withValues(alpha: 0.08),
              borderRadius: const BorderRadius.all(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_graph_rounded,
                    size: 18,
                    color: dark ? AppColors.darkDeep : AppColors.deep),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _linkedExercise != null
                        ? 'Simulation will use your actual ${_linkedExercise!.name} logs to project progress. $weeks weekly milestones with 10% progression and built-in deload weeks.'
                        : 'The engine will break this into $weeks weekly milestones with a 10% progression rate and built-in deload weeks. Link an exercise above for real data.',
                    style: text.bodySmall?.copyWith(
                      color: dark ? AppColors.darkInk : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: TextStyle(color: AppColors.clay, fontSize: 13),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(AppRadius.md)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Create goal',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  String _domainLabel(GoalDomain d) => switch (d) {
        GoalDomain.workout => 'Workout',
        GoalDomain.running => 'Running',
        GoalDomain.habit => 'Habit',
        GoalDomain.custom => 'Custom',
      };
}

// ── Linked exercise badge ─────────────────────────────────────────────────────

class _LinkedExerciseBadge extends StatelessWidget {
  final Exercise exercise;
  final bool dark;
  final TextTheme text;
  final VoidCallback onClear;

  const _LinkedExerciseBadge({
    required this.exercise,
    required this.dark,
    required this.text,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: (dark ? AppColors.darkDeep : AppColors.deep)
            .withValues(alpha: 0.1),
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(
          color: (dark ? AppColors.darkDeep : AppColors.deep)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.fitness_center_rounded,
              size: 16,
              color: dark ? AppColors.darkDeep : AppColors.deep),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? AppColors.darkInk : AppColors.ink,
                  ),
                ),
                Text(
                  exercise.equipment,
                  style: text.bodySmall?.copyWith(
                    color: dark
                        ? AppColors.darkInkSubtle
                        : AppColors.inkSubtle,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close_rounded,
                size: 18,
                color:
                    dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
          ),
        ],
      ),
    );
  }
}

// ── Exercise search picker ────────────────────────────────────────────────────

class _ExercisePicker extends StatelessWidget {
  final TextEditingController searchController;
  final List<Exercise> exercises;
  final bool loading;
  final bool dark;
  final TextTheme text;
  final ValueChanged<Exercise> onSelect;
  final VoidCallback onDismiss;

  const _ExercisePicker({
    required this.searchController,
    required this.exercises,
    required this.loading,
    required this.dark,
    required this.text,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.mist,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + dismiss
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Pick an exercise',
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: dark ? AppColors.darkInk : AppColors.ink,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onDismiss,
                  child: Icon(Icons.close_rounded,
                      size: 18,
                      color: dark
                          ? AppColors.darkInkSubtle
                          : AppColors.inkSubtle),
                ),
              ],
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: searchController,
              autofocus: true,
              style: TextStyle(
                  color: dark ? AppColors.darkInk : AppColors.ink,
                  fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search exercises…',
                hintStyle: TextStyle(
                    color: dark
                        ? AppColors.darkInkSubtle
                        : AppColors.inkSubtle,
                    fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 18,
                    color: dark
                        ? AppColors.darkInkSubtle
                        : AppColors.inkSubtle),
                filled: true,
                fillColor: dark
                    ? AppColors.darkCanvas.withValues(alpha: 0.5)
                    : AppColors.mist.withValues(alpha: 0.4),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // List
          if (loading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'No exercises found',
                style: text.bodySmall?.copyWith(
                  color:
                      dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                itemCount: exercises.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: dark ? AppColors.darkBorder : AppColors.mist,
                ),
                itemBuilder: (context, i) {
                  final ex = exercises[i];
                  return InkWell(
                    onTap: () => onSelect(ex),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm + 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ex.name,
                                  style: text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: dark
                                        ? AppColors.darkInk
                                        : AppColors.ink,
                                  ),
                                ),
                                Text(
                                  ex.equipment,
                                  style: text.bodySmall?.copyWith(
                                    color: dark
                                        ? AppColors.darkInkSubtle
                                        : AppColors.inkSubtle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.add_rounded,
                              size: 16,
                              color: dark
                                  ? AppColors.darkDeep
                                  : AppColors.deep),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String label;
  final bool dark;
  final TextTheme text;
  const _Label(this.label, {required this.dark, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: (dark ? AppColors.darkDeep : AppColors.deep)
              .withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final bool dark;
  final String hint;
  final bool numeric;
  const _Field({
    required this.controller,
    required this.dark,
    required this.hint,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: TextStyle(
        color: dark ? AppColors.darkInk : AppColors.ink,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
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
