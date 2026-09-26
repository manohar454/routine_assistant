import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/water_models.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';

const _defaultGoalMl = 3000;
const _waterGoalSettingKey = 'water_daily_goal_ml';

class WaterTrackerScreen extends StatefulWidget {
  const WaterTrackerScreen({super.key});

  @override
  State<WaterTrackerScreen> createState() => _WaterTrackerScreenState();
}

class _WaterTrackerScreenState extends State<WaterTrackerScreen>
    with SingleTickerProviderStateMixin {
  final db = DatabaseHelper.instance;
  int _goalMl = _defaultGoalMl;
  List<WaterLog> _todayLogs = [];
  bool _loading = true;

  late AnimationController _ringCtrl;
  late Animation<double> _ringAnim;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _ringAnim = CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOutCubic);
    _load();
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final goalSetting = await db.getSetting(_waterGoalSettingKey);
    final logs = await db.getWaterLogsForDay(DateTime.now());
    if (!mounted) return;
    setState(() {
      _goalMl = goalSetting != null
          ? int.tryParse(goalSetting) ?? _defaultGoalMl
          : _defaultGoalMl;
      _todayLogs = logs;
      _loading = false;
    });
    _ringCtrl.forward(from: 0);
  }

  int get _totalMl => _todayLogs.fold(0, (sum, l) => sum + l.amountMl);

  Future<void> _addWater(int amountMl) async {
    HapticFeedback.lightImpact();
    final log = WaterLog(
      id: const Uuid().v4(),
      amountMl: amountMl,
      timestamp: DateTime.now(),
    );
    await db.insertWaterLog(log);
    if (!mounted) return;

    final prevTotal = _totalMl;
    setState(() => _todayLogs = [log, ..._todayLogs]);
    _ringCtrl.forward(from: 0);

    if (_totalMl >= _goalMl && prevTotal < _goalMl) {
      await TtsService.instance
          .speak('Nice — you hit your water goal for today.');
    }
  }

  Future<void> _addCustomWater() async {
    final dark = context.isDark;
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? AppColors.darkSurface : Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadius.lg)),
        title: Text(
          'Custom amount',
          style: ctx.text.titleMedium?.copyWith(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.w700,
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: TextStyle(color: dark ? AppColors.darkInk : AppColors.ink),
          decoration: InputDecoration(
            hintText: 'e.g. 350',
            suffixText: 'ml',
            hintStyle: TextStyle(
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            filled: true,
            fillColor: dark ? AppColors.darkCard : AppColors.cardSurface,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(AppRadius.sm),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(AppRadius.sm),
              borderSide: BorderSide(
                color: dark ? AppColors.darkDeep : AppColors.deep,
                width: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(
                    color: dark
                        ? AppColors.darkInkSubtle
                        : AppColors.inkSubtle)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(AppRadius.pill)),
            ),
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, v);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    await _addWater(result);
  }

  Future<void> _undoLog(WaterLog log) async {
    await db.deleteWaterLog(log.id);
    if (!mounted) return;
    setState(() => _todayLogs.remove(log));
    _ringCtrl.forward(from: 0);
  }

  Future<void> _editGoal() async {
    final dark = context.isDark;
    final controller = TextEditingController(text: '${_goalMl ~/ 1000}');
    final newGoalLiters = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? AppColors.darkSurface : Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadius.lg)),
        title: Text(
          'Daily water goal',
          style: ctx.text.titleMedium?.copyWith(
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: TextStyle(color: dark ? AppColors.darkInk : AppColors.ink),
          decoration: InputDecoration(
            suffixText: 'liters',
            filled: true,
            fillColor: dark ? AppColors.darkCard : AppColors.cardSurface,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(AppRadius.sm),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(AppRadius.pill)),
            ),
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newGoalLiters == null || newGoalLiters <= 0) return;
    final newGoalMl = (newGoalLiters * 1000).round();
    await db.setSetting(_waterGoalSettingKey, '$newGoalMl');
    if (!mounted) return;
    setState(() => _goalMl = newGoalMl);
    _ringCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dark = context.isDark;
    final progress = (_totalMl / _goalMl).clamp(0.0, 1.0);
    final liters = (_totalMl / 1000).toStringAsFixed(1);
    final goalLiters = (_goalMl / 1000).toStringAsFixed(1);
    final done = _totalMl >= _goalMl;

    return Scaffold(
      backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Water',
          style: context.text.titleLarge?.copyWith(
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.tune_rounded,
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
            ),
            onPressed: _editGoal,
            tooltip: 'Edit goal',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, AppSpacing.lg, 20, 60),
        children: [
          // ── Ring gauge ──────────────────────────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: _ringAnim,
              builder: (_, __) {
                final animProgress =
                    (progress * _ringAnim.value).clamp(0.0, 1.0);
                return SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: animProgress,
                          strokeWidth: 16,
                          strokeCap: StrokeCap.round,
                          backgroundColor:
                              dark ? AppColors.darkBorder : AppColors.mist,
                          color: done
                              ? (dark ? AppColors.darkMoss : AppColors.moss)
                              : (dark ? AppColors.darkDeep : AppColors.deep),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (done)
                            Icon(
                              Icons.check_circle_rounded,
                              color: dark
                                  ? AppColors.darkMoss
                                  : AppColors.moss,
                              size: 28,
                            ),
                          Text(
                            '${liters}L',
                            style: context.text.displaySmall?.copyWith(
                              color: dark ? AppColors.darkInk : AppColors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 32,
                            ),
                          ),
                          Text(
                            'of ${goalLiters}L goal',
                            style: context.text.bodySmall?.copyWith(
                              color: dark
                                  ? AppColors.darkInkSubtle
                                  : AppColors.inkSubtle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Quick add ────────────────────────────────────────────────
          Text(
            'QUICK ADD',
            style: context.text.labelSmall?.copyWith(
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _QuickAddButton(
                label: '250 ml',
                onTap: () => _addWater(250),
                dark: dark,
                onText: context.text,
              ),
              const SizedBox(width: AppSpacing.sm),
              _QuickAddButton(
                label: '500 ml',
                onTap: () => _addWater(500),
                dark: dark,
                onText: context.text,
              ),
              const SizedBox(width: AppSpacing.sm),
              _QuickAddButton(
                label: '1 L',
                onTap: () => _addWater(1000),
                dark: dark,
                onText: context.text,
                accent: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Custom amount row
          GestureDetector(
            onTap: _addCustomWater,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(AppRadius.md),
                border: Border.all(
                  color: dark ? AppColors.darkBorder : AppColors.mist,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit_rounded,
                      size: 16,
                      color: dark ? AppColors.darkDeep : AppColors.deep),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Custom amount',
                    style: context.text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: dark ? AppColors.darkDeep : AppColors.deep,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Log ─────────────────────────────────────────────────────
          if (_todayLogs.isNotEmpty) ...[
            Text(
              'TODAY',
              style: context.text.labelSmall?.copyWith(
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._todayLogs.map(
              (log) => Padding(
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
                      color: dark ? AppColors.darkBorder : AppColors.mist,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.water_drop_rounded,
                        size: 18,
                        color: dark ? AppColors.darkDeep : AppColors.deep,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '${log.amountMl} ml',
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: dark ? AppColors.darkInk : AppColors.ink,
                          ),
                        ),
                      ),
                      Text(
                        '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                        style: context.text.bodySmall?.copyWith(
                          color: dark
                              ? AppColors.darkInkSubtle
                              : AppColors.inkSubtle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _undoLog(log),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: dark
                                ? AppColors.darkInkSubtle
                                : AppColors.inkSubtle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool dark;
  final TextTheme onText;
  final bool accent;

  const _QuickAddButton({
    required this.label,
    required this.onTap,
    required this.dark,
    required this.onText,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = accent
        ? (dark ? AppColors.darkDeep : AppColors.deep)
        : (dark ? AppColors.darkCard : AppColors.cardSurface);
    final fg = accent
        ? Colors.white
        : (dark ? AppColors.darkInk : AppColors.ink);
    final border = accent
        ? Colors.transparent
        : (dark ? AppColors.darkBorder : AppColors.mist);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.all(AppRadius.md),
            border: Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: Text(
            '+ $label',
            style: onText.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
