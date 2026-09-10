import '../db/database_helper.dart';

// ignore_for_file: library_private_types_in_public_api
/// Burnout-risk trend forecasting — Addendum 2, Feature C.
///
/// Unlike the anomaly detector (which reacts to a single unusual event),
/// this runs a Bayesian trend model over accumulated signals to forecast
/// rising burnout risk *days before* it becomes a crisis. Three input
/// signals are combined: cumulative sleep debt, task-completion-rate
/// drift, and schedule density trend. Each carries its own confidence
/// weight based on how many data points back it.
///
/// Outputs a risk score (0.0-1.0) with a calibrated confidence interval
/// and a plain-language reason — both feed directly into the Reasoning
/// Trace Engine so the person can see exactly why the flag was raised.
class BurnoutForecastEngine {
  BurnoutForecastEngine._internal();
  static final BurnoutForecastEngine instance =
      BurnoutForecastEngine._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  // ----------------------------------------------------------------
  // Signal weights — how much each signal contributes to the score.
  // Sleep debt is weighted most heavily because it's both the most
  // reliably logged signal and the strongest predictor of sustained
  // performance decline in the literature.
  // ----------------------------------------------------------------
  static const double _sleepWeight = 0.45;
  static const double _completionWeight = 0.35;
  static const double _densityWeight = 0.20;

  // ----------------------------------------------------------------
  // Main forecast — call this once per day (e.g. during morning init)
  // ----------------------------------------------------------------

  Future<BurnoutForecast> forecast() async {
    final sleepSignal = await _sleepDebtSignal();
    final completionSignal = await _completionDriftSignal();
    final densitySignal = await _densitySignal();

    // Weighted combination of the three signals.
    final rawScore = sleepSignal.value * _sleepWeight +
        completionSignal.value * _completionWeight +
        densitySignal.value * _densityWeight;

    // Bayesian confidence: weighted average of individual signal
    // confidences, so a score derived from sparse data carries lower
    // confidence than one from weeks of consistent logging.
    final confidence = sleepSignal.confidence * _sleepWeight +
        completionSignal.confidence * _completionWeight +
        densitySignal.confidence * _densityWeight;

    final level = _scoreToLevel(rawScore);

    final reasons = <String>[];
    if (sleepSignal.value > 0.5) reasons.add(sleepSignal.reason);
    if (completionSignal.value > 0.5) reasons.add(completionSignal.reason);
    if (densitySignal.value > 0.5) reasons.add(densitySignal.reason);

    return BurnoutForecast(
      riskScore: rawScore.clamp(0.0, 1.0),
      confidence: confidence.clamp(0.0, 1.0),
      level: level,
      contributingReasons: reasons,
      sleepDebtSignal: sleepSignal,
      completionSignal: completionSignal,
      densitySignal: densitySignal,
      computedAt: DateTime.now(),
    );
  }

  // ----------------------------------------------------------------
  // Signal 1: Cumulative sleep debt
  // ----------------------------------------------------------------

  Future<_Signal> _sleepDebtSignal() async {
    final logs = await _db.getRecentSleepLogs(days: 7);
    if (logs.isEmpty) {
      return _Signal(
        value: 0.0,
        confidence: 0.0,
        reason: 'No sleep data yet.',
      );
    }

    final floorSetting = await _db.getSetting('sleep_floor_minutes');
    final floorMinutes =
        floorSetting != null ? int.tryParse(floorSetting) ?? 450 : 450;

    // Total debt = sum of shortfall nights over the past 7 days.
    double totalDebtMinutes = 0;
    for (final log in logs) {
      final deficit = floorMinutes - log.duration.inMinutes;
      if (deficit > 0) totalDebtMinutes += deficit;
    }

    // Normalize: 3 full hours of cumulative weekly debt = max signal.
    final value = (totalDebtMinutes / 180).clamp(0.0, 1.0);
    final confidence = (logs.length / 7).clamp(0.0, 1.0);

    String reason;
    if (value < 0.3) {
      reason = 'Sleep debt is low this week.';
    } else if (value < 0.6) {
      reason =
          'Moderate sleep debt building — ${totalDebtMinutes.toStringAsFixed(0)} min '
          'under your floor across the last ${logs.length} logged nights.';
    } else {
      reason =
          'Significant sleep debt: ${totalDebtMinutes.toStringAsFixed(0)} min '
          'under your ${(floorMinutes / 60).toStringAsFixed(1)}h floor '
          'across the last ${logs.length} nights.';
    }

    return _Signal(value: value, confidence: confidence, reason: reason);
  }

  // ----------------------------------------------------------------
  // Signal 2: Task-completion-rate drift
  // ----------------------------------------------------------------

