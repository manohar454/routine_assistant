import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// Screen for creating a one-time reminder at a specific date and time.
///
/// Saves the reminder as a [Task] with a concrete [plannedStart] and
/// schedules a local notification via [NotificationService].
///
/// If [initialDate] is provided (e.g. tapped from the calendar), the date
/// picker starts on that day.
class OneTimeReminderScreen extends StatefulWidget {
  final DateTime? initialDate;

  const OneTimeReminderScreen({super.key, this.initialDate});

  @override
  State<OneTimeReminderScreen> createState() => _OneTimeReminderScreenState();
}

class _OneTimeReminderScreenState extends State<OneTimeReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final base = widget.initialDate ?? DateTime.now();
    _selectedDate = DateTime(base.year, base.month, base.day);
    final now = TimeOfDay.now();
    // Round up to next 5-minute mark.
    final rawMin = now.minute;
    final nextMin = ((rawMin + 5) ~/ 5) * 5;
    _selectedTime = nextMin >= 60
        ? TimeOfDay(hour: (now.hour + 1) % 24, minute: nextMin - 60)
        : TimeOfDay(hour: now.hour, minute: nextMin);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ── Pickers ─────────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final label = _labelCtrl.text.trim();
      final note = _noteCtrl.text.trim();

      final plannedStart = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      final task = Task(
        id: const Uuid().v4(),
        name: label,
        category: 'reminder',
        plannedStart: plannedStart,
        estimatedDurationMinutes: 5,
        flexibility: TaskFlexibility.fixed,
        voiceMessage: note.isEmpty ? null : note,
      );

      await DatabaseHelper.instance.insertTask(task);

      // Schedule the notification.
      final notifId = task.id.hashCode.abs() % 2147483647;
      await NotificationService.instance.scheduleTaskReminder(
        notificationId: notifId,
        title: '⏰ $label',
        body: note.isEmpty ? 'Time for your reminder!' : note,
        scheduledTime: plannedStart,
        taskCategory: 'reminder',
      );

      if (!mounted) return;
      Navigator.pop(context, task); // return task to caller (calendar)
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final colors = context.colors;
    final text = context.text;

    final dateLabel =
        '${_selectedDate.day} ${_monthName(_selectedDate.month)} ${_selectedDate.year}';
    final timeLabel = _selectedTime.format(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('One-Time Reminder'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            // ── Label ───────────────────────────────────────────────────────
            TextFormField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Reminder label',
                hintText: 'e.g. Doctor appointment',
                prefixIcon: Icon(Icons.label_outline),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter a label';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Note ────────────────────────────────────────────────────────
            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Any extra details…',
                prefixIcon: Icon(Icons.notes),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 28),

            // ── Date & Time row ──────────────────────────────────────────────
            Text('When', style: text.titleSmall),
            const SizedBox(height: 12),

            Row(
              children: [
                // Date pill
                Expanded(
                  child: _PickerTile(
                    icon: Icons.calendar_today,
                    label: 'Date',
                    value: dateLabel,
                    dark: dark,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                // Time pill
                Expanded(
                  child: _PickerTile(
                    icon: Icons.access_time,
                    label: 'Time',
                    value: timeLabel,
                    dark: dark,
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // ── Save button ──────────────────────────────────────────────────
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.notifications_active_outlined),
              label: Text(_saving ? 'Saving…' : 'Schedule Reminder'),
            ),

            const SizedBox(height: 12),

            // Info note
            Row(
              children: [
                Icon(Icons.info_outline, size: 14,
                    color: dark
                        ? AppColors.darkInkSubtle
                        : AppColors.inkSubtle),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'You\'ll get a notification at the chosen date and time.',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

// ── Picker tile widget ────────────────────────────────────────────────────────

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool dark;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : AppColors.cardSurface,
          borderRadius: const BorderRadius.all(AppRadius.md),
          border: Border.all(
            color: dark ? AppColors.darkBorder : AppColors.mist,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14,
                    color: dark ? AppColors.darkDeep : AppColors.deep),
                const SizedBox(width: 4),
                Text(label, style: text.labelSmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: text.titleSmall,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
