import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/task.dart';
import '../models/timetable_models.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// Reusable timetable template screen.
///
/// Users define a set of task templates (name, time, duration).
/// A toggle lets them apply the timetable to the current week or month,
/// bulk-creating Task records in the DB for every day in that range.
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

enum _ApplyRange { week, month }

class _TimetableScreenState extends State<TimetableScreen> {
  final _db = DatabaseHelper.instance;
  List<TimetableEntry> _entries = [];
  _ApplyRange _range = _ApplyRange.week;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _db.getTimetableEntries();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _addEntry() async {
    final result = await showModalBottomSheet<TimetableEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EntryFormSheet(),
    );
    if (result != null) {
      await _db.insertTimetableEntry(result);
      await _load();
    }
  }

  Future<void> _editEntry(TimetableEntry entry) async {
    final result = await showModalBottomSheet<TimetableEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EntryFormSheet(existing: entry),
    );
    if (result != null) {
      await _db.updateTimetableEntry(result);
      await _load();
    }
  }

  Future<void> _deleteEntry(TimetableEntry entry) async {
    await _db.deleteTimetableEntry(entry.id);
    await _load();
  }

  Future<void> _applyTimetable() async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one task to the timetable first')),
      );
      return;
    }

    final days = _daysInRange();
    final rangeLabel = _range == _ApplyRange.week ? 'week' : 'month';
    final totalTasks = _entries.length * days.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apply to this $rangeLabel?'),
        content: Text(
          'This will create ${_entries.length} task(s) × '
          '${days.length} days = $totalTasks tasks.\n\n'
          'Existing tasks on those days are not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _applying = true);

    final uuid = const Uuid();
    int created = 0;

    try {
      for (final day in days) {
        if (!mounted) break;
        for (final entry in _entries) {
          if (!mounted) break;
          final task = entry.toTask(date: day, taskId: uuid.v4());
          await _db.insertTask(task);

          // Schedule voice check-in notification at task end
          if (task.plannedEnd.isAfter(DateTime.now())) {
            final baseId = task.id.hashCode & 0x7fffffff;
            await NotificationService.instance.scheduleVoiceCheckIn(
              taskId: task.id,
              notificationId: baseId + 1,
              taskName: task.name,
              checkInTime: task.plannedEnd,
            );
          }
          created++;
        }
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$created tasks created for this $rangeLabel'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  List<DateTime> _daysInRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_range == _ApplyRange.week) {
      // Monday–Sunday of current week
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return List.generate(7, (i) => monday.add(Duration(days: i)));
    } else {
      // All days in current month
      final firstDay = DateTime(now.year, now.month, 1);
      final lastDay  = DateTime(now.year, now.month + 1, 0);
      return List.generate(
        lastDay.day,
        (i) => firstDay.add(Duration(days: i)),
      );
    }
  }

  String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? AppColors.darkCanvas   : AppColors.canvas;
    final card   = isDark ? AppColors.darkCard      : AppColors.cardSurface;
    final border = isDark ? AppColors.darkBorder    : AppColors.mist;
    final ink    = isDark ? AppColors.darkInk       : AppColors.ink;
    final subtle = isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle;
    final accent = isDark ? AppColors.darkMoss      : AppColors.moss;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Timetable', style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: ink),
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: accent),
            tooltip: 'Add task template',
            onPressed: _addEntry,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Apply range toggle ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  _RangeChip(
                    label: 'This Week',
                    selected: _range == _ApplyRange.week,
                    accent: accent,
                    card: card,
                    isDark: isDark,
                    onTap: () => setState(() => _range = _ApplyRange.week),
                  ),
                  _RangeChip(
                    label: 'This Month',
                    selected: _range == _ApplyRange.month,
                    accent: accent,
                    card: card,
                    isDark: isDark,
                    onTap: () => setState(() => _range = _ApplyRange.month),
                  ),
                ],
              ),
            ),
          ),

          // ── Entry count info ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  '${_entries.length} task template${_entries.length == 1 ? '' : 's'}',
                  style: TextStyle(color: subtle, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  '${_daysInRange().length} days',
                  style: TextStyle(color: subtle, fontSize: 13),
                ),
              ],
            ),
          ),

          // ── Entry list ──
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.table_rows_rounded, size: 48, color: subtle),
                        const SizedBox(height: 12),
                        Text('No tasks in timetable',
                            style: TextStyle(color: subtle, fontSize: 15)),
                        const SizedBox(height: 6),
                        Text('Tap + to add a task template',
                            style: TextStyle(color: subtle, fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final e = _entries[i];
                      return GestureDetector(
                        onTap: () => _editEntry(e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border),
                          ),
                          child: Row(
                            children: [
                              // Time badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _fmt(e.hour, e.minute),
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Name + meta
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.name,
                                        style: TextStyle(
                                            color: ink,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15)),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(e.category,
                                            style: TextStyle(
                                                color: subtle, fontSize: 12)),
                                        Text(' · ',
                                            style:
                                                TextStyle(color: subtle, fontSize: 12)),
                                        Text('${e.estimatedDurationMinutes} min',
                                            style: TextStyle(
                                                color: subtle, fontSize: 12)),
                                        Text(' · ',
                                            style:
                                                TextStyle(color: subtle, fontSize: 12)),
                                        Text(
                                          e.flexibility == TaskFlexibility.flexible
                                              ? 'Flexible'
                                              : 'Fixed',
                                          style: TextStyle(
                                              color: subtle, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Delete
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded,
                                    color: subtle, size: 20),
                                onPressed: () => _deleteEntry(e),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),

      // ── Apply button ──
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _applying ? null : _applyTimetable,
            icon: _applying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_applying
                ? 'Applying…'
                : 'Apply to this ${_range == _ApplyRange.week ? 'week' : 'month'}'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Range toggle chip ─────────────────────────────────────────────────────────

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final Color card;
  final bool isDark;
  final VoidCallback onTap;

  const _RangeChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.card,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : (isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Entry form bottom sheet ───────────────────────────────────────────────────

class _EntryFormSheet extends StatefulWidget {
  final TimetableEntry? existing;
  const _EntryFormSheet({this.existing});

  @override
  State<_EntryFormSheet> createState() => _EntryFormSheetState();
}

class _EntryFormSheetState extends State<_EntryFormSheet> {
  final _nameCtrl = TextEditingController();
  final _catCtrl  = TextEditingController();
  final _durCtrl  = TextEditingController();
  TimeOfDay _time = TimeOfDay.now();
  TaskFlexibility _flex = TaskFlexibility.flexible;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _catCtrl.text  = e.category;
      _durCtrl.text  = '${e.estimatedDurationMinutes}';
      _time = TimeOfDay(hour: e.hour, minute: e.minute);
      _flex = e.flexibility;
    } else {
      _catCtrl.text = 'General';
      _durCtrl.text = '30';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _catCtrl.dispose();
    _durCtrl.dispose();
    super.dispose();
  }

  void _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final cat  = _catCtrl.text.trim();
    final dur  = int.tryParse(_durCtrl.text.trim()) ?? 30;
    if (name.isEmpty) return;

    final entry = TimetableEntry(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: name,
      category: cat.isEmpty ? 'General' : cat,
      hour: _time.hour,
      minute: _time.minute,
      estimatedDurationMinutes: dur.clamp(1, 1440),
      flexibility: _flex,
    );
    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? AppColors.darkCard    : AppColors.cardSurface;
    final ink     = isDark ? AppColors.darkInk     : AppColors.ink;
    final subtle  = isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle;
    final border  = isDark ? AppColors.darkBorder  : AppColors.mist;
    final accent  = isDark ? AppColors.darkMoss    : AppColors.moss;

    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            widget.existing == null ? 'Add Task Template' : 'Edit Task Template',
            style: TextStyle(
                color: ink, fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 20),

          // Task name
          _field(
            controller: _nameCtrl,
            label: 'Task name',
            isDark: isDark,
            ink: ink,
            border: border,
            autofocus: true,
          ),
          const SizedBox(height: 12),

          // Category
          _field(
            controller: _catCtrl,
            label: 'Category',
            isDark: isDark,
            ink: ink,
            border: border,
          ),
          const SizedBox(height: 12),

          // Time + duration row
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            color: accent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  controller: _durCtrl,
                  label: 'Duration (min)',
                  isDark: isDark,
                  ink: ink,
                  border: border,
                  keyboard: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Flexibility toggle
          Row(
            children: [
              Text('Flexibility', style: TextStyle(color: subtle, fontSize: 13)),
              const SizedBox(width: 12),
              _FlexChip(
                label: 'Flexible',
                selected: _flex == TaskFlexibility.flexible,
                accent: accent,
                isDark: isDark,
                onTap: () => setState(() => _flex = TaskFlexibility.flexible),
              ),
              const SizedBox(width: 8),
              _FlexChip(
                label: 'Fixed',
                selected: _flex == TaskFlexibility.fixed,
                accent: AppColors.amber,
                isDark: isDark,
                onTap: () => setState(() => _flex = TaskFlexibility.fixed),
              ),
            ],
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                widget.existing == null ? 'Add' : 'Save',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required bool isDark,
    required Color ink,
    required Color border,
    bool autofocus = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboard,
      style: TextStyle(color: ink, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
        filled: true,
        fillColor: isDark ? AppColors.darkSurface : AppColors.canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? AppColors.darkMoss : AppColors.moss, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    );
  }
}

class _FlexChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  const _FlexChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : (isDark ? AppColors.darkBorder : AppColors.mist),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : (isDark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
