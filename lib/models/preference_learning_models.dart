class ConflictOutcome {
  final String id;
  final String keptTaskCategory;
  final String droppedTaskCategory;
  final DateTime timestamp;
  final String? reason;

  ConflictOutcome({
    required this.id,
    required this.keptTaskCategory,
    required this.droppedTaskCategory,
    required this.timestamp,
    this.reason,
  });

  factory ConflictOutcome.fromMap(Map<String, dynamic> map) {
    return ConflictOutcome(
      id: map['id'] as String,
      keptTaskCategory: map['keptTaskCategory'] as String,
      droppedTaskCategory: map['droppedTaskCategory'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      reason: map['reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'keptTaskCategory': keptTaskCategory,
      'droppedTaskCategory': droppedTaskCategory,
      'timestamp': timestamp.toIso8601String(),
      'reason': reason,
    };
  }
}

class TaskImportanceWeight {
  final String taskCategory;
  double weight;
  int sampleCount;
  DateTime lastUpdated;

  TaskImportanceWeight({
    required this.taskCategory,
    this.weight = 0.5,
    this.sampleCount = 0,
    required this.lastUpdated,
  });

  factory TaskImportanceWeight.fromMap(Map<String, dynamic> map) {
    return TaskImportanceWeight(
      taskCategory: map['taskCategory'] as String,
      weight: (map['weight'] as num?)?.toDouble() ?? 0.5,
      sampleCount: (map['sampleCount'] as num?)?.toInt() ?? 0,
      lastUpdated: DateTime.parse(map['lastUpdated'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'taskCategory': taskCategory,
      'weight': weight,
      'sampleCount': sampleCount,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  bool get isReliable => sampleCount >= 5;
}