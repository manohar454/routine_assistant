import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../engine/goal_decomposition_engine.dart';
import '../models/goal_models.dart';
import '../theme/app_theme.dart';
import 'goal_creation_screen.dart';

class GoalProgressScreen extends StatefulWidget {
  const GoalProgressScreen({super.key});

  @override
  State<GoalProgressScreen> createState() => _GoalProgressScreenState();
}

class _GoalProgressScreenState extends State<GoalProgressScreen> {
  final _db = DatabaseHelper.instance;
  final _engine = GoalDecompositionEngine.instance;

  List<_GoalWithSim> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final plans = await _db.getActiveGoalPlans();
    final results = <_GoalWithSim>[];
    for (final plan in plans) {
      final actuals = await _engine.loadActualValues(plan);
      final sim = await _engine.simulate(plan: plan, actualValues: actuals);
      results.add(_GoalWithSim(plan: plan, sim: sim));
    }
    if (!mounted) return;
    setState(() {
      _items = results;
      _loading = false;
    });
  }

  Future<void> _markComplete(GoalPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadius.lg)),
        title: const Text('Mark goal complete?'),
        content: Text('Mark "${plan.name}" as completed?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Complete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.updateGoalPlanStatus(plan.id, GoalStatus.completed);
    await _load();
  }

  Future<void> _abandon(GoalPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadius.lg)),
        title: const Text('Abandon goal?'),
        content: Text('Remove "${plan.name}" from your active goals?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: AppColors.clay),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abandon'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.updateGoalPlanStatus(plan.id, GoalStatus.abandoned);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal Progress'),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _EmptyState(isDark: isDark)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (_, i) => _GoalCard(
                      item: _items[i],
                      isDark: isDark,
                      onComplete: () => _markComplete(_items[i].plan),
                      onAbandon: () => _abandon(_items[i].plan),
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const GoalCreationScreen()),
          );
          if (created == true) await _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Goal'),
      ),
    );
  }
}

// ─── Data holder ─────────────────────────────────────────────────────────────

class _GoalWithSim {
  final GoalPlan plan;
  final SimulationResult sim;
  const _GoalWithSim({required this.plan, required this.sim});
}

// ─── Goal card ────────────────────────────────────────────────────────────────

class _GoalCard extends StatelessWidget {
  final _GoalWithSim item;
  final bool isDark;
  final VoidCallback onComplete;
  final VoidCallback onAbandon;

  const _GoalCard({
    required this.item,
    required this.isDark,
    required this.onComplete,
    required this.onAbandon,
  });

  Color _outcomeColor(SimulationOutcome o) => switch (o) {
        SimulationOutcome.onTrack => isDark ? AppColors.darkMoss : AppColors.moss,
        SimulationOutcome.slightlyBehind =>
          isDark ? AppColors.darkAmber : AppColors.amber,
        SimulationOutcome.atRisk =>
          isDark ? const Color(0xFFD97B4B) : const Color(0xFFB85C1A),
        SimulationOutcome.offTrack => isDark ? AppColors.darkClay : AppColors.clay,
      };

  String _outcomeLabel(SimulationOutcome o) => switch (o) {
        SimulationOutcome.onTrack => 'On track',
        SimulationOutcome.slightlyBehind => 'Slightly behind',
        SimulationOutcome.atRisk => 'At risk',
        SimulationOutcome.offTrack => 'Off track',
      };

  IconData _domainIcon(GoalDomain d) => switch (d) {
        GoalDomain.workout => Icons.fitness_center_rounded,
        GoalDomain.running => Icons.directions_run_rounded,
        GoalDomain.habit => Icons.loop_rounded,
        GoalDomain.custom => Icons.flag_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final plan = item.plan;
    final sim = item.sim;
    final accent = _outcomeColor(sim.outcome);
    final bg = isDark ? AppColors.darkCard : AppColors.cardSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.mist;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.all(AppRadius.sm),
                  ),
                  child: Icon(_domainIcon(plan.domain), color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.name,
                          style: context.text.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(plan.outcomeDescription,
                          style: context.text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Outcome badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.all(AppRadius.pill),
                  ),
                  child: Text(
                    _outcomeLabel(sim.outcome),
                    style: context.text.labelSmall
                        ?.copyWith(color: accent, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),

          // ── Progress bar ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Week ${plan.currentWeek} of ${plan.totalWeeks}',
                      style: context.text.labelSmall?.copyWith(
                        color: isDark
                            ? AppColors.darkInkSubtle
                            : AppColors.inkSubtle,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(plan.progressFraction * 100).round()}%',
                      style: context.text.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: const BorderRadius.all(AppRadius.sm),
                  child: LinearProgressIndicator(
                    value: plan.progressFraction.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor:
                        isDark ? AppColors.darkBorder : AppColors.mist,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
              ],
            ),
          ),

