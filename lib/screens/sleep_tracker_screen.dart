import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/sleep_models.dart';
import '../theme/app_theme.dart';

const _defaultFloorMinutes = 450; // 7.5 hours
const _sleepFloorSettingKey = 'sleep_floor_minutes';

class SleepTrackerScreen extends StatefulWidget {
  const SleepTrackerScreen({super.key});

  @override
  State<SleepTrackerScreen> createState() => _SleepTrackerScreenState();
}

class _SleepTrackerScreenState extends State<SleepTrackerScreen> {
  final db = DatabaseHelper.instance;
  int _floorMinutes = _defaultFloorMinutes;
  List<SleepLog> _recentLogs = [];
  bool _loading = true;

  DateTime _bedTime = DateTime.now().subtract(const Duration(hours: 8));
  DateTime _wakeTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final floorSetting = await db.getSetting(_sleepFloorSettingKey);
    final logs = await db.getRecentSleepLogs(days: 14);
    if (!mounted) return;
    setState(() {
      _floorMinutes = floorSetting != null
          ? int.tryParse(floorSetting) ?? _defaultFloorMinutes
          : _defaultFloorMinutes;
      _recentLogs = logs;
      _loading = false;
    });
  }

  SleepLog? get _lastNight => _recentLogs.isEmpty ? null : _recentLogs.first;

  Future<void> _pickBedTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _bedTime,
      firstDate: DateTime.now().subtract(const Duration(days: 2)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_bedTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      _bedTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickWakeTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_wakeTime),
    );
    if (time == null || !mounted) return;

    // Only store the time component. The date is resolved in _saveLog()
    // relative to bedtime.
    setState(() {
      _wakeTime = DateTime(
        _wakeTime.year,
        _wakeTime.month,
        _wakeTime.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _saveLog() async {
    // Reconstruct wake time relative to bedtime. If wake time is earlier
    // than or equal to bedtime, it belongs to the next calendar day.
    final bedDate = DateTime(
      _bedTime.year,
      _bedTime.month,
      _bedTime.day,
      _bedTime.hour,
      _bedTime.minute,
    );

    var wakeDate = DateTime(
      bedDate.year,
      bedDate.month,
      bedDate.day,
      _wakeTime.hour,
      _wakeTime.minute,
    );

    if (!wakeDate.isAfter(bedDate)) {
      wakeDate = wakeDate.add(const Duration(days: 1));
    }

    if (wakeDate.difference(bedDate).inHours > 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("That's over 24 hours — check your times."),
        ),
      );
      return;
    }

    final log = SleepLog(
      id: const Uuid().v4(),
      bedTime: bedDate,
      wakeTime: wakeDate,
    );
    await db.insertSleepLog(log);
    if (!mounted) return;
    setState(() => _recentLogs = [log, ..._recentLogs]);
  }

  Future<void> _editFloor() async {
    final controller = TextEditingController(
      text: (_floorMinutes / 60).toStringAsFixed(1),
    );
    final newHours = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sleep floor'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'hours'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newHours == null || newHours <= 0) return;
    final minutes = (newHours * 60).round();
    await db.setSetting(_sleepFloorSettingKey, '$minutes');
    if (mounted) setState(() => _floorMinutes = minutes);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h${m > 0 ? ' ${m}m' : ''}';
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Duration _computeWakeDuration() {
    var wake = DateTime(
      _bedTime.year,
      _bedTime.month,
      _bedTime.day,
      _wakeTime.hour,
      _wakeTime.minute,
    );
    if (!wake.isAfter(_bedTime)) {
      wake = wake.add(const Duration(days: 1));
    }
    return wake.difference(_bedTime);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final lastNight = _lastNight;
    final belowFloor =
        lastNight != null && lastNight.duration.inMinutes < _floorMinutes;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Sleep'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _editFloor,
            tooltip: 'Edit floor',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (lastNight != null) ...[
              Text('LAST NIGHT', style: textTheme.labelSmall),
              const SizedBox(height: 4),
              Text(_formatDuration(lastNight.duration),
                  style: textTheme.displaySmall),
              const SizedBox(height: 4),
              Text(
                '${_formatTime(lastNight.bedTime)} → ${_formatTime(lastNight.wakeTime)}',
                style: textTheme.bodyMedium,
              ),
              if (belowFloor) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBEFE3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 18, color: AppColors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "That's under your ${(_floorMinutes / 60).toStringAsFixed(1)}h floor.",
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
            ],
            Text('LOG A NIGHT', style: textTheme.labelSmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _timeField(
                      'Bedtime', _formatTime(_bedTime), _pickBedTime),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _timeField(
                      'Wake time', _formatTime(_wakeTime), _pickWakeTime),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Duration: ${_formatDuration(_computeWakeDuration())}',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child:
                  FilledButton(onPressed: _saveLog, child: const Text('Save')),
            ),
            const SizedBox(height: 28),
            if (_recentLogs.isNotEmpty) ...[
              Text('RECENT NIGHTS', style: textTheme.labelSmall),
              const SizedBox(height: 10),
              for (final log in _recentLogs.take(10))
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    border: Border.all(color: AppColors.mist),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        log.duration.inMinutes < _floorMinutes
                            ? Icons.info_outline
                            : Icons.check_circle,
                        size: 16,
                        color: log.duration.inMinutes < _floorMinutes
                            ? AppColors.amber
                            : AppColors.moss,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${log.forDate.day}/${log.forDate.month}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(_formatDuration(log.duration),
                          style: textTheme.bodyMedium),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _timeField(String label, String value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: AppColors.mist),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(value, style: const TextStyle(color: AppColors.ink)),
        ),
      ],
    );
  }
}
