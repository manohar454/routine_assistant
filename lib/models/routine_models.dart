import 'dart:convert';
import 'package:flutter/material.dart' show TimeOfDay;

// ---------------------------------------------------------------------------
// Routine entry type — 6 generic behavioral categories
// ---------------------------------------------------------------------------

enum RoutineEntryType {
  wake,       // alarm-style wake-up (plays music, hard to dismiss)
  hydration,  // tracks water ml intake
  meal,       // food log confirmation (log what you ate)
  activity,   // timed block — work, workout, study, commute, anything
  reminder,   // simple fire-and-forget reminder (medicine, call, task)
  wind,       // end-of-day / sleep prep
}

extension RoutineEntryTypeExt on RoutineEntryType {
  String get label {
    switch (this) {
      case RoutineEntryType.wake:      return 'Wake Up';
      case RoutineEntryType.hydration: return 'Hydration';
      case RoutineEntryType.meal:      return 'Meal';
      case RoutineEntryType.activity:  return 'Activity';
      case RoutineEntryType.reminder:  return 'Reminder';
      case RoutineEntryType.wind:      return 'Wind Down';
    }
  }

  String get emoji {
    switch (this) {
      case RoutineEntryType.wake:      return '🌅';
      case RoutineEntryType.hydration: return '💧';
      case RoutineEntryType.meal:      return '🍽️';
      case RoutineEntryType.activity:  return '⏱️';
      case RoutineEntryType.reminder:  return '🔔';
      case RoutineEntryType.wind:      return '🌙';
    }
  }

  bool get isWake    => this == RoutineEntryType.wake;
  bool get isWater   => this == RoutineEntryType.hydration;
  bool get isMeal    => this == RoutineEntryType.meal;
  bool get isDuration => this == RoutineEntryType.activity;
  bool get isWind    => this == RoutineEntryType.wind;

