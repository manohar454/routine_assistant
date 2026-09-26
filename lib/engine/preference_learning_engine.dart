import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/preference_learning_models.dart';

/// The preference learning engine. Watches every conflict resolution
/// (when two things compete and you choose one over the other) and
/// updates learned importance weights so the system increasingly
/// anticipates what you'll protect — without you ever manually
/// configuring priorities.
///
/// Uses a simple online update rule: when you keep task A over task B,
/// A's weight nudges up toward 1.0 and B's nudges down toward 0.0.
/// The learning rate (alpha) is small enough that a single unusual
/// choice doesn't throw off the whole model — it takes a consistent
/// pattern over several conflicts to meaningfully shift a weight.
class PreferenceLearningEngine {
  PreferenceLearningEngine._internal();
  static final PreferenceLearningEngine instance =
      PreferenceLearningEngine._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  // In-memory weight cache for the current session.
  final Map<String, TaskImportanceWeight> _weights = {};

  static const double _alpha = 0.15; // learning rate — conservative

  // ----------------------------------------------------------------
  // Observing voluntary task creation
  // ----------------------------------------------------------------

  /// Call when the user explicitly creates a task. Treats this as a
  /// weak positive signal for that category — the user chose to schedule
  /// it, so it's something they care about. The nudge is smaller than
  /// a conflict resolution (0.05 vs 0.15) to avoid over-weighting.
  Future<void> observeTaskCreated(String taskCategory) async {
    const creationNudge = 0.05;
    final weight = await _getOrCreateWeight(taskCategory);
    weight.weight += creationNudge * (1.0 - weight.weight);
    weight.sampleCount++;
    weight.lastUpdated = DateTime.now();
    await _db.upsertTaskImportanceWeight(weight);
    _weights[taskCategory] = weight;
  }

  // ----------------------------------------------------------------
  // Recording conflict outcomes
  // ----------------------------------------------------------------

  /// Call this every time a real conflict is resolved — one task was
  /// protected and another was rescheduled/dropped to make room.
  /// This is the single training-data collection point.
  Future<void> recordConflict({
    required String keptTaskCategory,
    required String droppedTaskCategory,
    String? reason,
  }) async {
    final outcome = ConflictOutcome(
      id: const Uuid().v4(),
      keptTaskCategory: keptTaskCategory,
      droppedTaskCategory: droppedTaskCategory,
      timestamp: DateTime.now(),
      reason: reason,
    );
    await _db.insertConflictOutcome(outcome);
    await _updateWeights(keptTaskCategory, droppedTaskCategory);
  }

  Future<void> _updateWeights(
      String keptCategory, String droppedCategory) async {
    final keptWeight = await _getOrCreateWeight(keptCategory);
    final droppedWeight = await _getOrCreateWeight(droppedCategory);

    // Kept task: nudge weight toward 1.0 (you protected it).
    keptWeight.weight += _alpha * (1.0 - keptWeight.weight);
    keptWeight.sampleCount++;
    keptWeight.lastUpdated = DateTime.now();

    // Dropped task: nudge weight toward 0.0 (you let it slide).
    droppedWeight.weight -= _alpha * droppedWeight.weight;
    droppedWeight.sampleCount++;
    droppedWeight.lastUpdated = DateTime.now();

    await _db.upsertTaskImportanceWeight(keptWeight);
    await _db.upsertTaskImportanceWeight(droppedWeight);

    _weights[keptCategory] = keptWeight;
    _weights[droppedCategory] = droppedWeight;
  }

  // ----------------------------------------------------------------
  // Reading learned importance
  // ----------------------------------------------------------------

  /// Returns the learned importance weight for a task category.
  /// Returns 0.5 (neutral) if not enough data exists yet.
  Future<double> getImportance(String taskCategory) async {
    final weight = await _getOrCreateWeight(taskCategory);
    if (!weight.isReliable) return 0.5;
    return weight.weight;
  }

  /// Compares two task categories and returns which one the system
  /// has learned you prioritize more — used by the Decision Layer
  /// when a conflict needs to be resolved.
  Future<String> higherPriority(String categoryA, String categoryB) async {
    final weightA = await getImportance(categoryA);
    final weightB = await getImportance(categoryB);

    // If neither is reliable yet, fall back to alphabetical (arbitrary
    // but deterministic — never crashes, never silently picks wrong).
    return weightA >= weightB ? categoryA : categoryB;
  }

  /// Returns a plain-language explanation of why one task was considered
  /// more important — feeds directly into the Reasoning Trace Engine.
  Future<String> explainPriority(
      String keptCategory, String droppedCategory) async {
    final keptWeight = await _getOrCreateWeight(keptCategory);
    final droppedWeight = await _getOrCreateWeight(droppedCategory);

    if (!keptWeight.isReliable || !droppedWeight.isReliable) {
      return 'Still learning your priorities — not enough conflict '
          'history yet to explain this automatically.';
    }

    final keptPct = (keptWeight.weight * 100).toStringAsFixed(0);
    final droppedPct = (droppedWeight.weight * 100).toStringAsFixed(0);

    return 'Based on ${keptWeight.sampleCount} past conflicts, you\'ve '
        'typically protected $keptCategory ($keptPct% importance) '
        'over $droppedCategory ($droppedPct% importance).';
  }

  // ----------------------------------------------------------------
  // Lead-time and voice-disable preferences
  // ----------------------------------------------------------------

  static const _kLeadTimePrefix = 'pref_lead_time_';
  static const _kVoiceDisabledPrefix = 'pref_voice_disabled_';

  /// Returns how many minutes before task start the notification should
  /// fire for this category. Returns 0 (at task start) if not set.
  Future<int> getLeadTimeMinutes(String taskCategory) async {
    final raw = await _db.getSetting('$_kLeadTimePrefix$taskCategory');
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// Saves a per-category notification lead-time preference.
  Future<void> setLeadTimeMinutes(
      String taskCategory, int minutes) async {
    await _db.setSetting(
        '$_kLeadTimePrefix$taskCategory', minutes.toString());
  }

  /// Returns true if voice reminders should be suppressed for this category.
  Future<bool> isVoiceDisabled(String taskCategory) async {
    final raw = await _db.getSetting('$_kVoiceDisabledPrefix$taskCategory');
    return raw == '1';
  }

  /// Saves a per-category voice-disable preference.
  Future<void> setVoiceDisabled(
      String taskCategory, {required bool disabled}) async {
    await _db.setSetting(
        '$_kVoiceDisabledPrefix$taskCategory', disabled ? '1' : '0');
  }

  // ----------------------------------------------------------------
  // Summary for diagnostics / Reasoning Trace
  // ----------------------------------------------------------------

  /// Returns all learned weights sorted by importance descending.
  /// Useful for a "what the system thinks you prioritize" debug view.
  Future<List<TaskImportanceWeight>> getAllWeightsSorted() async {
    final weights = await _db.getAllTaskImportanceWeights();
    weights.sort((a, b) => b.weight.compareTo(a.weight));
    return weights;
  }

  Future<TaskImportanceWeight> _getOrCreateWeight(
      String taskCategory) async {
    if (_weights.containsKey(taskCategory)) return _weights[taskCategory]!;

    final fromDb = await _db.getTaskImportanceWeight(taskCategory);
    if (fromDb != null) {
      _weights[taskCategory] = fromDb;
      return fromDb;
    }

    final fresh = TaskImportanceWeight(
      taskCategory: taskCategory,
      lastUpdated: DateTime.now(),
    );
    _weights[taskCategory] = fresh;
    return fresh;
  }
}