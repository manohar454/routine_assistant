/// Phase 3 — Goal decomposition + simulation models.
///
/// A GoalPlan breaks a high-level outcome (e.g. "run 5 km without stopping")
/// into a sequence of weekly milestones. The simulation layer then projects
/// whether the user is on track given their actual logged performance so far.

library;

// ─── Goal types ──────────────────────────────────────────────────────────────

enum GoalDomain { workout, running, habit, custom }

enum GoalStatus { active, paused, completed, abandoned }

enum SimulationOutcome { onTrack, slightlyBehind, atRisk, offTrack }

// ─── Weekly milestone ─────────────────────────────────────────────────────────

/// One step in the decomposed plan — what you should be able to do
/// by the end of this specific week.
class WeeklyMilestone {
  final int weekNumber;      // 1-indexed from goal start
  final String description;  // human-readable target for this week
  final double targetValue;  // numeric representation (reps, km, minutes…)
  final String unit;         // "reps", "km", "min", "sessions"
  final bool isCheckpoint;   // true = a review week, not just progression

  const WeeklyMilestone({
    required this.weekNumber,
    required this.description,
    required this.targetValue,
    required this.unit,
    this.isCheckpoint = false,
  });

  Map<String, dynamic> toMap() => {
        'weekNumber': weekNumber,
        'description': description,
        'targetValue': targetValue,
        'unit': unit,
        'isCheckpoint': isCheckpoint ? 1 : 0,
      };

  factory WeeklyMilestone.fromMap(Map<String, dynamic> m) => WeeklyMilestone(
        weekNumber: m['weekNumber'] as int,
        description: m['description'] as String,
        targetValue: (m['targetValue'] as num).toDouble(),
        unit: m['unit'] as String,
        isCheckpoint: (m['isCheckpoint'] as int) == 1,
      );
}

// ─── Goal plan ────────────────────────────────────────────────────────────────

class GoalPlan {
  final String id;
  String name;
  GoalDomain domain;
  GoalStatus status;

  /// The final outcome — what you want to achieve.
  final String outcomeDescription;

  /// Numeric value for the final target (e.g. 5.0 for "run 5 km").
  final double targetValue;
  final String unit;

  /// Starting baseline — what you can do right now.
  final double baselineValue;

  final DateTime startDate;
  final DateTime targetDate;   // user's deadline

  /// The engine-generated week-by-week progression.
  List<WeeklyMilestone> milestones;

  /// Linked exercise or category this goal tracks (optional).
  final String? linkedExerciseId;
  final String? linkedCategory;

  GoalPlan({
    required this.id,
    required this.name,
    required this.domain,
    required this.status,
    required this.outcomeDescription,
    required this.targetValue,
    required this.unit,
    required this.baselineValue,
    required this.startDate,
    required this.targetDate,
    required this.milestones,
    this.linkedExerciseId,
    this.linkedCategory,
  });

  int get totalWeeks =>
      targetDate.difference(startDate).inDays ~/ 7;

  int get currentWeek {
    final elapsed = DateTime.now().difference(startDate).inDays ~/ 7;
    return (elapsed + 1).clamp(1, totalWeeks);
  }

  WeeklyMilestone? get currentMilestone {
    final found = milestones.where((m) => m.weekNumber == currentWeek);
    if (found.isNotEmpty) return found.first;
    return milestones.isNotEmpty ? milestones.last : null;
  }

  double get progressFraction =>
      DateTime.now().difference(startDate).inDays /
      targetDate.difference(startDate).inDays.clamp(1, 99999);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'domain': domain.name,
        'status': status.name,
        'outcomeDescription': outcomeDescription,
        'targetValue': targetValue,
        'unit': unit,
        'baselineValue': baselineValue,
        'startDate': startDate.toIso8601String(),
        'targetDate': targetDate.toIso8601String(),
        'linkedExerciseId': linkedExerciseId,
        'linkedCategory': linkedCategory,
      };

  factory GoalPlan.fromMap(Map<String, dynamic> m,
      {List<WeeklyMilestone> milestones = const []}) =>
      GoalPlan(
        id: m['id'] as String,
        name: m['name'] as String,
        domain: GoalDomain.values.byName(m['domain'] as String),
        status: GoalStatus.values.byName(m['status'] as String),
        outcomeDescription: m['outcomeDescription'] as String,
        targetValue: (m['targetValue'] as num).toDouble(),
        unit: m['unit'] as String,
        baselineValue: (m['baselineValue'] as num).toDouble(),
        startDate: DateTime.parse(m['startDate'] as String),
        targetDate: DateTime.parse(m['targetDate'] as String),
        milestones: milestones,
        linkedExerciseId: m['linkedExerciseId'] as String?,
        linkedCategory: m['linkedCategory'] as String?,
      );
}

// ─── Simulation result ────────────────────────────────────────────────────────

class SimulationResult {
  final GoalPlan plan;

  /// The outcome projected from actual performance data.
  final SimulationOutcome outcome;

  /// What you are actually tracking at right now (based on recent logs).
  final double currentActualValue;

  /// What you should be at right now per the milestone plan.
  final double expectedValueNow;

  /// The gap — positive means you're ahead, negative means behind.
  final double delta;

  /// Projected final value if current trend continues.
  final double projectedFinalValue;

  /// Whether the projection says you'll hit the target by the deadline.
  final bool projectedToSucceed;

  /// Plain-language explanation the UI can show.
  final String summary;

  /// Suggested corrective action, if behind.
  final String? correctionHint;

  const SimulationResult({
    required this.plan,
    required this.outcome,
    required this.currentActualValue,
    required this.expectedValueNow,
    required this.delta,
    required this.projectedFinalValue,
    required this.projectedToSucceed,
    required this.summary,
    this.correctionHint,
  });
}
