import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/routine_models.dart';
import '../services/routine_alarm_service.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import 'wake_alarm_screen.dart';
import 'calendar_screen.dart';

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
    // Remove any legacy seeded defaults from old DB versions.
    final legacyDefaults =
        stored.where((e) => e.id.startsWith('default_')).toList();
    for (final e in legacyDefaults) {
      await _db.deleteRoutineEntry(e.id);
    }
    final clean =
        stored.where((e) => !e.id.startsWith('default_')).toList();
    if (!mounted) return;
    setState(() {
      _entries = clean;
      _loading = false;
    });
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
    // Default to current time of day rounded to nearest 5 min.
    final now = DateTime.now();
    final rawMin = now.hour * 60 + now.minute;
    final roundedMin = ((rawMin + 2) ~/ 5) * 5; // round to nearest 5
    final entry = RoutineEntry(
      id: const Uuid().v4(),
      type: RoutineEntryType.reminder,
      timeOfDayMinutes: roundedMin,
      label: '',
      message: '',
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

  // ── Timetable settings ─────────────────────────────────────────────────────

  Future<void> _showTimetableSettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TimetableSettingsSheet(
        onResetToDefaults: _resetToDefaults,
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    final db = DatabaseHelper.instance;
    final waterGoal = int.tryParse(
            await db.getSetting('routine_waterGoalMl') ?? '') ?? 3000;
    final workoutDur = int.tryParse(
            await db.getSetting('routine_workoutDurationMinutes') ?? '') ?? 45;

    final defaults = DefaultRoutineTimetable.build(
      waterGoalMl: waterGoal,
      workoutDurationMinutes: workoutDur,
    );
    if (!mounted) return;
    setState(() {
      _entries = defaults;
      _entries.sort((a, b) => a.timeOfDayMinutes.compareTo(b.timeOfDayMinutes));
    });
    await _save();
  }

  // ── Wake alarm test ────────────────────────────────────────────────────────

  void _testWakeAlarm() {
    final wakeEntry = _entries
        .where((e) => e.type == RoutineEntryType.wake)
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
        onDelete: () async {
          final confirm = await showDialog<bool>(
            context: ctx,
            builder: (dCtx) => AlertDialog(
              title: const Text('Delete entry?'),
              content: Text(
                'Remove "${entry.label}" from your timetable?\n'
                'This cannot be undone — you can always reset to defaults from Settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dCtx, true),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(dCtx).colorScheme.error,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            _deleteEntry(entry.id);
            if (ctx.mounted) Navigator.pop(ctx);
          }
        },
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
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Monthly schedule & one-time reminders',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CalendarScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Timetable settings',
            onPressed: _showTimetableSettings,
          ),
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
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📋', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      'No entries yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap + Add Reminder to build your routine',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          _ScopeChip(
            label: 'Every day',
            icon: Icons.date_range_outlined,
            dark: dark,
            onTap: _applyToWholeWeek,
          ),
          const SizedBox(width: 8),
          _ScopeChip(
            label: 'This month',
            icon: Icons.calendar_today_outlined,
            dark: dark,
            onTap: _applyToWholeMonth,
          ),
          const Spacer(),
          GestureDetector(
            onTap: _testWakeAlarm,
            child: Row(
              children: [
                Icon(Icons.alarm_outlined,
                    size: 16,
                    color: dark
                        ? AppColors.darkInkSubtle
                        : AppColors.inkSubtle),
                const SizedBox(width: 4),
                Text(
                  'Test alarm',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: dark
                            ? AppColors.darkInkSubtle
                            : AppColors.inkSubtle,
                      ),
                ),
              ],
            ),
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
      case RoutineEntryType.wake:
        return dark ? const Color(0xFF2A2010) : AppColors.amberLight;
      case RoutineEntryType.activity:
        return dark ? const Color(0xFF0E2420) : AppColors.mossLight;
      case RoutineEntryType.meal:
        return dark ? const Color(0xFF1C1218) : AppColors.clayLight;
      case RoutineEntryType.hydration:
        return dark ? const Color(0xFF0C1E28) : const Color(0xFFE3F2FD);
      case RoutineEntryType.wind:
        return dark ? const Color(0xFF12101E) : const Color(0xFFEDE7F6);
      case RoutineEntryType.reminder:
        return dark ? AppColors.darkCard : AppColors.cardSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final emoji = (entry.extra['customEmoji'] as String?)?.isNotEmpty == true
        ? entry.extra['customEmoji'] as String
        : entry.type.emoji;

    return GestureDetector(
      onTap: onEdit,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: entry.enabled ? 1.0 : 0.45,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _cardColor(dark),
            borderRadius: const BorderRadius.all(AppRadius.lg),
            border: Border.all(
              color: (dark ? AppColors.darkBorder : AppColors.mist)
                  .withValues(alpha: entry.enabled ? 1.0 : 0.6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Time column
                SizedBox(
                  width: 60,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.formattedTime.split(' ')[0], // "7:00"
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        entry.formattedTime.split(' ')[1], // "AM/PM"
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
                // Vertical divider
                Container(
                  width: 1,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: (dark ? AppColors.darkBorder : AppColors.mist),
                ),
                // Emoji + label
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.label,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (entry.waterMl != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${entry.waterMl} ml',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: dark
                                        ? AppColors.darkDeep
                                        : AppColors.deep,
                                    fontSize: 11,
                                  ),
                        ),
                      ] else if (entry.durationMinutes != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${entry.durationMinutes} min',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: dark
                                        ? AppColors.darkInkSubtle
                                        : AppColors.inkSubtle,
                                    fontSize: 11,
                                  ),
                        ),
                      ] else if (entry.activeDays.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _daysLabel(entry.activeDays),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: dark
                                        ? AppColors.darkInkSubtle
                                        : AppColors.inkSubtle,
                                    fontSize: 11,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Toggle
                Switch(
                  value: entry.enabled,
                  onChanged: (_) => onToggle(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
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
  final Future<void> Function()? onDelete;

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
  late RoutineEntryType _type;
  late String _customEmoji;
  bool _enabled = true;
  bool _testingTts = false;
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _type         = e.type;
    _customEmoji  = (e.extra['customEmoji'] as String?) ?? '';
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

  void _onTypeChanged(RoutineEntryType? t) {
    if (t == null) return;
    setState(() {
      _type = t;
      // Auto-refresh label and message to match new type defaults only
      // if user hasn't customised them yet (matches current type defaults).
      final oldDefault = widget.entry.type.defaultMessage(
        waterMl: int.tryParse(_waterCtrl.text),
        durationMinutes: int.tryParse(_durationCtrl.text),
      );
      if (_messageCtrl.text.trim() == oldDefault ||
          _messageCtrl.text.trim() == widget.entry.message) {
        _messageCtrl.text = t.defaultMessage(
          waterMl: int.tryParse(_waterCtrl.text),
          durationMinutes: int.tryParse(_durationCtrl.text),
        );
      }
      if (_labelCtrl.text.trim() == widget.entry.type.label ||
          _labelCtrl.text.trim() == widget.entry.label) {
        _labelCtrl.text = t.label;
      }
      // Clear fields that don't apply to new type.
      if (!t.isWater) _waterCtrl.clear();
      if (!t.isDuration) _durationCtrl.clear();
    });
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
    if (picked == null || !mounted) return;
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
    final waterText = _waterCtrl.text.trim();
    final durText   = _durationCtrl.text.trim();

    // If field is now empty but had a value, explicitly clear to null.
    // Pass RoutineEntry._clearInt sentinel so copyWith doesn't keep old value.
    final int waterMl = waterText.isEmpty
        ? RoutineEntry.clearInt
        : (int.tryParse(waterText) ?? widget.entry.waterMl ?? RoutineEntry.clearInt);
    final int durationMins = durText.isEmpty
        ? RoutineEntry.clearInt
        : (int.tryParse(durText) ?? widget.entry.durationMinutes ?? RoutineEntry.clearInt);

    final updated = widget.entry.copyWith(
      type: _type,
      label: _labelCtrl.text.trim().isEmpty
          ? _type.label          // fall back to type name, not old label
          : _labelCtrl.text.trim(),
      message: _messageCtrl.text.trim().isEmpty
          ? _type.defaultMessage()
          : _messageCtrl.text.trim(),
      timeOfDayMinutes: _timeMin,
      waterMl: waterMl,
      durationMinutes: durationMins,
      activeDays: _activeDays,
      enabled: _enabled,
      extra: {
        ...widget.entry.extra,
        'customEmoji': _customEmoji,
      },
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
                    (_customEmoji.isNotEmpty) ? _customEmoji : _type.emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.entry.label.isEmpty ? 'New Entry' : 'Edit Entry',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.clay),
                    onPressed: widget.onDelete,
                    tooltip: 'Delete entry',
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
                  // Type picker
                  DropdownButtonFormField<RoutineEntryType>(
                    value: _type,
                    decoration: const InputDecoration(
                      labelText: 'Entry type',
                      border: inputBorder,
                    ),
                    items: RoutineEntryType.values.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Row(
                          children: [
                            Text(t.emoji,
                                style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(t.label),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _onTypeChanged,
                  ),
                  const SizedBox(height: 14),

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
                      hintText: 'e.g. Morning Run, Study Block…',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),

                  // Emoji picker
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showEmojiPicker = !_showEmojiPicker),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: dark
                            ? AppColors.darkSurface
                            : AppColors.cardSurface,
                        borderRadius:
                            const BorderRadius.all(AppRadius.sm),
                        border: Border.all(
                          color: dark
                              ? AppColors.darkBorder
                              : AppColors.mist,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _customEmoji.isNotEmpty
                                ? _customEmoji
                                : _type.emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Emoji icon',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium,
                            ),
                          ),
                          Icon(
                            _showEmojiPicker
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showEmojiPicker) ...[
                    const SizedBox(height: 8),
                    _EmojiGrid(
                      selected: _customEmoji,
                      onSelect: (e) => setState(() {
                        _customEmoji = e;
                        _showEmojiPicker = false;
                      }),
                    ),
                  ],
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

                  // Water ml — shown for all water-tracking types
                  if (_type.isWater) ...[
                    TextField(
                      controller: _waterCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Water amount (ml)',
                        hintText: 'e.g. 400',
                        border: inputBorder,
                        suffixText: 'ml',
                        helperText: 'Clear to remove water tracking',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Duration — shown for all timed-block types (workout, gym, nap, study)
                  if (_type.isDuration) ...[
                    TextField(
                      controller: _durationCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Duration (minutes)',
                        hintText: 'e.g. 45',
                        border: inputBorder,
                        suffixText: 'min',
                        helperText: 'Clear to omit duration from voice message',
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

// ── Emoji grid ────────────────────────────────────────────────────────────────

class _EmojiGrid extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;

  const _EmojiGrid({required this.selected, required this.onSelect});

  static const _emojis = [
    // Health & body
    '💧','🥤','🍎','🥗','🍽️','🥕','🍳','☕','🧃',
    // Fitness
    '🏃','🏋️','🚴','🧘','⚽','🏀','🎾','🤸','💪','🥊',
    // Mind & study
    '📚','📖','✏️','🎯','💡','🧠','📝','🖥️','🎓','📐',
    // Time & reminders
    '⏰','🔔','🔕','⏱️','⌚','📅','🗓️','⏳',
    // Routine
    '🌅','🌙','😴','🛏️','🚿','🪥','🪴','🧘',
    // Work
    '💼','📊','📈','📋','✅','🗂️','💬','📞','📧',
    // Fun & life
    '🎵','🎮','🎨','📸','🌿','🌸','🐾','🚗','🌍','❤️',
  ];

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.canvas,
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.mist,
        ),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: _emojis.map((e) {
          final isSel = e == selected;
          return GestureDetector(
            onTap: () => onSelect(e),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSel
                    ? (dark ? AppColors.darkDeep : AppColors.deep)
                        .withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: const BorderRadius.all(AppRadius.xs),
                border: isSel
                    ? Border.all(
                        color: dark ? AppColors.darkDeep : AppColors.deep,
                        width: 1.5,
                      )
                    : null,
              ),
              child: Center(
                child: Text(e, style: const TextStyle(fontSize: 20)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Timetable settings sheet ──────────────────────────────────────────────────

class _TimetableSettingsSheet extends StatefulWidget {
  final Future<void> Function() onResetToDefaults;

  const _TimetableSettingsSheet({required this.onResetToDefaults});

  @override
  State<_TimetableSettingsSheet> createState() =>
      _TimetableSettingsSheetState();
}

class _TimetableSettingsSheetState extends State<_TimetableSettingsSheet> {
  final _waterCtrl    = TextEditingController();
  final _workoutCtrl  = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final db = DatabaseHelper.instance;
    final water   = await db.getSetting('routine_waterGoalMl');
    final workout = await db.getSetting('routine_workoutDurationMinutes');
    if (!mounted) return;
    setState(() {
      _waterCtrl.text   = water   ?? '3000';
      _workoutCtrl.text = workout ?? '45';
    });
  }

  Future<void> _savePrefs() async {
    setState(() => _saving = true);
    final db = DatabaseHelper.instance;
    await db.setSetting('routine_waterGoalMl',
        '${int.tryParse(_waterCtrl.text) ?? 3000}');
    await db.setSetting('routine_workoutDurationMinutes',
        '${int.tryParse(_workoutCtrl.text) ?? 45}');
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Default settings saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to defaults?'),
        content: const Text(
          'This will replace your entire timetable with the default schedule '
          'using the settings above. All custom edits will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _savePrefs();
    await widget.onResetToDefaults();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _waterCtrl.dispose();
    _workoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(AppRadius.sm),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: dark ? AppColors.darkSurface : AppColors.cardSurface,
          borderRadius: const BorderRadius.vertical(top: AppRadius.xl),
        ),
        child: Column(
          children: [
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Default Timetable Settings',
                    style: Theme.of(context).textTheme.titleMedium,
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
                  Text(
                    'These values are used when resetting to the default timetable.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: dark
                              ? AppColors.darkInkSubtle
                              : AppColors.inkSubtle,
                        ),
                  ),
                  const SizedBox(height: 20),

                  // Daily water goal
                  TextField(
                    controller: _waterCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Daily water goal',
                      suffixText: 'ml',
                      helperText: 'Split evenly across water reminder slots',
                      border: inputBorder,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Workout duration
                  TextField(
                    controller: _workoutCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Default workout duration',
                      suffixText: 'min',
                      border: inputBorder,
                    ),
                  ),
                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: _saving ? null : _savePrefs,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(AppRadius.md),
                      ),
                    ),
                    child: const Text('Save Settings'),
                  ),
                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: _saving ? null : _confirmReset,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Reset Timetable to Defaults'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(AppRadius.md),
                      ),
                    ),
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

// ── Scope chip ────────────────────────────────────────────────────────────────

class _ScopeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool dark;
  final VoidCallback onTap;

  const _ScopeChip({
    required this.label,
    required this.icon,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : AppColors.canvas,
          borderRadius: const BorderRadius.all(AppRadius.pill),
          border: Border.all(
            color: dark ? AppColors.darkBorder : AppColors.mist,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color:
                    dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color:
                    dark ? AppColors.darkInk : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
