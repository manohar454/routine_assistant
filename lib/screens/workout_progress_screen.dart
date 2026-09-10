import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/workout_models.dart';
import '../theme/app_theme.dart';

/// Answers "did I complete today's/this week's plan" and shows the
/// progress picture the person actually asked to see — a real streak
/// count and a week-at-a-glance, derived directly from completed
/// WorkoutSession records rather than a separate tracked flag.
class WorkoutProgressScreen extends StatefulWidget {
  const WorkoutProgressScreen({super.key});

  @override
  State<WorkoutProgressScreen> createState() => _WorkoutProgressScreenState();
}

class _WorkoutProgressScreenState extends State<WorkoutProgressScreen> {
  final db = DatabaseHelper.instance;
  bool _loading = true;
  List<WorkoutSession> _sessions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions =
        await db.getCompletedSessionsSince(DateTime.now().subtract(const Duration(days: 90)));
        if (!mounted) return; 
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  Set<DateTime> get _completedDays => _sessions
      .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
      .toSet();

  bool _wasCompleted(DateTime day) =>
      _completedDays.contains(DateTime(day.year, day.month, day.day));

  int get _currentStreak {
    int streak = 0;
    var day = DateTime.now();
    // Today doesn't have to be done yet for the streak to still count —
    // only check backward from yesterday if today isn't logged yet.
    if (!_wasCompleted(day)) day = day.subtract(const Duration(days: 1));
    while (_wasCompleted(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final weekDays = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));

    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('Progress')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text('Your workout progress', style: textTheme.displaySmall),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: _statCard('$_currentStreak', 'day streak')),
                const SizedBox(width: 12),
                Expanded(child: _statCard('${_sessions.length}', 'sessions (90d)')),
              ],
            ),
            const SizedBox(height: 24),

            Text('This week', style: textTheme.titleLarge?.copyWith(fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final day in weekDays) _dayDot(day),
              ],
            ),
            const SizedBox(height: 24),

            Text('Recent sessions', style: textTheme.titleLarge?.copyWith(fontSize: 16)),
            const SizedBox(height: 12),
            if (_sessions.isEmpty)
              const Text('No completed sessions yet — finish a workout to see it here.')
            else
              for (final s in _sessions.take(10))
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    border: Border.all(color: AppColors.mist),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.moss, size: 20),
                      const SizedBox(width: 10),
                      Text('${s.date.day}/${s.date.month}/${s.date.year}'),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.mist),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Fraunces', fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.deep)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A80))),
        ],
      ),
    );
  }

  Widget _dayDot(DateTime day) {
    final done = _wasCompleted(day);
    final isToday = day.day == DateTime.now().day &&
        day.month == DateTime.now().month &&
        day.year == DateTime.now().year;
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? AppColors.moss : Colors.transparent,
            border: Border.all(
              color: isToday ? AppColors.deep : AppColors.mist,
              width: isToday ? 2 : 1,
            ),
          ),
          child: done ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
        ),
        const SizedBox(height: 4),
        Text(labels[day.weekday - 1],
            style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A80))),
      ],
    );
  }
}
