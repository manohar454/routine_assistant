import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/routine_models.dart';
import '../services/tts_service.dart';
import '../services/notification_service.dart';

/// Handles post-reminder confirmation flow for every RoutineEntry.
///
/// When a reminder fires the [RoutineAlarmService] calls [onReminderFired].
/// This service:
///   1. Creates a pending log row in routine_logs.
///   2. After a grace period (configurable per type) checks if confirmed.
///   3. If not confirmed: shows a missed-task notification with reschedule options.
///
/// Confirmations are written back via [confirmEntry] (called from the
/// confirmation bottom sheet shown on notification tap or in-app).
class RoutineConfirmationService {
  RoutineConfirmationService._internal();
  static final RoutineConfirmationService instance =
      RoutineConfirmationService._internal();

  final _db = DatabaseHelper.instance;
  final _uuid = const Uuid();

  // Active follow-up timers: entryId → timer
  final _followUpTimers = <String, Timer>{};

  // Common mess food presets
  static const messFoodPresets = [
    'Rice', 'Dal', 'Sambar', 'Rasam', 'Curd', 'Roti', 'Chapati',
    'Subji', 'Egg', 'Chicken', 'Fish', 'Upma', 'Pongal', 'Idli',
    'Dosa', 'Poha', 'Bread', 'Jam', 'Banana', 'Pappad',
  ];

  static const snackPresets = [
    'Banana', 'Groundnuts', 'Biscuits', 'Bread', 'Egg', 'Milk',
    'Tea', 'Coffee', 'Fruit', 'Protein bar', 'Oats',
  ];

  // Grace period before follow-up (minutes per type)
  static int gracePeriodMinutes(RoutineEntryType type) {
    switch (type) {
      case RoutineEntryType.wakeUp:        return 10;
      case RoutineEntryType.breakfast:
      case RoutineEntryType.lunch:
      case RoutineEntryType.dinner:        return 20;
      case RoutineEntryType.waterReminder:
      case RoutineEntryType.morningWater:
      case RoutineEntryType.postWorkoutWater: return 8;
      case RoutineEntryType.workout:
      case RoutineEntryType.gym:           return 5;
      case RoutineEntryType.nap:           return 5;
      case RoutineEntryType.study:         return 5;
      case RoutineEntryType.college:       return 5;
      case RoutineEntryType.snacks:        return 15;
      default:                             return 10;
    }
  }

  // ── Called by RoutineAlarmService when a notification fires ─────────────────

  Future<void> onReminderFired(RoutineEntry entry) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final logId = _uuid.v4();

    // Create pending log row
    await _db.upsertRoutineLog({
      'id': logId,
      'entryId': entry.id,
      'entryType': entry.type.name,
      'scheduledMinutes': entry.timeOfDayMinutes,
      'confirmedAt': null,
      'rescheduledTo': null,
      'skipped': 0,
      'waterMlLogged': null,
      'foodItems': null,
      'notes': null,
      'date': today,
    });

