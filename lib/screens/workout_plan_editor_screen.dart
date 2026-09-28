import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/workout_models.dart';
import '../theme/app_theme.dart';
import 'workout_template_editor_screen.dart';

const _dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];

class WorkoutPlanEditorScreen extends StatefulWidget {
  final WorkoutPlan? initialPlan;
  const WorkoutPlanEditorScreen({super.key, this.initialPlan});

  @override
  State<WorkoutPlanEditorScreen> createState() => _WorkoutPlanEditorScreenState();
}

class _WorkoutPlanEditorScreenState extends State<WorkoutPlanEditorScreen> {
  final db = DatabaseHelper.instance;
  List<WorkoutPlan> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plans = await db.getAllWorkoutPlans();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _loading = false;
    });
    if (widget.initialPlan != null && mounted) {
      await _openPlan(widget.initialPlan!);
    }
  }

  Future<void> _addPlan() async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? AppColors.darkSurface : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(AppRadius.lg)),
        title: Text('New plan',
            style: TextStyle(
              fontFamily: 'Fraunces',
              color: dark ? AppColors.darkInk : AppColors.ink,
              fontWeight: FontWeight.w700,
            )),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: TextStyle(color: dark ? AppColors.darkInk : AppColors.ink),
          decoration: InputDecoration(
            hintText: 'e.g. My Custom Split',
            hintStyle: TextStyle(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            filled: true,
            fillColor: dark ? AppColors.darkCard : AppColors.mist.withValues(alpha: 0.35),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(AppRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(AppRadius.pill)),
            ),
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await db.insertWorkoutPlan(WorkoutPlan(id: const Uuid().v4(), name: name));
    await _load();
  }

  Future<void> _deletePlan(WorkoutPlan plan) async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? AppColors.darkSurface : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(AppRadius.lg)),
        title: Text('Delete "${plan.name}"?',
            style: TextStyle(
              fontFamily: 'Fraunces',
              color: dark ? AppColors.darkInk : AppColors.ink,
              fontWeight: FontWeight.w700,
            )),
        content: Text(
          'This removes the plan and all its days. This cannot be undone.',
          style: TextStyle(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.clay)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await db.deleteWorkoutPlan(plan.id);
    await _load();
  }

  Future<void> _openPlan(WorkoutPlan plan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PlanDaysScreen(plan: plan)),
    );
    await _load();
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
        title: Text('Manage Plans',
            style: text.titleMedium?.copyWith(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              color: dark ? AppColors.darkInk : AppColors.ink,
            )),
        centerTitle: false,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: dark ? AppColors.darkDeep : AppColors.deep,
                strokeWidth: 2,
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    20, AppSpacing.md, 20, AppSpacing.xxl),
                children: [
                  Text('Your plans',
                      style: text.displaySmall?.copyWith(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w700,
                        color: dark ? AppColors.darkInk : AppColors.ink,
                      )),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _plans.isEmpty
                        ? 'Create your first workout plan below.'
                        : '${_plans.length} plan${_plans.length == 1 ? '' : 's'} · tap to manage days',
                    style: text.bodyMedium?.copyWith(
                        color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_plans.isEmpty)
                    _EmptyPlansCard(dark: dark, text: text)
                  else
                    for (final plan in _plans)
                      _PlanCard(
                        plan: plan,
                        dark: dark,
                        text: text,
                        onTap: () => _openPlan(plan),
                        onDelete: () => _deletePlan(plan),
                      ),
                  const SizedBox(height: AppSpacing.md),
                  _AddButton(
                    label: 'New plan',
                    dark: dark,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _addPlan();
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final WorkoutPlan plan;
  final bool dark;
  final TextTheme text;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PlanCard({
    required this.plan,
    required this.dark,
    required this.text,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : AppColors.cardSurface,
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(
            color: dark
                ? AppColors.darkBorder.withValues(alpha: 0.6)
                : AppColors.mist.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            // Deep-colored accent strip
            Container(
              width: 4,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.deep,
                borderRadius: BorderRadius.only(
                  topLeft: AppRadius.md,
                  bottomLeft: AppRadius.md,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: dark ? AppColors.darkInk : AppColors.ink,
                        )),
                    if (plan.referenceNotes != null && plan.referenceNotes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(plan.referenceNotes!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
                      ),
                  ],
                ),
              ),
            ),
            // Edit arrow
            Icon(Icons.chevron_right_rounded,
                size: 20, color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            const SizedBox(width: AppSpacing.xs),
            // Delete
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onDelete();
              },
              child: Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.clay.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.all(AppRadius.sm),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: AppColors.clay),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlansCard extends StatelessWidget {
  final bool dark;
  final TextTheme text;
  const _EmptyPlansCard({required this.dark, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.darkDeep.withValues(alpha: 0.12)
            : AppColors.deep.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(
          color: dark
              ? AppColors.darkDeep.withValues(alpha: 0.25)
              : AppColors.deep.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.fitness_center_rounded,
              size: 36,
              color: (dark ? AppColors.darkDeep : AppColors.deep).withValues(alpha: 0.5)),
          const SizedBox(height: AppSpacing.md),
          Text('No plans yet',
              style: text.titleMedium?.copyWith(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w700,
                color: dark ? AppColors.darkInk : AppColors.ink,
              )),
          const SizedBox(height: AppSpacing.xs),
          Text('Create a plan to organize your weekly workout schedule.',
              textAlign: TextAlign.center,
              style: text.bodySmall
                  ?.copyWith(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final bool dark;
  final VoidCallback onTap;
  const _AddButton({required this.label, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(
            color: dark ? AppColors.darkBorder : AppColors.mist,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                size: 18, color: dark ? AppColors.darkDeep : AppColors.deep),
            const SizedBox(width: AppSpacing.xs),
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: dark ? AppColors.darkDeep : AppColors.deep,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Plan days screen
// ─────────────────────────────────────────────

class _PlanDaysScreen extends StatefulWidget {
  final WorkoutPlan plan;
  const _PlanDaysScreen({required this.plan});

  @override
  State<_PlanDaysScreen> createState() => _PlanDaysScreenState();
}

class _PlanDaysScreenState extends State<_PlanDaysScreen> {
  final db = DatabaseHelper.instance;
  List<WorkoutTemplate> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final templates = await db.getTemplatesForPlan(widget.plan.id);
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _loading = false;
    });
  }

  Future<void> _addDay() async {
    final dark = context.isDark;
    final usedDays = _templates.map((t) => t.dayOfWeek).toSet();
    final available =
        List.generate(7, (i) => i + 1).where((d) => !usedDays.contains(d)).toList();

    if (available.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('All 7 days already have a template in this plan.'),
          backgroundColor: dark ? AppColors.darkSurface : null,
        ),
      );
      return;
    }

    final chosenDay = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? AppColors.darkSurface : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(AppRadius.lg)),
        title: Text('Add a day',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              color: dark ? AppColors.darkInk : AppColors.ink,
            )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in available)
              InkWell(
                borderRadius: const BorderRadius.all(AppRadius.sm),
                onTap: () => Navigator.pop(ctx, d),
                child: Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
                  decoration: BoxDecoration(
                    color: dark
                        ? AppColors.darkCard
                        : AppColors.mist.withValues(alpha: 0.4),
                    borderRadius: const BorderRadius.all(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_dayNames[d - 1],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: dark ? AppColors.darkInk : AppColors.ink,
                            )),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 16,
                          color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosenDay == null) return;

    final template = WorkoutTemplate(
      id: const Uuid().v4(),
      planId: widget.plan.id,
      name: _dayNames[chosenDay - 1],
      dayOfWeek: chosenDay,
      exerciseIds: const [],
    );
    await db.insertWorkoutTemplate(template);
    await _load();

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => WorkoutTemplateEditorScreen(templateId: template.id)),
      );
      await _load();
    }
  }

  Future<void> _deleteDay(WorkoutTemplate template) async {
    final dark = context.isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? AppColors.darkSurface : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(AppRadius.lg)),
        title: Text('Remove ${template.name}?',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              color: dark ? AppColors.darkInk : AppColors.ink,
            )),
        content: Text('This removes the day template and all its exercises.',
            style: TextStyle(
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style:
                    TextStyle(color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.clay)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await db.deleteWorkoutTemplate(template.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final text = context.text;
    final sorted = List.of(_templates)..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

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
        title: Text(widget.plan.name,
            style: text.titleMedium?.copyWith(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              color: dark ? AppColors.darkInk : AppColors.ink,
            )),
        centerTitle: false,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: dark ? AppColors.darkDeep : AppColors.deep,
                strokeWidth: 2,
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    20, AppSpacing.md, 20, AppSpacing.xxl),
                children: [
                  Text('Days in this plan',
                      style: text.displaySmall?.copyWith(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w700,
                        color: dark ? AppColors.darkInk : AppColors.ink,
                      )),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    sorted.isEmpty
                        ? 'Add your first day below.'
                        : '${sorted.length} of 7 days scheduled',
                    style: text.bodyMedium?.copyWith(
                        color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Day progress strip
                  if (sorted.isNotEmpty) ...[
                    _DayStrip(templates: sorted, dark: dark),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  for (final t in sorted)
                    _DayTemplateCard(
                      template: t,
                      dark: dark,
                      text: text,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  WorkoutTemplateEditorScreen(templateId: t.id)),
                        );
                        await _load();
                      },
                      onDelete: () {
                        HapticFeedback.lightImpact();
                        _deleteDay(t);
                      },
                    ),
                  const SizedBox(height: AppSpacing.md),
                  _AddButton(
                    label: 'Add a day',
                    dark: dark,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _addDay();
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  final List<WorkoutTemplate> templates;
  final bool dark;
  const _DayStrip({required this.templates, required this.dark});

  @override
  Widget build(BuildContext context) {
    final filled = templates.map((t) => t.dayOfWeek).toSet();
    return Row(
      children: List.generate(7, (i) {
        final day = i + 1;
        final isSet = filled.contains(day);
        final template = isSet
            ? templates.where((t) => t.dayOfWeek == day).firstOrNull
            : null;
        final isRest = template?.isRestDay ?? false;
        return Expanded(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(AppRadius.pill),
                  color: isSet
                      ? (isRest
                          ? (dark ? AppColors.darkAmber : AppColors.amber)
                          : (dark ? AppColors.darkMoss : AppColors.moss))
                      : (dark
                          ? AppColors.darkBorder.withValues(alpha: 0.4)
                          : AppColors.mist),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _dayNames[i].substring(0, 2),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSet ? FontWeight.w700 : FontWeight.w400,
                  color: isSet
                      ? (dark ? AppColors.darkInk : AppColors.ink)
                      : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _DayTemplateCard extends StatelessWidget {
  final WorkoutTemplate template;
  final bool dark;
  final TextTheme text;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _DayTemplateCard({
    required this.template,
    required this.dark,
    required this.text,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isRest = template.isRestDay;
    final accentColor = isRest
        ? (dark ? AppColors.darkAmber : AppColors.amber)
        : (dark ? AppColors.darkMoss : AppColors.moss);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : AppColors.cardSurface,
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(
            color: dark
                ? AppColors.darkBorder.withValues(alpha: 0.6)
                : AppColors.mist.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            // Accent strip
            Container(
              width: 4,
              height: 64,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: AppRadius.md,
                  bottomLeft: AppRadius.md,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.name,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: dark ? AppColors.darkInk : AppColors.ink,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      isRest
                          ? 'Rest day'
                          : '${template.exerciseIds.length} exercises · ${template.sessionType.name}',
                      style: text.bodySmall?.copyWith(
                          color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
                    ),
                  ],
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20,
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            const SizedBox(width: AppSpacing.xs),
            GestureDetector(
              onTap: onDelete,
              child: Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.clay.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.all(AppRadius.sm),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: AppColors.clay),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
