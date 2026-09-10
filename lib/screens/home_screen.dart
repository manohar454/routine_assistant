import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/task.dart';
import '../engine/reschedule_engine.dart';
import '../engine/adaptive_learning_engine.dart';
import '../engine/burnout_forecast_engine.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final db = DatabaseHelper.instance;
  final rescheduleEngine = RescheduleEngine();
  List<Task> _todayTasks = [];
  Task? _activeMusicTask;
  bool _musicPlaying = false;
  int _todayWaterMl = 0;
  Duration? _lastNightSleep;
  int _mealsLoggedToday = 0;
  BurnoutForecast? _burnoutForecast;

  @override
  void initState() {
    super.initState();
    MusicService.instance.init();
    _loadToday();
  }

  Future<void> _loadToday() async {
    final tasks = await db.getTasksForDay(DateTime.now());
    if (!mounted) return;
    setState(() => _todayTasks = tasks);
    await _loadWaterAndSleepSummary();
    await _checkForActiveMoodTask(tasks);

    final forecast = await BurnoutForecastEngine.instance.forecast();
    if (!mounted) return;
    setState(() => _burnoutForecast = forecast);
  }

  Future<void> _loadWaterAndSleepSummary() async {
    final waterMl = await DatabaseHelper.instance.getTotalWaterMlForDay(DateTime.now());
    final lastNight = await DatabaseHelper.instance.getLastNightSleep();
    final mealLogs = await db.getMealLogsForDay(DateTime.now());
    if (!mounted) return;
    setState(() {
      _todayWaterMl = waterMl;
      _lastNightSleep = lastNight?.duration;
      _mealsLoggedToday = mealLogs.length;
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
    setState(() => _musicPlaying = !_musicPlaying);
  }

  /// Lets the person pick which plan is active right now (Gym/Home/
  /// Transformation), per the "all of them, selectable" decision — then
  /// finds today's day-of-week template within that plan and launches it.
  Future<void> _showPlanPicker(BuildContext context) async {
    final plans = await db.getAllWorkoutPlans();
    if (!context.mounted) return;

    final chosen = await showModalBottomSheet<WorkoutPlan>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // Scrollable so any number of plans (or a small screen) never
        // overflows — this was rendering an actual RenderFlex overflow
        // banner before, since the Column had no scroll fallback.
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
                    color: AppColors.mist,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Choose a plan', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              for (final plan in plans)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(plan.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: plan.referenceNotes != null
                      ? Text(plan.referenceNotes!,
                          maxLines: 2, overflow: TextOverflow.ellipsis)
                      : null,
                  trailing: const Icon(Icons.chevron_right, color: AppColors.deepLight),
                  onTap: () => Navigator.pop(ctx, plan),
                ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune, color: AppColors.deep),
                title: const Text('Manage plans',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Add, edit, or remove plans and days'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WorkoutPlanEditorScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen == null || !context.mounted) return;

    final templates = await db.getTemplatesForPlan(chosen.id);
    final todayWeekday = DateTime.now().weekday; // 1=Mon ... 7=Sun
    final todaysTemplate = templates.where((t) => t.dayOfWeek == todayWeekday);

    if (todaysTemplate.isEmpty) {
      // Previously this silently did nothing — exactly what looked like
      // "the plan won't open." Now it explains why and offers the fix.
      if (!context.mounted) return;
      final goAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('No day set for today in "${chosen.name}"'),
          content: const Text(
              'This plan doesn\'t have a workout configured for today yet. Add one?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add a day')),
          ],
        ),
      );
      if (goAdd == true && context.mounted) {
        final nav = Navigator.of(context);
        if (!context.mounted) return;

        await nav.push(
          MaterialPageRoute(
            builder: (_) => WorkoutPlanEditorScreen(initialPlan: chosen),
          ),
        );
      }
    }

    if (context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkoutSessionScreen(templateId: todaysTemplate.first.id),
        ),
      );
    }
  }

  Future<void> _checkIn(Task task) async {
    // Phase 2: check if this task is running abnormally long BEFORE
    // showing the modal — this drives the framing of the question.
    String checkInSubtitle = 'Is this done?';

    if (task.actualStart != null) {
      final elapsedMinutes =
          DateTime.now().difference(task.actualStart!).inMinutes.toDouble();
      final anomaly =
          await AdaptiveLearningEngine.instance.checkDurationAnomaly(
        taskCategory: task.category,
        elapsedMinutes: elapsedMinutes,
      );

      if (!mounted) return;

      if (anomaly.level == AnomalyLevel.mild) {
        checkInSubtitle = 'Taking a bit longer than usual — still going?';
      } else if (anomaly.level == AnomalyLevel.strong) {
        checkInSubtitle =
            'This is running significantly longer than your usual pace.';
      }
    }

    if (!mounted) return;

    // Keep the BuildContext usage inside a separate synchronous helper.
    // This avoids use_build_context_synchronously after the adaptive
    // engine's await above.
    final isDone = await _showCheckInSheet(
      taskName: task.name,
      subtitle: checkInSubtitle,
    );

    if (isDone == null) return;

    if (isDone) {
      AdaptiveLearningEngine.instance.recordInterventionOutcome(
        InterventionStyle.gentleVoice,
        success: true,
      );
      await rescheduleEngine.markCompleted(task);
      await TtsService.instance.speak('Nice work finishing ${task.name}.');
    } else {
      if (!mounted) return;
      final extraMinutes = await _askExtraTime();
      if (extraMinutes == null) return;

      final result = await rescheduleEngine.applyDelay(
        delayedTask: task,
        delayMinutes: extraMinutes,
      );

      if (result.conflictedFixedTask != null) {
        await TtsService.instance.speak(
          'Heads up — this delay runs into your fixed task, '
          '${result.conflictedFixedTask!.name}. Please review your schedule.',
        );
      } else if (result.shiftedTasks.isNotEmpty) {
        await TtsService.instance.speak(
          'No problem. I have shifted ${result.shiftedTasks.length} '
          'later tasks by $extraMinutes minutes.',
        );
      }
    }

    await _loadToday();
  }

  Future<bool?> _showCheckInSheet({
    required String taskName,
    required String subtitle,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CheckInSheet(
        taskName: taskName,
        subtitle: subtitle,
      ),
    );
  }

  Future<int?> _askExtraTime() async {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _ExtraTimeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dateLabel = DateFormat('EEEE, MMMM d').format(DateTime.now());

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadToday,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              Text(dateLabel.toUpperCase(), style: textTheme.labelSmall),
              const SizedBox(height: 4),
              Text('Good morning', style: textTheme.displaySmall),
              const SizedBox(height: 20),
              if (_activeMusicTask != null) ...[
                MiniPlayer(
                  trackTitle: _activeMusicTask!.name,
                  subtitle: 'Now playing · ${_activeMusicTask!.moodTag}',
                  isPlaying: _musicPlaying,
                  onTogglePlay: _toggleMusic,
                ),
                const SizedBox(height: 20),
              ],
              _WorkoutQuickStart(
                onTap: () async {
                  if (context.mounted) await _showPlanPicker(context);
                },
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WorkoutProgressScreen()),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('View progress',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.deepLight)),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward, size: 14, color: AppColors.deepLight),
                    ],
                  ),
                ),
              ),
              if (_burnoutForecast != null &&
                  _burnoutForecast!.shouldSurface &&
                  _burnoutForecast!.level != BurnoutRiskLevel.low)
                _BurnoutCard(forecast: _burnoutForecast!),
              if (_burnoutForecast != null &&
                  _burnoutForecast!.shouldSurface &&
                  _burnoutForecast!.level != BurnoutRiskLevel.low)
                const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.water_drop,
                      iconColor: AppColors.deepLight,
                      title: '${(_todayWaterMl / 1000).toStringAsFixed(1)}L',
                      subtitle: 'Water today',
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const WaterTrackerScreen()));
                        await _loadWaterAndSleepSummary();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.bedtime,
                      iconColor: AppColors.moss,
                      title: _lastNightSleep != null ? '${_lastNightSleep!.inHours}h${_lastNightSleep!.inMinutes % 60}m' : '—',
                      subtitle: 'Sleep last night',
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const SleepTrackerScreen()));
                        await _loadWaterAndSleepSummary();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.restaurant,
                      iconColor: AppColors.amber,
                      title: '$_mealsLoggedToday',
                      subtitle: 'Meals today',
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MealTrackerScreen()));
                        await _loadWaterAndSleepSummary();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DaySpineTimeline(tasks: _todayTasks, onCheckIn: _checkIn),
            ],
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
        child: const Icon(Icons.add),
      ),
    );
  }
}


