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
      builder: (ctx) {
        final dark = ctx.isDark;
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              20, AppSpacing.sm,
              20, AppSpacing.xl,
            ),
            decoration: BoxDecoration(
              color: dark ? AppColors.darkSurface : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: AppRadius.xl,
              ),
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
                      color: dark ? AppColors.darkBorder : AppColors.mist,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Log ${_mealLabel(type)}',
                  style: ctx.text.titleLarge?.copyWith(
                    color: dark ? AppColors.darkInk : AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: descController,
                  autofocus: true,
                  style: ctx.text.bodyLarge?.copyWith(
                    color: dark ? AppColors.darkInk : AppColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'What did you eat?',
                    hintStyle: ctx.text.bodyLarge?.copyWith(
                      color: (dark
                              ? AppColors.darkInkSubtle
                              : AppColors.inkSubtle)
                          .withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: dark ? AppColors.darkCard : AppColors.cardSurface,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(AppRadius.md),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: notesController,
                  style: ctx.text.bodyMedium?.copyWith(
                    color: dark ? AppColors.darkInk : AppColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Notes (optional)',
                    hintStyle: ctx.text.bodyMedium?.copyWith(
                      color: (dark
                              ? AppColors.darkInkSubtle
                              : AppColors.inkSubtle)
                          .withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: dark ? AppColors.darkCard : AppColors.cardSurface,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(AppRadius.md),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          dark ? AppColors.darkAmber : AppColors.amber,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(AppRadius.md),
                      ),
                    ),
                    child: Text(
                      'Save',
                      style: ctx.text.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;
    final desc = descController.text.trim();
    if (desc.isEmpty) return;

    final log = MealLog(
      id: const Uuid().v4(),
      mealType: type,
      description: desc,
      notes: notesController.text.trim().isNotEmpty
          ? notesController.text.trim()
          : null,
      timestamp: DateTime.now(),
    );
    await db.insertMealLog(log);
    if (!mounted) return;
    setState(() => _todayLogs = [log, ..._todayLogs]);
  }

  Future<void> _deleteLog(MealLog log) async {
    await db.deleteMealLog(log.id);
    if (!mounted) return;
    setState(() => _todayLogs.remove(log));
  }

  String _mealLabel(MealType type) => switch (type) {
        MealType.breakfast => 'Breakfast',
        MealType.lunch => 'Lunch',
        MealType.dinner => 'Dinner',
        MealType.snack => 'Snack',
      };

  IconData _mealIcon(MealType type) => switch (type) {
        MealType.breakfast => Icons.wb_sunny_rounded,
        MealType.lunch => Icons.lunch_dining_rounded,
        MealType.dinner => Icons.dinner_dining_rounded,
        MealType.snack => Icons.cookie_rounded,
      };

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dark = context.isDark;

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
          'Meals',
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
        children: MealType.values.map((type) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            child: _MealSection(
              type: type,
              logs: _todayLogs.where((l) => l.mealType == type).toList(),
              dark: dark,
              onText: context.text,
              mealLabel: _mealLabel,
              mealIcon: _mealIcon,
              formatTime: _formatTime,
              onLog: () => _logMeal(type),
              onDelete: _deleteLog,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Meal section ─────────────────────────────────────────────────────────────

class _MealSection extends StatelessWidget {
  final MealType type;
  final List<MealLog> logs;
  final bool dark;
  final TextTheme onText;
  final String Function(MealType) mealLabel;
  final IconData Function(MealType) mealIcon;
  final String Function(DateTime) formatTime;
  final VoidCallback onLog;
  final Future<void> Function(MealLog) onDelete;

  const _MealSection({
    required this.type,
    required this.logs,
    required this.dark,
    required this.onText,
    required this.mealLabel,
    required this.mealIcon,
    required this.formatTime,
    required this.onLog,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogs = logs.isNotEmpty;
    final accent = dark ? AppColors.darkAmber : AppColors.amber;
    final subtle = dark ? AppColors.darkInkSubtle : AppColors.inkSubtle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(
              mealIcon(type),
              size: 16,
              color: hasLogs ? accent : subtle,
            ),
            const SizedBox(width: 6),
            Text(
              mealLabel(type).toUpperCase(),
              style: onText.labelSmall?.copyWith(
                color: hasLogs ? accent : subtle,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onLog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 4, vertical: 4),
                decoration: BoxDecoration(
                  color: dark ? AppColors.darkCard : AppColors.cardSurface,
                  borderRadius: const BorderRadius.all(AppRadius.pill),
                  border: Border.all(
                    color: dark ? AppColors.darkBorder : AppColors.mist,
                  ),
                ),
                child: Text(
                  hasLogs ? '+ Add another' : '+ Log',
                  style: onText.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? AppColors.darkDeep : AppColors.deep,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        if (!hasLogs)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: dark ? AppColors.darkCard : AppColors.cardSurface,
              borderRadius: const BorderRadius.all(AppRadius.md),
              border: Border.all(
                color: dark ? AppColors.darkBorder : AppColors.mist,
              ),
            ),
            child: Text(
              'Not logged yet',
              style: onText.bodyMedium?.copyWith(
                color: subtle.withValues(alpha: 0.6),
              ),
            ),
          )
        else
          ...logs.map(
            (log) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: dark ? AppColors.darkCard : AppColors.cardSurface,
                  borderRadius: const BorderRadius.all(AppRadius.md),
                  border: Border.all(
                    color: dark ? AppColors.darkBorder : AppColors.mist,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.description,
                            style: onText.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: dark ? AppColors.darkInk : AppColors.ink,
                            ),
                          ),
                          if (log.notes != null && log.notes!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              log.notes!,
                              style: onText.bodySmall?.copyWith(
                                color: subtle,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            formatTime(log.timestamp),
                            style: onText.labelSmall?.copyWith(color: subtle),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => onDelete(log),
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: subtle),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
