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
      _bedTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickWakeTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_wakeTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      _wakeTime = DateTime(
          _wakeTime.year, _wakeTime.month, _wakeTime.day, time.hour, time.minute);
    });
  }

  Future<void> _saveLog() async {
    final bedDate = DateTime(
      _bedTime.year, _bedTime.month, _bedTime.day,
      _bedTime.hour, _bedTime.minute,
    );
    var wakeDate = DateTime(
      bedDate.year, bedDate.month, bedDate.day,
      _wakeTime.hour, _wakeTime.minute,
    );
    if (!wakeDate.isAfter(bedDate)) wakeDate = wakeDate.add(const Duration(days: 1));

    if (wakeDate.difference(bedDate).inHours > 24) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That's over 24 hours — check your times.")),
      );
      return;
    }

    final log = SleepLog(id: const Uuid().v4(), bedTime: bedDate, wakeTime: wakeDate);
    await db.insertSleepLog(log);
    if (!mounted) return;
    setState(() => _recentLogs = [log, ..._recentLogs]);
  }

  Future<void> _editFloor() async {
    final controller =
        TextEditingController(text: (_floorMinutes / 60).toStringAsFixed(1));
    final newHours = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final dark = ctx.isDark;
        return AlertDialog(
          backgroundColor: dark ? AppColors.darkSurface : Colors.white,
          title: Text(
            'Sleep floor',
            style: ctx.text.titleMedium?.copyWith(
              color: dark ? AppColors.darkInk : AppColors.ink,
            ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              suffixText: 'hours',
              filled: true,
              fillColor: dark ? AppColors.darkCard : AppColors.cardSurface,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(AppRadius.sm),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text)),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (newHours == null || newHours <= 0) return;
    final minutes = (newHours * 60).round();
    await db.setSetting(_sleepFloorSettingKey, '$minutes');
    if (!mounted) return;
    setState(() => _floorMinutes = minutes);
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
      _bedTime.year, _bedTime.month, _bedTime.day,
      _wakeTime.hour, _wakeTime.minute,
    );
    if (!wake.isAfter(_bedTime)) wake = wake.add(const Duration(days: 1));
    return wake.difference(_bedTime);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dark = context.isDark;
    final lastNight = _lastNight;
    final belowFloor =
        lastNight != null && lastNight.duration.inMinutes < _floorMinutes;
    final wakeDuration = _computeWakeDuration();
    final floorHours = (_floorMinutes / 60).toStringAsFixed(1);

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
          'Sleep',
          style: context.text.titleLarge?.copyWith(
            color: dark ? AppColors.darkInk : AppColors.ink,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.tune_rounded,
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            onPressed: _editFloor,
            tooltip: 'Edit floor',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          20, AppSpacing.md,
          20, 60,
        ),
        children: [
          // ── Last night summary ────────────────────────────────────────
          if (lastNight != null) ...[
            _SleepSummaryCard(
              log: lastNight,
              floorMinutes: _floorMinutes,
              floorHours: floorHours,
              belowFloor: belowFloor,
              dark: dark,
              formatDuration: _formatDuration,
              formatTime: _formatTime,
              onText: context.text,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

          // ── Log input ─────────────────────────────────────────────────
          Text(
            'LOG A NIGHT',
            style: context.text.labelSmall?.copyWith(
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: 'Bedtime',
                  value: _formatTime(_bedTime),
                  dark: dark,
                  onText: context.text,
                  onTap: _pickBedTime,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _TimeButton(
                  label: 'Wake time',
                  value: _formatTime(_wakeTime),
                  dark: dark,
                  onText: context.text,
                  onTap: _pickWakeTime,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 14,
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
              ),
              const SizedBox(width: 4),
              Text(
                'Duration: ${_formatDuration(wakeDuration)}',
                style: context.text.bodySmall?.copyWith(
                  color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saveLog,
              style: FilledButton.styleFrom(
                backgroundColor: dark ? AppColors.darkDeep : AppColors.deep,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(AppRadius.md),
                ),
              ),
              child: Text(
                'Save',
                style: context.text.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── History ───────────────────────────────────────────────────
          if (_recentLogs.isNotEmpty) ...[
            Text(
              'RECENT NIGHTS',
              style: context.text.labelSmall?.copyWith(
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._recentLogs.take(10).map(
              (log) {
                final ok = log.duration.inMinutes >= _floorMinutes;
                return Padding(
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
                          ok
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: ok
                              ? (dark ? AppColors.darkMoss : AppColors.moss)
                              : (dark ? AppColors.darkAmber : AppColors.amber),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '${log.forDate.day}/${log.forDate.month}',
                            style: context.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: dark ? AppColors.darkInk : AppColors.ink,
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(log.duration),
                          style: context.text.bodySmall?.copyWith(
                            color: ok
                                ? (dark ? AppColors.darkMoss : AppColors.moss)
                                : (dark ? AppColors.darkAmber : AppColors.amber),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Last night card ─────────────────────────────────────────────────────────

class _SleepSummaryCard extends StatelessWidget {
  final SleepLog log;
  final int floorMinutes;
  final String floorHours;
  final bool belowFloor;
  final bool dark;
  final String Function(Duration) formatDuration;
  final String Function(DateTime) formatTime;
  final TextTheme onText;

  const _SleepSummaryCard({
    required this.log,
    required this.floorMinutes,
    required this.floorHours,
    required this.belowFloor,
    required this.dark,
    required this.formatDuration,
    required this.formatTime,
    required this.onText,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        belowFloor ? (dark ? AppColors.darkAmber : AppColors.amber) : (dark ? AppColors.darkMoss : AppColors.moss);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.lg),
        border: Border.all(color: dark ? AppColors.darkBorder : AppColors.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LAST NIGHT',
            style: onText.labelSmall?.copyWith(
              color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatDuration(log.duration),
                style: onText.displaySmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${formatTime(log.bedTime)} → ${formatTime(log.wakeTime)}',
                  style: onText.bodySmall?.copyWith(
                    color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                  ),
                ),
              ),
            ],
          ),
          if (belowFloor) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              decoration: BoxDecoration(
              color: (dark ? AppColors.darkAmber : AppColors.amber)
              .withValues(alpha: 0.1),
              borderRadius: const BorderRadius.all(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14,
                      color: dark ? AppColors.darkAmber : AppColors.amber),
                  const SizedBox(width: 6),
                  Text(
                    "Under your ${floorHours}h floor",
                    style: onText.labelSmall?.copyWith(
                      color: dark ? AppColors.darkAmber : AppColors.amber,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Time button ─────────────────────────────────────────────────────────────

class _TimeButton extends StatelessWidget {
  final String label;
  final String value;
  final bool dark;
  final TextTheme onText;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.value,
    required this.dark,
    required this.onText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : AppColors.cardSurface,
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(color: dark ? AppColors.darkBorder : AppColors.mist),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: onText.labelSmall?.copyWith(
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: onText.titleMedium?.copyWith(
                color: dark ? AppColors.darkInk : AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
