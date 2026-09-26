import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final match =
      RegExp(r'(\d+)\s*(sec|min)', caseSensitive: false).firstMatch(target);
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

  int _exerciseIndex = 0;
  int _round = 1;

  OverloadComparison? _comparison;
  GoalSuggestion? _currentSuggestion;

  final _valueController = TextEditingController();
  final _weightController = TextEditingController();

  Timer? _sessionTicker;
  Duration _elapsed = Duration.zero;

  Timer? _restTimer;
  int _restSecondsLeft = 0;

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
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final mainExercises = await db.getExercisesForIds(template.exerciseIds);
    final warmupExercises =
        await db.getExercisesForIds(template.warmupExerciseIds);
    final session = await engine.startOrResumeSession(widget.templateId);
    final logs = await db.getLogsForSession(session.id);

    if (!mounted) return;
    setState(() {
      _template = template;
      _mainExercises = mainExercises;
      _warmupExercises = warmupExercises;
      _session = session;
      _allLogs = logs;
      _warmupDone = warmupExercises.isEmpty;
      _loading = false;
    });

    if (template.sessionType == SessionType.sequential) {
      _exerciseIndex = _findFirstIncompleteSequentialExercise();
    }

    _startSessionTimer(session.startTime);
    await WorkoutForegroundService.instance.start(templateName: template.name);
    await _refreshComparison();
  }

  int _findFirstIncompleteSequentialExercise() {
    for (int i = 0; i < _mainExercises.length; i++) {
      final loggedCount =
          _allLogs.where((l) => l.exerciseId == _mainExercises[i].id).length;
      if (loggedCount < _template!.effectiveSets(_mainExercises[i])) return i;
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

  Exercise? get _currentExercise =>
      _mainExercises.isEmpty ? null : _mainExercises[_exerciseIndex];

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
    if (!mounted) return;
    setState(() => _comparison = comparison);
    final suggestion = await GoalScalingEngine.instance.suggestNext(ex);
    if (!mounted) return;
    setState(() => _currentSuggestion = suggestion);
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
    await TtsService.instance
        .speak('$exerciseName, $seconds seconds. Starting now.');
    _runExerciseTick(exerciseName, seconds, onComplete);
  }

  void _runExerciseTick(
    String exerciseName,
    int targetSeconds,
    VoidCallback? onComplete,
  ) {
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
          setState(
              () => _valueController.text = _formatDurationLabel(targetSeconds));
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

  Future<void> _logSequentialSet() async {
    final ex = _currentExercise;
    final template = _template;
    if (ex == null || _session == null || template == null) return;
    if (_valueController.text.trim().isEmpty) return;

    HapticFeedback.lightImpact();
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

    final stillMoreSets =
        _currentExerciseLogs.length < template.effectiveSets(ex);
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

  Future<void> _logCircuitExercise() async {
    final ex = _currentExercise;
    final template = _template;
    if (ex == null || _session == null || template == null) return;
    if (_valueController.text.trim().isEmpty) return;

    HapticFeedback.lightImpact();
    await engine.logSet(
      sessionId: _session!.id,
      exerciseId: ex.id,
      setNumber: _round,
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

  bool _isWeighted(Exercise exercise) {
    const weightedEquipment = {'barbell', 'dumbbell', 'cable', 'machine'};
    return weightedEquipment.contains(exercise.equipment.toLowerCase());
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

    final dark = context.isDark;

    return Scaffold(
      backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: dark ? AppColors.darkInk : AppColors.ink),
          onPressed: () async {
            final nav = Navigator.of(context);
            await WorkoutForegroundService.instance.stop();
            if (!mounted) return;
            await nav.maybePop();
          },
        ),
        title: Text(
          _template!.name,
          style: context.text.titleLarge?.copyWith(
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 4, vertical: 4),
                decoration: BoxDecoration(
                  color: (dark ? AppColors.darkMoss : AppColors.moss)
                      .withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.all(AppRadius.pill),
                ),
                child: Text(
                  _formatElapsed(_elapsed),
                  style: context.text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? AppColors.darkMoss : AppColors.moss,
                  ),
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
    final dark = context.isDark;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          20, AppSpacing.sm,
          20, 60),
      children: [
        Text(
          'WARM-UP',
          style: context.text.labelSmall?.copyWith(
            color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Before you start',
          style: context.text.displaySmall?.copyWith(
            color: dark ? AppColors.darkInk : AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final w in _warmupExercises) _warmupRow(w),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => _warmupDone = true),
            style: FilledButton.styleFrom(
              backgroundColor: dark ? AppColors.darkMoss : AppColors.moss,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(AppRadius.md)),
            ),
            child: Text(
              _warmupChecked.length == _warmupExercises.length
                  ? 'Start main workout'
                  : 'Skip / start main workout',
              style: context.text.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _warmupRow(Exercise w) {
    final dark = context.isDark;
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
        title: Text(w.name,
            style: context.text.bodyMedium?.copyWith(
              color: dark ? AppColors.darkInk : AppColors.ink,
              fontWeight: FontWeight.w600,
            )),
        subtitle: Text(w.repsTarget,
            style: context.text.bodySmall?.copyWith(
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            )),
        activeColor: dark ? AppColors.darkMoss : AppColors.moss,
        contentPadding: EdgeInsets.zero,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: isChecked
            ? (dark ? AppColors.darkMoss : AppColors.moss).withValues(alpha: 0.1)
            : (dark ? AppColors.darkCard : AppColors.cardSurface),
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(
          color: isChecked
              ? (dark ? AppColors.darkMoss : AppColors.moss).withValues(alpha: 0.4)
              : (dark ? AppColors.darkBorder : AppColors.mist),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: dark ? AppColors.darkInk : AppColors.ink,
                    )),
                Text(
                  isRunningThis
                      ? (_exercisePaused
                          ? 'Paused — ${_exerciseSecondsLeft}s left'
                          : '${_exerciseSecondsLeft}s left')
                      : isChecked
                          ? 'Done ✓'
                          : _formatDurationLabel(seconds),
                  style: context.text.labelSmall?.copyWith(
                    color: isChecked
                        ? (dark ? AppColors.darkMoss : AppColors.moss)
                        : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
                  ),
                ),
              ],
            ),
          ),
          if (isChecked)
            Icon(Icons.check_circle_rounded,
                color: dark ? AppColors.darkMoss : AppColors.moss)
          else if (isRunningThis) ...[
            GestureDetector(
              onTap: _exercisePaused ? _resumeExerciseTimer : _pauseExerciseTimer,
              child: Icon(
                _exercisePaused
                    ? Icons.play_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                color: dark ? AppColors.darkDeep : AppColors.deep,
                size: 28,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: 1 - (_exerciseSecondsLeft / seconds),
                strokeWidth: 3,
                color: dark ? AppColors.darkMoss : AppColors.moss,
                backgroundColor: dark ? AppColors.darkBorder : AppColors.mist,
              ),
            ),
          ] else
            IconButton(
              icon: Icon(Icons.play_circle_outline_rounded,
                  color: dark ? AppColors.darkDeep : AppColors.deep),
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
    final dark = context.isDark;
    final ex = _currentExercise!;
    final loggedSets = _currentExerciseLogs;
    final isLastExercise = _exerciseIndex == _mainExercises.length - 1;
    final currentExerciseDone =
        loggedSets.length >= _template!.effectiveSets(ex);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          20, AppSpacing.sm,
          20, 60),
      children: [
        Text(
          'EXERCISE ${_exerciseIndex + 1} OF ${_mainExercises.length}',
          style: context.text.labelSmall?.copyWith(
            color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          ex.name,
          style: context.text.displaySmall?.copyWith(
            color: dark ? AppColors.darkInk : AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _restBanner(),
        for (final log in loggedSets) _loggedRow(log),
        if (_currentSuggestion != null && _currentSuggestion!.confidence > 0.3)
          _GoalSuggestionCard(suggestion: _currentSuggestion!),
        if (_currentSuggestion != null && _currentSuggestion!.confidence > 0.3)
          const SizedBox(height: AppSpacing.sm),
        if (!currentExerciseDone)
          _logInput(
            exercise: ex,
            badge: '${loggedSets.length + 1}',
            onLog: _logSequentialSet,
          ),
        const SizedBox(height: AppSpacing.md),
        _comparisonCard(),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            if (_exerciseIndex > 0)
              Expanded(child: _outlineButton('← Back', _previousExercise)),
            if (_exerciseIndex > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: isLastExercise
                  ? FilledButton(
                      onPressed: _finishWorkout,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            dark ? AppColors.darkMoss : AppColors.moss,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.all(AppRadius.md)),
                      ),
                      child: Text('Finish workout',
                          style: context.text.labelLarge?.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                    )
                  : FilledButton(
                      onPressed: _nextExercise,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            dark ? AppColors.darkDeep : AppColors.deep,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.all(AppRadius.md)),
                      ),
                      child: Text('Next →',
                          style: context.text.labelLarge?.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCircuitBody() {
    final dark = context.isDark;
    final ex = _currentExercise!;
    final template = _template!;
    final alreadyLoggedThisRound =
        _currentExerciseLogs.any((l) => l.setNumber == _round);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          20, AppSpacing.sm,
          20, 60),
      children: [
        Text(
          'ROUND $_round OF ${template.circuitRounds} · EXERCISE ${_exerciseIndex + 1} OF ${_mainExercises.length}',
          style: context.text.labelSmall?.copyWith(
            color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          ex.name,
          style: context.text.displaySmall?.copyWith(
            color: dark ? AppColors.darkInk : AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _restBanner(),
        for (final log in _currentExerciseLogs)
          _loggedRow(log, label: 'R${log.setNumber}'),
        if (_currentSuggestion != null && _currentSuggestion!.confidence > 0.3)
          _GoalSuggestionCard(suggestion: _currentSuggestion!),
        if (_currentSuggestion != null && _currentSuggestion!.confidence > 0.3)
          const SizedBox(height: AppSpacing.sm),
        if (!alreadyLoggedThisRound && !_circuitComplete)
          _logInput(
            exercise: ex,
            badge: 'R$_round',
            onLog: _logCircuitExercise,
          ),
        const SizedBox(height: AppSpacing.md),
        _comparisonCard(),
        const SizedBox(height: AppSpacing.lg),
        if (_circuitComplete)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _finishWorkout,
              style: FilledButton.styleFrom(
                backgroundColor: dark ? AppColors.darkMoss : AppColors.moss,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(AppRadius.md)),
              ),
              child: Text('Finish workout',
                  style: context.text.labelLarge?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          )
        else
          Text(
            'Circuit: no rest within round — ${template.restAfterRoundSeconds}s after each full round.',
            style: context.text.bodySmall?.copyWith(
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            ),
          ),
      ],
    );
  }

  Widget _restBanner() {
    if (_restSecondsLeft <= 0) return const SizedBox.shrink();
    final dark = context.isDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkDeep : AppColors.deep,
          borderRadius: const BorderRadius.all(AppRadius.lg),
        ),
        child: Column(
          children: [
            Text(
              'REST',
              style: context.text.labelSmall?.copyWith(
                color: Colors.white54,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '0:${_restSecondsLeft.toString().padLeft(2, '0')}',
              style: context.text.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton(
              onPressed: _skipRest,
              child: Text('Skip rest',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loggedRow(ExerciseLog log, {String? label}) {
    final dark = context.isDark;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: (dark ? AppColors.darkMoss : AppColors.moss).withValues(alpha: 0.08),
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(
          color: (dark ? AppColors.darkMoss : AppColors.moss).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          _badge(label ?? '${log.setNumber}'),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${log.performedValue}${log.weight > 0 ? " · ${log.weight}kg" : ""}',
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: dark ? AppColors.darkInk : AppColors.ink,
              ),
            ),
          ),
          Icon(Icons.check_circle_rounded,
              color: dark ? AppColors.darkMoss : AppColors.moss, size: 18),
        ],
      ),
    );
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
    final dark = context.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(color: dark ? AppColors.darkBorder : AppColors.mist),
      ),
      child: Row(
        children: [
          _badge(badge),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: _valueController,
              style: context.text.bodyMedium?.copyWith(
                color: dark ? AppColors.darkInk : AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: context.text.bodyMedium?.copyWith(
                  color: (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)
                      .withValues(alpha: 0.5),
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          if (showWeight) ...[
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 56,
              child: TextField(
                controller: _weightController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: context.text.bodyMedium?.copyWith(
                  color: dark ? AppColors.darkInk : AppColors.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'kg',
                  hintStyle: context.text.bodySmall?.copyWith(
                    color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                  ),
                  isDense: true,
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: onLog,
            child: Icon(Icons.check_circle_rounded,
                color: dark ? AppColors.darkDeep : AppColors.deep, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _durationInputRow({
    required String badge,
    required String exerciseName,
    required int targetSeconds,
    required VoidCallback onLog,
  }) {
    final dark = context.isDark;
    final hasPrefilled =
        _valueController.text.isNotEmpty && !_exerciseTimerActive;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(color: dark ? AppColors.darkBorder : AppColors.mist),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _badge(badge),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _exerciseTimerActive
                      ? (_exercisePaused
                          ? 'Paused — ${_exerciseSecondsLeft}s left'
                          : 'Running — ${_exerciseSecondsLeft}s left')
                      : hasPrefilled
                          ? 'Done — confirm or adjust'
                          : 'Target: ${_formatDurationLabel(targetSeconds)}',
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: dark ? AppColors.darkInk : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_exerciseTimerActive)
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value:
                          1 - (_exerciseSecondsLeft / targetSeconds),
                      color: dark ? AppColors.darkMoss : AppColors.moss,
                      backgroundColor:
                          dark ? AppColors.darkBorder : AppColors.mist,
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
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
                    style: context.text.bodyMedium?.copyWith(
                      color: dark ? AppColors.darkInk : AppColors.ink,
                    ),
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  ),
                ),
                GestureDetector(
                  onTap: onLog,
                  child: Icon(Icons.check_circle_rounded,
                      color: dark ? AppColors.darkDeep : AppColors.deep, size: 28),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    _startExerciseDurationTimer(exerciseName, targetSeconds),
                style: FilledButton.styleFrom(
                  backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(AppRadius.sm)),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text('Start ($badge)',
                    style: context.text.labelMedium
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _comparisonCard() {
    if (_comparison == null) return const SizedBox.shrink();
    final dark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(color: dark ? AppColors.darkBorder : AppColors.mist),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _comparison!.improved
                ? Icons.trending_up_rounded
                : Icons.info_outline_rounded,
            color: _comparison!.improved
                ? (dark ? AppColors.darkMoss : AppColors.moss)
                : (dark ? AppColors.darkDeep : AppColors.deepLight),
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _comparison!.message,
              style: context.text.bodyMedium?.copyWith(
                color: dark ? AppColors.darkInk : AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _outlineButton(String label, VoidCallback onTap) {
    final dark = context.isDark;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: dark ? AppColors.darkBorder : AppColors.mist),
        foregroundColor: dark ? AppColors.darkInk : AppColors.ink,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadius.md)),
      ),
      child: Text(label,
          style: context.text.labelLarge
              ?.copyWith(fontWeight: FontWeight.w600)),
    );
  }

  Widget _badge(String label) {
    final dark = context.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (dark ? AppColors.darkDeep : AppColors.deep).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: dark ? AppColors.darkDeep : AppColors.deep,
        ),
      ),
    );
  }
}

// ─── Goal suggestion card ────────────────────────────────────────────────────

class _GoalSuggestionCard extends StatelessWidget {
  final GoalSuggestion suggestion;
  const _GoalSuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final ready = suggestion.readyToProgress;
    final accent =
        ready ? (dark ? AppColors.darkMoss : AppColors.moss) : (dark ? AppColors.darkDeep : AppColors.deepLight);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.trending_up_rounded : Icons.info_outline_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.displayText,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  suggestion.reason,
                  style: context.text.bodySmall?.copyWith(
                    color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(suggestion.confidence * 100).toStringAsFixed(0)}% confidence',
                  style: context.text.labelSmall?.copyWith(
                    color: (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)
                        .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Rest day view ────────────────────────────────────────────────────────────

class _RestDayView extends StatelessWidget {
  final String templateName;
  const _RestDayView({required this.templateName});

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Scaffold(
      backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: dark ? AppColors.darkInk : AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: (dark ? AppColors.darkMoss : AppColors.moss)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.self_improvement_rounded,
                    size: 36, color: dark ? AppColors.darkMoss : AppColors.moss),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                templateName,
                style: context.text.displaySmall?.copyWith(
                  color: dark ? AppColors.darkInk : AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Rest & recovery day — light walk, hydrate, stretch, breathe.',
                style: context.text.bodyMedium?.copyWith(
                  color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
