import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/workout_models.dart';

/// Seeds the three real workout plans provided by the user: Gym, Home, and
/// Transformation. Exercises with the same name are reused (same Exercise
/// id) across days/plans so progressive-overload history accumulates
/// correctly for a movement regardless of which day it appears on.
///
/// Note: the original documents' workout-time-window text (17:00-18:30 for
/// Gym/Home, 6:00-8:00 AM for Transformation) is stored only as reference
/// notes on the WorkoutPlan — per the decision that these are informational,
/// not enforced scheduling rules.
class WorkoutPlanSeeder {
  static const gymPlanId = 'plan-gym';
  static const homePlanId = 'plan-home';
  static const transformationPlanId = 'plan-transformation';

  static final DatabaseHelper _db = DatabaseHelper.instance;
  static final Map<String, Exercise> _exerciseCache = {};

  static Future<void> ensureAllPlansExist() async {
    final existing = await _db.getAllWorkoutPlans();
    // Only seed once, ever — if the person has ANY plan (even one they made
    // themselves), never auto-reseed. Previously this checked only for the
    // Gym plan's specific id, so deleting it caused a silent full reseed
    // AND duplicated every exercise (fresh rows each time).
    if (existing.isNotEmpty) return;

    _exerciseCache.clear();

    // Shared warm-up block reused by Gym and Home plans.
    final warmup = [
      await _ex('Jumping Jacks', 'bodyweight', 1, '2 min'),
      await _ex('Arm Circles', 'bodyweight', 1, '2 min'),
      await _ex('Bodyweight Squats', 'bodyweight', 1, '2 min'),
      await _ex('Dynamic Stretching', 'bodyweight', 1, '4 min'),
    ];
    final warmupIds = warmup.map((e) => e.id).toList();

    await _seedGymPlan(warmupIds);
    await _seedHomePlan(warmupIds);
    await _seedTransformationPlan();
  }

  /// Gets-or-creates an Exercise by name, so the same movement appearing
  /// on multiple days shares one history for progressive overload.
  static Future<Exercise> _ex(
    String name,
    String equipment,
    int sets,
    String repsTarget, {
    String? note,
  }) async {
    if (_exerciseCache.containsKey(name)) return _exerciseCache[name]!;
    final exercise = Exercise(
      id: const Uuid().v4(),
      name: name,
      equipment: equipment,
      targetSets: sets,
      repsTarget: repsTarget,
      progressionNote: note,
      isSeeded: true,
    );
    await _db.insertExercise(exercise);
    _exerciseCache[name] = exercise;
    return exercise;
  }

  static Future<void> _template({
    required String planId,
    required String name,
    required int dayOfWeek,
    List<String> warmupIds = const [],
    required List<String> exerciseIds,
    int restBetweenSets = 60,
    int restBetweenExercises = 90,
    bool isRestDay = false,
  }) async {
    final template = WorkoutTemplate(
      id: const Uuid().v4(),
      planId: planId,
      name: name,
      dayOfWeek: dayOfWeek,
      warmupExerciseIds: warmupIds,
      exerciseIds: exerciseIds,
      sessionType: SessionType.sequential,
      restBetweenSetsSeconds: restBetweenSets,
      restBetweenExercisesSeconds: restBetweenExercises,
      isRestDay: isRestDay,
    );
    await _db.insertWorkoutTemplate(template);
  }

  // ---------------- Gym Plan ----------------
  static Future<void> _seedGymPlan(List<String> warmupIds) async {
    await _db.insertWorkoutPlan(WorkoutPlan(
      id: gymPlanId,
      name: 'Gym Plan',
      referenceNotes:
          'Reference only — workout window 17:00-18:30, cool-down stretching at end.',
    ));

    Future<String> id(String n, String eq, int s, String r, {String? note}) async =>
        (await _ex(n, eq, s, r, note: note)).id;

    await _template(
      planId: gymPlanId, name: 'Monday — Chest & Core', dayOfWeek: 1,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Bench Press', 'barbell', 4, '10'),
        await id('Incline Dumbbell Press', 'dumbbell', 4, '10'),
        await id('Chest Fly', 'dumbbell', 3, '12'),
        await id('Push-ups', 'bodyweight', 3, 'Max'),
        await id('Crunches', 'bodyweight', 4, '20'),
        await id('Leg Raises', 'bodyweight', 4, '15'),
        await id('Plank', 'bodyweight', 3, '45 sec'),
      ],
    );

