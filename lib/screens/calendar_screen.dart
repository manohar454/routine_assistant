import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';
import 'one_time_reminder_screen.dart';

/// Monthly calendar view for one-time reminders.
///
/// Shows a month grid with dot indicators on days that have scheduled tasks.
/// Tapping a day shows a list of that day's one-time reminders (Tasks) and
/// lets the user add a new one.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _db = DatabaseHelper.instance;

  late DateTime _focusedMonth;
  DateTime? _selectedDay;

  // task id → Task, for the whole visible month + neighbours.
  Map<String, List<Task>> _tasksByDay = {};
  List<Task> _dayTasks = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _loadMonth();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadMonth() async {
    setState(() => _loading = true);

    // Load from 1 week before start of month to 1 week after end.
    final start = _focusedMonth.subtract(const Duration(days: 7));
    final end = DateTime(
        _focusedMonth.year, _focusedMonth.month + 1, 0 + 7);

    final Map<String, List<Task>> byDay = {};

    // Iterate day by day across the range.
    var cur = DateTime(start.year, start.month, start.day);
    while (!cur.isAfter(end)) {
      final tasks = await _db.getTasksForDay(cur);
      if (tasks.isNotEmpty) {
        byDay[_dayKey(cur)] = tasks;
      }
      cur = cur.add(const Duration(days: 1));
    }

    if (!mounted) return;
    setState(() {
      _tasksByDay = byDay;
      _loading = false;
    });

    if (_selectedDay != null) {
      _loadDayTasks(_selectedDay!);
    }
  }

  void _loadDayTasks(DateTime day) {
    final key = _dayKey(day);
    setState(() {
      _dayTasks = _tasksByDay[key] ?? [];
    });
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Navigation ────────────────────────────────────────────────────────────

  void _prevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
    });
    _loadMonth();
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
    });
    _loadMonth();
  }

  void _selectDay(DateTime day) {
    setState(() => _selectedDay = day);
    _loadDayTasks(day);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _addReminder() async {
    final result = await Navigator.push<Task>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OneTimeReminderScreen(initialDate: _selectedDay),
      ),
    );
    if (result != null) {
      await _loadMonth(); // refresh dots + list
    }
  }

  Future<void> _editTask(Task task) async {
    final result = await Navigator.push<Task>(
      context,
      MaterialPageRoute(
        builder: (_) => OneTimeReminderScreen(task: task),
      ),
    );
    if (result != null) {
      await _loadMonth();
    }
  }

  Future<void> _deleteTask(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('Remove "${task.name}"?'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteTask(task.id);
      await _loadMonth();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final text = context.text;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alarm),
            tooltip: 'Add one-time reminder',
            onPressed: _addReminder,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addReminder,
        icon: const Icon(Icons.add),
        label: const Text('Add Reminder'),
      ),
      body: Column(
        children: [
          // ── Month grid ────────────────────────────────────────────────────
          _buildMonthHeader(dark, text),
          _buildWeekdayRow(text),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildDayGrid(dark, text),

          const Divider(height: 1),

          // ── Day detail ────────────────────────────────────────────────────
          Expanded(child: _buildDayDetail(dark, text)),
        ],
      ),
    );
  }

  Widget _buildMonthHeader(bool dark, TextTheme text) {
    final label =
        '${_monthName(_focusedMonth.month)} ${_focusedMonth.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _prevMonth,
          ),
          Text(label, style: text.titleLarge),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _nextMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayRow(TextTheme text) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: days
            .map((d) => Expanded(
                  child: Center(
                    child: Text(d,
                        style: text.labelSmall
                            ?.copyWith(letterSpacing: 0.5)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildDayGrid(bool dark, TextTheme text) {
    final firstDay = _focusedMonth;
    // Monday = 0 offset; DateTime.weekday: Mon=1, Sun=7
    final startOffset = (firstDay.weekday - 1) % 7;
    final daysInMonth = DateUtils.getDaysInMonth(
        _focusedMonth.year, _focusedMonth.month);

    final cells = <DateTime?>[];
    for (int i = 0; i < startOffset; i++) cells.add(null);
    for (int d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(_focusedMonth.year, _focusedMonth.month, d));
    }
    // Pad to full rows of 7.
    while (cells.length % 7 != 0) cells.add(null);

    final today = DateTime.now();
    final todayKey = _dayKey(today);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 0.85,
        ),
        itemCount: cells.length,
        itemBuilder: (ctx, i) {
          final day = cells[i];
          if (day == null) return const SizedBox();
          return _DayCell(
            day: day,
            isToday: _dayKey(day) == todayKey,
            isSelected: _selectedDay != null &&
                _dayKey(day) == _dayKey(_selectedDay!),
            hasTasks: _tasksByDay.containsKey(_dayKey(day)),
            dark: dark,
            onTap: () => _selectDay(day),
          );
        },
      ),
    );
  }

  Widget _buildDayDetail(bool dark, TextTheme text) {
    if (_selectedDay == null) {
      return Center(
        child: Text('Tap a day to see reminders', style: text.bodyMedium),
      );
    }

    final label =
        '${_selectedDay!.day} ${_monthName(_selectedDay!.month)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: text.headlineSmall),
              TextButton.icon(
                onPressed: _addReminder,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        if (_dayTasks.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_available,
                      size: 40,
                      color: dark
                          ? AppColors.darkInkSubtle
                          : AppColors.inkSubtle),
                  const SizedBox(height: 8),
                  Text('No reminders for this day',
                      style: text.bodyMedium),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: _dayTasks.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 8),
              itemBuilder: (ctx, i) =>
                  _TaskTile(
                    task: _dayTasks[i],
                    dark: dark,
                    onEdit: () => _editTask(_dayTasks[i]),
                    onDelete: () => _deleteTask(_dayTasks[i]),
                  ),
            ),
          ),
      ],
    );
  }

  String _monthName(int m) => const [
        '', 'January', 'February', 'March', 'April', 'May',
        'June', 'July', 'August', 'September', 'October',
        'November', 'December'
      ][m];
}

