/// Timetable template models.
///
/// A [TimetableEntry] is a reusable task template (no date).
/// When the user applies the timetable to a week or month, the app
/// instantiates actual [Task] records for each day in the range.

import 'task.dart';

class TimetableEntry {
  final String id;
  String name;
  String category;
  int hour;   // 0-23
  int minute; // 0-59
  int estimatedDurationMinutes;
  TaskFlexibility flexibility;

  TimetableEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.hour,
    required this.minute,
    required this.estimatedDurationMinutes,
    this.flexibility = TaskFlexibility.flexible,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'hour': hour,
    'minute': minute,
    'estimatedDurationMinutes': estimatedDurationMinutes,
    'flexibility': flexibility.name,
  };

  factory TimetableEntry.fromMap(Map<String, dynamic> m) => TimetableEntry(
    id: m['id'] as String,
    name: m['name'] as String,
    category: m['category'] as String,
    hour: m['hour'] as int,
    minute: m['minute'] as int,
    estimatedDurationMinutes: m['estimatedDurationMinutes'] as int,
    flexibility: TaskFlexibility.values.firstWhere(
      (f) => f.name == m['flexibility'],
      orElse: () => TaskFlexibility.flexible,
    ),
  );

  /// Instantiates this template as a Task for [date].
  Task toTask({required DateTime date, required String taskId}) {
    final plannedStart = DateTime(date.year, date.month, date.day, hour, minute);
    return Task(
      id: taskId,
      name: name,
      category: category,
      plannedStart: plannedStart,
      estimatedDurationMinutes: estimatedDurationMinutes,
      flexibility: flexibility,
    );
  }
}