          // ── Simulation summary ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(sim.summary, style: context.text.bodyMedium),
          ),

          if (sim.correctionHint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      size: 14,
                      color: isDark ? AppColors.darkAmber : AppColors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sim.correctionHint!,
                      style: context.text.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkAmber : AppColors.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Current milestone ───────────────────────────────────────
          if (plan.currentMilestone != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface
                      : AppColors.canvas,
                  borderRadius: const BorderRadius.all(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 14,
                        color: isDark
                            ? AppColors.darkInkSubtle
                            : AppColors.inkSubtle),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This week: ${plan.currentMilestone!.description}',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Milestone list ──────────────────────────────────────────
          if (plan.milestones.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _MilestoneRow(
                milestones: plan.milestones,
                currentWeek: plan.currentWeek,
                accent: accent,
                isDark: isDark,
              ),
            ),

          // ── Actions ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        size: 16),
                    label: const Text('Complete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          isDark ? AppColors.darkMoss : AppColors.moss,
                      side: BorderSide(
                          color: isDark ? AppColors.darkMoss : AppColors.moss),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: onAbandon,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.clay,
                    side: BorderSide(
                        color: AppColors.clay.withValues(alpha: 0.4)),
                  ),
                  child: const Text('Abandon'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Milestone dot row ────────────────────────────────────────────────────────

class _MilestoneRow extends StatelessWidget {
  final List<WeeklyMilestone> milestones;
  final int currentWeek;
  final Color accent;
  final bool isDark;

  const _MilestoneRow({
    required this.milestones,
    required this.currentWeek,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Show at most 8 milestone dots to avoid overflow
    final shown = milestones.length > 8 ? milestones.sublist(0, 8) : milestones;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.mist;

    return Row(
      children: [
        for (int i = 0; i < shown.length; i++) ...[
          _MilestoneDot(
            milestone: shown[i],
            isCurrent: shown[i].weekNumber == currentWeek,
            isPast: shown[i].weekNumber < currentWeek,
            accent: accent,
            isDark: isDark,
          ),
          if (i < shown.length - 1)
            Expanded(
              child: Container(
                height: 2,
                color: shown[i].weekNumber < currentWeek
                    ? accent.withValues(alpha: 0.4)
                    : borderColor,
              ),
            ),
        ],
        if (milestones.length > 8) ...[
          const SizedBox(width: 4),
          Text(
            '+${milestones.length - 8}',
            style: context.text.labelSmall?.copyWith(
              color: isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            ),
          ),
        ],
      ],
    );
  }
}

class _MilestoneDot extends StatelessWidget {
  final WeeklyMilestone milestone;
  final bool isCurrent;
  final bool isPast;
  final Color accent;
  final bool isDark;

  const _MilestoneDot({
    required this.milestone,
    required this.isCurrent,
    required this.isPast,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final size = isCurrent ? 14.0 : 10.0;
    final color = isPast || isCurrent
        ? accent
        : (isDark ? AppColors.darkBorder : AppColors.mist);

    return Tooltip(
      message: 'Wk ${milestone.weekNumber}: ${milestone.description}',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isCurrent
              ? Border.all(color: accent.withValues(alpha: 0.4), width: 3)
              : null,
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 56,
              color: isDark ? AppColors.darkBorder : AppColors.mist,
            ),
            const SizedBox(height: 20),
            Text('No active goals',
                style: context.text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to set a goal and get a week-by-week plan.',
              style: context.text.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
