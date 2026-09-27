import 'package:flutter/material.dart';
import '../models/routine_models.dart';
import '../services/routine_confirmation_service.dart';
import '../services/tts_service.dart';

/// Full-screen confirmation page opened when user taps a routine notification.
///
/// Wraps [showRoutineConfirmSheet] content in a Scaffold so it works
/// as a push route from the navigator (no context needed).
class RoutineConfirmScreen extends StatefulWidget {
  final RoutineEntry entry;
  const RoutineConfirmScreen({super.key, required this.entry});

  @override
  State<RoutineConfirmScreen> createState() => _RoutineConfirmScreenState();
}

class _RoutineConfirmScreenState extends State<RoutineConfirmScreen> {
  final _svc = RoutineConfirmationService.instance;
  final _notesCtrl = TextEditingController();
  final _waterCtrl = TextEditingController();
  final _customTimeCtrl = TextEditingController();

  final Set<String> _selectedFood = {};
  bool _showReschedule = false;
  int? _rescheduleMinutes;
  bool _submitting = false;
  bool _ttsSpoken = false;

  @override
  void initState() {
    super.initState();
    if (widget.entry.waterMl != null) {
      _waterCtrl.text = widget.entry.waterMl.toString();
    }
    Future.delayed(const Duration(milliseconds: 400), _speakPrompt);
  }

  Future<void> _speakPrompt() async {
    if (_ttsSpoken) return;
    if (!mounted) return;
    _ttsSpoken = true;
    final type = widget.entry.type;
    String prompt;
    if (type.isMeal) {
      prompt = 'Boss, did you have your ${widget.entry.label}? Log what you ate.';
    } else if (type.isWater) {
      prompt = 'Boss, log your water intake — ${widget.entry.waterMl ?? 400} ml.';
    } else {
      prompt = 'Boss, confirm your ${widget.entry.label}.';
    }
    await TtsService.instance.speak(prompt);
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
    TtsService.instance.stop();

    final waterMl = int.tryParse(_waterCtrl.text.trim());
    final food = _selectedFood.isNotEmpty ? _selectedFood.toList() : null;
    final notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    await _svc.confirmEntry(
      widget.entry,
      waterMlLogged: widget.entry.type.isWater ? waterMl : null,
      foodItems: widget.entry.type.isMeal ? food : null,
      notes: notes,
    );

    await TtsService.instance.speak('Confirmed! Great job, boss.');
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _skip() async {
    TtsService.instance.stop();
    await _svc.skipEntry(widget.entry);
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _reschedule(int minutes) async {
    TtsService.instance.stop();
    await _svc.rescheduleEntry(widget.entry, minutes);
    final timeStr = _minutesToHhmm(minutes);
    await TtsService.instance
        .speak('Rescheduled to $timeStr. I\'ll remind you then, boss.');
    if (mounted) Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMeal = widget.entry.type.isMeal;
    final isWater = widget.entry.type.isWater;
    final presets = widget.entry.type == RoutineEntryType.snacks
        ? RoutineConfirmationService.snackPresets
        : RoutineConfirmationService.messFoodPresets;
    final suggestions = _svc.suggestRescheduleTimes(widget.entry);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.entry.type.emoji} ${widget.entry.label}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            onPressed: () {
              _ttsSpoken = false;
              _speakPrompt();
            },
            tooltip: 'Replay',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Time badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Scheduled: ${widget.entry.formattedTime}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Water log
          if (isWater) ...[
            Text('Water logged (ml)',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _waterCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'e.g. 400',
                    suffixText: 'ml',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Quick presets
              ...([200, 400, 500].map((ml) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ActionChip(
                      label: Text('${ml}ml'),
                      onPressed: () =>
                          _waterCtrl.text = ml.toString(),
                    ),
                  ))),
            ]),
            const SizedBox(height: 20),
          ],

          // Food log
          if (isMeal) ...[
            Text('What did you eat?',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: presets.map((item) {
                final selected = _selectedFood.contains(item);
                return FilterChip(
                  label: Text(item),
                  selected: selected,
                  onSelected: (v) => setState(() => v
                      ? _selectedFood.add(item)
                      : _selectedFood.remove(item)),
                  selectedColor:
                      theme.colorScheme.primaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                hintText: 'Other items or notes...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Generic notes
          if (!isMeal && !isWater) ...[
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                hintText: 'Notes (optional)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Confirm
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _confirm,
              icon: const Icon(Icons.check_circle),
              label: const Text('Done — Confirm'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Reschedule section
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Reschedule'),
              initiallyExpanded: _showReschedule,
              onExpansionChanged: (v) =>
                  setState(() => _showReschedule = v),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quick options:',
                          style: theme.textTheme.labelSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: suggestions.map((m) {
                          return ActionChip(
                            label: Text(_minutesToHhmm(m)),
                            onPressed: () => _reschedule(m),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _customTimeCtrl,
                            readOnly: true,
                            decoration: InputDecoration(
                              hintText: 'Custom time',
                              prefixIcon:
                                  const Icon(Icons.access_time),
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12),
                            ),
                            onTap: () async {
                              final now = TimeOfDay.now();
                              final picked = await showTimePicker(
                                  context: context,
                                  initialTime: now);
                              if (picked != null) {
                                final m = picked.hour * 60 +
                                    picked.minute;
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
                              : () =>
                                  _reschedule(_rescheduleMinutes!),
                          child: const Text('Set'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Skip
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
    );
  }
}
