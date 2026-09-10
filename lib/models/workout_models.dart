/// Workout module models — redesigned around a DYNAMIC session structure.
///
/// Instead of hardcoding "sets of one exercise, then next exercise," each
/// WorkoutTemplate declares its own session shape (sequential vs circuit)
/// and its own rest timings. The engine reads this and adapts — adding a
/// new workout style later means adding a new template, not new code.
library;

enum SessionType { sequential, circuit }

class Exercise {
  final String id;
  String name;
  String equipment;
  int targetSets;

  /// Free-text target instead of a rigid int — real plans mix rep counts
  /// ("10"), open-ended targets ("Max"), and duration-based targets
  /// ("45 sec"). Logging captures whatever the person actually did as a
  /// matching free-text value, so this never has to special-case format.
  String repsTarget;

  String? progressionNote;

  /// True only for the built-in reference exercises created by
  /// WorkoutPlanSeeder. The "add exercise" picker only suggests exercises
  /// the person actually created themselves — this flag is what makes
  /// that distinction possible.
  bool isSeeded;

  Exercise({
    required this.id,
    required this.name,
    required this.equipment,
    required this.targetSets,
    required this.repsTarget,
    this.progressionNote,
    this.isSeeded = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'equipment': equipment,
        'targetSets': targetSets,
        'repsTarget': repsTarget,
        'progressionNote': progressionNote,
        'isSeeded': isSeeded ? 1 : 0,
      };

  factory Exercise.fromMap(Map<String, dynamic> map) => Exercise(
        id: map['id'] as String,
        name: map['name'] as String,
        equipment: map['equipment'] as String,
        targetSets: map['targetSets'] as int,
        repsTarget: map['repsTarget'] as String,
        progressionNote: map['progressionNote'] as String?,
        isSeeded: (map['isSeeded'] as int? ?? 0) == 1,
      );
}

/// Groups related templates together (e.g. "Gym Plan", "Home Plan",
/// "Transformation Plan") so the person can select which plan is active,
/// per the "all of them, selectable" decision.
class WorkoutPlan {
  final String id;
  String name;
  String? referenceNotes; // e.g. original time-window text, informational only

  WorkoutPlan({required this.id, required this.name, this.referenceNotes});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'referenceNotes': referenceNotes,
      };

  factory WorkoutPlan.fromMap(Map<String, dynamic> map) => WorkoutPlan(
        id: map['id'] as String,
        name: map['name'] as String,
        referenceNotes: map['referenceNotes'] as String?,
      );
}

class WorkoutTemplate {
  final String id;
  final String planId;
  String name; // e.g. "Monday — Chest + Cardio"
  int dayOfWeek; // 1 = Monday ... 7 = Sunday
  List<String> warmupExerciseIds; // optional, run before the main block
  List<String> exerciseIds; // ordered, the main block

  SessionType sessionType;

  // Sequential timings (ignored if sessionType == circuit)
  int restBetweenSetsSeconds;
  int restBetweenExercisesSeconds;

  // Circuit timings (ignored if sessionType == sequential)
  int circuitRounds;
  int restBetweenExercisesInRoundSeconds; // typically 0
  int restAfterRoundSeconds;

  bool isRestDay; // e.g. Transformation plan's Sunday — no exercises at all

  /// Per-day overrides, keyed by exerciseId. An exercise's default
  /// targetSets/repsTarget live on the shared Exercise record (so history
  /// stays continuous across every day it appears on) — but a specific
  /// day can override just its own sets/reps without touching that shared
  /// record, so editing "Arm Circles" for Monday never silently changes
  /// it in the Home plan's warm-up too.
  Map<String, int> setsOverrides;
  Map<String, String> repsOverrides;

  WorkoutTemplate({
    required this.id,
    required this.planId,
    required this.name,
    required this.dayOfWeek,
    this.warmupExerciseIds = const [],
    this.exerciseIds = const [],
    this.sessionType = SessionType.sequential,
    this.restBetweenSetsSeconds = 60,
    this.restBetweenExercisesSeconds = 90,
    this.circuitRounds = 1,
    this.restBetweenExercisesInRoundSeconds = 0,
    this.restAfterRoundSeconds = 60,
    this.isRestDay = false,
    Map<String, int>? setsOverrides,
    Map<String, String>? repsOverrides,
  })  : setsOverrides = setsOverrides ?? {},
        repsOverrides = repsOverrides ?? {};

  int effectiveSets(Exercise exercise) => setsOverrides[exercise.id] ?? exercise.targetSets;
  String effectiveReps(Exercise exercise) => repsOverrides[exercise.id] ?? exercise.repsTarget;
  bool hasOverride(String exerciseId) =>
      setsOverrides.containsKey(exerciseId) || repsOverrides.containsKey(exerciseId);

