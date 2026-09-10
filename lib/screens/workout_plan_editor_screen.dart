import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/workout_models.dart';
import '../theme/app_theme.dart';
import 'workout_template_editor_screen.dart';

const _dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];

/// This is the actual fix for "plans are static" — plans and their day
/// templates are now fully manageable from the app: add a plan, delete
/// one, add a day, edit or remove exercises within it. The seeded Gym/
/// Home/Transformation plans are just a starting point, not a ceiling.
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
      // Jump straight into "add a day" territory rather than making the
      // person navigate back into the plan they just picked.
      await _openPlan(widget.initialPlan!);
    }
  }

  Future<void> _addPlan() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New plan'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: 'e.g. My Custom Split'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${plan.name}"?'),
        content: const Text('This removes the plan and all its days. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('Manage plans')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  Text('Your plans', style: textTheme.displaySmall),
                  const SizedBox(height: 16),
                  for (final plan in _plans)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        border: Border.all(color: AppColors.mist),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        title: Text(plan.name,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: plan.referenceNotes != null
                            ? Text(plan.referenceNotes!,
                                maxLines: 2, overflow: TextOverflow.ellipsis)
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.clay),
                          onPressed: () => _deletePlan(plan),
                        ),
                        onTap: () => _openPlan(plan),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addPlan,
                      icon: const Icon(Icons.add),
                      label: const Text('New plan'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.mist),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Shows the days (templates) inside one plan, with add/delete/edit.
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
    final usedDays = _templates.map((t) => t.dayOfWeek).toSet();
    final available = List.generate(7, (i) => i + 1).where((d) => !usedDays.contains(d)).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All 7 days already have a template in this plan.')),
      );
      return;
    }

    final chosenDay = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a day'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in available)
              ListTile(
                title: Text(_dayNames[d - 1]),
                onTap: () => Navigator.pop(ctx, d),
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
        MaterialPageRoute(builder: (_) => WorkoutTemplateEditorScreen(templateId: template.id)),
      );
      await _load();
    }
  }

  Future<void> _deleteDay(WorkoutTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${template.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
    final textTheme = Theme.of(context).textTheme;
    final sorted = List.of(_templates)..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: Text(widget.plan.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  Text('Days in this plan', style: textTheme.displaySmall),
                  const SizedBox(height: 16),
                  for (final t in sorted)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        border: Border.all(color: AppColors.mist),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(t.isRestDay
                            ? 'Rest day'
                            : '${t.exerciseIds.length} exercises · ${t.sessionType.name}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.clay),
                          onPressed: () => _deleteDay(t),
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => WorkoutTemplateEditorScreen(templateId: t.id)),
                          );
                          await _load();
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addDay,
                      icon: const Icon(Icons.add),
                      label: const Text('Add a day'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.mist),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
