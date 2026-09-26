import 'dart:convert';
import 'package:flutter/material.dart' show TimeOfDay;

// ---------------------------------------------------------------------------
// Routine entry type — every kind of reminder in the AI Voice Companion
// ---------------------------------------------------------------------------

enum RoutineEntryType {
  wakeUp,          // 5:30 AM alarm + motivational music
  morningWater,    // water after wake
  workout,         // morning workout block
  postWorkoutWater,
  breakfast,
  waterReminder,   // periodic water throughout the day
  lunch,
  gym,             // evening gym session
  postGymProtein,  // protein meal / cook reminder
  dinner,
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
      case RoutineEntryType.lunch:            return 'Lunch';
      case RoutineEntryType.gym:              return 'Gym Session';
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
      case RoutineEntryType.lunch:            return '🍱';
      case RoutineEntryType.gym:              return '🏃';
      case RoutineEntryType.postGymProtein:   return '🥗';
      case RoutineEntryType.dinner:           return '🍽️';
      case RoutineEntryType.bedtimePrep:      return '🌙';
      case RoutineEntryType.custom:           return '⭐';
    }
  }

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

  RoutineEntry copyWith({
    RoutineEntryType? type,
    int? timeOfDayMinutes,
    String? label,
    String? message,
    int? waterMl,
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
      waterMl: waterMl ?? this.waterMl,
      durationMinutes: durationMinutes ?? this.durationMinutes,
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

  static const _waterSlots = [
    _WaterSlot(330,  RoutineEntryType.morningWater,    'Morning Water'),
    _WaterSlot(575,  RoutineEntryType.waterReminder,   'Water Break'),
    _WaterSlot(635,  RoutineEntryType.waterReminder,   'Water Break'),
    _WaterSlot(695,  RoutineEntryType.waterReminder,   'Water Break'),
    _WaterSlot(755,  RoutineEntryType.waterReminder,   'Lunch Water'),
    _WaterSlot(815,  RoutineEntryType.waterReminder,   'Afternoon Water'),
    _WaterSlot(875,  RoutineEntryType.waterReminder,   'Afternoon Water'),
    _WaterSlot(935,  RoutineEntryType.waterReminder,   'Pre-Gym Water'),
    _WaterSlot(1025, RoutineEntryType.postWorkoutWater,'Post-Gym Water'),
    _WaterSlot(1145, RoutineEntryType.waterReminder,   'Evening Water'),
    _WaterSlot(1205, RoutineEntryType.waterReminder,   'Dinner Water'),
    _WaterSlot(1265, RoutineEntryType.waterReminder,   'Night Water'),
  ];

  /// Builds a complete default day schedule.
  static List<RoutineEntry> build({
    int waterGoalMl = 5000,
    int workoutDurationMinutes = 45,
  }) {
    final perSlotMl = (waterGoalMl / _waterSlots.length).round();
    final entries = <RoutineEntry>[];
    int counter = 1;
    String nextId() => 'default_${counter++}';

    // 1. Wake-up 5:30 AM
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.wakeUp,
      timeOfDayMinutes: 330,
      label: 'Wake Up',
      message: RoutineEntryType.wakeUp.defaultMessage(),
    ));

    // 2. Morning water
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.morningWater,
      timeOfDayMinutes: 330,
      label: 'Morning Water',
      message: RoutineEntryType.morningWater.defaultMessage(waterMl: perSlotMl),
      waterMl: perSlotMl,
    ));

    // 3. Workout 5:40 AM
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.workout,
      timeOfDayMinutes: 340,
      label: 'Morning Workout',
      message: RoutineEntryType.workout
          .defaultMessage(durationMinutes: workoutDurationMinutes),
      durationMinutes: workoutDurationMinutes,
    ));

    // 4. Post-workout water
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.postWorkoutWater,
      timeOfDayMinutes: 340 + workoutDurationMinutes,
      label: 'Post-Workout Water',
      message:
          RoutineEntryType.postWorkoutWater.defaultMessage(waterMl: perSlotMl),
      waterMl: perSlotMl,
    ));

    // 5. Breakfast 8:30 AM
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.breakfast,
      timeOfDayMinutes: 510,
      label: 'Breakfast',
      message: RoutineEntryType.breakfast.defaultMessage(),
    ));

    // 6-8. Pre-lunch water reminders
    for (int i = 1; i <= 3; i++) {
      final slot = _waterSlots[i];
      entries.add(RoutineEntry(
        id: nextId(),
        type: slot.type,
        timeOfDayMinutes: slot.minutesSinceMidnight,
        label: slot.slotLabel,
        message: slot.type.defaultMessage(waterMl: perSlotMl),
        waterMl: perSlotMl,
      ));
    }

    // 9. Lunch 12:30 PM = 750 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.lunch,
      timeOfDayMinutes: 750,
      label: 'Lunch',
      message: RoutineEntryType.lunch.defaultMessage(),
    ));

    // 10-12. Post-lunch afternoon water
    for (int i = 4; i <= 6; i++) {
      final slot = _waterSlots[i];
      entries.add(RoutineEntry(
        id: nextId(),
        type: slot.type,
        timeOfDayMinutes: slot.minutesSinceMidnight,
        label: slot.slotLabel,
        message: slot.type.defaultMessage(waterMl: perSlotMl),
        waterMl: perSlotMl,
      ));
    }

    // 13. Pre-gym water
    final preGymSlot = _waterSlots[7];
    entries.add(RoutineEntry(
      id: nextId(),
      type: preGymSlot.type,
      timeOfDayMinutes: preGymSlot.minutesSinceMidnight,
      label: preGymSlot.slotLabel,
      message: preGymSlot.type.defaultMessage(waterMl: perSlotMl),
      waterMl: perSlotMl,
    ));

    // 14. Gym 5:00 PM = 1020 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.gym,
      timeOfDayMinutes: 1020,
      label: 'Gym Session',
      message: RoutineEntryType.gym.defaultMessage(),
    ));

    // 15. Post-gym water
    final postGymSlot = _waterSlots[8];
    entries.add(RoutineEntry(
      id: nextId(),
      type: postGymSlot.type,
      timeOfDayMinutes: postGymSlot.minutesSinceMidnight,
      label: postGymSlot.slotLabel,
      message: postGymSlot.type.defaultMessage(waterMl: perSlotMl),
      waterMl: perSlotMl,
    ));

    // 16. Post-gym protein ~6:05 PM = 1085 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.postGymProtein,
      timeOfDayMinutes: 1085,
      label: 'Protein Meal',
      message: RoutineEntryType.postGymProtein.defaultMessage(),
    ));

    // 17-18. Evening water
    for (int i = 9; i <= 10; i++) {
      final slot = _waterSlots[i];
      entries.add(RoutineEntry(
        id: nextId(),
        type: slot.type,
        timeOfDayMinutes: slot.minutesSinceMidnight,
        label: slot.slotLabel,
        message: slot.type.defaultMessage(waterMl: perSlotMl),
        waterMl: perSlotMl,
      ));
    }

    // 19. Dinner 8:00 PM = 1200 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.dinner,
      timeOfDayMinutes: 1200,
      label: 'Dinner',
      message: RoutineEntryType.dinner.defaultMessage(),
    ));

    // 20. Final night water
    final nightWater = _waterSlots[11];
    entries.add(RoutineEntry(
      id: nextId(),
      type: nightWater.type,
      timeOfDayMinutes: nightWater.minutesSinceMidnight,
      label: nightWater.slotLabel,
      message: nightWater.type.defaultMessage(waterMl: perSlotMl),
      waterMl: perSlotMl,
    ));

    // 21. Bedtime prep 9:30 PM = 1290 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.bedtimePrep,
      timeOfDayMinutes: 1290,
      label: 'Bedtime Prep',
      message: RoutineEntryType.bedtimePrep.defaultMessage(),
    ));

    entries.sort((a, b) => a.timeOfDayMinutes.compareTo(b.timeOfDayMinutes));
    return entries;
  }
}