    // Schedule follow-up check
    final grace = gracePeriodMinutes(entry.type);
    _followUpTimers[entry.id]?.cancel();
    _followUpTimers[entry.id] = Timer(
      Duration(minutes: grace),
      () => _checkAndFollowUp(entry, logId, today),
    );
  }

  Future<void> _checkAndFollowUp(
      RoutineEntry entry, String logId, String date) async {
    final log = await _db.getRoutineLog(entry.id, date);
    if (log == null) return;
    if (log['confirmedAt'] != null || (log['skipped'] as int) == 1) return;

    // Not confirmed — send follow-up TTS + missed notification
    final msg = _missedMessage(entry);
    await TtsService.instance.speak(msg);

    // Send high-priority missed-task notification
    await _sendMissedNotification(entry);
  }

  String _missedMessage(RoutineEntry entry) {
    switch (entry.type) {
      case RoutineEntryType.wakeUp:
        return "Boss! It's time to wake up. You haven't confirmed yet. "
            "Get up now — champions don't sleep in!";
      case RoutineEntryType.breakfast:
      case RoutineEntryType.lunch:
      case RoutineEntryType.dinner:
        return "Boss, did you eat your ${entry.label.toLowerCase()}? "
            "Please confirm or reschedule.";
      case RoutineEntryType.waterReminder:
      case RoutineEntryType.morningWater:
      case RoutineEntryType.postWorkoutWater:
        return "Boss! You haven't logged your water yet. "
            "Drink ${entry.waterMl ?? 400}ml now and confirm.";
      case RoutineEntryType.workout:
      case RoutineEntryType.gym:
        return "Boss, your ${entry.label} reminder went unanswered. "
            "Did you complete it or should we reschedule?";
      case RoutineEntryType.study:
        return "Study time is passing, boss! "
            "Have you started or do you want to reschedule?";
      default:
        return "Boss, you missed your ${entry.label} reminder. "
            "Please confirm or reschedule.";
    }
  }

  Future<void> _sendMissedNotification(RoutineEntry entry) async {
    // Uses the existing notification plugin via NotificationService
    // Payload: 'missed:${entry.id}' for tap routing
    await NotificationService.instance.showMissedRoutineNotification(entry);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Mark an entry as confirmed for today.
  Future<void> confirmEntry(
    RoutineEntry entry, {
    int? waterMlLogged,
    List<String>? foodItems,
    String? notes,
  }) async {
    _followUpTimers[entry.id]?.cancel();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final existing = await _db.getRoutineLog(entry.id, today);

    final logId = existing?['id'] as String? ?? _uuid.v4();
    await _db.upsertRoutineLog({
      'id': logId,
      'entryId': entry.id,
      'entryType': entry.type.name,
      'scheduledMinutes': entry.timeOfDayMinutes,
      'confirmedAt': DateTime.now().toIso8601String(),
      'rescheduledTo': existing?['rescheduledTo'],
      'skipped': 0,
      'waterMlLogged': waterMlLogged,
      'foodItems': foodItems != null ? foodItems.join(',') : null,
      'notes': notes,
      'date': today,
    });
  }

  /// Skip an entry for today (user chose not to do it).
  Future<void> skipEntry(RoutineEntry entry) async {
    _followUpTimers[entry.id]?.cancel();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final existing = await _db.getRoutineLog(entry.id, today);
    final logId = existing?['id'] as String? ?? _uuid.v4();
    await _db.upsertRoutineLog({
      'id': logId,
      'entryId': entry.id,
      'entryType': entry.type.name,
      'scheduledMinutes': entry.timeOfDayMinutes,
      'confirmedAt': null,
      'rescheduledTo': existing?['rescheduledTo'],
      'skipped': 1,
      'waterMlLogged': null,
      'foodItems': null,
      'notes': null,
      'date': today,
    });
  }

  /// Reschedule an entry to a new time today.
  /// [newMinutes] = minutes since midnight.
  Future<void> rescheduleEntry(RoutineEntry entry, int newMinutes) async {
    _followUpTimers[entry.id]?.cancel();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final existing = await _db.getRoutineLog(entry.id, today);
    final logId = existing?['id'] as String? ?? _uuid.v4();

    await _db.upsertRoutineLog({
      'id': logId,
      'entryId': entry.id,
      'entryType': entry.type.name,
      'scheduledMinutes': entry.timeOfDayMinutes,
      'confirmedAt': null,
      'rescheduledTo': newMinutes,
      'skipped': 0,
      'waterMlLogged': null,
      'foodItems': null,
      'notes': null,
      'date': today,
    });

    // Re-arm the notification at the new time
    await _rescheduleNotification(entry, newMinutes);

    // Set a new follow-up
    final now = DateTime.now();
    final fireAt = DateTime(now.year, now.month, now.day,
        newMinutes ~/ 60, newMinutes % 60);
    final delay = fireAt.difference(now);
    if (delay.isNegative) return;

    _followUpTimers[entry.id] = Timer(
      delay + Duration(minutes: gracePeriodMinutes(entry.type)),
      () => _checkAndFollowUp(entry, logId, today),
    );
  }

  Future<void> _rescheduleNotification(
      RoutineEntry entry, int newMinutes) async {
    await NotificationService.instance
        .scheduleRescheduledReminder(entry, newMinutes);
  }

  /// Suggest 3 flexible reschedule times based on current time + entry type.
  List<int> suggestRescheduleTimes(RoutineEntry entry) {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // Suggest: +15 min, +30 min, +60 min from now (capped to end of day)
    final offsets = [15, 30, 60];
    return offsets
        .map((o) => currentMinutes + o)
        .where((m) => m < 22 * 60) // not after 10 PM
        .toList();
  }

  /// Whether an entry has been confirmed today.
  Future<bool> isConfirmedToday(String entryId) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final log = await _db.getRoutineLog(entryId, today);
    return log != null && log['confirmedAt'] != null;
  }

  /// Cancel all pending follow-up timers.
  /// Call before re-arming (e.g. when scheduleAll is called again after a
  /// timetable edit) to prevent duplicate onReminderFired callbacks.
  void cancelAllFollowUpTimers() {
    for (final t in _followUpTimers.values) {
      t.cancel();
    }
    _followUpTimers.clear();
  }

  void dispose() => cancelAllFollowUpTimers();
}

