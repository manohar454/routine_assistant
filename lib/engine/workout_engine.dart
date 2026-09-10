import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/workout_models.dart';

class OverloadComparison {
  final bool hasHistory;
  final String message;
  final bool improved;

  OverloadComparison({
    required this.hasHistory,
    required this.message,
    this.improved = false,
  });
}

class WorkoutEngine {
  final DatabaseHelper db = DatabaseHelper.instance;

  /// Starts a new session, OR resumes an existing in-progress one from
  /// today if the user quit mid-workout — draft save/resume driven
  /// entirely by DB state, no separate "draft" flag needed.
  Future<WorkoutSession> startOrResumeSession(String templateId) async {
    final today = DateTime.now();
    final existing = await db.getInProgressSession(templateId, today);
    if (existing != null) return existing;

    final session = WorkoutSession(
      id: const Uuid().v4(),
      templateId: templateId,
      date: DateTime(today.year, today.month, today.day),
      startTime: today,
    );
    await db.insertSession(session);
    return session;
  }

  Future<void> logSet({
    required String sessionId,
    required String exerciseId,
    required int setNumber,
    required String performedValue,
    double weight = 0,
    int? rpe,
  }) async {
    final log = ExerciseLog(
      id: const Uuid().v4(),
      sessionId: sessionId,
      exerciseId: exerciseId,
      setNumber: setNumber,
      performedValue: performedValue,
      weight: weight,
      rpe: rpe,
      timestamp: DateTime.now(),
    );
    await db.insertExerciseLog(log);
  }

  Future<void> completeSession(WorkoutSession session) async {
    session.status = SessionStatus.completed;
    session.endTime = DateTime.now();
    await db.updateSession(session);
  }

  /// Extracts a leading number from a free-text performed value so
  /// "45 sec" -> 45, "22" -> 22, "Max" -> null (not comparable numerically).
  /// This is what lets progressive overload work across rep counts,
  /// duration holds, AND stay silent (rather than wrong) for open-ended
  /// "Max" targets where only the person knows if they improved.
  double? _parseNumeric(String value) {
    final match = RegExp(r'[\d.]+').firstMatch(value);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }

  ExerciseLog _bestLog(List<ExerciseLog> logs) {
    return logs.reduce((a, b) {
      if (b.weight != a.weight) return b.weight > a.weight ? b : a;
      final aNum = _parseNumeric(a.performedValue) ?? 0;
      final bNum = _parseNumeric(b.performedValue) ?? 0;
      return bNum > aNum ? b : a;
    });
  }

  /// Compares today's best effort for an exercise against the last time it
  /// was logged. Weight-bearing exercises compare weight first (tie-broken
  /// by the numeric performed value); bodyweight/duration exercises compare
  /// the numeric performed value directly. Falls back to a neutral message
  /// when values aren't numerically comparable (e.g. "Max").
  Future<OverloadComparison> compareToLastSession({
    required String exerciseId,
    required String exerciseName,
    required List<ExerciseLog> todaysLogsForExercise,
  }) async {
    final previous =
        await db.getPreviousLogsForExercise(exerciseId, DateTime.now());

    if (previous.isEmpty || todaysLogsForExercise.isEmpty) {
      return OverloadComparison(
        hasHistory: previous.isNotEmpty,
        message: previous.isEmpty
            ? 'First time logging $exerciseName — building your baseline.'
            : 'Log a set to compare against last time.',
      );
    }

    final prevBest = _bestLog(previous);
    final todayBest = _bestLog(todaysLogsForExercise);

    final prevLabel =
        '${previous.length}x${prevBest.performedValue}${prevBest.weight > 0 ? " @ ${prevBest.weight}kg" : ""}';
    final todayLabel =
        '${todaysLogsForExercise.length}x${todayBest.performedValue}${todayBest.weight > 0 ? " @ ${todayBest.weight}kg" : ""}';

    final prevNum = _parseNumeric(prevBest.performedValue);
    final todayNum = _parseNumeric(todayBest.performedValue);

    bool? improved;
    if (todayBest.weight != prevBest.weight) {
      improved = todayBest.weight > prevBest.weight;
    } else if (prevNum != null && todayNum != null) {
      improved = todayNum > prevNum;
    }

    if (improved == null) {
      return OverloadComparison(
        hasHistory: true,
        message: 'Last time: $prevLabel — today so far: $todayLabel',
      );
    }

    return OverloadComparison(
      hasHistory: true,
      improved: improved,
      message: improved
          ? 'Beat last time: $prevLabel → today $todayLabel'
          : 'Last time: $prevLabel — today so far: $todayLabel',
    );
  }
}