class _BurnoutCard extends StatelessWidget {
  final BurnoutForecast forecast;
  const _BurnoutCard({required this.forecast});

  Color get _cardColor {
    switch (forecast.level) {
      case BurnoutRiskLevel.low:
        return const Color(0xFFEFF3EE);
      case BurnoutRiskLevel.moderate:
        return const Color(0xFFFBF3E8);
      case BurnoutRiskLevel.high:
        return const Color(0xFFFBEAE0);
    }
  }

  Color get _iconColor {
    switch (forecast.level) {
      case BurnoutRiskLevel.low:
        return AppColors.moss;
      case BurnoutRiskLevel.moderate:
        return AppColors.amber;
      case BurnoutRiskLevel.high:
        return AppColors.clay;
    }
  }

  IconData get _icon {
    switch (forecast.level) {
      case BurnoutRiskLevel.low:
        return Icons.check_circle_outline;
      case BurnoutRiskLevel.moderate:
        return Icons.info_outline;
      case BurnoutRiskLevel.high:
        return Icons.warning_amber_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                forecast.level == BurnoutRiskLevel.high
                    ? 'High recovery load'
                    : 'Recovery load building',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _iconColor,
                ),
              ),
              const Spacer(),
              Text(
                '${(forecast.confidence * 100).toStringAsFixed(0)}% confidence',
                style: textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(forecast.summary, style: textTheme.bodyMedium),
          if (forecast.contributingReasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final reason in forecast.contributingReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Text(
                        reason,
                        style: textTheme.bodyMedium?.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CheckInSheet extends StatelessWidget {
  final String taskName;
  final String subtitle;

  const _CheckInSheet({
    required this.taskName,
    this.subtitle = 'Is this done?',
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.mist,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF3EE),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.task_alt, color: AppColors.moss, size: 24),
          ),
          const SizedBox(height: 16),
          Text(subtitle, style: textTheme.titleLarge),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.mist),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Not yet'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExtraTimeSheet extends StatefulWidget {
  const _ExtraTimeSheet();

  @override
  State<_ExtraTimeSheet> createState() => _ExtraTimeSheetState();
}

class _ExtraTimeSheetState extends State<_ExtraTimeSheet> {
  int _selected = 15;
  final options = const [5, 15, 30];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                color: AppColors.mist,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('How much more time?', style: textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final m in options)
                _TimeChip(
                  label: '$m min',
                  selected: _selected == m,
                  onTap: () => setState(() => _selected = m),
                ),
            ],
          ),
          const SizedBox(height: 20),
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
  final VoidCallback onTap;
  const _TimeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.deep : Colors.transparent,
          border: Border.all(color: selected ? AppColors.deep : AppColors.mist),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? AppColors.canvas : AppColors.deepLight,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SummaryCard({required this.icon, required this.iconColor, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.cardSurface, border: Border.all(color: AppColors.mist), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontFamily: 'Fraunces', fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.deep)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A80))),
        ]),
      ),
    );
  }
}

/// A simple entry card into the workout module. This stands in for the
/// full Monthly Template Editor screen (a separate future piece) — for
/// now it launches (or resumes) today's demo Push Day session directly.
class _WorkoutQuickStart extends StatelessWidget {
  final VoidCallback onTap;
  const _WorkoutQuickStart({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.mist),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF3EE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.fitness_center, color: AppColors.moss),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Push Day',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  SizedBox(height: 2),
                  Text('Tap to start or resume today\'s workout',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8A8A80))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.deepLight),
          ],
        ),
      ),
    );
  }
}
