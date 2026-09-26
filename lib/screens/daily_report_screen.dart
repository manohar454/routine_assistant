import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../db/database_helper.dart';
import '../engine/burnout_forecast_engine.dart';
import '../models/goal_models.dart';
import '../models/task.dart';
import '../models/sleep_models.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

// ── Notification IDs ─────────────────────────────────────────────────────────
const _kDailyReportNotifId = 77777;
const _kSettingReportHour = 'daily_report_hour';
const _kSettingReportMinute = 'daily_report_minute';
const _kSettingReportEnabled = 'daily_report_enabled';

/// Schedules (or cancels) the daily summary notification.
Future<void> scheduleDailyReport({
  required int hour,
  required int minute,
  required bool enabled,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.cancel(_kDailyReportNotifId);

  if (!enabled) return;

  final db = DatabaseHelper.instance;
  await db.setSetting(_kSettingReportHour, hour.toString());
  await db.setSetting(_kSettingReportMinute, minute.toString());
  await db.setSetting(_kSettingReportEnabled, enabled ? '1' : '0');

  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute);
  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }

  const androidDetails = AndroidNotificationDetails(
    'daily_report_channel',
    'Daily Summary',
    channelDescription: 'Your end-of-day routine summary',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );
  const details = NotificationDetails(android: androidDetails);

  await plugin.zonedSchedule(
    _kDailyReportNotifId,
    'Daily Summary Ready',
    'Tap to see how your day went.',
    scheduled,
    details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseHelper.instance;

  bool _loading = true;

  // Today's summary data
  List<Task> _tasks = [];
  int _completedTasks = 0;
  int _totalTasks = 0;
  int _waterMl = 0;
  SleepLog? _lastSleep;
  List<GoalPlan> _activeGoals = [];
  BurnoutForecast? _burnout;

  // Schedule settings
  bool _reportEnabled = false;
  int _reportHour = 21;
  int _reportMinute = 0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();

    final tasks = await _db.getTasksForDay(now);
    final water = await _db.getTotalWaterMlForDay(now);
    final sleep = await _db.getLastNightSleep();
    final goals = await _db.getActiveGoalPlans();
    final burnout = await BurnoutForecastEngine.instance.forecast();

    // Load schedule settings
    final enabledStr = await _db.getSetting(_kSettingReportEnabled);
    final hourStr = await _db.getSetting(_kSettingReportHour);
    final minuteStr = await _db.getSetting(_kSettingReportMinute);

    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _completedTasks =
          tasks.where((t) => t.status == TaskStatus.completed).length;
      _totalTasks = tasks.length;
      _waterMl = water;
      _lastSleep = sleep;
      _activeGoals = goals;
      _burnout = burnout;
      _reportEnabled = enabledStr == '1';
      _reportHour = int.tryParse(hourStr ?? '21') ?? 21;
      _reportMinute = int.tryParse(minuteStr ?? '0') ?? 0;
      _loading = false;
    });
  }

  Future<void> _toggleEnabled(bool val) async {
    setState(() => _reportEnabled = val);
    await _db.setSetting(_kSettingReportEnabled, val ? '1' : '0');
    await scheduleDailyReport(
      hour: _reportHour,
      minute: _reportMinute,
      enabled: val,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(val
              ? 'Daily report scheduled for ${_fmt(_reportHour, _reportMinute)}'
              : 'Daily report notification disabled'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reportHour, minute: _reportMinute),
    );
    if (picked == null) return;
    setState(() {
      _reportHour = picked.hour;
      _reportMinute = picked.minute;
    });
    await scheduleDailyReport(
      hour: _reportHour,
      minute: _reportMinute,
      enabled: _reportEnabled,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report time set to ${_fmt(_reportHour, _reportMinute)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _fmt(int h, int m) {
    final period = h < 12 ? 'AM' : 'PM';
    final hour = h == 0 ? 12 : h > 12 ? h - 12 : h;
    final min = m.toString().padLeft(2, '0');
    return '$hour:$min $period';
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final text = context.text;

    return Scaffold(
      backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: dark ? AppColors.darkInk : AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Daily Report',
          style: text.titleMedium?.copyWith(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.w700,
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: dark ? AppColors.darkDeep : AppColors.deep,
          unselectedLabelColor:
              dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
          indicatorColor: dark ? AppColors.darkDeep : AppColors.deep,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Schedule'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : TabBarView(
              controller: _tabController,
              children: [
                _TodayTab(
                  tasks: _tasks,
                  completedTasks: _completedTasks,
                  totalTasks: _totalTasks,
                  waterMl: _waterMl,
                  lastSleep: _lastSleep,
                  activeGoals: _activeGoals,
                  burnout: _burnout,
                  dark: dark,
                  text: text,
                ),
                _ScheduleTab(
                  enabled: _reportEnabled,
                  hour: _reportHour,
                  minute: _reportMinute,
                  fmt: _fmt,
                  onToggle: _toggleEnabled,
                  onPickTime: _pickTime,
                  dark: dark,
                  text: text,
                ),
              ],
            ),
    );
  }
}

// ── Today tab ─────────────────────────────────────────────────────────────────

class _TodayTab extends StatelessWidget {
  final List<Task> tasks;
  final int completedTasks;
  final int totalTasks;
  final int waterMl;
  final SleepLog? lastSleep;
  final List<GoalPlan> activeGoals;
  final BurnoutForecast? burnout;
  final bool dark;
  final TextTheme text;

  const _TodayTab({
    required this.tasks,
    required this.completedTasks,
    required this.totalTasks,
    required this.waterMl,
    required this.lastSleep,
    required this.activeGoals,
    required this.burnout,
    required this.dark,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final completionRate =
        totalTasks == 0 ? 0.0 : completedTasks / totalTasks;
    final completionColor = completionRate >= 0.8
        ? AppColors.moss
        : completionRate >= 0.5
            ? AppColors.amber
            : AppColors.clay;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.lg, 20, 80),
      children: [
        // Date header
        Text(
          '${_weekdayName(now.weekday)}, ${now.day} ${_monthName(now.month)}',
          style: text.headlineSmall?.copyWith(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.w700,
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Here\'s how your day went.',
          style: text.bodyMedium?.copyWith(
            color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // ── Tasks ───────────────────────────────────────────────────────
        _ReportSection(
          icon: Icons.check_circle_outline_rounded,
          title: 'Tasks',
          dark: dark,
          text: text,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$completedTasks / $totalTasks',
                          style: text.headlineMedium?.copyWith(
                            fontFamily: 'Fraunces',
                            fontWeight: FontWeight.w700,
                            color: completionColor,
                          ),
                        ),
                        Text(
                          totalTasks == 0
                              ? 'No tasks today'
                              : '${(completionRate * 100).round()}% complete',
                          style: text.bodySmall?.copyWith(
                            color: dark
                                ? AppColors.darkInkSubtle
                                : AppColors.inkSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (totalTasks > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius:
                      const BorderRadius.all(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: completionRate,
                    minHeight: 7,
                    backgroundColor:
                        (dark ? AppColors.darkBorder : AppColors.mist)
                            .withValues(alpha: 0.5),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        completionColor.withValues(alpha: 0.8)),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Incomplete tasks
                ...tasks
                    .where((t) => t.status != TaskStatus.completed)
                    .take(3)
                    .map((t) => _TaskRow(task: t, dark: dark, text: text)),
                if (tasks
                        .where((t) => t.status != TaskStatus.completed)
                        .length >
                    3)
                  Padding(
                    padding:
                        const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '+ ${tasks.where((t) => t.status != TaskStatus.completed).length - 3} more incomplete',
                      style: text.bodySmall?.copyWith(
                        color: dark
                            ? AppColors.darkInkSubtle
                            : AppColors.inkSubtle,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ── Water & Sleep ────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _ReportSection(
                icon: Icons.water_drop_outlined,
                title: 'Water',
                dark: dark,
                text: text,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      waterMl >= 1000
                          ? '${(waterMl / 1000).toStringAsFixed(1)}L'
                          : '${waterMl}ml',
                      style: text.headlineMedium?.copyWith(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w700,
                        color: dark ? AppColors.darkDeep : AppColors.deep,
                      ),
                    ),
                    Text(
                      _waterLabel(waterMl),
                      style: text.bodySmall?.copyWith(
                        color: dark
                            ? AppColors.darkInkSubtle
                            : AppColors.inkSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ReportSection(
                icon: Icons.bedtime_outlined,
                title: 'Sleep',
                dark: dark,
                text: text,
                child: lastSleep == null
                    ? Text('Not logged',
                        style: text.bodySmall?.copyWith(
                          color: dark
                              ? AppColors.darkInkSubtle
                              : AppColors.inkSubtle,
                        ))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _durationLabel(lastSleep!.duration),
                            style: text.headlineMedium?.copyWith(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w700,
                              color:
                                  dark ? AppColors.darkInk : AppColors.ink,
                            ),
                          ),
                          if (lastSleep!.quality != null)
                            Text(
                              'Quality: ${lastSleep!.quality}/5',
                              style: text.bodySmall?.copyWith(
                                color: dark
                                    ? AppColors.darkInkSubtle
                                    : AppColors.inkSubtle,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.md),

        // ── Goals ────────────────────────────────────────────────────────
        _ReportSection(
          icon: Icons.flag_outlined,
          title: 'Active Goals',
          dark: dark,
          text: text,
          child: activeGoals.isEmpty
              ? Text('No active goals',
                  style: text.bodySmall?.copyWith(
                    color: dark
                        ? AppColors.darkInkSubtle
                        : AppColors.inkSubtle,
                  ))
              : Column(
                  children: activeGoals
                      .take(3)
                      .map((g) => _GoalRow(goal: g, dark: dark, text: text))
                      .toList(),
                ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ── Burnout ──────────────────────────────────────────────────────
        if (burnout != null)
          _ReportSection(
            icon: Icons.monitor_heart_outlined,
            title: 'Burnout Signal',
            dark: dark,
            text: text,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  burnout!.summary,
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: dark ? AppColors.darkInk : AppColors.ink,
                  ),
                ),
                if (burnout!.contributingReasons.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  ...burnout!.contributingReasons.take(2).map((r) =>
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '· $r',
                          style: text.bodySmall?.copyWith(
                            color: dark
                                ? AppColors.darkInkSubtle
                                : AppColors.inkSubtle,
                          ),
                        ),
                      )),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _weekdayName(int wd) =>
      const ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][wd];

  String _monthName(int m) =>
      const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m];

  String _waterLabel(int ml) {
    if (ml == 0) return 'Nothing yet';
    if (ml < 1000) return 'Keep going';
    if (ml < 2000) return 'Good progress';
    return 'Well hydrated';
  }

  String _durationLabel(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

// ── Schedule tab ──────────────────────────────────────────────────────────────

class _ScheduleTab extends StatelessWidget {
  final bool enabled;
  final int hour;
  final int minute;
  final String Function(int, int) fmt;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;
  final bool dark;
  final TextTheme text;

  const _ScheduleTab({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.fmt,
    required this.onToggle,
    required this.onPickTime,
    required this.dark,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.lg, 20, 80),
      children: [
        Text(
          'Daily Notification',
          style: text.titleMedium?.copyWith(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.w700,
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Get a daily nudge to open your summary report.',
          style: text.bodySmall?.copyWith(
            color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Toggle row
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: dark ? AppColors.darkCard : AppColors.cardSurface,
            borderRadius: const BorderRadius.all(AppRadius.lg),
            border: Border.all(
                color: dark ? AppColors.darkBorder : AppColors.mist),
          ),
          child: Row(
            children: [
              Icon(Icons.notifications_outlined,
                  size: 20,
                  color: dark ? AppColors.darkDeep : AppColors.deep),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Enable daily report',
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: dark ? AppColors.darkInk : AppColors.ink,
                  ),
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onToggle(v);
                },
                activeColor: dark ? AppColors.darkDeep : AppColors.deep,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Time picker row
        GestureDetector(
          onTap: enabled ? onPickTime : null,
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 150),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: dark ? AppColors.darkCard : AppColors.cardSurface,
                borderRadius: const BorderRadius.all(AppRadius.lg),
                border: Border.all(
                    color: dark ? AppColors.darkBorder : AppColors.mist),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      size: 20,
                      color: dark ? AppColors.darkDeep : AppColors.deep),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Report time',
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color:
                                dark ? AppColors.darkInk : AppColors.ink,
                          ),
                        ),
                        Text(
                          fmt(hour, minute),
                          style: text.bodySmall?.copyWith(
                            color: dark
                                ? AppColors.darkInkSubtle
                                : AppColors.inkSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18,
                      color: dark
                          ? AppColors.darkInkSubtle
                          : AppColors.inkSubtle),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.xl),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: (dark ? AppColors.darkDeep : AppColors.deep)
                .withValues(alpha: 0.06),
            borderRadius: const BorderRadius.all(AppRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16,
                  color: dark ? AppColors.darkDeep : AppColors.deep),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'The notification is a tap-through — it opens this report screen so you can see your actual data, not just a number.',
                  style: text.bodySmall?.copyWith(
                    color: dark ? AppColors.darkInk : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Row widgets ───────────────────────────────────────────────────────────────

class _ReportSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final bool dark;
  final TextTheme text;

  const _ReportSection({
    required this.icon,
    required this.title,
    required this.child,
    required this.dark,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(
            color: dark ? AppColors.darkBorder : AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: dark ? AppColors.darkDeep : AppColors.deep),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                title,
                style: text.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: (dark ? AppColors.darkDeep : AppColors.deep)
                      .withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Task task;
  final bool dark;
  final TextTheme text;
  const _TaskRow(
      {required this.task, required this.dark, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            task.status == TaskStatus.skipped
                ? Icons.skip_next_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 14,
            color: task.status == TaskStatus.skipped
                ? AppColors.inkSubtle
                : AppColors.clay.withValues(alpha: 0.7),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Text(
              task.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: dark ? AppColors.darkInk : AppColors.ink,
              ),
            ),
          ),
          Text(
            task.status.name,
            style: TextStyle(
              fontSize: 11,
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final GoalPlan goal;
  final bool dark;
  final TextTheme text;
  const _GoalRow(
      {required this.goal, required this.dark, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.flag_rounded,
              size: 14,
              color: dark ? AppColors.darkDeep : AppColors.deep),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Text(
              goal.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: dark ? AppColors.darkInk : AppColors.ink,
              ),
            ),
          ),
          Text(
            'Wk ${goal.currentWeek}/${goal.totalWeeks}',
            style: TextStyle(
              fontSize: 11,
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            ),
          ),
        ],
      ),
    );
  }
}
