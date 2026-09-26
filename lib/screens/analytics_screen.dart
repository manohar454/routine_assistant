import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../engine/burnout_forecast_engine.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';

/// Analytics screen — task completion trends + burnout score history.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _db = DatabaseHelper.instance;

  bool _loading = true;

  // Task completion per day (last 14 days)
  List<_DayStat> _dayStats = [];

  // Overall stats
  int _totalCompleted = 0;
  int _totalScheduled = 0;
  double _avgCompletionRate = 0;

  // Burnout
  BurnoutForecast? _burnout;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final now = DateTime.now();
    final stats = <_DayStat>[];

    for (int i = 13; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final tasks = await _db.getTasksForDay(day);
      final total = tasks.length;
      final done =
          tasks.where((t) => t.status == TaskStatus.completed).length;
      stats.add(_DayStat(date: day, total: total, completed: done));
    }

    int totalCompleted = 0;
    int totalScheduled = 0;
    for (final s in stats) {
      totalCompleted += s.completed;
      totalScheduled += s.total;
    }

    final daysWithTasks = stats.where((s) => s.total > 0).toList();
    final avgRate = daysWithTasks.isEmpty
        ? 0.0
        : daysWithTasks.fold<double>(0, (sum, s) => sum + s.rate) /
            daysWithTasks.length;

    final burnout = await BurnoutForecastEngine.instance.forecast();

    if (!mounted) return;
    setState(() {
      _dayStats = stats;
      _totalCompleted = totalCompleted;
      _totalScheduled = totalScheduled;
      _avgCompletionRate = avgRate;
      _burnout = burnout;
      _loading = false;
    });
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
          'Analytics',
          style: text.titleMedium?.copyWith(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.w700,
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                size: 20, color: dark ? AppColors.darkInk : AppColors.ink),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(20, AppSpacing.md, 20, 80),
                children: [
                  // ── Summary chips ─────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _StatChip(
                          label: 'COMPLETED',
                          value: '$_totalCompleted',
                          sub: '14-day total',
                          dark: dark,
                          text: text,
                          color: AppColors.moss,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _StatChip(
                          label: 'AVG RATE',
                          value:
                              '${(_avgCompletionRate * 100).round()}%',
                          sub: 'days with tasks',
                          dark: dark,
                          text: text,
                          color: dark
                              ? AppColors.darkDeep
                              : AppColors.deep,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // ── Bar chart ─────────────────────────────────────────
                  _SectionHeader(
                      'COMPLETION — LAST 14 DAYS',
                      dark: dark,
                      text: text),
                  _CompletionBarChart(
                      stats: _dayStats, dark: dark, text: text),

                  const SizedBox(height: AppSpacing.lg),

                  // ── Burnout ───────────────────────────────────────────
                  _SectionHeader('BURNOUT RISK', dark: dark, text: text),
                  if (_burnout != null)
                    _BurnoutCard(
                        forecast: _burnout!, dark: dark, text: text),

                  const SizedBox(height: AppSpacing.lg),

                  // ── Per-day breakdown ─────────────────────────────────
                  _SectionHeader(
                      'DAY BREAKDOWN', dark: dark, text: text),
                  ..._dayStats.reversed
                      .where((s) => s.total > 0)
                      .map((s) =>
                          _DayRow(stat: s, dark: dark, text: text)),

                  if (_dayStats.every((s) => s.total == 0))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xl),
                      child: Center(
                        child: Text(
                          'No tasks scheduled in the last 14 days.',
                          style: text.bodySmall?.copyWith(
                            color: dark
                                ? AppColors.darkInkSubtle
                                : AppColors.inkSubtle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _DayStat {
  final DateTime date;
  final int total;
  final int completed;
  _DayStat(
      {required this.date, required this.total, required this.completed});
  double get rate => total == 0 ? 0 : completed / total;
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool dark;
  final TextTheme text;
  const _SectionHeader(this.label, {required this.dark, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: (dark ? AppColors.darkDeep : AppColors.deep)
              .withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final bool dark;
  final TextTheme text;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.sub,
    required this.dark,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(
              letterSpacing: 1.0,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: text.headlineMedium?.copyWith(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              color: dark ? AppColors.darkInk : AppColors.ink,
            ),
          ),
          Text(
            sub,
            style: text.bodySmall?.copyWith(
              color: dark
                  ? AppColors.darkInkSubtle
                  : AppColors.inkSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionBarChart extends StatelessWidget {
  final List<_DayStat> stats;
  final bool dark;
  final TextTheme text;

  const _CompletionBarChart(
      {required this.stats, required this.dark, required this.text});

  @override
  Widget build(BuildContext context) {
    final maxVal =
        stats.fold<int>(0, (m, s) => s.total > m ? s.total : m);
    final safeMax = maxVal == 0 ? 1 : maxVal;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.mist,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: stats.map((s) {
                final doneH =
                    (s.completed / safeMax * 72).clamp(0.0, 72.0);
                final missedH =
                    ((s.total - s.completed) / safeMax * 72)
                        .clamp(0.0, 72.0 - doneH);
                return Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (s.total == 0)
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: (dark
                                      ? AppColors.darkBorder
                                      : AppColors.mist)
                                  .withValues(alpha: 0.4),
                              borderRadius:
                                  const BorderRadius.all(AppRadius.xs),
                            ),
                          )
                        else
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (missedH > 0)
                                Container(
                                  height: missedH,
                                  decoration: BoxDecoration(
                                    color: AppColors.clay
                                        .withValues(alpha: 0.25),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: AppRadius.xs,
                                      topRight: AppRadius.xs,
                                    ),
                                  ),
                                ),
                              Container(
                                height: doneH.clamp(4.0, 72.0),
                                decoration: BoxDecoration(
                                  color: AppColors.moss
                                      .withValues(alpha: 0.75),
                                  borderRadius: missedH > 0
                                      ? BorderRadius.zero
                                      : const BorderRadius.only(
                                          topLeft: AppRadius.xs,
                                          topRight: AppRadius.xs,
                                        ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          // Day labels — M W F S only to avoid crowding
          Row(
            children: stats.map((s) {
              final wd = s.date.weekday;
              final label = wd == 1
                  ? 'M'
                  : wd == 3
                      ? 'W'
                      : wd == 5
                          ? 'F'
                          : wd == 7
                              ? 'S'
                              : '';
              return Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      color: dark
                          ? AppColors.darkInkSubtle
                          : AppColors.inkSubtle,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _Dot(color: AppColors.moss.withValues(alpha: 0.75)),
              const SizedBox(width: 4),
              Text('Done',
                  style: TextStyle(
                      fontSize: 11,
                      color: dark
                          ? AppColors.darkInkSubtle
                          : AppColors.inkSubtle)),
              const SizedBox(width: AppSpacing.md),
              _Dot(color: AppColors.clay.withValues(alpha: 0.25)),
              const SizedBox(width: 4),
              Text('Missed',
                  style: TextStyle(
                      fontSize: 11,
                      color: dark
                          ? AppColors.darkInkSubtle
                          : AppColors.inkSubtle)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.all(AppRadius.xs),
        ),
      );
}

class _BurnoutCard extends StatelessWidget {
  final BurnoutForecast forecast;
  final bool dark;
  final TextTheme text;

  const _BurnoutCard(
      {required this.forecast, required this.dark, required this.text});

  Color get _color => switch (forecast.level) {
        BurnoutRiskLevel.high => AppColors.clay,
        BurnoutRiskLevel.moderate => AppColors.amber,
        BurnoutRiskLevel.low => AppColors.moss,
      };

  String get _label => switch (forecast.level) {
        BurnoutRiskLevel.high => 'High risk',
        BurnoutRiskLevel.moderate => 'Moderate',
        BurnoutRiskLevel.low => 'Low risk',
      };

  @override
  Widget build(BuildContext context) {
    final pct = (forecast.riskScore * 100).round();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.all(AppRadius.pill),
                ),
                child: Text(
                  _label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _color,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$pct / 100',
                style: text.titleMedium?.copyWith(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w700,
                  color: dark ? AppColors.darkInk : AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: const BorderRadius.all(AppRadius.pill),
            child: LinearProgressIndicator(
              value: forecast.riskScore.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor:
                  (dark ? AppColors.darkBorder : AppColors.mist)
                      .withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            forecast.summary,
            style: text.bodySmall?.copyWith(
              color: dark ? AppColors.darkInk : AppColors.ink,
            ),
          ),
          if (forecast.contributingReasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs + 2),
            ...forecast.contributingReasons.map((r) => Padding(
                  padding:
                      const EdgeInsets.only(top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('· ',
                          style: TextStyle(
                              color: _color,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      Expanded(
                        child: Text(
                          r,
                          style: text.bodySmall?.copyWith(
                            color: dark
                                ? AppColors.darkInkSubtle
                                : AppColors.inkSubtle,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final _DayStat stat;
  final bool dark;
  final TextTheme text;

  const _DayRow(
      {required this.stat, required this.dark, required this.text});

  static const _wd = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final pct = stat.total == 0 ? 0 : (stat.rate * 100).round();
    final color = stat.rate >= 0.8
        ? AppColors.moss
        : stat.rate >= 0.5
            ? AppColors.amber
            : AppColors.clay;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              _wd[stat.date.weekday],
              style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: dark ? AppColors.darkInk : AppColors.ink,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${stat.date.day}/${stat.date.month}',
              style: text.bodySmall?.copyWith(
                color: dark
                    ? AppColors.darkInkSubtle
                    : AppColors.inkSubtle,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.all(AppRadius.pill),
              child: LinearProgressIndicator(
                value: stat.rate,
                minHeight: 6,
                backgroundColor:
                    (dark ? AppColors.darkBorder : AppColors.mist)
                        .withValues(alpha: 0.5),
                valueColor: AlwaysStoppedAnimation<Color>(
                    color.withValues(alpha: 0.75)),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 56,
            child: Text(
              '${stat.completed}/${stat.total} $pct%',
              textAlign: TextAlign.right,
              style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
