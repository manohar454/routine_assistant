import 'dart:convert';
import 'package:flutter/material.dart' show TimeOfDay;

// ---------------------------------------------------------------------------
// Routine entry type — every kind of reminder in the AI Voice Companion
// ---------------------------------------------------------------------------

enum RoutineEntryType {
  wakeUp,          // 5:45 AM alarm + motivational music
  morningWater,    // soaked water / morning water
  workout,         // morning workout block
  postWorkoutWater,
  breakfast,       // mess breakfast
  waterReminder,   // periodic water throughout the day
  study,           // study session reminder
  college,         // go to college
  lunch,           // mess lunch
  nap,             // afternoon nap
  snacks,          // post-college snacks
  gym,             // evening gym / physical activity
  postGymProtein,  // protein meal / cook reminder
  dinner,          // mess dinner
  bedtimePrep,     // soak grains/chia/sabja seeds
  custom,          // user-created entry
}

extension RoutineEntryTypeExt on RoutineEntryType {
  String get label {
    switch (this) {
      case RoutineEntryType.wakeUp:           return 'Wake Up';
      case RoutineEntryType.morningWater:     return 'Morning Water';
      case RoutineEntryType.workout:          return 'Morning Workout';
      case RoutineEntryType.postWorkoutWater: return 'Post-Workout Water';
      case RoutineEntryType.breakfast:        return 'Breakfast';
      case RoutineEntryType.waterReminder:    return 'Water Reminder';
      case RoutineEntryType.study:            return 'Study';
      case RoutineEntryType.college:          return 'College';
      case RoutineEntryType.lunch:            return 'Lunch';
      case RoutineEntryType.nap:              return 'Nap';
      case RoutineEntryType.snacks:           return 'Snacks';
      case RoutineEntryType.gym:              return 'Gym / Activity';
      case RoutineEntryType.postGymProtein:   return 'Post-Gym Protein';
      case RoutineEntryType.dinner:           return 'Dinner';
      case RoutineEntryType.bedtimePrep:      return 'Bedtime Prep';
      case RoutineEntryType.custom:           return 'Custom';
    }
  }

  String get emoji {
    switch (this) {
      case RoutineEntryType.wakeUp:           return '🌅';
      case RoutineEntryType.morningWater:     return '💧';
      case RoutineEntryType.workout:          return '🏋️';
      case RoutineEntryType.postWorkoutWater: return '💧';
      case RoutineEntryType.breakfast:        return '🍳';
      case RoutineEntryType.waterReminder:    return '🥤';
      case RoutineEntryType.study:            return '📚';
      case RoutineEntryType.college:          return '🎓';
      case RoutineEntryType.lunch:            return '🍱';
      case RoutineEntryType.nap:              return '😴';
      case RoutineEntryType.snacks:           return '🍌';
      case RoutineEntryType.gym:              return '🏃';
      case RoutineEntryType.postGymProtein:   return '🥗';
      case RoutineEntryType.dinner:           return '🍽️';
      case RoutineEntryType.bedtimePrep:      return '🌙';
      case RoutineEntryType.custom:           return '⭐';
    }
  }

  /// Whether this type is a food/mess entry (requires food log confirmation).
  bool get isMeal =>
      this == RoutineEntryType.breakfast ||
      this == RoutineEntryType.lunch ||
      this == RoutineEntryType.dinner ||
      this == RoutineEntryType.snacks;

  /// Whether this type tracks water ml.
  bool get isWater =>
      this == RoutineEntryType.morningWater ||
      this == RoutineEntryType.waterReminder ||
      this == RoutineEntryType.postWorkoutWater;

  /// Whether this is a timed block (nap, study, workout, gym).
  bool get isDuration =>
      this == RoutineEntryType.nap ||
      this == RoutineEntryType.study ||
      this == RoutineEntryType.workout ||
      this == RoutineEntryType.gym;

