/// Behavioral profile — Phase 2's statistical foundation.
///
/// Tracks mean and variance per task type from real logged history.
/// Uses exponential moving average (EMA) so recent behavior is
/// weighted more heavily than old behavior — if your routine changes
/// (new job, new season, etc.) the model adapts automatically without
/// needing a manual reset.
library;

class BehaviorProfile {
  final String id;
  final String taskCategory;
  final String contextKey;

  double meanDurationMinutes;
  double varianceDurationMinutes;
  int sampleCount;
  double meanResponseLatencySeconds;
  DateTime lastUpdated;

  BehaviorProfile({
    required this.id,
    required this.taskCategory,
    required this.contextKey,
    this.meanDurationMinutes = 0,
    this.varianceDurationMinutes = 0,
    this.sampleCount = 0,
    this.meanResponseLatencySeconds = 120,
    required this.lastUpdated,
  });

  bool get isReliable => sampleCount >= 7;

  double? zScore(double observedMinutes) {
    if (!isReliable || varianceDurationMinutes <= 0) return null;
    return (observedMinutes - meanDurationMinutes) / varianceDurationMinutes;
  }

  void update({
    required double actualDurationMinutes,
    double? responseLatencySeconds,
    double alpha = 0.2,
  }) {
    if (sampleCount == 0) {
      meanDurationMinutes = actualDurationMinutes;
      varianceDurationMinutes = 0;
    } else {
      final diff = actualDurationMinutes - meanDurationMinutes;
      meanDurationMinutes += alpha * diff;
      varianceDurationMinutes =
          (1 - alpha) * (varianceDurationMinutes + alpha * diff * diff);
    }

    if (responseLatencySeconds != null) {
      meanResponseLatencySeconds =
          (1 - alpha) * meanResponseLatencySeconds + alpha * responseLatencySeconds;
    }

    sampleCount++;
    lastUpdated = DateTime.now();
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'taskCategory': taskCategory,
        'contextKey': contextKey,
        'meanDurationMinutes': meanDurationMinutes,
        'varianceDurationMinutes': varianceDurationMinutes,
        'sampleCount': sampleCount,
        'meanResponseLatencySeconds': meanResponseLatencySeconds,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory BehaviorProfile.fromMap(Map<String, dynamic> map) => BehaviorProfile(
        id: map['id'] as String,
        taskCategory: map['taskCategory'] as String,
        contextKey: map['contextKey'] as String,
        // Null-safe numeric casts — DB may return int or double
        meanDurationMinutes:
            (map['meanDurationMinutes'] as num? ?? 0).toDouble(),
        varianceDurationMinutes:
            (map['varianceDurationMinutes'] as num? ?? 0).toDouble(),
        sampleCount: (map['sampleCount'] as num? ?? 0).toInt(),
        meanResponseLatencySeconds:
            (map['meanResponseLatencySeconds'] as num? ?? 120).toDouble(),
        lastUpdated: DateTime.parse(map['lastUpdated'] as String),
      );
}
