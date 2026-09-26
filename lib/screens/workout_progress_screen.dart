import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/workout_models.dart';
import '../theme/app_theme.dart';

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
    final sessions = await db.getCompletedSessionsSince(
        DateTime.now().subtract(const Duration(days: 90)));
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
    if (!_wasCompleted(day)) day = day.subtract(const Duration(days: 1));
    while (_wasCompleted(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  List<DateTime> get _weekDays {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dark = context.isDark;
    final weekDays = _weekDays;
    final streak = _currentStreak;

    return Scaffold(
      backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: dark ? AppColors.darkInk : AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Progress',
          style: context.text.titleLarge?.copyWith(
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          20, AppSpacing.md,
          20, 60,
        ),
        children: [
          // ── Headline ──────────────────────────────────────────────────
          Text(
            'Your progress',
            style: context.text.displaySmall?.copyWith(
              color: dark ? AppColors.darkInk : AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Stat cards ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  value: '$streak',
                  label: 'day streak',
                  icon: Icons.local_fire_department_rounded,
                  accent: dark ? AppColors.darkAmber : AppColors.amber,
                  dark: dark,
                  onText: context.text,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  value: '${_sessions.length}',
                  label: '90-day sessions',
                  icon: Icons.fitness_center_rounded,
                  accent: dark ? AppColors.darkDeep : AppColors.deep,
                  dark: dark,
                  onText: context.text,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Week view ─────────────────────────────────────────────────
          Text(
            'THIS WEEK',
            style: context.text.labelSmall?.copyWith(
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weekDays.map((day) {
              final done = _wasCompleted(day);
              final isToday = day.day == DateTime.now().day &&
                  day.month == DateTime.now().month &&
                  day.year == DateTime.now().year;
              const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

              return Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? (dark ? AppColors.darkMoss : AppColors.moss)
                          : Colors.transparent,
                      border: Border.all(
                        color: isToday && !done
                            ? (dark ? AppColors.darkDeep : AppColors.deep)
                            : done
                                ? Colors.transparent
                                : (dark
                                    ? AppColors.darkBorder
                                    : AppColors.mist),
                        width: isToday && !done ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: done
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 16)
                        : isToday
                            ? Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color:
                                      dark ? AppColors.darkDeep : AppColors.deep,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[day.weekday - 1],
                    style: context.text.labelSmall?.copyWith(
                      color: isToday
                          ? (dark ? AppColors.darkDeep : AppColors.deep)
                          : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Recent sessions ───────────────────────────────────────────
          Text(
            'RECENT SESSIONS',
            style: context.text.labelSmall?.copyWith(
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          if (_sessions.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: dark ? AppColors.darkCard : AppColors.cardSurface,
                borderRadius: const BorderRadius.all(AppRadius.md),
                border: Border.all(
                    color: dark ? AppColors.darkBorder : AppColors.mist),
              ),
              child: Column(
                children: [
                  Icon(Icons.fitness_center_rounded,
                      size: 32,
                      color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'No sessions yet',
                    style: context.text.bodyMedium?.copyWith(
                      color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._sessions.take(20).map((s) {
              final durMin = s.endTime != null
                  ? s.endTime!.difference(s.startTime).inMinutes
                  : 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: dark ? AppColors.darkCard : AppColors.cardSurface,
                    borderRadius: const BorderRadius.all(AppRadius.md),
                    border: Border.all(
                        color: dark ? AppColors.darkBorder : AppColors.mist),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: (dark ? AppColors.darkMoss : AppColors.moss)
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check_rounded,
                            size: 16,
                            color: dark ? AppColors.darkMoss : AppColors.moss),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '${s.date.day}/${s.date.month}/${s.date.year}',
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: dark ? AppColors.darkInk : AppColors.ink,
                          ),
                        ),
                      ),
                      if (durMin > 0)
                        Text(
                          '$durMin min',
                          style: context.text.labelSmall?.copyWith(
                            color: dark
                                ? AppColors.darkInkSubtle
                                : AppColors.inkSubtle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color accent;
  final bool dark;
  final TextTheme onText;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
    required this.dark,
    required this.onText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(
            color: dark ? AppColors.darkBorder : AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: onText.headlineMedium?.copyWith(
              color: dark ? AppColors.darkInk : AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: onText.labelSmall?.copyWith(
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            ),
          ),
        ],
      ),
    );
  }
}
