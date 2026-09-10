/// Preference learning — Phase 2.
///
/// Instead of you manually assigning priority tiers, the system infers
/// which tasks you actually treat as non-negotiable by watching what
/// happens when time is scarce and two things compete. Over enough
/// conflict resolutions, it fits a simple importance weight per task
/// type that best explains your past choices.
///
/// Implementation: lightweight logistic-regression-style weight update
/// (no external ML library needed — a few lines of math). Each conflict
/// outcome is one training example: task A vs task B, you kept A →
/// A's weight increases slightly, B's decreases slightly.
library;

/// One recorded conflict outcome — the raw training data for preference
/// learning. Stored in the DB so the model can be retrained as history
/// accumulates, rather than being fit once and frozen.
class ConflictOutcome {
  final String id;
  final String keptTaskCategory;   // the task you chose to protect
  final String droppedTaskCategory; // the task you let slip/reschedule
  final DateTime timestamp;
  final String? reason; // optional free-text, for the reasoning trace

  ConflictOutcome({
    required this.id,
    required this.keptTaskCategory,
    required this.droppedTaskCategory,
    required this.timestamp,
    this.reason,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'keptTaskCategory': keptTaskCategory,
        'droppedTaskCategory': droppedTaskCategory,
        'timestamp': timestamp.toIso8601String(),
        'reason': reason,
      };

  factory ConflictOutcome.fromMap(Map<String, dynamic> map) => ConflictOutcome(
        id: map['id'] as String,
        keptTaskCategory: map['keptTaskCategory'] as String,
        droppedTaskCategory: map['droppedTaskCategory'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        reason: map['reason'] as String?,
      );
}

/// The learned importance weight for one task category.
/// Higher weight = the system has observed you protecting this type
/// more often than dropping it when something had to give.
class TaskImportanceWeight {
  final String taskCategory;
  double weight; // 0.0-1.0, initialized at 0.5 (neutral)
  int sampleCount;
  DateTime lastUpdated;

  TaskImportanceWeight({
    required this.taskCategory,
    this.weight = 0.5,
    this.sampleCount = 0,
    required this.lastUpdated,
  });

  /// Whether this weight has enough observations to be meaningful.
  /// Below this threshold, treat all categories as equally important.
  bool get isReliable => sampleCount >= 5;

  Map<String, dynamic> toMap() => {
        'taskCategory': taskCategory,
        'weight': weight,
        'sampleCount': sampleCount,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory TaskImportanceWeight.fromMap(Map<String, dynamic> map) =>
      TaskImportanceWeight(
        taskCategory: map['taskCategory'] as String,
        weight: (map['weight'] as num).toDouble(),
        sampleCount: map['sampleCount'] as int,
        lastUpdated: DateTime.parse(map['lastUpdated'] as String),
      );
}