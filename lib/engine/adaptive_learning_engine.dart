import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/behavior_profile.dart';

/// The level of concern the anomaly detector assigns to a deviation.
/// Deliberately coarse — three levels is enough to drive meaningful
/// action differences without false precision.
enum AnomalyLevel {
  normal,   // within expected range, no action
  mild,     // slightly unusual, soft check-in
  strong,   // clearly abnormal for this person, escalate
}

/// Result of an anomaly check — carries the level plus the plain-language
/// reason the Reasoning Trace Engine can surface to the user if asked
/// "why did this happen?"
class AnomalyResult {
  final AnomalyLevel level;
  final String reason;
  final double? zScore;
  final bool usedFallback; // true if profile wasn't reliable yet

  const AnomalyResult({
    required this.level,
    required this.reason,
    this.zScore,
    this.usedFallback = false,
  });
}

/// Which intervention style to try next — the adaptive selector learns
/// which of these actually gets a response from you, and shifts toward
/// those over time.
enum InterventionStyle {
  gentleVoice,    // soft spoken reminder, quiet music
  energeticVoice, // louder, more urgent spoken prompt
  verificationChallenge, // ask a simple question to confirm alertness
  silentVibration, // no audio, just haptic
}

/// The Phase 2 adaptive learning engine. Everything in Phase 1 used
/// fixed thresholds ("escalate after 10 minutes"). This replaces those
/// fixed numbers with learned, per-person, per-context baselines so
/// the system reacts to what's genuinely unusual *for you*, not to a
/// generic rule.
class AdaptiveLearningEngine {
  AdaptiveLearningEngine._internal();
  static final AdaptiveLearningEngine instance =
      AdaptiveLearningEngine._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  // In-memory cache of profiles loaded this session — avoids repeated
  // DB reads for the same profile during a single day's operation.
  final Map<String, BehaviorProfile> _cache = {};

  // Simple intervention success log — keyed by style, value is
  // [successes, total_attempts]. Powers the bandit-style selector.
  final Map<InterventionStyle, List<int>> _interventionStats = {
    for (final s in InterventionStyle.values) s: [0, 0],
  };

  // ----------------------------------------------------------------
  // Profile management
  // ----------------------------------------------------------------

  String _profileKey(String taskCategory, String contextKey) =>
      '${taskCategory}__$contextKey';

  Future<BehaviorProfile> _getOrCreateProfile(
      String taskCategory, String contextKey) async {
    final key = _profileKey(taskCategory, contextKey);
    if (_cache.containsKey(key)) return _cache[key]!;

    final fromDb = await _db.getBehaviorProfile(taskCategory, contextKey);
    if (fromDb != null) {
      _cache[key] = fromDb;
      return fromDb;
    }

    final fresh = BehaviorProfile(
      id: const Uuid().v4(),
      taskCategory: taskCategory,
      contextKey: contextKey,
      lastUpdated: DateTime.now(),
    );
    _cache[key] = fresh;
    return fresh;
  }

  /// Call this every time a task actually completes with known timing.
  /// This is the single update point that makes the whole system learn —
  /// every completed task feeds the profile that future anomaly checks
  /// will read from.
  Future<void> recordTaskCompletion({
    required String taskCategory,
    required double actualDurationMinutes,
    double? responseLatencySeconds,
    String contextKey = 'any',
  }) async {
    final profile = await _getOrCreateProfile(taskCategory, contextKey);
    profile.update(
      actualDurationMinutes: actualDurationMinutes,
      responseLatencySeconds: responseLatencySeconds,
    );
    await _db.upsertBehaviorProfile(profile);
  }

  // ----------------------------------------------------------------
  // Anomaly detection
  // ----------------------------------------------------------------

  /// Checks whether an elapsed time is genuinely abnormal for this
  /// person/task-type combination, returning a level and a plain-
  /// language reason the Reasoning Trace Engine can surface.
  Future<AnomalyResult> checkDurationAnomaly({
    required String taskCategory,
    required double elapsedMinutes,
    String contextKey = 'any',
  }) async {
    final profile = await _getOrCreateProfile(taskCategory, contextKey);

    if (!profile.isReliable) {
      // Not enough data yet — use conservative fixed fallback thresholds
      // rather than making predictions from 1-2 data points.
      return _fallbackCheck(elapsedMinutes, taskCategory);
    }

    final z = profile.zScore(elapsedMinutes);
    if (z == null) {
      return const AnomalyResult(
        level: AnomalyLevel.normal,
        reason: 'Variance not yet established — no anomaly flagged.',
      );
    }

    if (z < 1.5) {
      return AnomalyResult(
        level: AnomalyLevel.normal,
        reason:
            'Within your normal range for $taskCategory (z=${ z.toStringAsFixed(1)}).',
        zScore: z,
      );
    } else if (z < 2.5) {
      return AnomalyResult(
        level: AnomalyLevel.mild,
        reason:
            'Slightly longer than your usual $taskCategory '
            '(~${elapsedMinutes.toStringAsFixed(0)} min vs your '
            'typical ~${profile.meanDurationMinutes.toStringAsFixed(0)} min).',
        zScore: z,
      );
    } else {
      return AnomalyResult(
        level: AnomalyLevel.strong,
        reason:
            'Well outside your normal range for $taskCategory — '
            '${elapsedMinutes.toStringAsFixed(0)} min vs your typical '
            '${profile.meanDurationMinutes.toStringAsFixed(0)} ± '
            '${profile.varianceDurationMinutes.toStringAsFixed(0)} min.',
        zScore: z,
      );
    }
  }