  String defaultMessage({int? waterMl, int? durationMinutes}) {
    switch (this) {
      case RoutineEntryType.wakeUp:
        return "Good morning! Rise and shine — it's time to conquer the day. "
            "Let's start with some motivational energy!";
      case RoutineEntryType.morningWater:
        return "Boss, drink ${waterMl ?? 500} ml of water to kick-start your "
            "metabolism and wake up your system.";
      case RoutineEntryType.workout:
        return "Time for your morning workout! Let's go through your exercise "
            "list. You have ${durationMinutes ?? 45} minutes — make every rep count!";
      case RoutineEntryType.postWorkoutWater:
        return "Great workout! Now refuel with ${waterMl ?? 500} ml of water "
            "to aid muscle recovery.";
      case RoutineEntryType.breakfast:
        return "Boss, it's breakfast time! A good breakfast fuels your brain "
            "and keeps you sharp all morning. Go eat!";
      case RoutineEntryType.waterReminder:
        return "Time for your water top-up! Drink ${waterMl ?? 400} ml to "
            "stay hydrated and keep your energy up.";
      case RoutineEntryType.study:
        return "Boss, study time! ${durationMinutes != null ? 'You have $durationMinutes minutes — ' : ''}"
            "Focus up, close distractions, and get into deep work mode.";
      case RoutineEntryType.college:
        return "Boss, time to head to college! Don't be late — gather your stuff and go.";
      case RoutineEntryType.nap:
        return "Short nap time! ${durationMinutes != null ? '$durationMinutes minutes — ' : ''}"
            "Set your alarm and recharge. Your afternoon self will thank you.";
      case RoutineEntryType.snacks:
        return "Snack break! Grab something to eat and refuel before your evening session.";
      case RoutineEntryType.lunch:
        return "Boss, lunch time! Your body needs fuel for the afternoon. "
            "Step away from work and eat a solid meal.";
      case RoutineEntryType.gym:
        return "Boss, it's gym time! Your muscles are calling. Get in there "
            "and crush today's session — you're one workout away from a better "
            "version of yourself!";
      case RoutineEntryType.postGymProtein:
        return "Excellent gym session! Now is the golden window — cook or "
            "prepare your protein meal within the next 30 minutes for maximum "
            "muscle synthesis.";
      case RoutineEntryType.dinner:
        return "Boss, dinner time! A nutritious dinner helps your body recover "
            "while you sleep. Go eat!";
      case RoutineEntryType.bedtimePrep:
        return "Almost time to rest! Before you sleep, remember to soak your "
            "grains, chia seeds, and sabja seeds in water — they'll be ready "
            "for your morning. Good night, champion!";
      case RoutineEntryType.custom:
        return "Reminder from your Routine Assistant!";
    }
  }
}

// ---------------------------------------------------------------------------
// RoutineEntry — one slot in the timetable
// ---------------------------------------------------------------------------

class RoutineEntry {
  final String id;
  final RoutineEntryType type;

  /// Minutes since midnight (e.g. 5:30 AM = 330).
  final int timeOfDayMinutes;

  /// Display label — editable by user.
  final String label;

  /// Voice message spoken via TTS — editable.
  final String message;

  /// For water reminders: how much to drink in ml.
  final int? waterMl;

  /// For workout: duration in minutes.
  final int? durationMinutes;

  /// Days this entry is active: 0=Mon … 6=Sun (weekday index).
  /// Empty list = every day.
  final List<int> activeDays;

  /// Whether this entry is enabled.
  final bool enabled;

  /// Extra JSON-encoded key/value pairs for future extensibility.
  final Map<String, dynamic> extra;

  const RoutineEntry({
    required this.id,
    required this.type,
    required this.timeOfDayMinutes,
    required this.label,
    required this.message,
    this.waterMl,
    this.durationMinutes,
    this.activeDays = const [],
    this.enabled = true,
    this.extra = const {},
  });

  TimeOfDay get timeOfDay => TimeOfDay(
        hour: timeOfDayMinutes ~/ 60,
        minute: timeOfDayMinutes % 60,
      );

  String get formattedTime {
    final h = timeOfDayMinutes ~/ 60;
    final m = timeOfDayMinutes % 60;
    final period = h < 12 ? 'AM' : 'PM';
    final displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayHour:${m.toString().padLeft(2, '0')} $period';
  }

  /// Sentinel value for explicitly clearing an optional int field via [copyWith].
  /// Pass this instead of null to force a field back to null.
  static const clearInt = -999999;

  RoutineEntry copyWith({
    RoutineEntryType? type,
    int? timeOfDayMinutes,
    String? label,
    String? message,
    /// Pass [RoutineEntry._clearInt] to explicitly clear to null.
    int? waterMl,
    /// Pass [RoutineEntry._clearInt] to explicitly clear to null.
    int? durationMinutes,
    List<int>? activeDays,
    bool? enabled,
    Map<String, dynamic>? extra,
  }) {
    return RoutineEntry(
      id: id,
      type: type ?? this.type,
      timeOfDayMinutes: timeOfDayMinutes ?? this.timeOfDayMinutes,
      label: label ?? this.label,
      message: message ?? this.message,
      waterMl: waterMl == clearInt ? null : (waterMl ?? this.waterMl),
      durationMinutes: durationMinutes == clearInt
          ? null
          : (durationMinutes ?? this.durationMinutes),
      activeDays: activeDays ?? this.activeDays,
      enabled: enabled ?? this.enabled,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'timeOfDayMinutes': timeOfDayMinutes,
        'label': label,
        'message': message,
        'waterMl': waterMl,
        'durationMinutes': durationMinutes,
        'activeDays': jsonEncode(activeDays),
        'enabled': enabled ? 1 : 0,
        'extra': jsonEncode(extra),
      };

  factory RoutineEntry.fromMap(Map<String, dynamic> m) => RoutineEntry(
        id: m['id'] as String,
        type: RoutineEntryType.values.firstWhere(
          (e) => e.name == m['type'],
          orElse: () => RoutineEntryType.custom,
        ),
        timeOfDayMinutes: m['timeOfDayMinutes'] as int,
        label: m['label'] as String,
        message: m['message'] as String,
        waterMl: m['waterMl'] as int?,
        durationMinutes: m['durationMinutes'] as int?,
        activeDays:
            (jsonDecode(m['activeDays'] as String) as List).cast<int>(),
        enabled: (m['enabled'] as int) == 1,
        extra: Map<String, dynamic>.from(
            jsonDecode(m['extra'] as String) as Map),
      );
}

// ---------------------------------------------------------------------------
// DefaultRoutineTimetable — factory for a complete starter schedule
// ---------------------------------------------------------------------------

class _WaterSlot {
  final int minutesSinceMidnight;
  final RoutineEntryType type;
  final String slotLabel;
  const _WaterSlot(this.minutesSinceMidnight, this.type, this.slotLabel);
}

class DefaultRoutineTimetable {
  DefaultRoutineTimetable._();

