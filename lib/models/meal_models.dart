/// Meal tracking — deliberately lightweight, matching water/sleep: log
/// what you ate and when, per meal type. No calorie/macro counting (that
/// was never actually requested — the original ask was meal timing and
/// basic completion, not a full nutrition-calculation system).
library;

enum MealType { breakfast, lunch, dinner, snack }

class MealLog {
  final String id;
  final MealType mealType;
  final String description;
  final DateTime timestamp;
  final String? notes; // e.g. "soaked chia seeds", "extra protein"

  MealLog({
    required this.id,
    required this.mealType,
    required this.description,
    required this.timestamp,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'mealType': mealType.name,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'notes': notes,
      };

  factory MealLog.fromMap(Map<String, dynamic> map) => MealLog(
        id: map['id'] as String,
        mealType: MealType.values.firstWhere((t) => t.name == map['mealType']),
        description: map['description'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        notes: map['notes'] as String?,
      );
}