  /// Response-latency anomaly — checks if you're taking unusually long
  /// to respond to a reminder, which can indicate you're not hearing it.
  Future<AnomalyResult> checkResponseAnomaly({
    required String taskCategory,
    required double elapsedSecondsSinceReminder,
    String contextKey = 'any',
  }) async {
    final profile = await _getOrCreateProfile(taskCategory, contextKey);
    final mean = profile.meanResponseLatencySeconds;

    // Simpler check than duration — just compare directly to the
    // learned mean, since response latency has high natural variance.
    final ratio = elapsedSecondsSinceReminder / mean.clamp(10, double.infinity);

    if (ratio < 2.0) {
      return AnomalyResult(
        level: AnomalyLevel.normal,
        reason: 'Response time within expected range.',
      );
    } else if (ratio < 4.0) {
      return AnomalyResult(
        level: AnomalyLevel.mild,
        reason:
            'Slower to respond than usual — you typically respond to '
            '$taskCategory reminders within ${mean.toStringAsFixed(0)}s.',
      );
    } else {
      return AnomalyResult(
        level: AnomalyLevel.strong,
        reason:
            'No response for ${elapsedSecondsSinceReminder.toStringAsFixed(0)}s — '
            'your usual response time is ~${mean.toStringAsFixed(0)}s.',
      );
    }
  }

  AnomalyResult _fallbackCheck(double elapsedMinutes, String taskCategory) {
    // Conservative static fallbacks used before enough data exists.
    // These are generous ranges so the system doesn't over-alert on
    // cold start with only 1-2 observations.
    if (elapsedMinutes < 60) {
      return AnomalyResult(
        level: AnomalyLevel.normal,
        reason: 'Still building your baseline for $taskCategory.',
        usedFallback: true,
      );
    } else if (elapsedMinutes < 90) {
      return AnomalyResult(
        level: AnomalyLevel.mild,
        reason: 'Running long — still learning your typical pace for $taskCategory.',
        usedFallback: true,
      );
    } else {
      return AnomalyResult(
        level: AnomalyLevel.strong,
        reason: 'Significantly over time — this will improve as your '
            'baseline for $taskCategory develops.',
        usedFallback: true,
      );
    }
  }

  // ----------------------------------------------------------------
  // Adaptive intervention selector (bandit-style)
  // ----------------------------------------------------------------

  /// Selects which intervention style to try next based on what has
  /// actually worked for you before. Uses an epsilon-greedy approach:
  /// 80% of the time, picks the style with the highest observed
  /// success rate; 20% of the time, explores a less-used option so
  /// it doesn't get permanently stuck on something that's locally
  /// good but not optimal.
  InterventionStyle selectIntervention({double epsilon = 0.2}) {
    // Exploration: try a random style occasionally.
    if (_interventionStats.values.every((s) => s[1] == 0) ||
        (DateTime.now().millisecondsSinceEpoch % 10) < (epsilon * 10)) {
      final styles = InterventionStyle.values;
      return styles[DateTime.now().millisecondsSinceEpoch % styles.length];
    }

    // Exploitation: pick the style with the highest success rate.
    InterventionStyle best = InterventionStyle.gentleVoice;
    double bestRate = -1;

    for (final entry in _interventionStats.entries) {
      final attempts = entry.value[1];
      if (attempts == 0) continue;
      final rate = entry.value[0] / attempts;
      if (rate > bestRate) {
        bestRate = rate;
        best = entry.key;
      }
    }
    return best;
  }

  /// Record whether an intervention actually led to a timely response.
  /// This is what drives the bandit selector's learning.
  void recordInterventionOutcome(InterventionStyle style, {required bool success}) {
    final stats = _interventionStats[style]!;
    if (success) stats[0]++;
    stats[1]++;
  }

  // ----------------------------------------------------------------
  // Convenience summary for the Reasoning Trace Engine
  // ----------------------------------------------------------------

  Future<Map<String, dynamic>> getProfileSummary(
      String taskCategory, String contextKey) async {
    final profile = await _getOrCreateProfile(taskCategory, contextKey);
    return {
      'taskCategory': taskCategory,
      'contextKey': contextKey,
      'meanDurationMinutes': profile.meanDurationMinutes,
      'varianceDurationMinutes': profile.varianceDurationMinutes,
      'sampleCount': profile.sampleCount,
      'isReliable': profile.isReliable,
      'meanResponseLatencySeconds': profile.meanResponseLatencySeconds,
    };
  }
}