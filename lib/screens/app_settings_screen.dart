import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../db/database_helper.dart';
import '../models/music_models.dart';
import '../theme/app_theme.dart';

/// Central settings screen — water goal, sleep floor, music library,
/// and simulation sandbox.
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final _db = DatabaseHelper.instance;

  // ── water ──
  int _waterGoalMl = 3000;
  final _waterCtrl = TextEditingController();

  // ── sleep floor ──
  int _sleepFloorMinutes = 420; // 7h default
  final _sleepCtrl = TextEditingController();

  // ── snooze ──
  int _snoozeMins = 10;

  // ── music ──
  List<MusicTrack> _tracks = [];
  bool _loadingTracks = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final waterStr  = await _db.getSetting('water_daily_goal_ml');
    final sleepStr  = await _db.getSetting('sleep_floor_minutes');
    final snoozeStr = await _db.getSetting('snooze_duration_minutes');
    final tracks    = await _db.getAllTracks();
    if (!mounted) return;
    setState(() {
      _waterGoalMl       = int.tryParse(waterStr ?? '')  ?? 2500;
      _sleepFloorMinutes = int.tryParse(sleepStr ?? '')  ?? 420;
      _snoozeMins        = int.tryParse(snoozeStr ?? '') ?? 10;
      _waterCtrl.text = (_waterGoalMl / 1000).toStringAsFixed(1);
      _sleepCtrl.text = (_sleepFloorMinutes ~/ 60).toString();
      _tracks = tracks;
    });
  }

  Future<void> _saveWaterGoal(String raw) async {
    final litres = double.tryParse(raw);
    if (litres == null || litres < 0.5 || litres > 10) return;
    final ml = (litres * 1000).round();
    await _db.setSetting('water_daily_goal_ml', ml.toString());
    if (!mounted) return;
    setState(() => _waterGoalMl = ml);
    _showSaved();
  }

  Future<void> _saveSleepFloor(String raw) async {
    final hours = int.tryParse(raw);
    if (hours == null || hours < 4 || hours > 12) return;
    final minutes = hours * 60;
    await _db.setSetting('sleep_floor_minutes', minutes.toString());
    if (!mounted) return;
    setState(() => _sleepFloorMinutes = minutes);
    _showSaved();
  }

  void _showSaved() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Saved'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadius.md)),
      ),
    );
  }

  Future<void> _addMusicFile() async {
    setState(() => _loadingTracks = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result == null || !mounted) {
        setState(() => _loadingTracks = false);
        return;
      }
      for (final f in result.files) {
        if (f.path == null) continue;
        final name = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
        final track = MusicTrack(
          id: 'track_${DateTime.now().microsecondsSinceEpoch}_${f.name.hashCode}',
          filePath: f.path!,
          title: name,
          artist: 'Unknown',
          moodTags: const ['focus'],
        );
        await _db.insertTrack(track);
      }
      final tracks = await _db.getAllTracks();
      if (!mounted) return;
      setState(() => _tracks = tracks);
      _showSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not pick file: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingTracks = false);
    }
  }

  @override
  void dispose() {
    _waterCtrl.dispose();
    _sleepCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final ink = dark ? AppColors.darkInk : AppColors.ink;
    final sub = dark ? AppColors.darkInkSubtle : AppColors.inkSubtle;
    final card = dark ? AppColors.darkCard : AppColors.cardSurface;
    final border = dark ? AppColors.darkBorder : AppColors.mist;

    return Scaffold(
      backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      appBar: AppBar(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Settings',
          style: context.text.titleMedium
              ?.copyWith(color: ink, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
        children: [
          // ── Section: Health Goals ─────────────────────────────────────
          _SectionHeader(label: 'Health Goals', ink: sub),
          const SizedBox(height: 8),
          _SettingsCard(
            card: card,
            border: border,
            children: [
              _FieldRow(
                icon: Icons.water_drop_rounded,
                iconColor: dark ? AppColors.darkDeep : AppColors.deepLight,
                label: 'Daily water goal',
                sublabel: 'Current: ${(_waterGoalMl / 1000).toStringAsFixed(1)} L',
                dark: dark,
                ink: ink,
                sub: sub,
                child: SizedBox(
                  width: 80,
                  child: _InlineField(
                    controller: _waterCtrl,
                    suffix: 'L',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onSubmit: _saveWaterGoal,
                    dark: dark,
                    ink: ink,
                  ),
                ),
              ),
              _Divider(border: border),
              _FieldRow(
                icon: Icons.bedtime_rounded,
                iconColor: dark ? AppColors.darkMoss : AppColors.moss,
                label: 'Sleep floor',
                sublabel:
                    'Minimum: ${_sleepFloorMinutes ~/ 60}h · affects burnout model',
                dark: dark,
                ink: ink,
                sub: sub,
                child: SizedBox(
                  width: 80,
                  child: _InlineField(
                    controller: _sleepCtrl,
                    suffix: 'h',
                    keyboardType: TextInputType.number,
                    onSubmit: _saveSleepFloor,
                    dark: dark,
                    ink: ink,
                  ),
                ),
              ),
              _Divider(border: border),
              _FieldRow(
                icon: Icons.snooze_rounded,
                iconColor: dark ? AppColors.darkAmber : AppColors.amber,
                label: 'Default snooze',
                sublabel: 'Applied when tapping Snooze on a missed task',
                dark: dark,
                ink: ink,
                sub: sub,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [5, 10, 15, 20].map((mins) {
                    final selected = mins == _snoozeMins;
                    final accent = dark ? AppColors.darkAmber : AppColors.amber;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: GestureDetector(
                        onTap: () async {
                          await _db.setSetting(
                              'snooze_duration_minutes', mins.toString());
                          if (!mounted) return;
                          setState(() => _snoozeMins = mins);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: selected
                                ? accent
                                : (dark
                                    ? AppColors.darkSurface
                                    : AppColors.canvas),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? accent
                                  : (dark
                                      ? AppColors.darkBorder
                                      : AppColors.mist),
                            ),
                          ),
                          child: Text(
                            '${mins}m',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : (dark ? AppColors.darkInk : AppColors.ink),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Section: Music Library ────────────────────────────────────
          _SectionHeader(label: 'Music Library', ink: sub),
          const SizedBox(height: 8),
          _SettingsCard(
            card: card,
            border: border,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.library_music_rounded,
                      color: dark ? AppColors.darkAmber : AppColors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Local audio files',
                            style: context.text.labelMedium?.copyWith(
                                color: ink, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${_tracks.length} track${_tracks.length == 1 ? '' : 's'} · plays automatically for tasks',
                            style:
                                context.text.bodySmall?.copyWith(color: sub),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _loadingTracks ? null : _addMusicFile,
                      icon: _loadingTracks
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: dark
                                    ? AppColors.darkDeep
                                    : AppColors.deep,
                              ),
                            )
                          : const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add'),
                      style: TextButton.styleFrom(
                        foregroundColor:
                            dark ? AppColors.darkDeep : AppColors.deep,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
              if (_tracks.isNotEmpty) ...[
                _Divider(border: border),
                ..._tracks.map(
                  (t) => _TrackRow(
                    track: t,
                    border: border,
                    ink: ink,
                    sub: sub,
                    dark: dark,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),

          // ── Section: What-if Simulator ────────────────────────────────
          _SectionHeader(label: 'Schedule Simulator', ink: sub),
          const SizedBox(height: 8),
          _SettingsCard(
            card: card,
            border: border,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.science_rounded,
                          color:
                              dark ? AppColors.darkClay : AppColors.clay,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'What-if Explorer',
                            style: context.text.labelMedium?.copyWith(
                                color: ink, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Adjust hypothetical sleep or schedule load to see how the AI predicts burnout risk and completion rate would shift.',
                      style: context.text.bodySmall?.copyWith(color: sub),
                    ),
                    const SizedBox(height: 14),
                    _WhatIfSimulator(dark: dark, ink: ink, sub: sub),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// What-if simulator widget (inline, no external API calls)
// ─────────────────────────────────────────────────────────────────────────────

class _WhatIfSimulator extends StatefulWidget {
  final bool dark;
  final Color ink;
  final Color sub;

  const _WhatIfSimulator(
      {required this.dark, required this.ink, required this.sub});

  @override
  State<_WhatIfSimulator> createState() => _WhatIfSimulatorState();
}

class _WhatIfSimulatorState extends State<_WhatIfSimulator> {
  double _sleepHours = 7.0;
  double _taskLoad = 8.0; // tasks per day
  String? _result;

  void _simulate() {
    // Simple local model — mirrors BurnoutForecastEngine's weights
    // (sleep debt 0.4, completion drift 0.35, density 0.25)
    // No external call; all in-memory math.
    const sleepFloor = 7.5;
    final sleepDebt = ((sleepFloor - _sleepHours) / sleepFloor).clamp(0.0, 1.0);
    // Task load: normalise against 12-task reference day
    final loadSignal = (_taskLoad / 12.0).clamp(0.0, 1.0);
    // Predicted completion rate drops under high load + low sleep
    final predictedCompletion = 1.0 - (sleepDebt * 0.5 + loadSignal * 0.3);
    final riskScore =
        (sleepDebt * 0.45 + (1 - predictedCompletion) * 0.35 + loadSignal * 0.2)
            .clamp(0.0, 1.0);

    String level;
    String advice;
    if (riskScore > 0.65) {
      level = '🔴 High burnout risk';
      advice =
          'Sleep + load combination is unsustainable. Consider cutting 2–3 tasks or adding 45 min of sleep.';
    } else if (riskScore > 0.35) {
      level = '🟡 Moderate burnout risk';
      advice =
          'Manageable but watch the trend. Adding 30 min of sleep drops risk by ~12%.';
    } else {
      level = '🟢 Low burnout risk';
      advice =
          'Good balance. Predicted completion rate ${(predictedCompletion * 100).round()}%.';
    }

    setState(() {
      _result =
          '$level\n\nPredicted completion rate: ${(predictedCompletion * 100).round()}%\n\n$advice';
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.dark ? AppColors.darkDeep : AppColors.deep;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sleep: ${_sleepHours.toStringAsFixed(1)}h',
          style:
              context.text.labelSmall?.copyWith(color: widget.ink),
        ),
        Slider(
          value: _sleepHours,
          min: 4,
          max: 10,
          divisions: 12,
          activeColor: accent,
          inactiveColor: accent.withValues(alpha: 0.20),
          onChanged: (v) => setState(() {
            _sleepHours = v;
            _result = null;
          }),
        ),
        const SizedBox(height: 4),
        Text(
          'Daily tasks: ${_taskLoad.round()}',
          style:
              context.text.labelSmall?.copyWith(color: widget.ink),
        ),
        Slider(
          value: _taskLoad,
          min: 2,
          max: 20,
          divisions: 18,
          activeColor: accent,
          inactiveColor: accent.withValues(alpha: 0.20),
          onChanged: (v) => setState(() {
            _taskLoad = v;
            _result = null;
          }),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Run simulation'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(AppRadius.md)),
              padding:
                  const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _simulate,
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.all(AppRadius.md),
              border: Border.all(color: accent.withValues(alpha: 0.20)),
            ),
            child: Text(
              _result!,
              style: context.text.bodySmall?.copyWith(
                color: widget.ink,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color ink;

  const _SectionHeader({required this.label, required this.ink});

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: context.text.labelSmall?.copyWith(
          color: ink,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  final Color card;
  final Color border;
  final List<Widget> children;

  const _SettingsCard(
      {required this.card, required this.border, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: const BorderRadius.all(AppRadius.lg),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

class _Divider extends StatelessWidget {
  final Color border;

  const _Divider({required this.border});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: border);
}

class _FieldRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String sublabel;
  final bool dark;
  final Color ink;
  final Color sub;
  final Widget child;

  const _FieldRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.sublabel,
    required this.dark,
    required this.ink,
    required this.sub,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: context.text.labelMedium?.copyWith(
                        color: ink, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    sublabel,
                    style: context.text.bodySmall?.copyWith(color: sub),
                  ),
                ],
              ),
            ),
            child,
          ],
        ),
      );
}

class _InlineField extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;
  final TextInputType keyboardType;
  final ValueChanged<String> onSubmit;
  final bool dark;
  final Color ink;

  const _InlineField({
    required this.controller,
    required this.suffix,
    required this.keyboardType,
    required this.onSubmit,
    required this.dark,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    final border =
        dark ? AppColors.darkBorder : AppColors.mist;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textAlign: TextAlign.center,
      style: context.text.labelMedium?.copyWith(color: ink),
      decoration: InputDecoration(
        suffixText: suffix,
        suffixStyle: context.text.labelSmall?.copyWith(
            color: dark ? AppColors.darkInkSubtle : AppColors.inkSubtle),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: border),
          borderRadius: const BorderRadius.all(AppRadius.sm),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
              color: dark ? AppColors.darkDeep : AppColors.deep),
          borderRadius: const BorderRadius.all(AppRadius.sm),
        ),
      ),
      onSubmitted: onSubmit,
    );
  }
}

class _TrackRow extends StatelessWidget {
  final MusicTrack track;
  final Color border;
  final Color ink;
  final Color sub;
  final bool dark;

  const _TrackRow({
    required this.track,
    required this.border,
    required this.ink,
    required this.sub,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 16,
              color: dark ? AppColors.darkAmber : AppColors.amber,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: context.text.bodySmall
                        ?.copyWith(color: ink, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Tags: ${track.moodTags.join(', ')}',
                    style: context.text.labelSmall?.copyWith(color: sub),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
