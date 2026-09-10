import 'dart:async';
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../engine/workout_engine.dart';
import '../engine/goal_scaling_engine.dart';
import '../models/workout_models.dart';
import '../services/tts_service.dart';
import '../services/workout_foreground_service.dart';
import '../theme/app_theme.dart';

/// Parses a duration-shaped target like "45 sec" or "2 min" into seconds.
/// Returns null for rep-count or "Max" targets, which stay manual-entry.
int? parseDurationSeconds(String target) {
  final match = RegExp(r'(\d+)\s*(sec|min)', caseSensitive: false)
      .firstMatch(target);
  if (match == null) return null;
  final value = int.parse(match.group(1)!);
  final unit = match.group(2)!.toLowerCase();
  return unit == 'min' ? value * 60 : value;
}

class WorkoutSessionScreen extends StatefulWidget {
  final String templateId;
  const WorkoutSessionScreen({super.key, required this.templateId});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  final db = DatabaseHelper.instance;
  final engine = WorkoutEngine();

  WorkoutTemplate? _template;
  List<Exercise> _mainExercises = [];
  List<Exercise> _warmupExercises = [];
  WorkoutSession? _session;
  List<ExerciseLog> _allLogs = [];

  bool _loading = true;
  bool _warmupDone = false;
  final Set<String> _warmupChecked = {};
  String? _activeWarmupId;

  // Sequential position
  int _exerciseIndex = 0;

  // Circuit position
  int _round = 1;

  OverloadComparison? _comparison;
  GoalSuggestion? _currentSuggestion;

  final _valueController = TextEditingController();
  final _weightController = TextEditingController();

  Timer? _sessionTicker;
  Duration _elapsed = Duration.zero;

  Timer? _restTimer;
  int _restSecondsLeft = 0;

  // Per-exercise duration timer — e.g. "Plank 45 sec", "Jumping Jacks 2 min".
  // Separate from the session timer (counts up, always running) and the
  // rest timer (counts down between sets/exercises/rounds).
  Timer? _exerciseTimer;
  int _exerciseSecondsLeft = 0;
  bool _exerciseTimerActive = false;
  bool _exercisePaused = false;
  String? _runningTimerExerciseName;
  int? _runningTimerTargetSeconds;
  VoidCallback? _runningTimerOnComplete;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sessionTicker?.cancel();
    _restTimer?.cancel();
    _exerciseTimer?.cancel();
    WorkoutForegroundService.instance.stop();
    _valueController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final template = await db.getWorkoutTemplate(widget.templateId);
    if (template == null || template.isRestDay) {
      setState(() => _loading = false);
      return;
    }
    final mainExercises = await db.getExercisesForIds(template.exerciseIds);
    final warmupExercises =
        await db.getExercisesForIds(template.warmupExerciseIds);
    final session = await engine.startOrResumeSession(widget.templateId);
    final logs = await db.getLogsForSession(session.id);

    setState(() {
      _template = template;
      _mainExercises = mainExercises;
      _warmupExercises = warmupExercises;
      _session = session;
      _allLogs = logs;
      _warmupDone = warmupExercises.isEmpty; // nothing to warm up -> skip
      _loading = false;
    });

    if (template.sessionType == SessionType.sequential) {
      _exerciseIndex = _findFirstIncompleteSequentialExercise();
    }