  String defaultMessage({int? waterMl, int? durationMinutes, String? entryLabel}) {
    switch (this) {
      case RoutineEntryType.wake:
        return "Time to wake up! Start your day strong.";
      case RoutineEntryType.hydration:
        return "Time to hydrate — drink ${waterMl ?? 400} ml of water now.";
      case RoutineEntryType.meal:
        return "${entryLabel ?? 'Meal'} time! Fuel up and log what you eat.";
      case RoutineEntryType.activity:
        return "${entryLabel ?? 'Activity'} starting now.${durationMinutes != null ? ' Duration: $durationMinutes minutes.' : ''}";
      case RoutineEntryType.reminder:
        return "Reminder: ${entryLabel ?? 'time for your task'}.";
      case RoutineEntryType.wind:
        return "Time to wind down and prepare for rest.";
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

  factory RoutineEntry.fromMap(Map<String, dynamic> m) {
    final rawType = m['type'] as String;
    final resolvedType = _migrateTypeName(rawType);
    return RoutineEntry(
      id: m['id'] as String,
      type: resolvedType,
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

  /// Maps old lifestyle-specific type names to new generic ones.
  static RoutineEntryType _migrateTypeName(String name) {
    switch (name) {
      case 'wake':           return RoutineEntryType.wake;
      case 'hydration':      return RoutineEntryType.hydration;
      case 'meal':           return RoutineEntryType.meal;
      case 'activity':       return RoutineEntryType.activity;
      case 'reminder':       return RoutineEntryType.reminder;
      case 'wind':           return RoutineEntryType.wind;
      // Legacy mappings
      case 'wakeUp':         return RoutineEntryType.wake;
      case 'morningWater':   return RoutineEntryType.hydration;
      case 'postWorkoutWater': return RoutineEntryType.hydration;
      case 'waterReminder':  return RoutineEntryType.hydration;
      case 'breakfast':      return RoutineEntryType.meal;
      case 'lunch':          return RoutineEntryType.meal;
      case 'dinner':         return RoutineEntryType.meal;
      case 'snacks':         return RoutineEntryType.meal;
      case 'workout':        return RoutineEntryType.activity;
      case 'gym':            return RoutineEntryType.activity;
      case 'study':          return RoutineEntryType.activity;
      case 'college':        return RoutineEntryType.activity;
      case 'nap':            return RoutineEntryType.activity;
      case 'postGymProtein': return RoutineEntryType.reminder;
      case 'bedtimePrep':    return RoutineEntryType.wind;
      case 'custom':         return RoutineEntryType.reminder;
      default:               return RoutineEntryType.reminder;
    }
  }
}

// ---------------------------------------------------------------------------
// DefaultRoutineTimetable — generic starter schedule
// ---------------------------------------------------------------------------

class DefaultRoutineTimetable {
  DefaultRoutineTimetable._();

  /// Builds a generic daily template that works for anyone.
  ///
  /// Timeline:
  ///  6:30 Wake → 7:00 Hydration (morning, 500ml) → 7:30 Breakfast →
  ///  12:30 Lunch → 3:00 Hydration (afternoon, 400ml) →
  ///  6:00 Evening workout (45 min) → 6:45 Post-workout water (400ml) →
  ///  8:00 Dinner → 9:30 Wind down
  static List<RoutineEntry> build({
    int waterGoalMl = 3000,
    int workoutDurationMinutes = 45,
  }) {
    final perSlotMl = (waterGoalMl / 3).round();
    final entries = <RoutineEntry>[];
    int counter = 1;
    String nextId() => 'default_${counter++}';

    // 1. Wake 6:30 AM = 390 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.wake,
      timeOfDayMinutes: 390,
      label: 'Wake Up',
      message: RoutineEntryType.wake.defaultMessage(),
    ));

    // 2. Morning hydration 7:00 AM = 420 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.hydration,
      timeOfDayMinutes: 420,
      label: 'Morning Water',
      message: RoutineEntryType.hydration.defaultMessage(waterMl: perSlotMl),
      waterMl: perSlotMl,
    ));

    // 3. Breakfast 7:30 AM = 450 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.meal,
      timeOfDayMinutes: 450,
      label: 'Breakfast',
      message: RoutineEntryType.meal.defaultMessage(entryLabel: 'Breakfast'),
    ));

    // 4. Lunch 12:30 PM = 750 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.meal,
      timeOfDayMinutes: 750,
      label: 'Lunch',
      message: RoutineEntryType.meal.defaultMessage(entryLabel: 'Lunch'),
    ));

    // 5. Afternoon hydration 3:00 PM = 900 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.hydration,
      timeOfDayMinutes: 900,
      label: 'Afternoon Water',
      message: RoutineEntryType.hydration.defaultMessage(waterMl: perSlotMl),
      waterMl: perSlotMl,
    ));

    // 6. Evening workout 6:00 PM = 1080 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.activity,
      timeOfDayMinutes: 1080,
      label: 'Evening Workout',
      message: RoutineEntryType.activity.defaultMessage(
        entryLabel: 'Evening Workout',
        durationMinutes: workoutDurationMinutes,
      ),
      durationMinutes: workoutDurationMinutes,
    ));

    // 7. Post-workout hydration 6:45 PM = 1080 + 45 = 1125 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.hydration,
      timeOfDayMinutes: 1080 + workoutDurationMinutes,
      label: 'Post-Workout Water',
      message: RoutineEntryType.hydration.defaultMessage(waterMl: perSlotMl),
      waterMl: perSlotMl,
    ));

    // 8. Dinner 8:00 PM = 1200 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.meal,
      timeOfDayMinutes: 1200,
      label: 'Dinner',
      message: RoutineEntryType.meal.defaultMessage(entryLabel: 'Dinner'),
    ));

    // 9. Wind down 9:30 PM = 1290 min
    entries.add(RoutineEntry(
      id: nextId(),
      type: RoutineEntryType.wind,
      timeOfDayMinutes: 1290,
      label: 'Bedtime Prep',
      message: RoutineEntryType.wind.defaultMessage(),
    ));

    entries.sort((a, b) => a.timeOfDayMinutes.compareTo(b.timeOfDayMinutes));
    return entries;
  }
}
