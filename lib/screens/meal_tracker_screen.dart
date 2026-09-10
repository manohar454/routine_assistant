import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/meal_models.dart';
import '../theme/app_theme.dart';

class MealTrackerScreen extends StatefulWidget {
  const MealTrackerScreen({super.key});

  @override
  State<MealTrackerScreen> createState() => _MealTrackerScreenState();
}

class _MealTrackerScreenState extends State<MealTrackerScreen> {
  final db = DatabaseHelper.instance;
  List<MealLog> _todayLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await db.getMealLogsForDay(DateTime.now());
    if (!mounted) return;
    setState(() {
      _todayLogs = logs;
      _loading = false;
    });
  }

  Future<void> _logMeal(MealType type) async {
    final descController = TextEditingController();
    final notesController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
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
              Text(
                'Log ${_mealLabel(type)}',
                style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'What did you eat?',
                  hintText: 'e.g. oats with banana, protein shake',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'e.g. soaked chia seeds, extra protein',
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    if (descController.text.trim().isEmpty) return;

    final log = MealLog(
      id: const Uuid().v4(),
      mealType: type,
      description: descController.text.trim(),
      timestamp: DateTime.now(),
      notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
    );

    await db.insertMealLog(log);
    if (!mounted) return;
    setState(() => _todayLogs = [..._todayLogs, log]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
  }

  Future<void> _deleteLog(MealLog log) async {
    await db.deleteMealLog(log.id);
    if (!mounted) return;
    setState(() => _todayLogs.remove(log));
  }

  String _mealLabel(MealType type) {
    switch (type) {
      case MealType.breakfast: return 'Breakfast';
      case MealType.lunch: return 'Lunch';
      case MealType.dinner: return 'Dinner';
      case MealType.snack: return 'Snack';
    }
  }

  IconData _mealIcon(MealType type) {
    switch (type) {
      case MealType.breakfast: return Icons.wb_sunny_outlined;
      case MealType.lunch: return Icons.wb_cloudy_outlined;
      case MealType.dinner: return Icons.bedtime_outlined;
      case MealType.snack: return Icons.apple;
    }
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Build a view that shows all four meal slots in order, showing what
    // was logged (or a quiet "not yet logged" state) — so you get a clear
    // picture of the whole day at once, not just a flat list of entries.
    final orderedTypes = [
      MealType.breakfast,
      MealType.lunch,
      MealType.dinner,
      MealType.snack,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Meals'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text('TODAY', style: textTheme.labelSmall),
            const SizedBox(height: 12),

            for (final type in orderedTypes) ...[
              _mealSection(type, textTheme),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mealSection(MealType type, TextTheme textTheme) {
    final logs = _todayLogs.where((l) => l.mealType == type).toList();
    final hasLogs = logs.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_mealIcon(type),
                size: 16,
                color: hasLogs ? AppColors.moss : AppColors.deepLight),
            const SizedBox(width: 6),
            Text(
              _mealLabel(type).toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: hasLogs ? AppColors.moss : null,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _logMeal(type),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  border: Border.all(color: AppColors.mist),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hasLogs ? '+ Add another' : '+ Log',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deep,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (!hasLogs)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              border: Border.all(color: AppColors.mist),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Not logged yet',
              style: textTheme.bodyMedium,
            ),
          )
        else
          for (final log in logs)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                border: Border.all(color: AppColors.mist),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(log.description,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (log.notes != null) ...[
                          const SizedBox(height: 2),
                          Text(log.notes!,
                              style: textTheme.bodyMedium?.copyWith(fontSize: 12)),
                        ],
                        const SizedBox(height: 4),
                        Text(_formatTime(log.timestamp),
                            style: textTheme.bodyMedium?.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: AppColors.clay),
                    onPressed: () => _deleteLog(log),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}