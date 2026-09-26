import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/routine_models.dart';
import '../services/routine_alarm_service.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import 'wake_alarm_screen.dart';

/// AI Voice Companion — Timetable editor screen.
///
/// Shows the full day schedule as a sorted list of [RoutineEntry] cards.
/// Each card can be toggled, edited, and reordered.
///
/// Top panel: active days selector (per-day toggles) + apply-to-week /
/// apply-to-month shortcuts.
///
/// FAB: add a new custom entry.
/// Save button: persists all entries and reschedules alarms.
class RoutineTimetableScreen extends StatefulWidget {
  const RoutineTimetableScreen({super.key});

  @override
  State<RoutineTimetableScreen> createState() =>
      _RoutineTimetableScreenState();
}

class _RoutineTimetableScreenState extends State<RoutineTimetableScreen> {
  final _db = DatabaseHelper.instance;

  List<RoutineEntry> _entries = [];
  bool _loading = true;
  bool _saving = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stored = await _db.getAllRoutineEntries();
    if (stored.isEmpty) {
      // First launch — populate with defaults.
      final defaults = DefaultRoutineTimetable.build();
      for (final e in defaults) {
        await _db.upsertRoutineEntry(e);
      }
      setState(() {
        _entries = defaults;
        _loading = false;
      });
    } else {
      setState(() {
        _entries = stored;
        _loading = false;
      });
    }
  }

  // ── Save & schedule ────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _db.replaceAllRoutineEntries(_entries);
      await RoutineAlarmService.instance.rescheduleAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schedule saved and alarms updated ✓'),
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Entry CRUD ─────────────────────────────────────────────────────────────

  void _toggleEnabled(RoutineEntry entry) {
    final idx = _entries.indexWhere((e) => e.id == entry.id);
    if (idx < 0) return;
    setState(() {
      _entries[idx] = entry.copyWith(enabled: !entry.enabled);
    });
  }

  void _updateEntry(RoutineEntry updated) {
    final idx = _entries.indexWhere((e) => e.id == updated.id);
    if (idx < 0) return;
    setState(() {
      _entries[idx] = updated;
      _entries.sort((a, b) => a.timeOfDayMinutes.compareTo(b.timeOfDayMinutes));
    });
  }

  void _deleteEntry(String id) {
    setState(() => _entries.removeWhere((e) => e.id == id));
  }

  void _addCustomEntry() {
    final entry = RoutineEntry(
      id: const Uuid().v4(),
      type: RoutineEntryType.custom,
      timeOfDayMinutes: 720, // default noon
      label: 'Custom Reminder',
      message: RoutineEntryType.custom.defaultMessage(),
    );
    setState(() {
      _entries.add(entry);
      _entries.sort((a, b) => a.timeOfDayMinutes.compareTo(b.timeOfDayMinutes));
    });
    // Open editor immediately.
    _showEditSheet(entry);
  }

  // ── Apply to week/month ────────────────────────────────────────────────────

  /// Clears activeDays on all entries → every day active.
  void _applyToWholeWeek() {
    setState(() {
      _entries = _entries.map((e) => e.copyWith(activeDays: [])).toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Schedule will repeat every day of the week'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Same as week — recurring daily alarms already cover every day.
  /// This conveys user intent for the full month.
  void _applyToWholeMonth() {
    setState(() {
      _entries = _entries.map((e) => e.copyWith(activeDays: [])).toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Schedule set for every day this month'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ── Wake alarm test ────────────────────────────────────────────────────────

  void _testWakeAlarm() {
    final wakeEntry = _entries
        .where((e) => e.type == RoutineEntryType.wakeUp)
        .firstOrNull;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WakeAlarmScreen(entry: wakeEntry),
      ),
    );
  }

  // ── Edit bottom sheet ──────────────────────────────────────────────────────

  void _showEditSheet(RoutineEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EntryEditSheet(
        entry: entry,
        onSave: (updated) {
          _updateEntry(updated);
          Navigator.pop(ctx);
        },
        onDelete: entry.type == RoutineEntryType.custom
            ? () {
                _deleteEntry(entry.id);
                Navigator.pop(ctx);
              }
            : null,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Routine'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomEntry,
        icon: const Icon(Icons.add),
        label: const Text('Add Reminder'),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Apply panel ──
          SliverToBoxAdapter(child: _buildApplyPanel(dark)),

          // ── Entries list ──
          if (_entries.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text('No reminders yet — tap + to add one.'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              sliver: SliverList.builder(
                itemCount: _entries.length,
                itemBuilder: (ctx, i) =>
                    _EntryCard(
                      entry: _entries[i],
                      onToggle: () => _toggleEnabled(_entries[i]),
                      onEdit: () => _showEditSheet(_entries[i]),
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildApplyPanel(bool dark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              const Icon(Icons.calendar_month, size: 16),
              const SizedBox(width: 6),
              Text(
                'Schedule scope',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionChip(
                  label: 'Whole Week',
                  icon: Icons.date_range,
                  onTap: _applyToWholeWeek,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionChip(
                  label: 'Whole Month',
                  icon: Icons.calendar_today,
                  onTap: _applyToWholeMonth,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionChip(
                  label: 'Test Wake',
                  icon: Icons.alarm,
                  onTap: _testWakeAlarm,
                  accent: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Entry card ───────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final RoutineEntry entry;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _EntryCard({
    required this.entry,
    required this.onToggle,
    required this.onEdit,
  });

  Color _cardColor(bool dark) {
    if (!entry.enabled) {
      return dark ? AppColors.darkSurface : AppColors.mist.withValues(alpha: 0.5);
    }
    switch (entry.type) {
      case RoutineEntryType.wakeUp:
        return dark ? const Color(0xFF2A2010) : AppColors.amberLight;
      case RoutineEntryType.workout:
      case RoutineEntryType.gym:
        return dark ? const Color(0xFF0E2420) : AppColors.mossLight;
      case RoutineEntryType.breakfast:
      case RoutineEntryType.lunch:
      case RoutineEntryType.dinner:
      case RoutineEntryType.postGymProtein:
        return dark ? const Color(0xFF1C1218) : AppColors.clayLight;
      case RoutineEntryType.morningWater:
      case RoutineEntryType.waterReminder:
      case RoutineEntryType.postWorkoutWater:
        return dark ? const Color(0xFF0C1E28) : const Color(0xFFE3F2FD);
      case RoutineEntryType.bedtimePrep:
        return dark ? const Color(0xFF12101E) : const Color(0xFFEDE7F6);
      case RoutineEntryType.custom:
        return dark ? AppColors.darkCard : AppColors.cardSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onEdit,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: entry.enabled ? 1.0 : 0.55,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: _cardColor(dark),
            borderRadius: const BorderRadius.all(AppRadius.md),
            border: Border.all(
              color: dark ? AppColors.darkBorder : AppColors.mist,
            ),
          ),
          child: Row(
            children: [
              // Emoji icon
              Text(entry.type.emoji,
                  style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              // Label + time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: entry.enabled
                                ? null
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.formattedTime,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: dark
                                ? AppColors.darkInkSubtle
                                : AppColors.inkSubtle,
                          ),
                    ),
                    if (entry.waterMl != null)
                      Text(
                        '💧 ${entry.waterMl} ml',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: dark
                                  ? AppColors.darkDeep
                                  : AppColors.deep,
                            ),
                      ),
                    if (entry.activeDays.isNotEmpty)
                      Text(
                        _daysLabel(entry.activeDays),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: dark
                                  ? AppColors.darkInkSubtle
                                  : AppColors.inkSubtle,
                              fontSize: 11,
                            ),
                      ),
                  ],
                ),
              ),
              // Toggle
              Switch(
                value: entry.enabled,
                onChanged: (_) => onToggle(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              // Edit chevron
              Icon(
                Icons.chevron_right,
                color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _daysLabel(List<int> days) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days.map((d) => names[d.clamp(0, 6)]).join(', ');
  }
}

// ── Edit bottom sheet ─────────────────────────────────────────────────────────

class _EntryEditSheet extends StatefulWidget {
  final RoutineEntry entry;
  final void Function(RoutineEntry) onSave;
  final VoidCallback? onDelete;

  const _EntryEditSheet({
    required this.entry,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_EntryEditSheet> createState() => _EntryEditSheetState();
}

class _EntryEditSheetState extends State<_EntryEditSheet> {
  late TextEditingController _labelCtrl;
  late TextEditingController _messageCtrl;
  late TextEditingController _waterCtrl;
  late TextEditingController _durationCtrl;
  late int _timeMin;
  late List<int> _activeDays;
  bool _enabled = true;
  bool _testingTts = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _labelCtrl    = TextEditingController(text: e.label);
    _messageCtrl  = TextEditingController(text: e.message);
    _waterCtrl    = TextEditingController(
        text: e.waterMl != null ? '${e.waterMl}' : '');
    _durationCtrl = TextEditingController(
        text: e.durationMinutes != null ? '${e.durationMinutes}' : '');
    _timeMin      = e.timeOfDayMinutes;
    _activeDays   = List.of(e.activeDays);
    _enabled      = e.enabled;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _messageCtrl.dispose();
    _waterCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final tod = TimeOfDay(
      hour: _timeMin ~/ 60,
      minute: _timeMin % 60,
    );
    final picked = await showTimePicker(context: context, initialTime: tod);
    if (picked == null) return;
    setState(() {
      _timeMin = picked.hour * 60 + picked.minute;
    });
  }

  Future<void> _testTts() async {
    setState(() => _testingTts = true);
    await TtsService.instance.speak(_messageCtrl.text.trim());
    if (mounted) setState(() => _testingTts = false);
  }

  void _save() {
    final updated = widget.entry.copyWith(
      label: _labelCtrl.text.trim().isEmpty
          ? widget.entry.label
          : _labelCtrl.text.trim(),
      message: _messageCtrl.text.trim().isEmpty
          ? widget.entry.message
          : _messageCtrl.text.trim(),
      timeOfDayMinutes: _timeMin,
      waterMl: int.tryParse(_waterCtrl.text.trim()),
      durationMinutes: int.tryParse(_durationCtrl.text.trim()),
      activeDays: _activeDays,
      enabled: _enabled,
    );
    widget.onSave(updated);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final h = _timeMin ~/ 60;
    final m = _timeMin % 60;
    final period = h < 12 ? 'AM' : 'PM';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final timeLabel = '$dh:${m.toString().padLeft(2, '0')} $period';

    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(AppRadius.sm),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: dark ? AppColors.darkSurface : AppColors.cardSurface,
          borderRadius:
              const BorderRadius.vertical(top: AppRadius.xl),
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: dark ? AppColors.darkBorder : AppColors.mist,
                  borderRadius: const BorderRadius.all(AppRadius.pill),
                ),
              ),
            ),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    widget.entry.type.emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit ${widget.entry.type.label}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.clay),
                      onPressed: widget.onDelete,
                      tooltip: 'Delete',
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // Enable toggle
                  Row(
                    children: [
                      const Text('Enabled'),
                      const Spacer(),
                      Switch(
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Time picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Time'),
                    subtitle: Text(timeLabel),
                    trailing: const Icon(Icons.access_time),
                    onTap: _pickTime,
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.all(AppRadius.sm),
                      side: BorderSide(
                        color: dark ? AppColors.darkBorder : AppColors.mist,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Label
                  TextField(
                    controller: _labelCtrl,
                    decoration: InputDecoration(
                      labelText: 'Label',
                      border: inputBorder,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Message
                  TextField(
                    controller: _messageCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Voice message',
                      alignLabelWithHint: true,
                      border: inputBorder,
                      suffixIcon: IconButton(
                        icon: _testingTts
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.volume_up),
                        onPressed: _testingTts ? null : _testTts,
                        tooltip: 'Preview voice',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Water ml (only for water types)
                  if (widget.entry.type == RoutineEntryType.morningWater ||
                      widget.entry.type == RoutineEntryType.waterReminder ||
                      widget.entry.type == RoutineEntryType.postWorkoutWater) ...[
                    TextField(
                      controller: _waterCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Water amount (ml)',
                        border: inputBorder,
                        suffixText: 'ml',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Duration (for workout)
                  if (widget.entry.type == RoutineEntryType.workout ||
                      widget.entry.type == RoutineEntryType.gym) ...[
                    TextField(
                      controller: _durationCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Duration (minutes)',
                        border: inputBorder,
                        suffixText: 'min',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Active days
                  const SizedBox(height: 4),
                  Text(
                    'Active days (empty = every day)',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      final active = _activeDays.contains(i);
                      return FilterChip(
                        label: Text(days[i]),
                        selected: active,
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _activeDays.add(i);
                            } else {
                              _activeDays.remove(i);
                            }
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Save button
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(AppRadius.md),
                      ),
                    ),
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action chip helper ────────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: accent
              ? AppColors.moss.withValues(alpha: dark ? 0.3 : 0.12)
              : (dark ? AppColors.darkSurface : AppColors.mist),
          borderRadius: const BorderRadius.all(AppRadius.sm),
          border: Border.all(
            color: accent
                ? AppColors.moss.withValues(alpha: 0.5)
                : (dark ? AppColors.darkBorder : AppColors.mistDark),
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 18,
                color: accent
                    ? AppColors.moss
                    : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle)),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent
                    ? AppColors.moss
                    : (dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