  // Water slots mapped to the college day schedule
  // (5:45 AM wake → study → college → mess → nap → college → snacks → gym → dinner → sleep)
  static const _waterSlots = [
    _WaterSlot(345,  RoutineEntryType.morningWater,    'Morning Water'),     // 5:45 AM
    _WaterSlot(485,  RoutineEntryType.waterReminder,   'Pre-Breakfast Water'),// 8:05 AM
    _WaterSlot(570,  RoutineEntryType.waterReminder,   'Mid-Morning Water'),  // 9:30 AM
    _WaterSlot(660,  RoutineEntryType.waterReminder,   'Late Morning Water'), // 11:00 AM
    _WaterSlot(750,  RoutineEntryType.waterReminder,   'Pre-Lunch Water'),    // 12:30 PM
    _WaterSlot(840,  RoutineEntryType.waterReminder,   'Afternoon Water'),    // 2:00 PM
    _WaterSlot(930,  RoutineEntryType.waterReminder,   'Post-Nap Water'),     // 3:30 PM
    _WaterSlot(1020, RoutineEntryType.waterReminder,   'Pre-Gym Water'),      // 5:00 PM
    _WaterSlot(1110, RoutineEntryType.postWorkoutWater,'Post-Gym Water'),     // 6:30 PM
    _WaterSlot(1170, RoutineEntryType.waterReminder,   'Evening Water'),      // 7:30 PM
    _WaterSlot(1230, RoutineEntryType.waterReminder,   'Dinner Water'),       // 8:30 PM
    _WaterSlot(1290, RoutineEntryType.waterReminder,   'Night Water'),        // 9:30 PM
  ];

  /// Builds a complete default day schedule matching the college routine.
  ///
  /// Timeline:
  ///  5:45 Wake → 6:00 Soaked water → 6:10 Workout (45 min) → 7:00 Post-workout water
  ///  8:00 Study → 8:30 Breakfast (mess) → 9:30 College →
  ///  12:30 Mess Lunch → 1:30 Nap (30 min) → 3:00 College (afternoon) →
  ///  5:00 Snacks → 5:30 Gym/Activity → 6:30 Post-gym protein →
  ///  8:00 Dinner (mess) → 9:00 Study → 9:30 Bedtime prep → 10:00 Sleep
  static List<RoutineEntry> build({
    int waterGoalMl = 5000,
    int workoutDurationMinutes = 45,
    int napDurationMinutes = 30,
    int studyDurationMinutes = 60,
  }) {
    final perSlotMl = (waterGoalMl / _waterSlots.length).round();
    final entries = <RoutineEntry>[];
    int counter = 1;
    String nextId() => 'default_${counter++}';

    void addWaterSlot(int idx) {
      final slot = _waterSlots[idx];
      entries.add(RoutineEntry(
        id: nextId(),
        type: slot.type,
        timeOfDayMinutes: slot.minutesSinceMidnight,
        label: slot.slotLabel,
        message: slot.type.defaultMessage(waterMl: perSlotMl),
        waterMl: perSlotMl,
      ));
    }

    // 1. Wake-up 5:45 AM = 345 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.wakeUp,
      timeOfDayMinutes: 345,
      label: 'Wake Up',
      message: RoutineEntryType.wakeUp.defaultMessage(),
    ));

    // 2. Soaked water (grains/chia/sabja) 6:00 AM = 360 min
    addWaterSlot(0); // 5:45 slot — shift to 6:00
    entries.last = entries.last.copyWith(
      timeOfDayMinutes: 360,
      label: 'Soaked Water',
      message: 'Boss, drink your soaked water — grains, chia, and sabja seeds. '
          'Your ${perSlotMl}ml morning hydration boost!',
    );