// ── Confirmation Bottom Sheet ─────────────────────────────────────────────────

/// Shows the confirmation sheet for a routine entry.
/// Returns true if confirmed, false if skipped.
Future<bool?> showRoutineConfirmSheet(
  BuildContext context,
  RoutineEntry entry,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ConfirmSheet(entry: entry),
  );
}

class _ConfirmSheet extends StatefulWidget {
  final RoutineEntry entry;
  const _ConfirmSheet({required this.entry});

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  final _svc = RoutineConfirmationService.instance;
  final _notesCtrl = TextEditingController();
  final _waterCtrl = TextEditingController();
  final _customTimeCtrl = TextEditingController();

  final Set<String> _selectedFood = {};
  bool _showReschedule = false;
  int? _rescheduleMinutes;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.entry.waterMl != null) {
      _waterCtrl.text = widget.entry.waterMl.toString();
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _waterCtrl.dispose();
    _customTimeCtrl.dispose();
    super.dispose();
  }

  String _minutesToHhmm(int m) {
    final h = m ~/ 60;
    final min = m % 60;
    final period = h >= 12 ? 'PM' : 'AM';
    final displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$displayH:${min.toString().padLeft(2, '0')} $period';
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final waterMl = int.tryParse(_waterCtrl.text.trim());
    final food = _selectedFood.isNotEmpty ? _selectedFood.toList() : null;
    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    await _svc.confirmEntry(
      widget.entry,
      waterMlLogged: widget.entry.type.isWater ? waterMl : null,
      foodItems: widget.entry.type.isMeal ? food : null,
      notes: notes,
    );

    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _skip() async {
    await _svc.skipEntry(widget.entry);
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _reschedule(int minutes) async {
    await _svc.rescheduleEntry(widget.entry, minutes);
    if (mounted) Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final isMeal = widget.entry.type.isMeal;
    final isWater = widget.entry.type.isWater;
    final suggestions = _svc.suggestRescheduleTimes(widget.entry);
    final presets = widget.entry.type == RoutineEntryType.snacks
        ? RoutineConfirmationService.snackPresets
        : RoutineConfirmationService.messFoodPresets;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(children: [
              Text(widget.entry.type.emoji,
                  style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.entry.label,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'Scheduled: ${widget.entry.formattedTime}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // ── Water log ──
            if (isWater) ...[
              Text('Water logged (ml)',
                  style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _waterCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'e.g. 400',
                  suffixText: 'ml',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Food log ──
            if (isMeal) ...[
              Text('What did you eat? (tap to select)',
                  style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: presets.map((item) {
                  final selected = _selectedFood.contains(item);
                  return FilterChip(
                    label: Text(item),
                    selected: selected,
                    onSelected: (v) => setState(() =>
                        v ? _selectedFood.add(item) : _selectedFood.remove(item)),
                    selectedColor:
                        theme.colorScheme.primaryContainer,
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                  hintText: 'Add other items...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Notes (non-food/non-water) ──
            if (!isMeal && !isWater) ...[
              TextField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                  hintText: 'Notes (optional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Confirm button ──
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _confirm,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Done — Confirm'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Reschedule toggle ──
            TextButton.icon(
              onPressed: () =>
                  setState(() => _showReschedule = !_showReschedule),
              icon: Icon(_showReschedule
                  ? Icons.expand_less
                  : Icons.schedule),
              label: const Text('Reschedule'),
            ),

            if (_showReschedule) ...[
              const SizedBox(height: 8),
              Text('Quick options:',
                  style: theme.textTheme.labelSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: suggestions.map((m) {
                  return ActionChip(
                    label: Text(_minutesToHhmm(m)),
                    onPressed: () => _reschedule(m),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              // Custom time picker
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _customTimeCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Custom time',
                      prefixIcon: const Icon(Icons.access_time),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onTap: () async {
                      final now = TimeOfDay.now();
                      final picked = await showTimePicker(
                          context: context, initialTime: now);
                      if (picked != null) {
                        final m = picked.hour * 60 + picked.minute;
                        setState(() {
                          _rescheduleMinutes = m;
                          _customTimeCtrl.text =
                              _minutesToHhmm(m);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _rescheduleMinutes == null
                      ? null
                      : () => _reschedule(_rescheduleMinutes!),
                  child: const Text('Set'),
                ),
              ]),
            ],

            const SizedBox(height: 16),

            // ── Skip ──
            Center(
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  'Skip for today',
                  style: TextStyle(
                      color: theme.colorScheme.error, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