    await _template(
      planId: gymPlanId, name: 'Tuesday — Back & Core', dayOfWeek: 2,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Lat Pulldown', 'cable', 4, '10'),
        await id('Seated Row', 'cable', 4, '12'),
        await id('Deadlift', 'barbell', 4, '8'),
        await id('Hanging Knee Raises', 'bodyweight', 4, '15'),
        await id('Russian Twists', 'bodyweight', 4, '20'),
        await id('Plank', 'bodyweight', 3, '45 sec'),
      ],
    );

    await _template(
      planId: gymPlanId, name: 'Wednesday — Shoulders & Core', dayOfWeek: 3,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Shoulder Press', 'dumbbell', 4, '10'),
        await id('Lateral Raises', 'dumbbell', 4, '15'),
        await id('Front Raises', 'dumbbell', 3, '12'),
        await id('Bicycle Crunch', 'bodyweight', 4, '20'),
        await id('Leg Raises', 'bodyweight', 4, '15'),
      ],
    );

    await _template(
      planId: gymPlanId, name: 'Thursday — Arms & Core', dayOfWeek: 4,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Barbell Curl', 'barbell', 4, '12'),
        await id('Dumbbell Curl', 'dumbbell', 3, '12'),
        await id('Triceps Pushdown', 'cable', 4, '15'),
        await id('Dips', 'bodyweight', 3, 'Max'),
        await id('Cable Crunch', 'cable', 4, '15'),
        await id('Plank', 'bodyweight', 3, '60 sec'),
      ],
    );

    await _template(
      planId: gymPlanId, name: 'Friday — Chest & Shoulders', dayOfWeek: 5,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Incline Bench Press', 'barbell', 4, '8'),
        await id('Dumbbell Press', 'dumbbell', 4, '10'),
        await id('Lateral Raises', 'dumbbell', 4, '15'),
        await id('Hanging Leg Raises', 'bodyweight', 4, '15'),
        await id('Mountain Climbers', 'bodyweight', 4, '30 sec'),
      ],
    );

    await _template(
      planId: gymPlanId, name: 'Saturday — Legs', dayOfWeek: 6,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Squats', 'barbell', 4, '12'),
        await id('Leg Press', 'machine', 4, '12'),
        await id('Deadlift', 'barbell', 4, '10'),
        await id('Standing Calf Raises', 'machine', 4, '20'),
        await id('Plank', 'bodyweight', 3, '60 sec'),
      ],
    );
  }

  // ---------------- Home Plan ----------------
  static Future<void> _seedHomePlan(List<String> warmupIds) async {
    await _db.insertWorkoutPlan(WorkoutPlan(
      id: homePlanId,
      name: 'Home Plan',
      referenceNotes:
          'Reference only — use when gym is not available. Same window/rest rules as Gym Plan.',
    ));

    Future<String> id(String n, String eq, int s, String r) async =>
        (await _ex(n, eq, s, r)).id;

    await _template(
      planId: homePlanId, name: 'Monday — Push & Core', dayOfWeek: 1,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Push-ups', 'bodyweight', 5, '20'),
        await id('Wide Push-ups', 'bodyweight', 4, '15'),
        await id('Decline Push-ups', 'bodyweight', 4, '12'),
        await id('Crunches', 'bodyweight', 4, '25'),
        await id('Leg Raises', 'bodyweight', 4, '15'),
        await id('Plank', 'bodyweight', 3, '60 sec'),
      ],
    );

    await _template(
      planId: homePlanId, name: 'Tuesday — Back & Core', dayOfWeek: 2,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Resistance Band Rows', 'band', 5, '20'),
        await id('Superman Hold', 'bodyweight', 4, '40 sec'),
        await id('Russian Twists', 'bodyweight', 4, '30'),
        await id('Plank', 'bodyweight', 3, '60 sec'),
      ],
    );

    await _template(
      planId: homePlanId, name: 'Wednesday — Shoulders', dayOfWeek: 3,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Pike Push-ups', 'bodyweight', 5, '12'),
        await id('Band Shoulder Press', 'band', 4, '20'),
        await id('Lateral Raises', 'band', 4, '20'),
        await id('Leg Raises', 'bodyweight', 4, '15'),
        await id('Mountain Climbers', 'bodyweight', 4, '40 sec'),
      ],
    );

    await _template(
      planId: homePlanId, name: 'Thursday — Arms', dayOfWeek: 4,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Band Curls', 'band', 5, '20'),
        await id('Hammer Curls', 'dumbbell', 4, '15'),
        await id('Chair Dips', 'bodyweight', 5, '15'),
        await id('Diamond Push-ups', 'bodyweight', 4, '12'),
        await id('Plank Shoulder Taps', 'bodyweight', 4, '30'),
      ],
    );

    await _template(
      planId: homePlanId, name: 'Friday — Chest', dayOfWeek: 5,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Decline Push-ups', 'bodyweight', 5, '12'),
        await id('Explosive Push-ups', 'bodyweight', 4, '10'),
        await id('Band Flys', 'band', 4, '20'),
        await id('Knee Raises', 'bodyweight', 4, '15'),
        await id('Plank', 'bodyweight', 3, '75 sec'),
      ],
    );

    await _template(
      planId: homePlanId, name: 'Saturday — Full Body', dayOfWeek: 6,
      warmupIds: warmupIds, restBetweenSets: 50, restBetweenExercises: 70,
      exerciseIds: [
        await id('Squats', 'bodyweight', 5, '25'),
        await id('Push-ups', 'bodyweight', 5, '20'),
        await id('Jump Squats', 'bodyweight', 5, '15'),
        await id('Mountain Climbers', 'bodyweight', 5, '40 sec'),
        await id('Flutter Kicks', 'bodyweight', 4, '40 sec'),
        await id('Plank', 'bodyweight', 2, '90 sec'),
      ],
    );
  }

  // ---------------- Transformation Plan ----------------
  static Future<void> _seedTransformationPlan() async {
    await _db.insertWorkoutPlan(WorkoutPlan(
      id: transformationPlanId,
      name: 'Transformation Plan',
      referenceNotes:
          'Reference only — suggested window 6:00-8:00 AM. Includes nutrition/hydration '
          'guidance and a 7-8hr sleep target; those belong to future Nutrition/Sleep '
          'modules, not tracked here.',
    ));

    Future<String> id(String n, String eq, int s, String r) async =>
        (await _ex(n, eq, s, r)).id;

    await _template(
      planId: transformationPlanId, name: 'Monday — Chest + Cardio', dayOfWeek: 1,
      restBetweenSets: 45, restBetweenExercises: 45,
      exerciseIds: [
        await id('Resistance Band Chest Press', 'band', 4, '12'),
        await id('Incline Push-ups', 'bodyweight', 4, '12'),
        await id('Band Flys', 'band', 4, '12'),
        await id('Burpees', 'bodyweight', 4, '12'),
        await id('Plank', 'bodyweight', 3, '45 sec'),
      ],
    );

    await _template(
      planId: transformationPlanId, name: 'Tuesday — Abs + Core', dayOfWeek: 2,
      restBetweenSets: 30, restBetweenExercises: 30,
      exerciseIds: [
        await id('Crunches', 'bodyweight', 4, '15'),
        await id('Leg Raises', 'bodyweight', 4, '15'),
        await id('Mountain Climbers', 'bodyweight', 4, '15'),
        await id('Band Russian Twists', 'band', 4, '15'),
        await id('Plank', 'bodyweight', 3, '45 sec'),
      ],
    );

    await _template(
      planId: transformationPlanId, name: 'Wednesday — Back + Arms', dayOfWeek: 3,
      restBetweenSets: 45, restBetweenExercises: 45,
      exerciseIds: [
        await id('Band Rows', 'band', 3, '15'),
        await id('Band Bicep Curls', 'band', 3, '15'),
        await id('Band Tricep Pushdowns', 'band', 3, '15'),
        await id('Side Plank', 'bodyweight', 2, '45 sec'),
      ],
    );

    // Thursday — genuine circuit: rounds of back-to-back exercises with no
    // rest inside a round, then rest after each full round. This is what
    // the dynamic sessionType is for — no special-cased code needed here,
    // just different template configuration.
    final circuitTemplate = WorkoutTemplate(
      id: const Uuid().v4(),
      planId: transformationPlanId,
      name: 'Thursday — Fat Burn Circuit',
      dayOfWeek: 4,
      exerciseIds: [
        await id('Jumping Jacks', 'bodyweight', 1, '30 sec'),
        await id('Push-ups', 'bodyweight', 1, '10'),
        await id('Mountain Climbers', 'bodyweight', 1, '20'),
        await id('High Knees', 'bodyweight', 1, '30 sec'),
        await id('Plank', 'bodyweight', 1, '30 sec'),
      ],
      sessionType: SessionType.circuit,
      circuitRounds: 3,
      restBetweenExercisesInRoundSeconds: 0,
      restAfterRoundSeconds: 60,
    );
    await _db.insertWorkoutTemplate(circuitTemplate);

    await _template(
      planId: transformationPlanId, name: 'Friday — Core + Chest Tone', dayOfWeek: 5,
      restBetweenSets: 40, restBetweenExercises: 40,
      exerciseIds: [
        await id('Band Chest Press', 'band', 3, '15'),
        await id('Band Pull-Aparts', 'band', 3, '15'),
        await id('Leg Raises', 'bodyweight', 3, '15'),
        await id('Flutter Kicks', 'bodyweight', 3, '15'),
        await id('Plank Shoulder Taps', 'bodyweight', 3, '15'),
      ],
    );

    await _template(
      planId: transformationPlanId, name: 'Saturday — Lower Body + Stretch', dayOfWeek: 6,
      restBetweenSets: 30, restBetweenExercises: 30,
      exerciseIds: [
        await id('Squats', 'bodyweight', 3, '20'),
        await id('Lunges', 'bodyweight', 3, '20'),
        await id('Glute Bridge', 'bodyweight', 3, '20'),
        await id('Light Yoga / Stretching', 'none', 1, '10 min'),
      ],
    );

    // Sunday — rest & recovery day, no exercises logged.
    await _template(
      planId: transformationPlanId,
      name: 'Sunday — Rest & Recovery',
      dayOfWeek: 7,
      exerciseIds: const [],
      isRestDay: true,
    );
  }
}
