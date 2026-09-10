/// Sleep tracking — logs a night's bedtime/wake time, computes duration,
/// and can be compared against a configurable sleep floor (the "protect
/// the sleep floor" idea discussed extensively earlier in the project,
/// now actually implemented rather than just designed).
library;

class SleepLog {
  final String id;
  final DateTime bedTime;
  final DateTime wakeTime;
  final int? quality; // optional, 1-5, self-rated

  SleepLog({
    required this.id,
    required this.bedTime,
    required this.wakeTime,
    this.quality,
  });

  Duration get duration => wakeTime.difference(bedTime);

  /// The date this sleep session "belongs to" — conventionally the wake
  /// date, since "last night's sleep" is how people think about it.
  DateTime get forDate =>
      DateTime(wakeTime.year, wakeTime.month, wakeTime.day);

  Map<String, dynamic> toMap() => {
        'id': id,
        'bedTime': bedTime.toIso8601String(),
        'wakeTime': wakeTime.toIso8601String(),
        'quality': quality,
      };

  factory SleepLog.fromMap(Map<String, dynamic> map) => SleepLog(
        id: map['id'] as String,
        bedTime: DateTime.parse(map['bedTime'] as String),
        wakeTime: DateTime.parse(map['wakeTime'] as String),
        quality: map['quality'] as int?,
      );
}