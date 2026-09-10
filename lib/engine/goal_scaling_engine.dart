import '../db/database_helper.dart';
import '../models/workout_models.dart';

/// Adaptive goal auto-scaling — Addendum 2, Feature D.
///
/// Instead of you manually deciding next week's workout targets,
/// this engine projects a sensible next step from your actual
/// performance trend. It reads completed exercise logs across recent
/// sessions, detects whether you're consistently hitting targets,
/// and suggests a conservative progression — the same progressive-
/// overload logic a coach would apply, automated from your own data.
///
/// Also implements Feature J (transfer learning across goal types):
/// when you set a brand-new exercise, it borrows progression rate
/// from structurally similar exercises you already have history on,
/// rather than cold-starting from zero.
class GoalScalingEngine {
  GoalScalingEngine._internal();
  static final GoalScalingEngine instance = GoalScalingEngine._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  // ----------------------------------------------------------------
  // Main suggestion — call when displaying next week's targets
  // ----------------------------------------------------------------

  /// Returns a suggested next target for [exercise] based on recent
  /// logged performance. Returns null if there isn't enough history
  /// to make a reliable suggestion yet.
  Future<GoalSuggestion?> suggestNext(Exercise exercise) async {
    final recentLogs =
        await _db.getPreviousLogsForExercise(exercise.id, DateTime.now());

    if (recentLogs.length < 3) {
      // Try transfer learning from similar exercises before giving up.
      return await _transferSuggestion(exercise);
    }

    return _projectFromHistory(exercise, recentLogs);
  }

  GoalSuggestion? _projectFromHistory(
      Exercise exercise, List<ExerciseLog> logs) {
    // Group logs by session (using setNumber as a proxy for round/set).
    // We want to know: over the last N sessions, did you consistently
    // hit the target reps/weight, or are you falling short?
    final numericValues = logs
        .map((l) => _parseNumeric(l.performedValue))
        .where((v) => v != null)
        .cast<double>()
        .toList();

    if (numericValues.isEmpty) {
      return GoalSuggestion(
        exercise: exercise,
        currentTarget: exercise.repsTarget,
        suggestedTarget: exercise.repsTarget,
        suggestedWeight: null,
        confidence: 0.0,
        reason: 'No numeric values to project from — target-based '
            'exercises like "Max" need manual review.',
        readyToProgress: false,
      );
    }

    final avgPerformed = numericValues.reduce((a, b) => a + b) / numericValues.length;
    final currentTarget = _parseNumeric(exercise.repsTarget) ?? avgPerformed;
    final hitRate = numericValues.where((v) => v >= currentTarget).length /
        numericValues.length;

    // Weight progression from logs.
    final weights = logs.map((l) => l.weight).where((w) => w > 0).toList();
    final avgWeight = weights.isEmpty
        ? 0.0
        : weights.reduce((a, b) => a + b) / weights.length;

    final readyToProgress = hitRate >= 0.8; // hit target 80%+ of sets

    if (!readyToProgress) {
      return GoalSuggestion(
        exercise: exercise,
        currentTarget: exercise.repsTarget,
        suggestedTarget: exercise.repsTarget,
        suggestedWeight: avgWeight > 0 ? avgWeight : null,
        confidence: (logs.length / 10.0).clamp(0.0, 1.0),
        reason: 'You\'re hitting the target ${(hitRate * 100).toStringAsFixed(0)}% '
            'of sets — keep at current weight until you hit it consistently '
            'before increasing.',
        readyToProgress: false,
      );
    }

    // Conservative progression:
    // - Weighted exercises: +2.5kg (standard micro-load)
    // - Rep-count exercises: +1-2 reps
    // - Duration exercises: +5 sec
    String suggestedTarget = exercise.repsTarget;
    double? suggestedWeight;

    if (avgWeight > 0) {
      suggestedWeight = avgWeight + 2.5;
      suggestedTarget = exercise.repsTarget; // keep reps same, increase weight
    } else if (exercise.repsTarget.contains('sec')) {
      final secs = _parseNumeric(exercise.repsTarget)?.toInt() ?? 30;
      suggestedTarget = '${secs + 5} sec';
    } else if (exercise.repsTarget.contains('min')) {
      final mins = _parseNumeric(exercise.repsTarget)?.toInt() ?? 1;
      suggestedTarget = '${mins + 1} min';
    } else {
      final reps = currentTarget.toInt();
      suggestedTarget = '${reps + 2}';
    }

    return GoalSuggestion(
      exercise: exercise,
      currentTarget: exercise.repsTarget,
      suggestedTarget: suggestedTarget,
      suggestedWeight: suggestedWeight,
      confidence: (logs.length / 10.0).clamp(0.3, 1.0),
      reason: 'You\'ve hit your target ${(hitRate * 100).toStringAsFixed(0)}% '
          'of sets across ${logs.length} recent logs — ready to progress.',
      readyToProgress: true,
    );
  }

