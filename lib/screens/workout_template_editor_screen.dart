import 'package:flutter/material.dart';
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
    t.restBetweenSetsSeconds = int.tryParse(_restSetsController.text) ?? t.restBetweenSetsSeconds;
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

  // ---------------- Main exercises ----------------

  void _removeExercise(Exercise ex) {
    setState(() => _exercises.remove(ex));
  }

  void _moveExercise(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _exercises.length) return;
    setState(() {
      final item = _exercises.removeAt(index);
      _exercises.insert(newIndex, item);
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

    // Let the person confirm/adjust sets & reps for THIS day before adding
    // — this is what makes it per-day rather than silently reusing (and
    // risking overwriting) whatever the shared exercise's defaults are.
    await _customizeForThisDay(picked, isWarmup: false);
    if (!mounted) return;
    setState(() => _exercises.add(picked));
  }

  // ---------------- Warm-up (the previously-missing dynamic piece) ----------------

  void _removeWarmup(Exercise ex) {
    setState(() => _warmupExercises.remove(ex));
  }

  void _moveWarmup(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _warmupExercises.length) return;
    setState(() {
      final item = _warmupExercises.removeAt(index);
      _warmupExercises.insert(newIndex, item);
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

  /// Shared by both the main exercise list and warm-up — opens the sets/
  /// reps editor for one exercise, saving the result as a per-template
  /// override rather than mutating the shared Exercise record.
  Future<void> _customizeForThisDay(Exercise exercise, {required bool isWarmup}) async {
    final t = _template!;
    final setsController =
        TextEditingController(text: '${t.effectiveSets(exercise)}');
    final repsController = TextEditingController(text: t.effectiveReps(exercise));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Customize ${exercise.name} for this day'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This only changes it for "${t.name}"${isWarmup ? " warm-up" : ""} — '
              'other days using ${exercise.name} are unaffected.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A80)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: setsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Sets'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: repsController,
                    decoration: const InputDecoration(
                      labelText: 'Target',
                      hintText: 'e.g. 10, Max, 45 sec',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
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
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_template == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('Template not found.')),
      );
    }

    final t = _template!;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Edit day'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _label('Day name'),
            TextField(controller: _nameController),
            const SizedBox(height: 20),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: t.isRestDay,
              onChanged: (v) => setState(() => t.isRestDay = v),
              title: const Text('Rest day (no exercises)'),
              activeThumbColor: AppColors.moss,
            ),

            if (!t.isRestDay) ...[
              const SizedBox(height: 12),

              // ---------------- Warm-up section (new) ----------------
              _label('Warm-up'),
              Text(
                'Runs before the main workout. Tap an item to customize it for this day.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < _warmupExercises.length; i++)
                _exerciseRow(
                  exercise: _warmupExercises[i],
                  index: i,
                  count: _warmupExercises.length,
                  onTap: () => _customizeForThisDay(_warmupExercises[i], isWarmup: true),
                  onMoveUp: () => _moveWarmup(i, -1),
                  onMoveDown: () => _moveWarmup(i, 1),
                  onRemove: () => _removeWarmup(_warmupExercises[i]),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addWarmupExercise,
                  icon: const Icon(Icons.add),
                  label: const Text('Add warm-up exercise'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.mist),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              _label('Session type'),
              Row(
                children: [
                  Expanded(
                    child: _segButton(
                      'Sequential',
                      t.sessionType == SessionType.sequential,
                      () => setState(() => t.sessionType = SessionType.sequential),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _segButton(
                      'Circuit',
                      t.sessionType == SessionType.circuit,
                      () => setState(() => t.sessionType = SessionType.circuit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (t.sessionType == SessionType.sequential) ...[
                Row(
                  children: [
                    Expanded(
                      child: _numberField('Rest between sets (s)', _restSetsController),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numberField(
                          'Rest between exercises (s)', _restExercisesController),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(child: _numberField('Rounds', _roundsController)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numberField('Rest after round (s)', _restAfterRoundController),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),

              _label('Exercises'),
              Text(
                'Tap an exercise to customize its sets/reps for this day only.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < _exercises.length; i++)
                _exerciseRow(
                  exercise: _exercises[i],
                  index: i,
                  count: _exercises.length,
                  onTap: () => _customizeForThisDay(_exercises[i], isWarmup: false),
                  onMoveUp: () => _moveExercise(i, -1),
                  onMoveDown: () => _moveExercise(i, 1),
                  onRemove: () => _removeExercise(_exercises[i]),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addExercise,
                  icon: const Icon(Icons.add),
                  label: const Text('Add exercise'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.mist),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One row shared by both the warm-up list and the main exercise list —
  /// same interaction pattern (tap to customize, reorder, remove) in both
  /// places, so warm-up is no longer a second-class, static citizen.
  Widget _exerciseRow({
    required Exercise exercise,
    required int index,
    required int count,
    required VoidCallback onTap,
    required VoidCallback onMoveUp,
    required VoidCallback onMoveDown,
    required VoidCallback onRemove,
  }) {
    final t = _template!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          border: Border.all(color: AppColors.mist),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(exercise.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (t.hasOverride(exercise.id)) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBEFE3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('CUSTOM',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.amber)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${t.effectiveSets(exercise)}x${t.effectiveReps(exercise)} · ${exercise.equipment}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A80)),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: index == 0 ? null : onMoveUp,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 18),
              onPressed: index == count - 1 ? null : onMoveDown,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.clay),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      );

  Widget _numberField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextField(controller: controller, keyboardType: TextInputType.number),
      ],
    );
  }

  Widget _segButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.deep : AppColors.cardSurface,
          border: Border.all(color: selected ? AppColors.deep : AppColors.mist),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.canvas : AppColors.deepLight,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for adding an exercise (used by both the warm-up and main
/// exercise sections): pick an existing user-created one, or create a
/// brand new one on the spot. Only exercises the person actually created
/// appear here — the built-in reference library is never suggested.
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
    final query = _nameController.text.trim().toLowerCase();
    if (query.isEmpty) return [];
    return widget.existing
        .where((e) => e.name.toLowerCase().contains(query))
        .take(5)
        .toList();
  }

  Future<void> _createAndReturn() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an exercise name before adding it.')),
      );
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
    final filtered = widget.existing
        .where((e) => e.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _creatingNew ? _buildCreateForm() : _buildPicker(filtered),
    );
  }

  Widget _buildPicker(List<Exercise> filtered) {
    return Column(
      children: [
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(color: AppColors.mist, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(height: 16),
        Text('Add exercise', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Only exercises you\'ve created appear here.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(hintText: 'Search your exercises...'),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No exercises yet — create your first one below.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final e in filtered)
                      ListTile(
                        title: Text(e.name),
                        subtitle: Text('${e.targetSets}x${e.repsTarget} · ${e.equipment}'),
                        onTap: () => Navigator.pop(context, e),
                      ),
                  ],
                ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => setState(() => _creatingNew = true),
            icon: const Icon(Icons.add),
            label: const Text('Create new exercise'),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateForm() {
    final suggestions = _nameSuggestions;

    return ListView(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _creatingNew = false),
            ),
            Text('New exercise', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          onChanged: (_) {
            if (_showNameError) setState(() => _showNameError = false);
            setState(() {});
          },
          decoration: InputDecoration(
            hintText: 'Exercise name',
            errorText: _showNameError ? 'Name is required' : null,
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.mist),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final s in suggestions)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 18, color: AppColors.deepLight),
                    title: Text(s.name),
                    subtitle: Text('${s.targetSets}x${s.repsTarget} · ${s.equipment} — already exists'),
                    onTap: () => Navigator.pop(context, s),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            for (final eq in _equipmentOptions)
              ChoiceChip(
                label: Text(eq),
                selected: _equipment == eq,
                onSelected: (_) => setState(() => _equipment = eq),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _toggleChip('Rep count', !_isDuration, () => setState(() => _isDuration = false)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggleChip('Time-based', _isDuration, () => setState(() => _isDuration = true)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_isDuration)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _durationValueController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Duration', hintText: 'e.g. 30'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: _toggleChip('sec', _durationUnit == 'sec',
                            () => setState(() => _durationUnit = 'sec'))),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _toggleChip('min', _durationUnit == 'min',
                            () => setState(() => _durationUnit = 'min'))),
                  ],
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _setsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sets', hintText: 'e.g. 3'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _repsController,
                  decoration: const InputDecoration(labelText: 'Reps', hintText: 'e.g. 10, or Max'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _createAndReturn,
            child: const Text('Add to day'),
          ),
        ),
      ],
    );
  }

  Widget _toggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.deep : AppColors.cardSurface,
          border: Border.all(color: selected ? AppColors.deep : AppColors.mist),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected ? AppColors.canvas : AppColors.deepLight,
          ),
        ),
      ),
    );
  }
}