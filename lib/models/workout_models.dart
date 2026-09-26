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
  String repsTarget;
  String? progressionNote;
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
        targetSets: (map['targetSets'] as num?)?.toInt() ?? 0,
        repsTarget: map['repsTarget'] as String? ?? '',
        progressionNote: map['progressionNote'] as String?,
        isSeeded: (map['isSeeded'] as num?)?.toInt() == 1,
      );
}

class WorkoutPlan {
  final String id;
  String name;
  String? referenceNotes;

  WorkoutPlan({
    required this.id,
    required this.name,
    this.referenceNotes,
  });

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
  String name;
  int dayOfWeek;
  List<String> warmupExerciseIds;
  List<String> exerciseIds;

  SessionType sessionType;

  int restBetweenSetsSeconds;
  int restBetweenExercisesSeconds;

  int circuitRounds;
  int restBetweenExercisesInRoundSeconds;
  int restAfterRoundSeconds;

  bool isRestDay;

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

  int effectiveSets(Exercise exercise) =>
      setsOverrides[exercise.id] ?? exercise.targetSets;

  String effectiveReps(Exercise exercise) =>
      repsOverrides[exercise.id] ?? exercise.repsTarget;

  bool hasOverride(String exerciseId) =>
      setsOverrides.containsKey(exerciseId) ||
      repsOverrides.containsKey(exerciseId);

  static String _encodeMap(Map<String, String> map) =>
      map.entries.map((e) => '${e.key}::${e.value}').join('||');

  static Map<String, String> _decodeMap(String raw) {
    if (raw.isEmpty) return {};

    return Map.fromEntries(
      raw
          .split('||')
          .where((pair) => pair.isNotEmpty)
          .map((pair) {
        final parts = pair.split('::');

        if (parts.length < 2) {
          return MapEntry(pair, '');
        }

        return MapEntry(
          parts[0],
          parts.sublist(1).join('::'),
        );
      }),
    );
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

  factory WorkoutTemplate.fromMap(Map<String, dynamic> map) =>
      WorkoutTemplate(
        id: map['id'] as String,
        planId: map['planId'] as String,
        name: map['name'] as String,
        dayOfWeek: (map['dayOfWeek'] as num?)?.toInt() ?? 1,
        warmupExerciseIds: (map['warmupExerciseIds'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
        exerciseIds: (map['exerciseIds'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),

        // Defensive fallback for old/invalid database values.
        sessionType: SessionType.values.firstWhere(
          (s) => s.name == map['sessionType'],
          orElse: () => SessionType.sequential,
        ),

        restBetweenSetsSeconds:
            (map['restBetweenSetsSeconds'] as num?)?.toInt() ?? 60,
        restBetweenExercisesSeconds:
            (map['restBetweenExercisesSeconds'] as num?)?.toInt() ?? 90,
        circuitRounds:
            (map['circuitRounds'] as num?)?.toInt() ?? 1,
        restBetweenExercisesInRoundSeconds:
            (map['restBetweenExercisesInRoundSeconds'] as num?)?.toInt() ?? 0,
        restAfterRoundSeconds:
            (map['restAfterRoundSeconds'] as num?)?.toInt() ?? 60,
        setsOverrides: _decodeMap(map['setsOverrides'] as String? ?? '')
            .map((k, v) => MapEntry(k, int.tryParse(v) ?? 0)),
        repsOverrides: _decodeMap(map['repsOverrides'] as String? ?? ''),
        isRestDay: (map['isRestDay'] as num?)?.toInt() == 1,
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

  factory WorkoutSession.fromMap(Map<String, dynamic> map) =>
      WorkoutSession(
        id: map['id'] as String,
        templateId: map['templateId'] as String,
        date: DateTime.parse(map['date'] as String),
        startTime: DateTime.parse(map['startTime'] as String),
        endTime: map['endTime'] != null
            ? DateTime.parse(map['endTime'] as String)
            : null,

        // Defensive fallback for old/invalid database values.
        status: SessionStatus.values.firstWhere(
          (s) => s.name == map['status'],
          orElse: () => SessionStatus.inProgress,
        ),
      );
}

class ExerciseLog {
  final String id;
  final String sessionId;
  final String exerciseId;
  final int setNumber;
  final String performedValue;
  final double weight;
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
        setNumber: (map['setNumber'] as num?)?.toInt() ?? 0,
        performedValue: map['performedValue'] as String? ?? '',
        weight: (map['weight'] as num?)?.toDouble() ?? 0.0,
        rpe: (map['rpe'] as num?)?.toInt(),
        timestamp: DateTime.parse(map['timestamp'] as String),
      );
}