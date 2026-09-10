/// Water tracking — deliberately simple: log amounts, compare to a daily
/// goal. This was the very first thing described for this whole project
/// (hourly water reminders), so it's kept lightweight on purpose rather
/// than over-engineered.
library;

class WaterLog {
  final String id;
  final int amountMl;
  final DateTime timestamp;

  WaterLog({
    required this.id,
    required this.amountMl,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'amountMl': amountMl,
        'timestamp': timestamp.toIso8601String(),
      };

  factory WaterLog.fromMap(Map<String, dynamic> map) => WaterLog(
        id: map['id'] as String,
        amountMl: map['amountMl'] as int,
        timestamp: DateTime.parse(map['timestamp'] as String),
      );
}