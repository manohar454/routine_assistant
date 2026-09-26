/// Core Task model — Phase 1 minimum core, plus moodTag for the music module.

library;

enum TaskFlexibility { fixed, flexible }

enum TaskStatus { pending, inProgress, completed, skipped }

class Task {
  final String id;

  String name;

  String category;

  DateTime plannedStart;

  int estimatedDurationMinutes;

  DateTime? actualStart;

  DateTime? actualEnd;

  TaskStatus status;

  TaskFlexibility flexibility;

  String? voiceMessage;

  String? moodTag;

  Task({
    required this.id,
    required this.name,
    required this.category,
    required this.plannedStart,
    required this.estimatedDurationMinutes,
    this.actualStart,
    this.actualEnd,
    this.status = TaskStatus.pending,
    this.flexibility = TaskFlexibility.flexible,
    this.voiceMessage,
    this.moodTag,
  });

  DateTime get plannedEnd =>
      plannedStart.add(Duration(minutes: estimatedDurationMinutes));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'plannedStart': plannedStart.toIso8601String(),
      'estimatedDurationMinutes': estimatedDurationMinutes,
      'actualStart': actualStart?.toIso8601String(),
      'actualEnd': actualEnd?.toIso8601String(),
      'status': status.name,
      'flexibility': flexibility.name,
      'voiceMessage': voiceMessage,
      'moodTag': moodTag,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      plannedStart: DateTime.parse(map['plannedStart'] as String),
      estimatedDurationMinutes: map['estimatedDurationMinutes'] as int,
      actualStart: map['actualStart'] != null
          ? DateTime.parse(map['actualStart'] as String)
          : null,
      actualEnd: map['actualEnd'] != null
          ? DateTime.parse(map['actualEnd'] as String)
          : null,
      status: TaskStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => TaskStatus.pending,
      ),
      flexibility: TaskFlexibility.values.firstWhere(
        (f) => f.name == map['flexibility'],
        orElse: () => TaskFlexibility.flexible,
      ),
      voiceMessage: map['voiceMessage'] as String?,
      moodTag: map['moodTag'] as String?,
    );
  }
}