  // ----------------------------------------------------------------
  // Feature J: Transfer learning across goal types
  // ----------------------------------------------------------------

  /// When an exercise has too little history, borrow progression
  /// insight from structurally similar exercises (same equipment,
  /// same rep range category) that already have enough history.
  Future<GoalSuggestion?> _transferSuggestion(Exercise exercise) async {
    final allExercises = await _db.getAllExercises();

    // Find exercises with the same equipment as a proxy for structural
    // similarity — a cable exercise is more similar to another cable
    // exercise than to a bodyweight one in terms of load progression.
    final similar = allExercises
        .where((e) =>
            e.id != exercise.id &&
            e.equipment == exercise.equipment &&
            !e.isSeeded)
        .toList();

    if (similar.isEmpty) return null;

    // Find the most-logged similar exercise to borrow from.
    Exercise? bestDonor;
    int bestCount = 0;

    for (final candidate in similar) {
      final logs = await _db.getPreviousLogsForExercise(
          candidate.id, DateTime.now());
      if (logs.length > bestCount) {
        bestCount = logs.length;
        bestDonor = candidate;
      }
    }

    if (bestDonor == null || bestCount < 3) return null;

    // Use the donor's hit rate as a confidence-weighted signal for
    // whether the current exercise is ready to progress.
    final donorLogs = await _db.getPreviousLogsForExercise(
        bestDonor.id, DateTime.now());
    final donorNumeric = donorLogs
        .map((l) => _parseNumeric(l.performedValue))
        .where((v) => v != null)
        .cast<double>()
        .toList();

    if (donorNumeric.isEmpty) return null;

    final donorTarget = _parseNumeric(bestDonor.repsTarget) ?? 10;
    final donorHitRate =
        donorNumeric.where((v) => v >= donorTarget).length / donorNumeric.length;

    return GoalSuggestion(
      exercise: exercise,
      currentTarget: exercise.repsTarget,
      suggestedTarget: exercise.repsTarget,
      suggestedWeight: null,
      // Low confidence since this is transferred, not direct evidence.
      confidence: 0.25,
      reason: 'Limited history for ${exercise.name} — borrowing progression '
          'signal from ${bestDonor.name} (same equipment, '
          '${(donorHitRate * 100).toStringAsFixed(0)}% hit rate). '
          'Log a few more sessions for a direct suggestion.',
      readyToProgress: donorHitRate >= 0.8,
    );
  }

  double? _parseNumeric(String value) {
    final match = RegExp(r'[\d.]+').firstMatch(value);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }
}

// ----------------------------------------------------------------
// Result type
// ----------------------------------------------------------------

class GoalSuggestion {
  final Exercise exercise;
  final String currentTarget;
  final String suggestedTarget;
  final double? suggestedWeight; // null for bodyweight/band exercises
  final double confidence;       // 0-1
  final String reason;           // for Reasoning Trace Engine
  final bool readyToProgress;

  const GoalSuggestion({
    required this.exercise,
    required this.currentTarget,
    required this.suggestedTarget,
    this.suggestedWeight,
    required this.confidence,
    required this.reason,
    required this.readyToProgress,
  });

  /// Formatted suggestion string for display in the workout UI.
  String get displayText {
    if (!readyToProgress) return 'Stay at: $currentTarget';
    if (suggestedWeight != null) {
      return 'Try: $suggestedTarget @ ${suggestedWeight!.toStringAsFixed(1)}kg';
    }
    return 'Try: $suggestedTarget';
  }
}