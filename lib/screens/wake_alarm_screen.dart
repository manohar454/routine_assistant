import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../db/database_helper.dart';
import '../models/routine_models.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';

/// Hard-to-dismiss morning wake-up screen.
///
/// The user must solve a simple arithmetic problem before they can dismiss
/// the alarm. This forces genuine alertness rather than a groggy swipe.
///
/// Music plays from the device's local library (via [just_audio]).
/// If no track is found the screen still shows — silence is fine.
///
/// Launched by:
///   - A notification tap with payload starting with 'routine:*:wakeUp'
///   - Directly from the Routine Timetable screen for preview/test
class WakeAlarmScreen extends StatefulWidget {
  /// The RoutineEntry that fired, or null if launched directly for preview.
  final RoutineEntry? entry;

  const WakeAlarmScreen({super.key, this.entry});

  @override
  State<WakeAlarmScreen> createState() => _WakeAlarmScreenState();
}

class _WakeAlarmScreenState extends State<WakeAlarmScreen>
    with TickerProviderStateMixin {
  // ── Math gate ──
  late int _a, _b, _operator; // 0=add, 1=sub, 2=mul
  late int _answer;
  final _inputController = TextEditingController();
  bool _wrongAnswer = false;
  int _attemptCount = 0;

  // ── Music ──
  AudioPlayer? _player;
  bool _musicPlaying = false;
  String? _nowPlaying;

  // ── TTS ──
  bool _ttsSpoken = false;

  // ── Animation ──
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  // ── Time display ──
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  // ── Motivational messages ──
  static const _motives = [
    "Every champion was once a contender that refused to give up.",
    "Your only limit is the one you set yourself.",
    "Rise up, show up, and never give up.",
    "Success is not given — it is earned before sunrise.",
    "5:30 AM. While others sleep, champions are made.",
    "Wake up with determination. Go to bed with satisfaction.",
    "You didn't come this far to only come this far.",
    "The morning is the foundation of the day — make it count.",
  ];

  String get _motive {
    final seed = _now.day + _now.month;
    return _motives[seed % _motives.length];
  }

  @override
  void initState() {
    super.initState();
    _generateProblem();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });

    // TTS greeting — slight delay so screen is visible first.
    Future.delayed(const Duration(milliseconds: 600), _speakGreeting);

    // Start music after TTS gets going.
    Future.delayed(const Duration(milliseconds: 2000), _startMusic);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _clockTimer.cancel();
    _inputController.dispose();
    _player?.dispose();
    super.dispose();
  }

  void _generateProblem() {
    final rng = Random();
    _operator = rng.nextInt(3);
    switch (_operator) {
      case 0: // add
        _a = rng.nextInt(30) + 10; // 10-39
        _b = rng.nextInt(20) + 5;  // 5-24
        _answer = _a + _b;
      case 1: // sub — ensure positive result
        _a = rng.nextInt(30) + 20; // 20-49
        _b = rng.nextInt(15) + 5;  // 5-19
        _answer = _a - _b;
      default: // mul — keep manageable
        _a = rng.nextInt(9) + 2;   // 2-10
        _b = rng.nextInt(9) + 2;   // 2-10
        _answer = _a * _b;
    }
  }

  String get _problemText {
    final ops = ['+', '−', '×'];
    return '$_a ${ops[_operator]} $_b = ?';
  }

  void _checkAnswer() {
    final val = int.tryParse(_inputController.text.trim());
    if (val == null) return;

    if (val == _answer) {
      _dismiss();
    } else {
      setState(() {
        _wrongAnswer = true;
        _attemptCount++;
        _inputController.clear();
      });
      // Generate harder problem after 3 wrong tries (more digits)
      if (_attemptCount >= 3) {
        setState(_generateProblem);
        _attemptCount = 0;
      }
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _wrongAnswer = false);
      });
    }
  }

  void _dismiss() {
    _player?.stop();
    TtsService.instance.stop();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _speakGreeting() async {
    if (_ttsSpoken) return;
    _ttsSpoken = true;
    final msg = widget.entry?.message ??
        RoutineEntryType.wakeUp.defaultMessage();
    await TtsService.instance.speak(msg);
  }

  Future<void> _startMusic() async {
    try {
      // Look for a track flagged as "motivational" in the music library.
      // Falls back to any available track if none tagged.
      final db = DatabaseHelper.instance;
      final tracks = await db.getAllTracks();

      String? path;
      if (tracks.isNotEmpty) {
        // Prefer tracks with "motivation" or "energy" in their mood tags.
        final motivational = tracks.where((t) =>
            t.moodTags.any((tag) =>
                tag.toLowerCase().contains('motivat') ||
                tag.toLowerCase().contains('energy') ||
                tag.toLowerCase().contains('workout'))).toList();

        final pick = motivational.isNotEmpty
            ? motivational[DateTime.now().second % motivational.length]
            : tracks[DateTime.now().second % tracks.length];
        path = pick.filePath;
        if (mounted) setState(() => _nowPlaying = pick.title);
      }

      if (path != null) {
        _player = AudioPlayer();
        await _player!.setFilePath(path);
        await _player!.setLoopMode(LoopMode.one);
        await _player!.play();
        if (mounted) setState(() => _musicPlaying = true);
      }
    } catch (_) {
      // No music — fine, alarm still works.
    }
  }

  void _toggleMusic() {
    if (_player == null) return;
    if (_musicPlaying) {
      _player!.pause();
    } else {
      _player!.play();
    }
    setState(() => _musicPlaying = !_musicPlaying);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');

    return PopScope(
      // Prevent back-button dismissal — must solve the problem.
      canPop: false,
      child: Scaffold(
        backgroundColor: dark ? const Color(0xFF0A1512) : const Color(0xFF1A2E25),
        body: SafeArea(
          child: Column(
            children: [
              // ── Header: time + motivational quote ──
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Pulsing sun icon
                      ScaleTransition(
                        scale: _pulse,
                        child: const Text('🌅', style: TextStyle(fontSize: 64)),
                      ),
                      const SizedBox(height: 16),
                      // Clock
                      Text(
                        '$h:$m:$s',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 56,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE8F5E9),
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Motivational quote
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius:
                              const BorderRadius.all(AppRadius.lg),
                        ),
                        child: Text(
                          '"$_motive"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFFB2DFDB),
                            fontStyle: FontStyle.italic,
                            height: 1.5,
                          ),
                        ),
                      ),
                      if (_nowPlaying != null) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _toggleMusic,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _musicPlaying
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                                color: const Color(0xFF80CBC4),
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _nowPlaying!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF80CBC4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Math gate ──
              Expanded(
                flex: 4,
                child: Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.all(AppRadius.xl),
                    border: Border.all(
                      color: _wrongAnswer
                          ? AppColors.clay.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.12),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Solve to dismiss',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF80CBC4),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: _wrongAnswer
                              ? AppColors.clay.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius:
                              const BorderRadius.all(AppRadius.md),
                        ),
                        child: Text(
                          _problemText,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE8F5E9),
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      if (_wrongAnswer)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Not quite — try again!',
                            style: TextStyle(
                              color: AppColors.clay,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      // Number input
                      TextField(
                        controller: _inputController,
                        keyboardType: const TextInputType.numberWithOptions(
                            signed: true),
                        textAlign: TextAlign.center,
                        autofocus: true,
                        style: const TextStyle(
                          color: Color(0xFFE8F5E9),
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Your answer',
                          hintStyle: TextStyle(
                            color:
                                const Color(0xFFE8F5E9).withValues(alpha: 0.3),
                            fontSize: 18,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius:
                                const BorderRadius.all(AppRadius.md),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                const BorderRadius.all(AppRadius.md),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(AppRadius.md),
                            borderSide: BorderSide(
                              color: AppColors.moss,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                        ),
                        onSubmitted: (_) => _checkAnswer(),
                      ),
                      const SizedBox(height: 16),
                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _checkAnswer,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.moss,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: const RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.all(AppRadius.md),
                            ),
                          ),
                          child: const Text(
                            'I\'m Awake! ✓',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Repeat TTS ──
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextButton.icon(
                  onPressed: _speakGreeting,
                  icon: const Icon(Icons.volume_up,
                      color: Color(0xFF80CBC4), size: 18),
                  label: const Text(
                    'Hear greeting again',
                    style: TextStyle(
                        color: Color(0xFF80CBC4), fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