    _startSessionTimer(session.startTime);
    await WorkoutForegroundService.instance.start(
      templateName: template.name,
    );
    await _refreshComparison();
  }

  int _findFirstIncompleteSequentialExercise() {
    final template = _template!;
    for (int i = 0; i < _mainExercises.length; i++) {
      final loggedCount =
          _allLogs.where((l) => l.exerciseId == _mainExercises[i].id).length;
      if (loggedCount < template.effectiveSets(_mainExercises[i])) return i;
    }
    return _mainExercises.isEmpty ? 0 : _mainExercises.length - 1;
  }

  void _startSessionTimer(DateTime startTime) {
    _sessionTicker?.cancel();
    _sessionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(startTime);
      setState(() => _elapsed = elapsed);
      WorkoutForegroundService.instance.updateElapsed(_formatElapsed(elapsed));
    });
  }

  Exercise? get _currentExercise {
    if (_mainExercises.isEmpty) return null;
    return _mainExercises[_exerciseIndex];
  }

  List<ExerciseLog> get _currentExerciseLogs {
    final ex = _currentExercise;
    if (ex == null) return [];
    return _allLogs.where((l) => l.exerciseId == ex.id).toList()
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
  }

  Future<void> _refreshComparison() async {
    final ex = _currentExercise;
    if (ex == null || _session == null) return;
    final comparison = await engine.compareToLastSession(
      exerciseId: ex.id,
      exerciseName: ex.name,
      todaysLogsForExercise: _currentExerciseLogs,
    );
    if (mounted) setState(() => _comparison = comparison);

    // Load goal scaling suggestion for this exercise.
    final suggestion = await GoalScalingEngine.instance.suggestNext(ex);
    if (mounted) setState(() => _currentSuggestion = suggestion);
  }

  Future<void> _reloadLogs() async {
    if (_session == null) return;
    final logs = await db.getLogsForSession(_session!.id);
     if (!mounted) return;
    setState(() => _allLogs = logs);
  }

  void _startRest(int seconds) {
    _restTimer?.cancel();
    if (seconds <= 0) {
      setState(() => _restSecondsLeft = 0);
      return;
    }
    setState(() => _restSecondsLeft = seconds);
    TtsService.instance.speak('Rest, $seconds seconds.');
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      if (_restSecondsLeft <= 1) {
        timer.cancel();
        setState(() => _restSecondsLeft = 0);
        await TtsService.instance.speak('Rest over. Next set.');
      } else {
        setState(() => _restSecondsLeft--);
      }
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    setState(() => _restSecondsLeft = 0);
  }

  /// Runs a countdown for a single duration-based exercise (Plank,
  /// Jumping Jacks, etc): speaks the exercise name and duration at the
  /// start, counts down visibly, then speaks completion and pre-fills the
  /// logged value with the target duration — the person still taps the
  /// log button to confirm (or edits it first if they stopped early),
  /// consistent with the rest of the app never logging anything silently.
  Future<void> _startExerciseDurationTimer(
    String exerciseName,
    int seconds, {
    VoidCallback? onComplete,
  }) async {
    _exerciseTimer?.cancel();
    setState(() {
      _exerciseTimerActive = true;
      _exercisePaused = false;
      _exerciseSecondsLeft = seconds;
      _runningTimerExerciseName = exerciseName;
      _runningTimerTargetSeconds = seconds;
      _runningTimerOnComplete = onComplete;
    });

    await TtsService.instance.speak('$exerciseName, $seconds seconds. Starting now.');
    _runExerciseTick(exerciseName, seconds, onComplete);
  }

  void _runExerciseTick(String exerciseName, int targetSeconds, VoidCallback? onComplete) {
    _exerciseTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      if (_exerciseSecondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _exerciseSecondsLeft = 0;
          _exerciseTimerActive = false;
        });
        if (onComplete != null) {
          onComplete();
        } else {
          setState(() => _valueController.text = _formatDurationLabel(targetSeconds));
        }
        await TtsService.instance.speak('Time. $exerciseName complete.');
      } else {
        setState(() => _exerciseSecondsLeft--);
      }
    });
  }

  void _pauseExerciseTimer() {
    _exerciseTimer?.cancel();
    setState(() => _exercisePaused = true);
  }

  void _resumeExerciseTimer() {
    if (_runningTimerExerciseName == null || _runningTimerTargetSeconds == null) return;
    setState(() => _exercisePaused = false);
    _runExerciseTick(
        _runningTimerExerciseName!, _runningTimerTargetSeconds!, _runningTimerOnComplete);
  }

  void _cancelExerciseDurationTimer() {
    _exerciseTimer?.cancel();
    setState(() {
      _exerciseTimerActive = false;
      _exercisePaused = false;
      _exerciseSecondsLeft = 0;
      _runningTimerExerciseName = null;
      _runningTimerTargetSeconds = null;
      _runningTimerOnComplete = null;
    });
  }

  String _formatDurationLabel(int seconds) {
    if (seconds >= 60 && seconds % 60 == 0) return '${seconds ~/ 60} min';
    return '$seconds sec';
  }

  // ---------------- Sequential logic ----------------

  Future<void> _logSequentialSet() async {
    final ex = _currentExercise;
    final template = _template;
    if (ex == null || _session == null || template == null) return;
    if (_valueController.text.trim().isEmpty) return;

    final nextSetNumber = _currentExerciseLogs.length + 1;
    await engine.logSet(
      sessionId: _session!.id,
      exerciseId: ex.id,
      setNumber: nextSetNumber,
      performedValue: _valueController.text.trim(),
      weight: double.tryParse(_weightController.text) ?? 0,
    );

    _valueController.clear();
    _weightController.clear();
    await _reloadLogs();
    await _refreshComparison();

    final stillMoreSets = _currentExerciseLogs.length < template.effectiveSets(ex);
    _startRest(stillMoreSets
        ? template.restBetweenSetsSeconds
        : template.restBetweenExercisesSeconds);
  }

  void _nextExercise() {
    if (_exerciseIndex < _mainExercises.length - 1) {
      _cancelExerciseDurationTimer();
      _valueController.clear();
      _weightController.clear();
      setState(() => _exerciseIndex++);
      _refreshComparison();
    }
  }

  void _previousExercise() {
    if (_exerciseIndex > 0) {
      _cancelExerciseDurationTimer();
      _valueController.clear();
      _weightController.clear();
      setState(() => _exerciseIndex--);
      _refreshComparison();
    }
  }

  // ---------------- Circuit logic ----------------

  Future<void> _logCircuitExercise() async {
    final ex = _currentExercise;
    final template = _template;
    if (ex == null || _session == null || template == null) return;
    if (_valueController.text.trim().isEmpty) return;

    await engine.logSet(
      sessionId: _session!.id,
      exerciseId: ex.id,
      setNumber: _round, // round number, not a traditional "set"
      performedValue: _valueController.text.trim(),
      weight: double.tryParse(_weightController.text) ?? 0,
    );

    _valueController.clear();
    _weightController.clear();
    await _reloadLogs();

    final isLastExerciseInRound = _exerciseIndex == _mainExercises.length - 1;

    if (!isLastExerciseInRound) {
      setState(() => _exerciseIndex++);
      _startRest(template.restBetweenExercisesInRoundSeconds);
    } else if (_round < template.circuitRounds) {
      setState(() {
        _round++;
        _exerciseIndex = 0;
      });
      _startRest(template.restAfterRoundSeconds);
    } else {
      // All rounds complete — nothing more to log.
      setState(() {});
    }
    await _refreshComparison();
  }

  bool get _circuitComplete {
    final template = _template;
    if (template == null) return false;
    return _round >= template.circuitRounds &&
        _exerciseIndex == _mainExercises.length - 1 &&
        _currentExerciseLogs.any((l) => l.setNumber == _round);
  }

  Future<void> _finishWorkout() async {
    if (_session == null) return;

    final nav = Navigator.of(context);

    await engine.completeSession(_session!);
    await WorkoutForegroundService.instance.stop();

    if (!mounted) return;
    await nav.maybePop();
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_template == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('Template not found.')),
      );
    }
    if (_template!.isRestDay) {
      return _RestDayView(templateName: _template!.name);
    }
    if (_mainExercises.isEmpty) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('No exercises in this template.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final nav = Navigator.of(context);

            await WorkoutForegroundService.instance.stop();

            if (!mounted) return;
            await nav.maybePop();
          },
        ),
        title: Text(_template!.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _formatElapsed(_elapsed),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.deepLight,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: !_warmupDone ? _buildWarmup() : _buildMainSession(),
      ),
    );
  }

  Widget _buildWarmup() {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text('WARM-UP', style: textTheme.labelSmall),
        const SizedBox(height: 4),
        Text('Before you start', style: textTheme.displaySmall),
        const SizedBox(height: 20),
        for (final w in _warmupExercises) _warmupRow(w),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => _warmupDone = true),
            child: Text(_warmupChecked.length == _warmupExercises.length
                ? 'Start main workout'
                : 'Skip remaining / start main workout'),
          ),
        ),
      ],
    );
  }

  /// A warm-up item's row. Duration-based items (all of them, in the
  /// seeded plans) get a Start-timer button with a live countdown and
  /// voice start/end cues, auto-checking the box on completion — same
  /// fix as the main-exercise timer, just simpler since nothing needs
  /// to be logged for progressive overload here.
  Widget _warmupRow(Exercise w) {
    final seconds = parseDurationSeconds(w.repsTarget);
    final isChecked = _warmupChecked.contains(w.id);
    final isRunningThis = _activeWarmupId == w.id && _exerciseTimerActive;

    if (seconds == null) {
      return CheckboxListTile(
        value: isChecked,
        onChanged: (v) => setState(() {
          if (v == true) {
            _warmupChecked.add(w.id);
          } else {
            _warmupChecked.remove(w.id);
          }
        }),
        title: Text(w.name),
        subtitle: Text(w.repsTarget),
        activeColor: AppColors.moss,
        contentPadding: EdgeInsets.zero,
      );
    }

    return Container(
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
                Text(w.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  isRunningThis
                      ? (_exercisePaused
                          ? 'Paused — ${_exerciseSecondsLeft}s left'
                          : '${_exerciseSecondsLeft}s left')
                      : isChecked
                          ? 'Done'
                          : _formatDurationLabel(seconds),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A80)),
                ),
              ],
            ),
          ),
          if (isChecked)
            const Icon(Icons.check_circle, color: AppColors.moss)
          else if (isRunningThis) ...[
            IconButton(
              icon: Icon(
                _exercisePaused ? Icons.play_circle_outline : Icons.pause_circle_outline,
                color: AppColors.deep,
              ),
              onPressed: _exercisePaused ? _resumeExerciseTimer : _pauseExerciseTimer,
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: 1 - (_exerciseSecondsLeft / seconds),
                strokeWidth: 3,
                color: AppColors.moss,
              ),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.play_circle_outline, color: AppColors.deep),
              onPressed: () {
                setState(() => _activeWarmupId = w.id);
                _startExerciseDurationTimer(
                  w.name,
                  seconds,
                  onComplete: () => setState(() => _warmupChecked.add(w.id)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMainSession() {
    final template = _template!;
    return template.sessionType == SessionType.sequential
        ? _buildSequentialBody()
        : _buildCircuitBody();
  }

  Widget _buildSequentialBody() {
    final textTheme = Theme.of(context).textTheme;
    final ex = _currentExercise!;
    final loggedSets = _currentExerciseLogs;
    final isLastExercise = _exerciseIndex == _mainExercises.length - 1;
    final currentExerciseDone = loggedSets.length >= _template!.effectiveSets(ex);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text('EXERCISE ${_exerciseIndex + 1} OF ${_mainExercises.length}',
            style: textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(ex.name, style: textTheme.displaySmall),
        const SizedBox(height: 16),
        _restBanner(),
        for (final log in loggedSets) _loggedRow(log),
        if (_currentSuggestion != null && _currentSuggestion!.confidence > 0.3)
          _GoalSuggestionCard(suggestion: _currentSuggestion!),
        if (_currentSuggestion != null && _currentSuggestion!.confidence > 0.3)
          const SizedBox(height: 12),
        if (!currentExerciseDone)
          _logInput(
            exercise: ex,
            badge: '${loggedSets.length + 1}',
            onLog: _logSequentialSet,
          ),
        const SizedBox(height: 16),
        _comparisonCard(),
        const SizedBox(height: 24),
        Row(
          children: [
            if (_exerciseIndex > 0)
              Expanded(
                child: _outlineButton('Previous', _previousExercise),
              ),
            if (_exerciseIndex > 0) const SizedBox(width: 10),
            Expanded(
              child: isLastExercise
                  ? FilledButton(
                      onPressed: _finishWorkout,
                      child: const Text('Finish workout'))
                  : FilledButton(
                      onPressed: _nextExercise,
                      child: const Text('Next exercise')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCircuitBody() {
    final textTheme = Theme.of(context).textTheme;
    final ex = _currentExercise!;
    final template = _template!;
    final alreadyLoggedThisRound =
        _currentExerciseLogs.any((l) => l.setNumber == _round);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text(
            'ROUND $_round OF ${template.circuitRounds} · EXERCISE ${_exerciseIndex + 1} OF ${_mainExercises.length}',
            style: textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(ex.name, style: textTheme.displaySmall),
        const SizedBox(height: 16),
        _restBanner(),
        for (final log in _currentExerciseLogs) _loggedRow(log, label: 'Round ${log.setNumber}'),
        if (_currentSuggestion != null && _currentSuggestion!.confidence > 0.3)
          _GoalSuggestionCard(suggestion: _currentSuggestion!),
        if (_currentSuggestion != null && _currentSuggestion!.confidence > 0.3)
          const SizedBox(height: 12),
        if (!alreadyLoggedThisRound && !_circuitComplete)
          _logInput(
            exercise: ex,
            badge: 'R$_round',
            onLog: _logCircuitExercise,
          ),
        const SizedBox(height: 16),
        _comparisonCard(),
        const SizedBox(height: 24),
        if (_circuitComplete)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _finishWorkout,
              child: const Text('Finish workout'),
            ),
          )
        else
          Text(
            'Circuit: no rest between exercises within a round, '
            '${template.restAfterRoundSeconds}s rest after each full round.',
            style: textTheme.bodyMedium,
          ),
      ],
    );
  }

  Widget _restBanner() {
    if (_restSecondsLeft <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.deep,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text('REST',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
            Text(
              '0:${_restSecondsLeft.toString().padLeft(2, '0')}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
            ),
            TextButton(
              onPressed: _skipRest,
              child: const Text('Skip rest', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loggedRow(ExerciseLog log, {String? label}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.mist),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _badge(label ?? '${log.setNumber}'),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${log.performedValue}${log.weight > 0 ? " · ${log.weight}kg" : ""}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.check_circle, color: AppColors.moss),
        ],
      ),
    );
  }

  /// Decides between two very different logging experiences based on the
  /// exercise's target shape: a guided countdown timer for duration-based
  /// moves (Plank, Jumping Jacks), or manual number entry for rep-count/
  /// "Max" targets — this is the actual fix for the timer confusion:
  /// duration exercises now get their OWN timer, separate from the
  /// always-running session clock.
  /// Only barbell/dumbbell/cable/machine exercises use an actual external
  /// weight — showing a "kg" field on bodyweight, band, or duration-based
  /// moves (Plank, Push-ups, Jumping Jacks) was confusing since there's
  /// nothing meaningful to enter there.
  bool _isWeighted(Exercise exercise) {
    const weightedEquipment = {'barbell', 'dumbbell', 'cable', 'machine'};
    return weightedEquipment.contains(exercise.equipment.toLowerCase());
  }

  Widget _logInput({
    required Exercise exercise,
    required String badge,
    required VoidCallback onLog,
  }) {
    final repsTarget = _template!.effectiveReps(exercise);
    final durationSeconds = parseDurationSeconds(repsTarget);

    if (durationSeconds == null) {
      return _manualInputRow(
        badge: badge,
        hint: repsTarget,
        showWeight: _isWeighted(exercise),
        onLog: onLog,
      );
    }
    return _durationInputRow(
      badge: badge,
      exerciseName: exercise.name,
      targetSeconds: durationSeconds,
      onLog: onLog,
    );
  }

  Widget _manualInputRow({
    required String badge,
    required String hint,
    required bool showWeight,
    required VoidCallback onLog,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.mist),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _badge(badge),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _valueController,
              decoration: InputDecoration(hintText: hint, isDense: true),
            ),
          ),
          if (showWeight) ...[
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: 'kg', isDense: true),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            onPressed: onLog,
            icon: const Icon(Icons.check_circle_outline, color: AppColors.deep),
          ),
        ],
      ),
    );
  }

  /// The new duration-timer card: shows a Start button before running,
  /// a live countdown while active (separate from the session clock),
  /// and — once it hits zero — the pre-filled log confirmation, matching
  /// how every other logged value in this app requires an explicit tap
  /// rather than being recorded silently.
  Widget _durationInputRow({
    required String badge,
    required String exerciseName,
    required int targetSeconds,
    required VoidCallback onLog,
  }) {
    final hasPrefilled = _valueController.text.isNotEmpty && !_exerciseTimerActive;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.mist),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _badge(badge),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _exerciseTimerActive
                      ? (_exercisePaused
                          ? 'Paused — ${_exerciseSecondsLeft}s left'
                          : 'Running — ${_exerciseSecondsLeft}s left')
                      : hasPrefilled
                          ? 'Logged ${_valueController.text} — confirm or adjust below'
                          : 'Target: ${_formatDurationLabel(targetSeconds)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_exerciseTimerActive)
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: 1 - (_exerciseSecondsLeft / targetSeconds),
                    color: AppColors.moss,
                    backgroundColor: AppColors.mist,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _exercisePaused
                      ? _resumeExerciseTimer
                      : _pauseExerciseTimer,
                  child: Text(_exercisePaused ? 'Resume' : 'Pause'),
                ),
                TextButton(
                  onPressed: _cancelExerciseDurationTimer,
                  child: const Text('Cancel'),
                ),
              ],
            )
          else if (hasPrefilled)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _valueController,
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onLog,
                  icon: const Icon(Icons.check_circle_outline, color: AppColors.deep),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    _startExerciseDurationTimer(exerciseName, targetSeconds),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text('Start ($badge)'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _comparisonCard() {
    if (_comparison == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.mist),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _comparison!.improved ? Icons.trending_up : Icons.info_outline,
            color: _comparison!.improved ? AppColors.moss : AppColors.deepLight,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_comparison!.message,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.ink)),
          ),
        ],
      ),
    );
  }

  Widget _outlineButton(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: AppColors.mist),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label),
    );
  }

  Widget _badge(String label) {
    return Container(
      width: 32,
      height: 26,
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.deep)),
    );
  }
}

class _GoalSuggestionCard extends StatelessWidget {
  final GoalSuggestion suggestion;
  const _GoalSuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: suggestion.readyToProgress ? const Color(0xFFEFF3EE) : AppColors.cardSurface,
        border: Border.all(color: suggestion.readyToProgress ? AppColors.moss : AppColors.mist),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            suggestion.readyToProgress ? Icons.trending_up : Icons.info_outline,
            size: 18,
            color: suggestion.readyToProgress ? AppColors.moss : AppColors.deepLight,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.displayText,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: suggestion.readyToProgress ? AppColors.moss : AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(suggestion.reason, style: textTheme.bodyMedium?.copyWith(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  '${(suggestion.confidence * 100).toStringAsFixed(0)}% confidence',
                  style: textTheme.bodyMedium?.copyWith(fontSize: 11, color: const Color(0xFF9A9A90)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestDayView extends StatelessWidget {
  final String templateName;
  const _RestDayView({required this.templateName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.self_improvement, size: 48, color: AppColors.moss),
              const SizedBox(height: 16),
              Text(templateName,
                  style: Theme.of(context).textTheme.displaySmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'Rest & recovery day — light walk, hydrate, stretch, deep breathing.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
