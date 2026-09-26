import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../models/music_models.dart';
import '../models/workout_models.dart';
import '../models/water_models.dart';
import '../models/sleep_models.dart';
import '../models/meal_models.dart';
import '../models/behavior_profile.dart';
import '../models/preference_learning_models.dart';
import '../models/day_clustering_models.dart';
import '../models/goal_models.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'routine_assistant.db');
    return openDatabase(
      path,
      version: 12,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            plannedStart TEXT NOT NULL,
            estimatedDurationMinutes INTEGER NOT NULL,
            actualStart TEXT,
            actualEnd TEXT,
            status TEXT NOT NULL,
            flexibility TEXT NOT NULL,
            voiceMessage TEXT,
            moodTag TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE music_tracks (
            id TEXT PRIMARY KEY,
            filePath TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            moodTags TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE playlists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            moodTag TEXT NOT NULL,
            trackIds TEXT NOT NULL,
            shuffle INTEGER NOT NULL
          )
        ''');
        await _createWorkoutTables(db);
        await _createAppSettingsTables(db);
        await _createGoalTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE tasks ADD COLUMN moodTag TEXT');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS music_tracks (
              id TEXT PRIMARY KEY,
              filePath TEXT NOT NULL,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              moodTags TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS playlists (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              moodTag TEXT NOT NULL,
              trackIds TEXT NOT NULL,
              shuffle INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await _createWorkoutTables(db);
        }
        if (oldVersion < 4) {
          // Schema shape changed substantially (plans, dynamic session
          // config, free-text rep targets) — safe to drop and recreate
          // since this is still early development with no real user data
          // to preserve yet.
          await db.execute('DROP TABLE IF EXISTS exercises');
          await db.execute('DROP TABLE IF EXISTS workout_templates');
          await db.execute('DROP TABLE IF EXISTS workout_sessions');
          await db.execute('DROP TABLE IF EXISTS exercise_logs');
          await _createWorkoutTables(db);
        }
        if (oldVersion < 5) {
          await db.execute(
              'ALTER TABLE workout_templates ADD COLUMN setsOverrides TEXT NOT NULL DEFAULT \'\'');
          await db.execute(
              'ALTER TABLE workout_templates ADD COLUMN repsOverrides TEXT NOT NULL DEFAULT \'\'');
        }
        if (oldVersion < 6) {
          await db.execute(
              'ALTER TABLE exercises ADD COLUMN isSeeded INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS water_logs (
              id TEXT PRIMARY KEY,
              amountMl INTEGER NOT NULL,
              timestamp TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sleep_logs (
              id TEXT PRIMARY KEY,
              bedTime TEXT NOT NULL,
              wakeTime TEXT NOT NULL,
              quality INTEGER
            )
          ''');
        }
        if (oldVersion < 8) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS meal_logs (
              id TEXT PRIMARY KEY,
              mealType TEXT NOT NULL,
              description TEXT NOT NULL,
              timestamp TEXT NOT NULL,
              notes TEXT
            )
          ''');
        }
        if (oldVersion < 9) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS behavior_profiles (
              id TEXT PRIMARY KEY,
              taskCategory TEXT NOT NULL,
              contextKey TEXT NOT NULL,
              meanDurationMinutes REAL NOT NULL DEFAULT 0,
              varianceDurationMinutes REAL NOT NULL DEFAULT 0,
              sampleCount INTEGER NOT NULL DEFAULT 0,
              meanResponseLatencySeconds REAL NOT NULL DEFAULT 120,
              lastUpdated TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_key '
            'ON behavior_profiles (taskCategory, contextKey)'
          );
        }
        if (oldVersion < 10) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS conflict_outcomes (
              id TEXT PRIMARY KEY,
              keptTaskCategory TEXT NOT NULL,
              droppedTaskCategory TEXT NOT NULL,
              timestamp TEXT NOT NULL,
              reason TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS task_importance_weights (
              taskCategory TEXT PRIMARY KEY,
              weight REAL NOT NULL DEFAULT 0.5,
              sampleCount INTEGER NOT NULL DEFAULT 0,
              lastUpdated TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS day_vectors (
              id TEXT PRIMARY KEY,
              date TEXT NOT NULL UNIQUE,
              sleepRatio REAL NOT NULL,
              wakeLatencyNormalized REAL NOT NULL,
              calendarDensity REAL NOT NULL,
              yesterdayCompletionRate REAL NOT NULL,
              assignedCluster INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS day_clusters (
              clusterId INTEGER PRIMARY KEY,
              centroid TEXT NOT NULL,
              inferredLabel TEXT NOT NULL,
              memberCount INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }
        if (oldVersion < 11) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS burnout_forecasts (
              id TEXT PRIMARY KEY,
              riskScore REAL NOT NULL,
              confidence REAL NOT NULL,
              level TEXT NOT NULL,
              reason TEXT NOT NULL,
              computedAt TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 12) {
          await _createGoalTables(db);
        }
      },
    );
  }

  Future<void> _createWorkoutTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        referenceNotes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercises (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        equipment TEXT NOT NULL,
        targetSets INTEGER NOT NULL,
        repsTarget TEXT NOT NULL,
        progressionNote TEXT,
        isSeeded INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_templates (
        id TEXT PRIMARY KEY,
        planId TEXT NOT NULL,
        name TEXT NOT NULL,
        dayOfWeek INTEGER NOT NULL,
        warmupExerciseIds TEXT NOT NULL,
        exerciseIds TEXT NOT NULL,
        sessionType TEXT NOT NULL,
        restBetweenSetsSeconds INTEGER NOT NULL,
        restBetweenExercisesSeconds INTEGER NOT NULL,
        circuitRounds INTEGER NOT NULL,
        restBetweenExercisesInRoundSeconds INTEGER NOT NULL,
        restAfterRoundSeconds INTEGER NOT NULL,
        isRestDay INTEGER NOT NULL,
        setsOverrides TEXT NOT NULL DEFAULT '',
        repsOverrides TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_sessions (
        id TEXT PRIMARY KEY,
        templateId TEXT NOT NULL,
        date TEXT NOT NULL,
        startTime TEXT NOT NULL,
        endTime TEXT,
        status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercise_logs (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        exerciseId TEXT NOT NULL,
        setNumber INTEGER NOT NULL,
        performedValue TEXT NOT NULL,
        weight REAL NOT NULL,
        rpe INTEGER,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createGoalTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS goal_plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        domain TEXT NOT NULL,
        status TEXT NOT NULL,
        outcomeDescription TEXT NOT NULL,
        targetValue REAL NOT NULL,
        unit TEXT NOT NULL,
        baselineValue REAL NOT NULL,
        startDate TEXT NOT NULL,
        targetDate TEXT NOT NULL,
        linkedExerciseId TEXT,
        linkedCategory TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS weekly_milestones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        goalPlanId TEXT NOT NULL,
        weekNumber INTEGER NOT NULL,
        description TEXT NOT NULL,
        targetValue REAL NOT NULL,
        unit TEXT NOT NULL,
        isCheckpoint INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (goalPlanId) REFERENCES goal_plans(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_milestones_plan '
        'ON weekly_milestones (goalPlanId)');
  }

  Future<void> _createAppSettingsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS water_logs (
        id TEXT PRIMARY KEY,
        amountMl INTEGER NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sleep_logs (
        id TEXT PRIMARY KEY,
        bedTime TEXT NOT NULL,
        wakeTime TEXT NOT NULL,
        quality INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_logs (
        id TEXT PRIMARY KEY,
        mealType TEXT NOT NULL,
        description TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS behavior_profiles (
        id TEXT PRIMARY KEY,
        taskCategory TEXT NOT NULL,
        contextKey TEXT NOT NULL,
        meanDurationMinutes REAL NOT NULL DEFAULT 0,
        varianceDurationMinutes REAL NOT NULL DEFAULT 0,
        sampleCount INTEGER NOT NULL DEFAULT 0,
        meanResponseLatencySeconds REAL NOT NULL DEFAULT 120,
        lastUpdated TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_key '
      'ON behavior_profiles (taskCategory, contextKey)'
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS conflict_outcomes (
        id TEXT PRIMARY KEY,
        keptTaskCategory TEXT NOT NULL,
        droppedTaskCategory TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        reason TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_importance_weights (
        taskCategory TEXT PRIMARY KEY,
        weight REAL NOT NULL DEFAULT 0.5,
        sampleCount INTEGER NOT NULL DEFAULT 0,
        lastUpdated TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS day_vectors (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL UNIQUE,
        sleepRatio REAL NOT NULL,
        wakeLatencyNormalized REAL NOT NULL,
        calendarDensity REAL NOT NULL,
        yesterdayCompletionRate REAL NOT NULL,
        assignedCluster INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS day_clusters (
        clusterId INTEGER PRIMARY KEY,
        centroid TEXT NOT NULL,
        inferredLabel TEXT NOT NULL,
        memberCount INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS burnout_forecasts (
        id TEXT PRIMARY KEY,
        riskScore REAL NOT NULL,
        confidence REAL NOT NULL,
        level TEXT NOT NULL,
        reason TEXT NOT NULL,
        computedAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> insertTask(Task task) async {
    final db = await database;
    await db.insert('tasks', task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateTask(Task task) async {
    final db = await database;
    await db.update('tasks', task.toMap(),
        where: 'id = ?', whereArgs: [task.id]);
  }

  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Task>> getTasksForDay(DateTime day) async {
    final db = await database;
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'tasks',
      where: 'plannedStart >= ? AND plannedStart < ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'plannedStart ASC',
    );

    return maps.map((m) => Task.fromMap(m)).toList();
  }

  Future<Task?> getTaskById(String id) async {
    final db = await database;
    final maps = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Task.fromMap(maps.first);
  }

  Future<void> insertTrack(MusicTrack track) async {
    final db = await database;
    await db.insert('music_tracks', track.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MusicTrack>> getAllTracks() async {
    final db = await database;
    final maps = await db.query('music_tracks');
    return maps.map((m) => MusicTrack.fromMap(m)).toList();
  }

  Future<void> insertPlaylist(Playlist playlist) async {
    final db = await database;
    await db.insert('playlists', playlist.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Playlist?> getPlaylistForMood(String moodTag) async {
    final db = await database;
    final maps = await db
        .query('playlists', where: 'moodTag = ?', whereArgs: [moodTag]);
    if (maps.isEmpty) return null;
    return Playlist.fromMap(maps.first);
  }

  Future<List<MusicTrack>> getTracksForIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final maps = await db.query('music_tracks',
        where: 'id IN ($placeholders)', whereArgs: ids);
    return maps.map((m) => MusicTrack.fromMap(m)).toList();
  }

  // ---------------- Workout module ----------------

  Future<void> insertWorkoutPlan(WorkoutPlan plan) async {
    final db = await database;
    await db.insert('workout_plans', plan.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<WorkoutPlan>> getAllWorkoutPlans() async {
    final db = await database;
    final maps = await db.query('workout_plans');
    return maps.map((m) => WorkoutPlan.fromMap(m)).toList();
  }

  Future<List<WorkoutTemplate>> getTemplatesForPlan(String planId) async {
    final db = await database;
    final maps = await db.query('workout_templates',
        where: 'planId = ?', whereArgs: [planId], orderBy: 'dayOfWeek ASC');
    return maps.map((m) => WorkoutTemplate.fromMap(m)).toList();
  }

  Future<void> deleteWorkoutTemplate(String id) async {
    final db = await database;
    await db.delete('workout_templates', where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes a plan and everything under it — templates are meaningless
  /// without their parent plan, so this cascades rather than leaving
  /// orphaned rows behind.
  Future<void> deleteWorkoutPlan(String planId) async {
    final db = await database;
    await db.delete('workout_templates', where: 'planId = ?', whereArgs: [planId]);
    await db.delete('workout_plans', where: 'id = ?', whereArgs: [planId]);
  }

  Future<List<Exercise>> getAllExercises() async {
    final db = await database;
    final maps = await db.query('exercises', orderBy: 'name ASC');
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  /// Only exercises the person actually created themselves — the "add
  /// exercise" picker uses this instead of getAllExercises() so it never
  /// suggests the built-in Gym/Home/Transformation reference library.
  Future<List<Exercise>> getUserCreatedExercises() async {
    final db = await database;
    final maps = await db.query('exercises',
        where: 'isSeeded = ?', whereArgs: [0], orderBy: 'name ASC');
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  Future<void> insertExercise(Exercise exercise) async {
    final db = await database;
    await db.insert('exercises', exercise.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Exercise>> getExercisesForIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final maps = await db.query('exercises',
        where: 'id IN ($placeholders)', whereArgs: ids);
    final all = maps.map((m) => Exercise.fromMap(m)).toList();
    // Preserve the template's exercise ORDER, not the DB's arbitrary order.
    return ids
        .map((id) {
  final matches = all.where((e) => e.id == id);
  return matches.isNotEmpty ? matches.first : null;
})
.whereType<Exercise>()
        .toList();
  }

  Future<void> insertWorkoutTemplate(WorkoutTemplate template) async {
    final db = await database;
    await db.insert('workout_templates', template.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async {
    final db = await database;
    final maps = await db
        .query('workout_templates', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return WorkoutTemplate.fromMap(maps.first);
  }

  Future<void> insertSession(WorkoutSession session) async {
    final db = await database;
    await db.insert('workout_sessions', session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSession(WorkoutSession session) async {
    final db = await database;
    await db.update('workout_sessions', session.toMap(),
        where: 'id = ?', whereArgs: [session.id]);
  }

  /// Finds an in-progress session for a template today, if the user quit
  /// mid-session and reopened the app — this is what powers draft
  /// save/resume rather than losing progress.
  Future<WorkoutSession?> getInProgressSession(
      String templateId, DateTime day) async {
    final db = await database;
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final maps = await db.query(
      'workout_sessions',
      where: 'templateId = ? AND date >= ? AND date < ? AND status = ?',
      whereArgs: [
        templateId,
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
        SessionStatus.inProgress.name,
      ],
    );
    if (maps.isEmpty) return null;
    return WorkoutSession.fromMap(maps.first);
  }

  Future<void> insertExerciseLog(ExerciseLog log) async {
    final db = await database;
    await db.insert('exercise_logs', log.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ExerciseLog>> getLogsForSession(String sessionId) async {
    final db = await database;
    final maps = await db.query('exercise_logs',
        where: 'sessionId = ?',
        whereArgs: [sessionId],
        orderBy: 'setNumber ASC');
    return maps.map((m) => ExerciseLog.fromMap(m)).toList();
  }

  /// The query that makes progressive-overload tracking possible: finds the
  /// most recent COMPLETED session (before today) that included this
  /// exercise, and returns its logged sets — this is what "beat last week's
  /// numbers" compares against.
  /// All completed sessions since [since] — powers the progress view
  /// (streaks, weekly completion) rather than duplicating this logic
  /// per-screen.
  Future<List<WorkoutSession>> getCompletedSessionsSince(DateTime since) async {
    final db = await database;
    final maps = await db.query(
      'workout_sessions',
      where: 'status = ? AND date >= ?',
      whereArgs: [SessionStatus.completed.name, since.toIso8601String()],
      orderBy: 'date DESC',
    );
    return maps.map((m) => WorkoutSession.fromMap(m)).toList();
  }

  Future<List<ExerciseLog>> getPreviousLogsForExercise(
      String exerciseId, DateTime beforeDate) async {
    final db = await database;

    final sessionMaps = await db.query(
      'workout_sessions',
      where: 'status = ? AND date < ?',
      whereArgs: [
        SessionStatus.completed.name,
        DateTime(beforeDate.year, beforeDate.month, beforeDate.day)
            .toIso8601String(),
      ],
      orderBy: 'date DESC',
    );

    for (final sessionMap in sessionMaps) {
      final sessionId = sessionMap['id'] as String;
      final logs = await db.query(
        'exercise_logs',
        where: 'sessionId = ? AND exerciseId = ?',
        whereArgs: [sessionId, exerciseId],
        orderBy: 'setNumber ASC',
      );
      if (logs.isNotEmpty) {
        return logs.map((m) => ExerciseLog.fromMap(m)).toList();
      }
    }
    return [];
  }

  // ---------------- App Settings ----------------

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );

    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  // ---------------- Water ----------------

  Future<void> insertWaterLog(WaterLog log) async {
    final db = await database;
    await db.insert(
      'water_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteWaterLog(String id) async {
    final db = await database;
    await db.delete(
      'water_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<WaterLog>> getWaterLogsForDay(DateTime day) async {
    final db = await database;
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'water_logs',
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
      ],
      orderBy: 'timestamp DESC',
    );

    return maps.map((m) => WaterLog.fromMap(m)).toList();
  }

  Future<int> getTotalWaterMlForDay(DateTime day) async {
    final logs = await getWaterLogsForDay(day);
    return logs.fold<int>(
      0,
      (sum, log) => sum + log.amountMl,
    );
  }

  // ---------------- Sleep ----------------

  Future<void> insertSleepLog(SleepLog log) async {
    final db = await database;
    await db.insert(
      'sleep_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SleepLog>> getRecentSleepLogs({int days = 14}) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: days));

    final maps = await db.query(
      'sleep_logs',
      where: 'wakeTime >= ?',
      whereArgs: [since.toIso8601String()],
      orderBy: 'wakeTime DESC',
    );

    return maps.map((m) => SleepLog.fromMap(m)).toList();
  }

  Future<SleepLog?> getLastNightSleep() async {
    final logs = await getRecentSleepLogs(days: 2);
    if (logs.isEmpty) return null;
    return logs.first;
  }


  // ---------------- Meals ----------------

  Future<void> insertMealLog(MealLog log) async {
    final db = await database;
    await db.insert(
      'meal_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMealLog(String id) async {
    final db = await database;
    await db.delete(
      'meal_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<MealLog>> getMealLogsForDay(DateTime day) async {
    final db = await database;

    final startOfDay = DateTime(
      day.year,
      day.month,
      day.day,
    );

    final endOfDay = startOfDay.add(
      const Duration(days: 1),
    );

    final maps = await db.query(
      'meal_logs',
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
      ],
      orderBy: 'timestamp ASC',
    );

    return maps.map((m) => MealLog.fromMap(m)).toList();
  }

  /// Counts logged meals of a given type since [since].
  Future<int> countMealTypeSince(
    MealType type,
    DateTime since,
  ) async {
    final db = await database;

    final maps = await db.query(
      'meal_logs',
      where: 'mealType = ? AND timestamp >= ?',
      whereArgs: [
        type.name,
        since.toIso8601String(),
      ],
    );

    return maps.length;
  }


  // ---------------- Behavior profiles (Phase 2) ----------------

  Future<BehaviorProfile?> getBehaviorProfile(
      String taskCategory, String contextKey) async {
    final db = await database;
    final maps = await db.query(
      'behavior_profiles',
      where: 'taskCategory = ? AND contextKey = ?',
      whereArgs: [taskCategory, contextKey],
    );
    if (maps.isEmpty) return null;
    return BehaviorProfile.fromMap(maps.first);
  }

  Future<void> upsertBehaviorProfile(BehaviorProfile profile) async {
    final db = await database;
    await db.insert(
      'behavior_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<BehaviorProfile>> getAllBehaviorProfiles() async {
    final db = await database;
    final maps = await db.query(
      'behavior_profiles',
      orderBy: 'lastUpdated DESC',
    );
    return maps.map((m) => BehaviorProfile.fromMap(m)).toList();
  }

  // ---------------- Preference learning (Phase 2) ----------------

  Future<void> insertConflictOutcome(ConflictOutcome outcome) async {
    final db = await database;
    await db.insert('conflict_outcomes', outcome.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ConflictOutcome>> getRecentConflictOutcomes({
    int days = 90,
  }) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: days));
    final maps = await db.query(
      'conflict_outcomes',
      where: 'timestamp >= ?',
      whereArgs: [since.toIso8601String()],
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => ConflictOutcome.fromMap(m)).toList();
  }

  Future<void> upsertTaskImportanceWeight(
      TaskImportanceWeight weight) async {
    final db = await database;
    await db.insert('task_importance_weights', weight.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<TaskImportanceWeight?> getTaskImportanceWeight(
      String taskCategory) async {
    final db = await database;
    final maps = await db.query('task_importance_weights',
        where: 'taskCategory = ?', whereArgs: [taskCategory]);
    if (maps.isEmpty) return null;
    return TaskImportanceWeight.fromMap(maps.first);
  }

  Future<List<TaskImportanceWeight>> getAllTaskImportanceWeights() async {
    final db = await database;
    final maps = await db.query('task_importance_weights',
        orderBy: 'weight DESC');
    return maps.map((m) => TaskImportanceWeight.fromMap(m)).toList();
  }

  // ---------------- Day clustering (Phase 2) ----------------

  Future<void> insertDayVector(DayVector vector) async {
    final db = await database;
    await db.insert('day_vectors', vector.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<DayVector>> getRecentDayVectors({int days = 90}) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: days));
    final maps = await db.query(
      'day_vectors',
      where: 'date >= ?',
      whereArgs: [since.toIso8601String()],
      orderBy: 'date DESC',
    );
    return maps.map((m) => DayVector.fromMap(m)).toList();
  }

  Future<void> upsertDayCluster(DayCluster cluster) async {
    final db = await database;
    await db.insert('day_clusters', cluster.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<DayCluster>> getAllDayClusters() async {
    final db = await database;
    final maps = await db.query('day_clusters',
        orderBy: 'clusterId ASC');
    return maps.map((m) => DayCluster.fromMap(m)).toList();
  }

  // ---------------- Burnout forecasting ----------------

  /// Returns all behavior profiles updated since [since].
  /// Used by burnout forecasting to compare recent vs baseline activity.
  Future<List<BehaviorProfile>> getBehaviorProfilesUpdatedSince(
      DateTime since) async {
    final db = await database;
    final maps = await db.query(
      'behavior_profiles',
      where: 'lastUpdated >= ?',
      whereArgs: [since.toIso8601String()],
    );
    return maps.map((m) => BehaviorProfile.fromMap(m)).toList();
  }

  /// Counts total tasks scheduled since [since].
  /// Used by burnout forecasting to detect schedule density spikes.
  Future<int> getTaskCountSince(DateTime since) async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'plannedStart >= ?',
      whereArgs: [since.toIso8601String()],
    );
    return maps.length;
  }

  /// Stores a lightweight burnout forecast for historical reference
  /// and the Reasoning Trace Engine.
  Future<void> saveBurnoutForecast(
    double riskScore,
    double confidence,
    String level,
    String reason,
  ) async {
    final db = await database;
    await db.insert(
      'burnout_forecasts',
      {
        'id': const Uuid().v4(),
        'riskScore': riskScore,
        'confidence': confidence,
        'level': level,
        'reason': reason,
        'computedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getLatestBurnoutForecast() async {
    final db = await database;
    final maps = await db.query(
      'burnout_forecasts',
      orderBy: 'computedAt DESC',
      limit: 1,
    );
    return maps.isEmpty ? null : maps.first;
  }

  // ---------------- Goal plans (Phase 3) ----------------

  Future<void> insertGoalPlan(GoalPlan plan) async {
    final db = await database;
    await db.insert('goal_plans', plan.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    // Re-insert milestones: delete existing first, then bulk-insert.
    await db.delete('weekly_milestones',
        where: 'goalPlanId = ?', whereArgs: [plan.id]);
    for (final m in plan.milestones) {
      await db.insert('weekly_milestones', {
        ...m.toMap(),
        'goalPlanId': plan.id,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<GoalPlan?> getGoalPlan(String id) async {
    final db = await database;
    final maps =
        await db.query('goal_plans', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final milestones = await _getMilestones(db, id);
    return GoalPlan.fromMap(maps.first, milestones: milestones);
  }

  Future<List<GoalPlan>> getActiveGoalPlans() async {
    final db = await database;
    final maps = await db.query('goal_plans',
        where: 'status = ?',
        whereArgs: [GoalStatus.active.name],
        orderBy: 'targetDate ASC');
    final plans = <GoalPlan>[];
    for (final m in maps) {
      final id = m['id'] as String;
      final milestones = await _getMilestones(db, id);
      plans.add(GoalPlan.fromMap(m, milestones: milestones));
    }
    return plans;
  }

  Future<List<GoalPlan>> getAllGoalPlans() async {
    final db = await database;
    final maps =
        await db.query('goal_plans', orderBy: 'targetDate ASC');
    final plans = <GoalPlan>[];
    for (final m in maps) {
      final id = m['id'] as String;
      final milestones = await _getMilestones(db, id);
      plans.add(GoalPlan.fromMap(m, milestones: milestones));
    }
    return plans;
  }

  Future<void> updateGoalPlanStatus(String id, GoalStatus status) async {
    final db = await database;
    await db.update('goal_plans', {'status': status.name},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteGoalPlan(String id) async {
    final db = await database;
    await db.delete('weekly_milestones',
        where: 'goalPlanId = ?', whereArgs: [id]);
    await db.delete('goal_plans', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<WeeklyMilestone>> _getMilestones(
      Database db, String goalPlanId) async {
    final maps = await db.query('weekly_milestones',
        where: 'goalPlanId = ?',
        whereArgs: [goalPlanId],
        orderBy: 'weekNumber ASC');
    return maps.map((m) => WeeklyMilestone.fromMap(m)).toList();
  }

}