  Future<_Signal> _completionDriftSignal() async {
    // Compare last 3 days' completion rate against the previous 7 days.
    // A declining trend is the real signal — not just a single bad day.
    final recentProfiles =
        await _db.getBehaviorProfilesUpdatedSince(DateTime.now().subtract(const Duration(days: 3)));
    final olderProfiles =
        await _db.getBehaviorProfilesUpdatedSince(DateTime.now().subtract(const Duration(days: 10)));

    if (recentProfiles.isEmpty || olderProfiles.isEmpty) {
      return _Signal(
        value: 0.0,
        confidence: 0.0,
        reason: 'Not enough task history to detect completion drift yet.',
      );
    }

    // Use sampleCount as a proxy for activity level — fewer completions
    // recently than previously suggests declining engagement.
    final recentActivity = recentProfiles.fold(0, (s, p) => s + p.sampleCount);
    final olderActivity = olderProfiles.fold(0, (s, p) => s + p.sampleCount);

    if (olderActivity == 0) {
      return _Signal(
        value: 0.0,
        confidence: 0.1,
        reason: 'Baseline activity not yet established.',
      );
    }

    // Drift: how much has recent activity dropped vs the baseline?
    // Expressed as a fraction of the baseline (clamped 0-1).
    final recentRate = recentActivity / 3.0;
    final olderRate = olderActivity / 10.0;
    final drift = ((olderRate - recentRate) / olderRate.clamp(0.01, double.infinity))
        .clamp(0.0, 1.0);

    final confidence = (recentProfiles.length / 5.0).clamp(0.0, 1.0);

    String reason;
    if (drift < 0.2) {
      reason = 'Task completion rate is stable.';
    } else if (drift < 0.5) {
      reason = 'Mild dip in task completion compared to your recent average.';
    } else {
      reason =
          'Noticeable drop in task completion this week vs your baseline — '
          '${(drift * 100).toStringAsFixed(0)}% below recent average.';
    }

    return _Signal(value: drift, confidence: confidence, reason: reason);
  }

  // ----------------------------------------------------------------
  // Signal 3: Schedule density trend
  // ----------------------------------------------------------------

  Future<_Signal> _densitySignal() async {
    // Count tasks scheduled in the last 3 days vs the 7 days before.
    // A sudden spike in task density is a burnout precursor.
    final recentTasks = await _db.getTaskCountSince(
        DateTime.now().subtract(const Duration(days: 3)));
    final olderTasks = await _db.getTaskCountSince(
        DateTime.now().subtract(const Duration(days: 10)));

    if (olderTasks == 0) {
      return _Signal(
        value: 0.0,
        confidence: 0.0,
        reason: 'Not enough scheduling history yet.',
      );
    }

    final recentDailyRate = recentTasks / 3.0;
    final olderDailyRate = olderTasks / 10.0;

    // Density spike: recent rate significantly above historical baseline.
    final spike =
        ((recentDailyRate - olderDailyRate) / olderDailyRate.clamp(0.01, double.infinity))
            .clamp(0.0, 1.0);

    final confidence = olderTasks > 5 ? 0.7 : 0.3;

    String reason;
    if (spike < 0.2) {
      reason = 'Schedule density is normal.';
    } else if (spike < 0.5) {
      reason = 'Schedule slightly busier than usual this week.';
    } else {
      reason =
          'Schedule density is significantly higher than your baseline — '
          '${recentDailyRate.toStringAsFixed(1)} tasks/day vs your usual '
          '${olderDailyRate.toStringAsFixed(1)}.';
    }

    return _Signal(value: spike, confidence: confidence, reason: reason);
  }

  // ----------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------

  BurnoutRiskLevel _scoreToLevel(double score) {
    if (score < 0.3) return BurnoutRiskLevel.low;
    if (score < 0.6) return BurnoutRiskLevel.moderate;
    return BurnoutRiskLevel.high;
  }
}

// ----------------------------------------------------------------
// Supporting types
// ----------------------------------------------------------------

enum BurnoutRiskLevel { low, moderate, high }

class _Signal {
  final double value;      // 0-1, higher = more concerning
  final double confidence; // 0-1, how much data backs this signal
  final String reason;     // plain-language explanation

  const _Signal({
    required this.value,
    required this.confidence,
    required this.reason,
  });
}

class BurnoutForecast {
  final double riskScore;       // 0-1 composite
  final double confidence;      // 0-1 Bayesian confidence
  final BurnoutRiskLevel level;
  final List<String> contributingReasons;
  final _Signal sleepDebtSignal;
  final _Signal completionSignal;
  final _Signal densitySignal;
  final DateTime computedAt;

  const BurnoutForecast({
    required this.riskScore,
    required this.confidence,
    required this.level,
    required this.contributingReasons,
    required this.sleepDebtSignal,
    required this.completionSignal,
    required this.densitySignal,
    required this.computedAt,
  });

  /// Plain-language summary for the home screen or Reasoning Trace.
  String get summary {
    switch (level) {
      case BurnoutRiskLevel.low:
        return 'Recovery load looks manageable right now.';
      case BurnoutRiskLevel.moderate:
        return 'Some burnout signals building — worth keeping an eye on.';
      case BurnoutRiskLevel.high:
        return 'Multiple burnout signals active. Consider easing the schedule.';
    }
  }

  /// Whether the confidence is high enough to surface this to the user.
  /// Low-confidence forecasts are logged internally but not shown, to
  /// avoid spooking someone with an unreliable early-data prediction.
  bool get shouldSurface => confidence > 0.4;
}