    // 3. Workout 6:10 AM = 370 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.workout,
      timeOfDayMinutes: 370,
      label: 'Morning Workout',
      message: RoutineEntryType.workout
          .defaultMessage(durationMinutes: workoutDurationMinutes),
      durationMinutes: workoutDurationMinutes,
    ));

    // 4. Post-workout water ~7:00 AM
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.postWorkoutWater,
      timeOfDayMinutes: 370 + workoutDurationMinutes,
      label: 'Post-Workout Water',
      message: RoutineEntryType.postWorkoutWater.defaultMessage(waterMl: perSlotMl),
      waterMl: perSlotMl,
    ));

    // 5. Study 8:00 AM = 480 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.study,
      timeOfDayMinutes: 480,
      label: 'Morning Study',
      message: RoutineEntryType.study.defaultMessage(durationMinutes: studyDurationMinutes),
      durationMinutes: studyDurationMinutes,
    ));

    // 6. Pre-breakfast water 8:00 AM
    addWaterSlot(1);

    // 7. Breakfast (mess) 8:30 AM = 510 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.breakfast,
      timeOfDayMinutes: 510,
      label: 'Breakfast (Mess)',
      message: 'Boss, breakfast time at the mess! Go eat — log what you have.',
    ));

    // 8. Mid-morning water
    addWaterSlot(2); // 9:30 AM

    // 9. College 9:30 AM = 570 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.college,
      timeOfDayMinutes: 570,
      label: 'Go to College',
      message: RoutineEntryType.college.defaultMessage(),
    ));

    // 10. Late morning water
    addWaterSlot(3); // 11:00 AM

    // 11. Pre-lunch water
    addWaterSlot(4); // 12:30 PM

    // 12. Lunch (mess) 12:30 PM = 750 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.lunch,
      timeOfDayMinutes: 750,
      label: 'Lunch (Mess)',
      message: 'Boss, lunch at the mess! Take a proper break — log what you eat.',
    ));

    // 13. Nap 1:30 PM = 810 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.nap,
      timeOfDayMinutes: 810,
      label: 'Afternoon Nap',
      message: RoutineEntryType.nap.defaultMessage(durationMinutes: napDurationMinutes),
      durationMinutes: napDurationMinutes,
    ));

    // 14. Afternoon water (post-nap)
    addWaterSlot(5); // 2:00 PM

    // 15. College afternoon 3:00 PM = 900 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.college,
      timeOfDayMinutes: 900,
      label: 'Afternoon College',
      message: 'Back to college, boss! Afternoon sessions — stay sharp.',
    ));

    // 16. Post-nap water
    addWaterSlot(6); // 3:30 PM

    // 17. Snacks 5:00 PM = 1020 min (after college)
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.snacks,
      timeOfDayMinutes: 1020,
      label: 'Evening Snacks',
      message: RoutineEntryType.snacks.defaultMessage(),
    ));

    // 18. Pre-gym water 5:00 PM
    addWaterSlot(7);

    // 19. Gym / Physical Activity 5:30 PM = 1050 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.gym,
      timeOfDayMinutes: 1050,
      label: 'Gym / Activity',
      message: RoutineEntryType.gym.defaultMessage(),
    ));

    // 20. Post-gym water 6:30 PM
    addWaterSlot(8);

    // 21. Post-gym protein 6:30 PM = 1110 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.postGymProtein,
      timeOfDayMinutes: 1110,
      label: 'Protein Meal',
      message: RoutineEntryType.postGymProtein.defaultMessage(),
    ));

    // 22. Evening water
    addWaterSlot(9); // 7:30 PM

    // 23. Dinner (mess) 8:00 PM = 1200 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.dinner,
      timeOfDayMinutes: 1200,
      label: 'Dinner (Mess)',
      message: 'Boss, dinner at the mess! Last proper meal of the day — log what you eat.',
    ));

    // 24. Dinner water
    addWaterSlot(10); // 8:30 PM

    // 25. Night study 9:00 PM = 1260 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.study,
      timeOfDayMinutes: 1260,
      label: 'Night Study',
      message: 'Final study session, boss! Review the day\'s material and prepare for tomorrow.',
      durationMinutes: studyDurationMinutes,
    ));

    // 26. Bedtime prep 9:30 PM = 1290 min (soak for tomorrow)
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.bedtimePrep,
      timeOfDayMinutes: 1290,
      label: 'Bedtime Prep',
      message: RoutineEntryType.bedtimePrep.defaultMessage(),
    ));

    // 27. Night water
    addWaterSlot(11); // 9:30 PM

    entries.sort((a, b) => a.timeOfDayMinutes.compareTo(b.timeOfDayMinutes));
    return entries;
  }
}
