import '../db/database_helper.dart';
import '../models/goal_models.dart';
import '../models/workout_models.dart';

/// Phase 3 — Goal decomposition + simulation engine.
///
/// Two responsibilities:
///
/// 1. DECOMPOSE: given a high-level goal (baseline → target, over N weeks),
///    generate a sensible week-by-week milestone plan using a conservative
///    progression curve — 10% per week for endurance/reps, with a deload
///    every 4th week (milestone stays flat) to allow recovery.
///
/// 2. SIMULATE: given a plan and actual performance history, project whether
///    the user is on track, slightly behind, at risk, or off track — and
///    explain what to adjust if behind.
class GoalDecompositionEngine {
  GoalDecompositionEngine._internal();
  static final GoalDecompositionEngine instance =
      GoalDecompositionEngine._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  // ── 1. Decompose ──────────────────────────────────────────────────────────

  /// Generates a list of weekly milestones from [baseline] → [target]
  /// spread across [weeks]. Uses a 10%-per-week progressive overload curve
  /// with a deload on every 4th week (value stays at prior week's level).
  List<WeeklyMilestone> decompose({
    required double baseline,
    required double target,
    required int weeks,
    required String unit,
    String Function(int week, double value, String unit)? descriptionBuilder,
  }) {
    if (weeks <= 0) return [];

    final milestones = <WeeklyMilestone>[];
    double current = baseline;
    final totalGain = target - baseline;

    // Compute per-week increment using exponential ramp flattened toward
    // the end: simple linear split for now (predictable, auditable).
    // Deload weeks get 0 increment; the remainder is distributed evenly.
    final activeWeeks = weeks - (weeks ~/ 4); // deload 1 in 4
    final weeklyIncrement =
        activeWeeks > 0 ? totalGain / activeWeeks : totalGain;

    for (int w = 1; w <= weeks; w++) {
      final isDeload = w % 4 == 0;
      final isCheckpoint = isDeload || w == weeks;

      if (!isDeload) {
        current = (current + weeklyIncrement).clamp(baseline, target);
      }
      // On final week always land exactly on target.
      final value = w == weeks ? target : current;

      final description = descriptionBuilder != null
          ? descriptionBuilder(w, value, unit)
          : _defaultDescription(w, value, unit, isDeload);

      milestones.add(WeeklyMilestone(
        weekNumber: w,
        description: description,
        targetValue: double.parse(value.toStringAsFixed(2)),
        unit: unit,
        isCheckpoint: isCheckpoint,
      ));
    }

    return milestones;
  }