  static String _encodeMap(Map<String, String> map) =>
      map.entries.map((e) => '${e.key}::${e.value}').join('||');

  static Map<String, String> _decodeMap(String raw) {
    if (raw.isEmpty) return {};
    return Map.fromEntries(raw.split('||').map((pair) {
      final parts = pair.split('::');
      return MapEntry(parts[0], parts.sublist(1).join('::'));
    }));
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'planId': planId,
        'name': name,
        'dayOfWeek': dayOfWeek,
        'warmupExerciseIds': warmupExerciseIds.join(','),
        'exerciseIds': exerciseIds.join(','),
        'sessionType': sessionType.name,
        'restBetweenSetsSeconds': restBetweenSetsSeconds,
        'restBetweenExercisesSeconds': restBetweenExercisesSeconds,
        'circuitRounds': circuitRounds,
        'restBetweenExercisesInRoundSeconds':
            restBetweenExercisesInRoundSeconds,
        'restAfterRoundSeconds': restAfterRoundSeconds,
        'isRestDay': isRestDay ? 1 : 0,
        'setsOverrides':
            _encodeMap(setsOverrides.map((k, v) => MapEntry(k, '$v'))),
        'repsOverrides': _encodeMap(repsOverrides),
      };

  factory WorkoutTemplate.fromMap(Map<String, dynamic> map) => WorkoutTemplate(
        id: map['id'] as String,
        planId: map['planId'] as String,
        name: map['name'] as String,
        dayOfWeek: map['dayOfWeek'] as int,
        warmupExerciseIds: (map['warmupExerciseIds'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
        exerciseIds: (map['exerciseIds'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
        sessionType:
            SessionType.values.firstWhere((s) => s.name == map['sessionType']),
        restBetweenSetsSeconds: map['restBetweenSetsSeconds'] as int,
        restBetweenExercisesSeconds: map['restBetweenExercisesSeconds'] as int,
        circuitRounds: map['circuitRounds'] as int,
        restBetweenExercisesInRoundSeconds:
            map['restBetweenExercisesInRoundSeconds'] as int,
        restAfterRoundSeconds: map['restAfterRoundSeconds'] as int,
        setsOverrides: _decodeMap(map['setsOverrides'] as String? ?? '')
            .map((k, v) => MapEntry(k, int.tryParse(v) ?? 0)),
        repsOverrides: _decodeMap(map['repsOverrides'] as String? ?? ''),
        isRestDay: (map['isRestDay'] as int) == 1,
      );
}

enum SessionStatus { inProgress, completed }

class WorkoutSession {
  final String id;
  final String templateId;
  final DateTime date;
  DateTime startTime;
  DateTime? endTime;
  SessionStatus status;

  WorkoutSession({
    required this.id,
    required this.templateId,
    required this.date,
    required this.startTime,
    this.endTime,
    this.status = SessionStatus.inProgress,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'templateId': templateId,
        'date': date.toIso8601String(),
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'status': status.name,
      };

  factory WorkoutSession.fromMap(Map<String, dynamic> map) => WorkoutSession(
        id: map['id'] as String,
        templateId: map['templateId'] as String,
        date: DateTime.parse(map['date'] as String),
        startTime: DateTime.parse(map['startTime'] as String),
        endTime: map['endTime'] != null
            ? DateTime.parse(map['endTime'] as String)
            : null,
        status:
            SessionStatus.values.firstWhere((s) => s.name == map['status']),
      );
}

/// One logged set. [performedValue] mirrors the exercise's free-text
/// repsTarget shape — "10" for a rep count, "Max" reps performed written
/// as e.g. "22", or "45 sec" for a duration hold — logging stays as
/// flexible as the plans themselves rather than forcing a single format.
class ExerciseLog {
  final String id;
  final String sessionId;
  final String exerciseId;
  final int setNumber; // for circuits, this is the ROUND number
  final String performedValue;
  final double weight; // 0 for bodyweight/band exercises
  final int? rpe;
  final DateTime timestamp;

  ExerciseLog({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.setNumber,
    required this.performedValue,
    required this.weight,
    this.rpe,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'exerciseId': exerciseId,
        'setNumber': setNumber,
        'performedValue': performedValue,
        'weight': weight,
        'rpe': rpe,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ExerciseLog.fromMap(Map<String, dynamic> map) => ExerciseLog(
        id: map['id'] as String,
        sessionId: map['sessionId'] as String,
        exerciseId: map['exerciseId'] as String,
        setNumber: map['setNumber'] as int,
        performedValue: map['performedValue'] as String,
        weight: (map['weight'] as num).toDouble(),
        rpe: map['rpe'] as int?,
        timestamp: DateTime.parse(map['timestamp'] as String),
      );
}
