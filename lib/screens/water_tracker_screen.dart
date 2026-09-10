import 'package:flutter/material.dart';
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

class _WaterTrackerScreenState extends State<WaterTrackerScreen> {
  final db = DatabaseHelper.instance;
  int _goalMl = _defaultGoalMl;
  List<WaterLog> _todayLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final goalSetting = await db.getSetting(_waterGoalSettingKey);
    final logs = await db.getWaterLogsForDay(DateTime.now());
    if (!mounted) return;
    setState(() {
      _goalMl = goalSetting != null ? int.tryParse(goalSetting) ?? _defaultGoalMl : _defaultGoalMl;
      _todayLogs = logs;
      _loading = false;
    });
  }

  int get _totalMl => _todayLogs.fold(0, (sum, l) => sum + l.amountMl);

  Future<void> _addWater(int amountMl) async {
    final log = WaterLog(
      id: const Uuid().v4(),
      amountMl: amountMl,
      timestamp: DateTime.now(),
    );
    await db.insertWaterLog(log);
    if (!mounted) return;

    final newTotal = _totalMl + amountMl;
    setState(() => _todayLogs = [log, ..._todayLogs]);

    // A small, honest celebration — only fires once, right as the goal is
    // actually crossed, not every time you log something after it.
    if (newTotal >= _goalMl && _totalMl < _goalMl) {
      await TtsService.instance.speak('Nice — you hit your water goal for today.');
    }
  }

  Future<void> _undoLog(WaterLog log) async {
    await db.deleteWaterLog(log.id);
    if (!mounted) return;
    setState(() => _todayLogs.remove(log));
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(text: '${_goalMl ~/ 1000}');
    final newGoalLiters = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily water goal'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'liters'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newGoalLiters == null || newGoalLiters <= 0) return;

    final newGoalMl = (newGoalLiters * 1000).round();
    await db.setSetting(_waterGoalSettingKey, '$newGoalMl');
    if (mounted) setState(() => _goalMl = newGoalMl);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final progress = (_totalMl / _goalMl).clamp(0.0, 1.0);
    final liters = (_totalMl / 1000).toStringAsFixed(1);
    final goalLiters = (_goalMl / 1000).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Water'),
        actions: [
          IconButton(icon: const Icon(Icons.tune), onPressed: _editGoal, tooltip: 'Edit goal'),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // The circular gauge, matching the very first mockup's design.
            Center(
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 14,
                        backgroundColor: AppColors.mist,
                        color: AppColors.deepLight,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${liters}L',
                            style: textTheme.displaySmall?.copyWith(fontSize: 30)),
                        Text('of ${goalLiters}L goal', style: textTheme.bodyMedium),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            Text('QUICK ADD', style: textTheme.labelSmall),
            const SizedBox(height: 10),
            Row(
              children: [
                _quickAddButton(250),
                const SizedBox(width: 10),
                _quickAddButton(500),
                const SizedBox(width: 10),
                _quickAddButton(1000, label: '1L'),
              ],
            ),
            const SizedBox(height: 28),

            if (_todayLogs.isNotEmpty) ...[
              Text('TODAY', style: textTheme.labelSmall),
              const SizedBox(height: 10),
              for (final log in _todayLogs)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    border: Border.all(color: AppColors.mist),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.water_drop, size: 18, color: AppColors.deepLight),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${log.amountMl}ml',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                        style: textTheme.bodyMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: AppColors.clay),
                        onPressed: () => _undoLog(log),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quickAddButton(int ml, {String? label}) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () => _addWater(ml),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: const BorderSide(color: AppColors.mist),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text('+ ${label ?? "${ml}ml"}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
      ),
    );
  }
}