  String _defaultDescription(
      int week, double value, String unit, bool isDeload) {
    if (isDeload) {
      return 'Week $week · Deload — consolidate at '
          '${_fmt(value)} $unit, no new push.';
    }
    return 'Week $week · Target: ${_fmt(value)} $unit';
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  // ── 2. Simulate ──────────────────────────────────────────────────────────

  /// Projects where the user is vs where they should be, and whether
  /// they'll reach the target by the deadline.
  ///
  /// [actualValues] is a time-ordered list of the user's recent
  /// performance values (e.g. reps logged, km run) — most recent last.
  Future<SimulationResult> simulate({
    required GoalPlan plan,
    required List<double> actualValues,
  }) async {
    final expected = plan.currentMilestone?.targetValue ?? plan.targetValue;
    final weeksRemaining = (plan.totalWeeks - plan.currentWeek).clamp(0, 999);

    // Current actual = average of last 3 data points (smoothed).
    final recent = actualValues.length > 3
        ? actualValues.sublist(actualValues.length - 3)
        : actualValues;
    final currentActual = recent.isEmpty
        ? plan.baselineValue
        : recent.reduce((a, b) => a + b) / recent.length;

    final delta = currentActual - expected;

    // Linear projection: assume the current weekly rate continues.
    final weeklyRate = actualValues.length >= 2
        ? (actualValues.last - actualValues.first) /
            (actualValues.length - 1).clamp(1, 999)
        : 0.0;
    final projectedFinal =
        currentActual + (weeklyRate * weeksRemaining);
    final projectedToSucceed = projectedFinal >= plan.targetValue * 0.95;

    final outcome = _classify(delta, expected, projectedToSucceed);
    final summary = _summarise(outcome, currentActual, expected, plan);
    final hint = _hint(outcome, plan, weeklyRate, weeksRemaining);

    return SimulationResult(
      plan: plan,
      outcome: outcome,
      currentActualValue: double.parse(currentActual.toStringAsFixed(2)),
      expectedValueNow: double.parse(expected.toStringAsFixed(2)),
      delta: double.parse(delta.toStringAsFixed(2)),
      projectedFinalValue:
          double.parse(projectedFinal.toStringAsFixed(2)),
      projectedToSucceed: projectedToSucceed,
      summary: summary,
      correctionHint: hint,
    );
  }

  SimulationOutcome _classify(
      double delta, double expected, bool projectedToSucceed) {
    if (expected == 0) return SimulationOutcome.onTrack;
    final ratio = delta / expected; // +ve = ahead, -ve = behind
    if (ratio >= -0.05) return SimulationOutcome.onTrack;
    if (ratio >= -0.15) return SimulationOutcome.slightlyBehind;
    if (projectedToSucceed) return SimulationOutcome.atRisk;
    return SimulationOutcome.offTrack;
  }

  String _summarise(SimulationOutcome outcome, double actual,
      double expected, GoalPlan plan) {
    final actualStr = _fmt(actual);
    final expectedStr = _fmt(expected);
    final unit = plan.unit;

    return switch (outcome) {
      SimulationOutcome.onTrack =>
        'On track — you\'re at $actualStr $unit, right where you need to be ($expectedStr $unit).',
      SimulationOutcome.slightlyBehind =>
        'Slightly behind — $actualStr vs $expectedStr $unit expected this week. '
            'A small push should close the gap.',
      SimulationOutcome.atRisk =>
        'At risk — $actualStr vs $expectedStr $unit expected. '
            'If the trend continues you may just make it, but it\'ll be tight.',
      SimulationOutcome.offTrack =>
        'Off track — $actualStr vs $expectedStr $unit expected. '
            'At the current pace you\'re unlikely to reach ${_fmt(plan.targetValue)} $unit '
            'by ${_dateLabel(plan.targetDate)}.',
    };
  }

  String? _hint(SimulationOutcome outcome, GoalPlan plan,
      double weeklyRate, int weeksRemaining) {
    if (outcome == SimulationOutcome.onTrack) return null;

    final needed = weeksRemaining > 0
        ? (plan.targetValue - plan.baselineValue) / plan.totalWeeks
        : null;

    if (outcome == SimulationOutcome.slightlyBehind) {
      return 'Try adding one extra session this week to get back on track.';
    }
    if (outcome == SimulationOutcome.atRisk) {
      return needed != null
          ? 'You need roughly ${_fmt(needed)} ${plan.unit} per week from here. '
              'Consider shortening your deload week or adding an extra session.'
          : 'Add one session per week and reassess in two weeks.';
    }
    // offTrack
    if (weeksRemaining > 2) {
      return 'Consider extending your deadline by ${(weeksRemaining * 0.3).ceil()} weeks, '
          'or reduce the target to something achievable in the time remaining.';
    }
    return 'With ${weeksRemaining} week(s) left, focus on the best single '
        'session you can deliver — then set a fresh goal.';
  }

  String _dateLabel(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  // ── Convenience: load actual values from DB ──────────────────────────────

  /// Pulls recent logged performance values for a linked exercise.
  /// Returns empty list if no exercise is linked or no logs found.
  Future<List<double>> loadActualValues(GoalPlan plan) async {
    if (plan.linkedExerciseId == null) return [];

    final logs = await _db.getPreviousLogsForExercise(
        plan.linkedExerciseId!, DateTime.now());

    return logs
        .map((l) => _parseNumeric(l.performedValue))
        .where((v) => v != null)
        .cast<double>()
        .toList();
  }

  double? _parseNumeric(String value) {
    final match = RegExp(r'[\d.]+').firstMatch(value);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }

  // ── Full pipeline: decompose + persist + simulate ────────────────────────

  /// Creates a new goal plan (decomposing milestones) and runs an
  /// immediate simulation against any existing logged history.
  Future<SimulationResult> createAndSimulate({
    required GoalPlan plan,
  }) async {
    // Generate milestones if not already provided.
    if (plan.milestones.isEmpty) {
      plan.milestones = decompose(
        baseline: plan.baselineValue,
        target: plan.targetValue,
        weeks: plan.totalWeeks.clamp(1, 52),
        unit: plan.unit,
      );
    }

    await _db.insertGoalPlan(plan);

    final actuals = await loadActualValues(plan);
    return simulate(plan: plan, actualValues: actuals);
  }
}
