import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/task.dart';
import '../engine/reschedule_engine.dart';
import '../engine/adaptive_learning_engine.dart';
import '../engine/preference_learning_engine.dart';
import '../engine/burnout_forecast_engine.dart';
import '../models/preference_learning_models.dart';
import '../services/tts_service.dart';
import '../services/music_service.dart';
import '../theme/app_theme.dart';
import '../widgets/day_spine_timeline.dart';
import '../widgets/mini_player.dart';
import '../models/workout_models.dart';
import 'add_task_screen.dart';
import 'workout_session_screen.dart';
import 'workout_progress_screen.dart';
import 'workout_plan_editor_screen.dart';
import 'water_tracker_screen.dart';
import 'sleep_tracker_screen.dart';
import 'meal_tracker_screen.dart';
import 'goal_progress_screen.dart';
import 'analytics_screen.dart';
import 'daily_report_screen.dart';
import 'llm_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final db = DatabaseHelper.instance;
  final rescheduleEngine = RescheduleEngine();

  List<Task> _todayTasks = [];
  Task? _activeMusicTask;
  bool _musicPlaying = false;
  int _todayWaterMl = 0;
  int _waterGoalMl = 2500;
  Duration? _lastNightSleep;
  int _mealsLoggedToday = 0;
  int _activeGoalCount = 0;
  BurnoutForecast? _burnoutForecast;
  List<TaskImportanceWeight> _newlyLearnedPrefs = [];
  final Set<String> _dismissedPrefCategories = {};

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    MusicService.instance.init();
    _loadToday();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadToday() async {
    final tasks = await db.getTasksForDay(DateTime.now());
    if (!mounted) return;
    setState(() => _todayTasks = tasks);
    await _loadSummaries();
    await _checkForActiveMoodTask(tasks);
    final forecast = await BurnoutForecastEngine.instance.forecast();
    final allWeights = await PreferenceLearningEngine.instance.getAllWeightsSorted();
    if (!mounted) return;
    setState(() {
      _burnoutForecast = forecast;
      _newlyLearnedPrefs = allWeights
          .where((w) =>
              w.isReliable &&
              !_dismissedPrefCategories.contains(w.taskCategory))
          .take(2)
          .toList();
    });
    _fadeCtrl.forward(from: 0);
  }

  Future<void> _loadSummaries() async {
    final waterMl =
        await DatabaseHelper.instance.getTotalWaterMlForDay(DateTime.now());
    final lastNight = await DatabaseHelper.instance.getLastNightSleep();
    final mealLogs = await db.getMealLogsForDay(DateTime.now());
    final goalPlans = await db.getActiveGoalPlans();
    if (!mounted) return;
    setState(() {
      _todayWaterMl = waterMl;
      _lastNightSleep = lastNight?.duration;
      _mealsLoggedToday = mealLogs.length;
      _activeGoalCount = goalPlans.length;
    });
  }

  Future<void> _checkForActiveMoodTask(List<Task> tasks) async {
    final now = DateTime.now();
    Task? current;
    for (final t in tasks) {
      if (t.moodTag != null &&
          t.status != TaskStatus.completed &&
          now.isAfter(t.plannedStart) &&
          now.isBefore(t.plannedEnd)) {
        current = t;
        break;
      }
    }

    if (current == null) {
      if (!mounted) return;
      setState(() {
        _activeMusicTask = null;
        _musicPlaying = false;
      });
      return;
    }
    if (_activeMusicTask?.id == current.id) return;

    final playlist = await db.getPlaylistForMood(current.moodTag!);
    if (playlist == null) return;
    final tracks = await db.getTracksForIds(playlist.trackIds);
    if (tracks.isEmpty) return;

    await MusicService.instance
        .startForTask(playlist: playlist, tracks: tracks, volume: 0.8);

    if (!mounted) return;
    setState(() {
      _activeMusicTask = current;
      _musicPlaying = true;
    });
  }

  Future<void> _toggleMusic() async {
    if (_musicPlaying) {
      await MusicService.instance.manualPause();
    } else {
      await MusicService.instance.manualResume();
    }
    if (!mounted) return;
    setState(() => _musicPlaying = !_musicPlaying);
  }

  Future<void> _showPlanPicker(BuildContext context) async {
    final plans = await db.getAllWorkoutPlans();
    if (!context.mounted) return;

    final chosen = await showModalBottomSheet<WorkoutPlan>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PlanPickerSheet(plans: plans),
    );

    if (chosen == null || !context.mounted) return;

    final templates = await db.getTemplatesForPlan(chosen.id);
    final todayWeekday = DateTime.now().weekday;
    final todaysTemplate =
        templates.where((t) => t.dayOfWeek == todayWeekday);

    if (todaysTemplate.isEmpty) {
      if (!context.mounted) return;
      final goAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(AppRadius.lg)),
          title: Text('No workout today in "${chosen.name}"'),
          content: const Text(
              'This plan has no session for today. Add one now?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add a day')),
          ],
        ),
      );
      if (goAdd == true && context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  WorkoutPlanEditorScreen(initialPlan: chosen)),
        );
      }
      return;
    }

    if (context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              WorkoutSessionScreen(templateId: todaysTemplate.first.id),
        ),
      );
    }
  }

  Future<void> _checkIn(Task task) async {
    String subtitle = 'Is this done?';

    if (task.actualStart != null) {
      final elapsed =
          DateTime.now().difference(task.actualStart!).inMinutes.toDouble();
      final anomaly =
          await AdaptiveLearningEngine.instance.checkDurationAnomaly(
        taskCategory: task.category,
        elapsedMinutes: elapsed,
      );
      if (!mounted) return;
      if (anomaly.level == AnomalyLevel.mild) {
        subtitle = 'Taking a bit longer than usual — still going?';
      } else if (anomaly.level == AnomalyLevel.strong) {
        subtitle = 'Running significantly longer than your usual pace.';
      }
    }

    if (!mounted) return;
    final isDone = await _showCheckInSheet(
        taskName: task.name, subtitle: subtitle);
    if (isDone == null) return;

    if (isDone) {
      AdaptiveLearningEngine.instance
          .recordInterventionOutcome(InterventionStyle.gentleVoice, success: true);
      await rescheduleEngine.markCompleted(task);
      await TtsService.instance.speak('Nice work finishing ${task.name}.');
    } else {
      if (!mounted) return;
      final extra = await _askExtraTime();
      if (extra == null) return;
      final result = await rescheduleEngine.applyDelay(
          delayedTask: task, delayMinutes: extra);
      if (result.conflictedFixedTask != null) {
        PreferenceLearningEngine.instance.recordConflict(
          keptTaskCategory: result.conflictedFixedTask!.category,
          droppedTaskCategory: task.category,
          reason: 'delay_conflict',
        );
        await TtsService.instance.speak(
            'Heads up — delay runs into ${result.conflictedFixedTask!.name}. Review your schedule.');
      } else if (result.shiftedTasks.isNotEmpty) {
        await TtsService.instance.speak(
            'No problem. Shifted ${result.shiftedTasks.length} tasks by $extra minutes.');
      }
    }
    await _loadToday();
  }

  Future<bool?> _showCheckInSheet(
      {required String taskName, required String subtitle}) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CheckInSheet(taskName: taskName, subtitle: subtitle),
    );
  }

  Future<int?> _askExtraTime() {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExtraTimeSheet(),
    );
  }

  // ─── Computed helpers ────────────────────────────────────────────────────

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  int get _completedCount =>
      _todayTasks.where((t) => t.status == TaskStatus.completed).length;

  double get _progressRatio =>
      _todayTasks.isEmpty ? 0 : _completedCount / _todayTasks.length;

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final dateLabel =
        DateFormat('EEEE, d MMMM').format(DateTime.now()).toUpperCase();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadToday,
          color: isDark ? AppColors.darkDeep : AppColors.deep,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: CustomScrollView(
              slivers: [
                // ── Header ──────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _Header(
                      dateLabel: dateLabel,
                      greeting: _greeting,
                      progressRatio: _progressRatio,
                      completed: _completedCount,
                      total: _todayTasks.length,
                      isDark: isDark,
                    ),
                  ),
                ),

                // ── Mini player ─────────────────────────────────────────
                if (_activeMusicTask != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: MiniPlayer(
                        trackTitle: _activeMusicTask!.name,
                        subtitle:
                            'Now playing · ${_activeMusicTask!.moodTag}',
                        isPlaying: _musicPlaying,
                        onTogglePlay: _toggleMusic,
                      ),
                    ),
                  ),

                // ── Preference confirmation banners ──────────────────────
                if (_newlyLearnedPrefs.isNotEmpty)
                  for (final pref in _newlyLearnedPrefs)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _PrefConfirmBanner(
                          weight: pref,
                          isDark: isDark,
                          onDismiss: () {
                            setState(() {
                              _dismissedPrefCategories.add(pref.taskCategory);
                              _newlyLearnedPrefs = _newlyLearnedPrefs
                                  .where((w) => w.taskCategory != pref.taskCategory)
                                  .toList();
                            });
                          },
                        ),
                      ),
                    ),

                // ── Burnout card ────────────────────────────────────────
                if (_burnoutForecast != null &&
                    _burnoutForecast!.shouldSurface &&
                    _burnoutForecast!.level != BurnoutRiskLevel.low)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _BurnoutCard(
                          forecast: _burnoutForecast!, isDark: isDark),
                    ),
                  ),

                // ── Quick-action grid ───────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _QuickActions(
                      waterMl: _todayWaterMl,
                      waterGoalMl: _waterGoalMl,
                      sleep: _lastNightSleep,
                      meals: _mealsLoggedToday,
                      activeGoals: _activeGoalCount,
                      isDark: isDark,
                      onWorkout: () => _showPlanPicker(context),
                      onProgress: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WorkoutProgressScreen()),
                      ),
                      onWater: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const WaterTrackerScreen()),
                        );
                        await _loadSummaries();
                      },
                      onSleep: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SleepTrackerScreen()),
                        );
                        await _loadSummaries();
                      },
                      onMeals: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MealTrackerScreen()),
                        );
                        await _loadSummaries();
                      },
                      onGoals: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const GoalProgressScreen()),
                        );
                        await _loadSummaries();
                      },
                      onAnalytics: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AnalyticsScreen()),
                      ),
                      onDailyReport: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DailyReportScreen()),
                      ),
                    ),
                  ),
                ),

                // ── Today's tasks heading ───────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                    child: Row(
                      children: [
                        Text(
                          'Today',
                          style: context.text.headlineSmall,
                        ),
                        const Spacer(),
                        if (_todayTasks.isNotEmpty)
                          Text(
                            '$_completedCount / ${_todayTasks.length} done',
                            style: context.text.labelMedium,
                          ),
                      ],
                    ),
                  ),
                ),

                // ── Timeline ────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  sliver: SliverToBoxAdapter(
                    child: DaySpineTimeline(
                      tasks: _todayTasks,
                      onCheckIn: _checkIn,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddTaskScreen()),
          );
          await _loadToday();
        },
        child: const Icon(Icons.add, size: 26),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header widget
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String dateLabel;
  final String greeting;
  final double progressRatio;
  final int completed;
  final int total;
  final bool isDark;

  const _Header({
    required this.dateLabel,
    required this.greeting,
    required this.progressRatio,
    required this.completed,
    required this.total,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: context.text.labelSmall?.copyWith(
                  color: isDark
                      ? AppColors.darkDeep
                      : AppColors.deepLight,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(greeting, style: context.text.displaySmall),
              if (total > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '$completed of $total tasks complete',
                  style: context.text.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          children: [
            _ProgressRing(ratio: progressRatio, isDark: isDark),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LlmSettingsScreen()),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: isDark
                    ? AppColors.darkInkSubtle
                    : AppColors.inkSubtle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final double ratio;
  final bool isDark;

  const _ProgressRing({required this.ratio, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: CustomPaint(
        painter: _RingPainter(
          ratio: ratio,
          trackColor:
              isDark ? AppColors.darkBorder : AppColors.mist,
          fillColor: isDark ? AppColors.darkMoss : AppColors.moss,
        ),
        child: Center(
          child: Text(
            '${(ratio * 100).round()}%',
            style: context.text.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.darkMoss : AppColors.moss,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double ratio;
  final Color trackColor;
  final Color fillColor;

  const _RingPainter(
      {required this.ratio,
      required this.trackColor,
      required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const stroke = 5.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    if (ratio > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * ratio,
        false,
        fillPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.ratio != ratio;
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick-action grid
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final int waterMl;
  final int waterGoalMl;
  final Duration? sleep;
  final int meals;
  final int activeGoals;
  final bool isDark;
  final VoidCallback onWorkout;
  final VoidCallback onProgress;
  final VoidCallback onWater;
  final VoidCallback onSleep;
  final VoidCallback onMeals;
  final VoidCallback onGoals;
  final VoidCallback onAnalytics;
  final VoidCallback onDailyReport;

  const _QuickActions({
    required this.waterMl,
    required this.waterGoalMl,
    required this.sleep,
    required this.meals,
    required this.activeGoals,
    required this.isDark,
    required this.onWorkout,
    required this.onProgress,
    required this.onWater,
    required this.onSleep,
    required this.onMeals,
    required this.onGoals,
    required this.onAnalytics,
    required this.onDailyReport,
  });

  @override
  Widget build(BuildContext context) {
    final sleepLabel = sleep != null
        ? '${sleep!.inHours}h ${sleep!.inMinutes % 60}m'
        : '—';
    final waterLabel =
        '${(waterMl / 1000).toStringAsFixed(1)}L';
    final waterRatio =
        (waterMl / waterGoalMl).clamp(0.0, 1.0);

    return Column(
      children: [
        // Workout hero card
        _WorkoutCard(
          isDark: isDark,
          onStart: onWorkout,
          onProgress: onProgress,
        ),
        const SizedBox(height: 12),
        // Goals card
        _GoalsCard(
          activeGoals: activeGoals,
          isDark: isDark,
          onTap: onGoals,
        ),
        const SizedBox(height: 12),
        // Analytics + Daily Report row
        Row(
          children: [
            Expanded(
              child: _NavCard(
                icon: Icons.bar_chart_rounded,
                label: 'Analytics',
                sub: 'Trends & burnout',
                isDark: isDark,
                onTap: onAnalytics,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NavCard(
                icon: Icons.summarize_rounded,
                label: 'Daily Report',
                sub: 'Summary & alerts',
                isDark: isDark,
                onTap: onDailyReport,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 3-stat row
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.water_drop_rounded,
                iconColor: isDark
                    ? AppColors.darkDeep
                    : AppColors.deepLight,
                value: waterLabel,
                label: 'Water',
                sub: '${(waterRatio * 100).round()}% of goal',
                progressRatio: waterRatio,
                progressColor:
                    isDark ? AppColors.darkDeep : AppColors.deepLight,
                isDark: isDark,
                onTap: onWater,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.bedtime_rounded,
                iconColor:
                    isDark ? AppColors.darkMoss : AppColors.moss,
                value: sleepLabel,
                label: 'Sleep',
                sub: 'Last night',
                isDark: isDark,
                onTap: onSleep,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.restaurant_rounded,
                iconColor:
                    isDark ? AppColors.darkAmber : AppColors.amber,
                value: '$meals',
                label: 'Meals',
                sub: 'Today',
                isDark: isDark,
                onTap: onMeals,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool isDark;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.label,
    required this.sub,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkCard : AppColors.cardSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.mist;
    final accent = isDark ? AppColors.darkDeep : AppColors.deep;
    final iconBg = isDark ? const Color(0xFF1D2535) : const Color(0xFFEEF2FF);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.all(AppRadius.lg),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: const BorderRadius.all(AppRadius.sm),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.text.titleSmall),
                  const SizedBox(height: 1),
                  Text(sub,
                      style: context.text.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalsCard extends StatelessWidget {
  final int activeGoals;
  final bool isDark;
  final VoidCallback onTap;

  const _GoalsCard({
    required this.activeGoals,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkCard : AppColors.cardSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.mist;
    final iconBg = isDark ? const Color(0xFF1D2535) : const Color(0xFFEEF2FF);
    final accent = isDark ? AppColors.darkDeep : AppColors.deep;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.all(AppRadius.lg),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: const BorderRadius.all(AppRadius.md),
              ),
              child: Icon(
                Icons.flag_rounded,
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Goals', style: context.text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    activeGoals == 0
                        ? 'No active goals — tap to add one'
                        : '$activeGoals active ${activeGoals == 1 ? 'goal' : 'goals'}',
                    style: context.text.bodyMedium,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  final bool isDark;
  final VoidCallback onStart;
  final VoidCallback onProgress;

  const _WorkoutCard({
    required this.isDark,
    required this.onStart,
    required this.onProgress,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkCard : AppColors.cardSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.mist;
    final iconBg = isDark
        ? const Color(0xFF1A2E1E)
        : AppColors.mossLight;

    return GestureDetector(
      onTap: onStart,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.all(AppRadius.lg),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: const BorderRadius.all(AppRadius.md),
              ),
              child: Icon(
                Icons.fitness_center_rounded,
                color: isDark ? AppColors.darkMoss : AppColors.moss,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Today's Workout",
                      style: context.text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to start or resume your session',
                    style: context.text.bodyMedium,
                  ),
                ],
              ),
            ),
            Column(
              children: [
                GestureDetector(
                  onTap: onStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkMoss
                          : AppColors.moss,
                      borderRadius: const BorderRadius.all(AppRadius.sm),
                    ),
                    child: Text(
                      'Start',
                      style: context.text.labelSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onProgress,
                  child: Text(
                    'Progress →',
                    style: context.text.labelSmall?.copyWith(
                      color: isDark
                          ? AppColors.darkDeep
                          : AppColors.deepLight,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String sub;
  final double? progressRatio;
  final Color? progressColor;
  final bool isDark;
  final VoidCallback onTap;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.sub,
    this.progressRatio,
    this.progressColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkCard : AppColors.cardSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.mist;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(height: 10),
            Text(
              value,
              style: context.text.headlineSmall?.copyWith(fontSize: 17),
            ),
            const SizedBox(height: 2),
            Text(label, style: context.text.labelSmall),
            if (progressRatio != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: const BorderRadius.all(AppRadius.sm),
                child: LinearProgressIndicator(
                  value: progressRatio,
                  minHeight: 3,
                  backgroundColor:
                      isDark ? AppColors.darkBorder : AppColors.mist,
                  valueColor:
                      AlwaysStoppedAnimation(progressColor!),
                ),
              ),
              const SizedBox(height: 4),
              Text(sub, style: context.text.bodySmall),
            ] else ...[
              const SizedBox(height: 2),
              Text(sub, style: context.text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preference confirmation banner
// ─────────────────────────────────────────────────────────────────────────────

class _PrefConfirmBanner extends StatelessWidget {
  final TaskImportanceWeight weight;
  final bool isDark;
  final VoidCallback onDismiss;

  const _PrefConfirmBanner({
    required this.weight,
    required this.isDark,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.darkDeep : AppColors.deep;
    final bg = isDark ? const Color(0xFF1D2535) : const Color(0xFFEEF2FF);
    final pct = (weight.weight * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You tend to prioritize ${weight.taskCategory}',
                  style: context.text.titleSmall?.copyWith(color: accent),
                ),
                const SizedBox(height: 2),
                Text(
                  'Learned from ${weight.sampleCount} sessions · $pct% importance',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            ),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Burnout card
// ─────────────────────────────────────────────────────────────────────────────

class _BurnoutCard extends StatelessWidget {
  final BurnoutForecast forecast;
  final bool isDark;

  const _BurnoutCard({required this.forecast, required this.isDark});

  Color get _bg => switch (forecast.level) {
        BurnoutRiskLevel.low  => AppColors.burnoutLow(isDark),
        BurnoutRiskLevel.moderate => AppColors.burnoutMid(isDark),
        BurnoutRiskLevel.high => AppColors.burnoutHigh(isDark),
      };

  Color get _accent => switch (forecast.level) {
        BurnoutRiskLevel.low  =>
          isDark ? AppColors.darkMoss : AppColors.moss,
        BurnoutRiskLevel.moderate =>
          isDark ? AppColors.darkAmber : AppColors.amber,
        BurnoutRiskLevel.high =>
          isDark ? AppColors.darkClay : AppColors.clay,
      };

  IconData get _icon => switch (forecast.level) {
        BurnoutRiskLevel.low      => Icons.check_circle_outline_rounded,
        BurnoutRiskLevel.moderate => Icons.info_outline_rounded,
        BurnoutRiskLevel.high     => Icons.warning_amber_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  forecast.level == BurnoutRiskLevel.high
                      ? 'High recovery load'
                      : 'Recovery load building',
                  style: context.text.titleSmall
                      ?.copyWith(color: _accent),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.all(AppRadius.pill),
                ),
                child: Text(
                  '${(forecast.confidence * 100).round()}%',
                  style: context.text.labelSmall
                      ?.copyWith(color: _accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(forecast.summary, style: context.text.bodyMedium),
          if (forecast.contributingReasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in forecast.contributingReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('·  ',
                        style: TextStyle(
                            color: _accent, fontWeight: FontWeight.w700)),
                    Expanded(
                        child: Text(r,
                            style: context.text.bodySmall)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plan picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PlanPickerSheet extends StatelessWidget {
  final List<WorkoutPlan> plans;
  const _PlanPickerSheet({required this.plans});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBorder
                      : AppColors.mist,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Choose a plan', style: context.text.titleLarge),
            const SizedBox(height: 16),
            for (final plan in plans)
              ListTile(
                title: Text(plan.name),
                subtitle: plan.referenceNotes != null
                    ? Text(plan.referenceNotes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis)
                    : null,
                trailing: Icon(Icons.chevron_right,
                    color: isDark
                        ? AppColors.darkDeep
                        : AppColors.deepLight),
                onTap: () => Navigator.pop(context, plan),
              ),
            Divider(
                color: isDark
                    ? AppColors.darkBorder
                    : AppColors.mist),
            ListTile(
              leading: Icon(Icons.tune_rounded,
                  color:
                      isDark ? AppColors.darkDeep : AppColors.deep),
              title: const Text('Manage plans'),
              subtitle:
                  const Text('Add, edit, or remove plans and days'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const WorkoutPlanEditorScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Check-in sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CheckInSheet extends StatelessWidget {
  final String taskName;
  final String subtitle;

  const _CheckInSheet({required this.taskName, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBorder : AppColors.mist,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1A2E1E)
                  : AppColors.mossLight,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.task_alt_rounded,
                color:
                    isDark ? AppColors.darkMoss : AppColors.moss,
                size: 26),
          ),
          const SizedBox(height: 16),
          Text(taskName,
              style: context.text.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(subtitle,
              style: context.text.bodyMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not yet'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done ✓'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Extra time sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ExtraTimeSheet extends StatefulWidget {
  const _ExtraTimeSheet();

  @override
  State<_ExtraTimeSheet> createState() => _ExtraTimeSheetState();
}

class _ExtraTimeSheetState extends State<_ExtraTimeSheet> {
  int _selected = 15;
  final _options = const [5, 15, 30, 60];

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color:
                    isDark ? AppColors.darkBorder : AppColors.mist,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('How much more time?', style: context.text.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Later tasks will shift accordingly.',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _options)
                _TimeChip(
                  label: m < 60 ? '$m min' : '1 hour',
                  selected: _selected == m,
                  isDark: isDark,
                  onTap: () => setState(() => _selected = m),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: const Text('Confirm — shift later tasks'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _TimeChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? AppColors.darkDeep : AppColors.deep;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.mist;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          border: Border.all(
              color: selected ? activeColor : borderColor),
          borderRadius: const BorderRadius.all(AppRadius.pill),
        ),
        child: Text(
          label,
          style: context.text.labelMedium?.copyWith(
            color: selected
                ? (isDark ? AppColors.darkCanvas : Colors.white)
                : (isDark
                    ? AppColors.darkInkSubtle
                    : AppColors.inkSubtle),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
