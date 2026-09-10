/// Behavioral profile — Phase 2's statistical foundation.
///
/// Tracks mean and variance per task type from real logged history.
/// Uses exponential moving average (EMA) so recent behavior is
/// weighted more heavily than old behavior — if your routine changes
/// (new job, new season, etc.) the model adapts automatically without
/// needing a manual reset.
///
/// Everything in Phase 2 (anomaly detection, adaptive interventions,
/// burnout forecasting) reads from this model rather than using fixed
/// thresholds — so "you're running late" means "later than *your*
/// normal for this task type in this context," not "later than a
/// number someone hardcoded."
library;

class BehaviorProfile {
  final String id;
  final String taskCategory;  // e.g. "health", "work", "personal"
  final String contextKey;    // e.g. "monday_morning", "weekday", "any"

  /// Exponential moving average of actual task durations in minutes.
  double meanDurationMinutes;

  /// Variance — how much duration typically varies for you on this
  /// task type. High variance = the system needs to see a bigger
  /// deviation before flagging it as genuinely abnormal.
  double varianceDurationMinutes;

  /// How many real events this profile has been updated from.
  /// Low sample counts mean low confidence — the system should fall
  /// back to generic defaults until this reaches a meaningful number.
  int sampleCount;

  /// EMA of how long (in seconds) you typically take to respond to
  /// a reminder for this task type. Used by the adaptive intervention
  /// selector — if you usually respond within 30s but now it's been
  /// 3 minutes, that's already anomalous before the task even starts.
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

  /// Whether this profile has enough data to trust for anomaly
  /// detection. Below this threshold, fall back to conservative
  /// generic defaults rather than making predictions from sparse data.
  bool get isReliable => sampleCount >= 7;

  /// Z-score: how many standard deviations the observed value is from
  /// the learned mean. This is what "anomaly detection" actually means
  /// in this system — no magic, just standard statistics.
  /// Returns null if variance is zero or profile isn't reliable yet.
  double? zScore(double observedMinutes) {
    if (!isReliable || varianceDurationMinutes <= 0) return null;
    final stdDev = varianceDurationMinutes;
    return (observedMinutes - meanDurationMinutes) / stdDev;
  }

  /// Update the profile with one new real observation, using an
  /// exponential moving average. alpha=0.2 means recent observations
  /// count for 20% of the new mean — enough to adapt over ~5-10
  /// events without being so reactive that a single unusual day
  /// throws off the whole model.
  void update({
    required double actualDurationMinutes,
    double? responseLatencySeconds,
    double alpha = 0.2,
  }) {
    if (sampleCount == 0) {
      // Cold start — use the first observation directly as the initial mean.
      meanDurationMinutes = actualDurationMinutes;
      varianceDurationMinutes = 0;
    } else {
      final diff = actualDurationMinutes - meanDurationMinutes;
      meanDurationMinutes += alpha * diff;
      // Welford-style running variance update, EMA-adapted.
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
        meanDurationMinutes: (map['meanDurationMinutes'] as num).toDouble(),
        varianceDurationMinutes:
            (map['varianceDurationMinutes'] as num).toDouble(),
        sampleCount: map['sampleCount'] as int,
        meanResponseLatencySeconds:
            (map['meanResponseLatencySeconds'] as num).toDouble(),
        lastUpdated: DateTime.parse(map['lastUpdated'] as String),
      );
}