// ── Day cell ──────────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool hasTasks;
  final bool dark;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.hasTasks,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.text;

    Color? bg;
    Color numColor = dark ? AppColors.darkInk : AppColors.ink;

    if (isSelected) {
      bg = dark ? AppColors.darkDeep : AppColors.deep;
      numColor = Colors.white;
    } else if (isToday) {
      bg = (dark ? AppColors.darkDeep : AppColors.deep)
          .withValues(alpha: 0.15);
      numColor = dark ? AppColors.darkDeep : AppColors.deep;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.all(AppRadius.sm),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: text.bodyMedium?.copyWith(
                color: numColor,
                fontWeight:
                    isSelected || isToday ? FontWeight.w700 : null,
              ),
            ),
            if (hasTasks) ...[
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.8)
                      : (dark ? AppColors.darkAmber : AppColors.amber),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Task tile ─────────────────────────────────────────────────────────────────

class _TaskTile extends StatelessWidget {
  final Task task;
  final bool dark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskTile({
    required this.task,
    required this.dark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final hour = task.plannedStart.hour;
    final min =
        task.plannedStart.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final timeStr = '$displayHour:$min $amPm';

    return GestureDetector(
      onTap: onEdit,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.cardSurface,
        borderRadius: const BorderRadius.all(AppRadius.md),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.mist,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.darkAmber.withValues(alpha: 0.15)
                  : AppColors.amberLight,
              borderRadius: const BorderRadius.all(AppRadius.xs),
            ),
            child: Text(timeStr,
                style: text.labelSmall
                    ?.copyWith(color: dark ? AppColors.darkAmber : AppColors.amber)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.name, style: text.titleSmall),
                if (task.voiceMessage != null &&
                    task.voiceMessage!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(task.voiceMessage!,
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined,
                size: 20,
                color: dark
                    ? AppColors.darkInkSubtle
                    : AppColors.inkSubtle),
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 20,
                color: dark
                    ? AppColors.darkInkSubtle
                    : AppColors.inkSubtle),
            onPressed: onDelete,
          ),
        ],
      ),
    ),
    );
  }
}
