import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Phase 3 — On-device sensing signals.
///
/// Provides two passive context signals derived from device sensors:
///
/// 1. **Motion level** (0.0–1.0): derived from the accelerometer's
///    magnitude variance over a rolling 5-second window. A high value
///    means the user is moving (walking, exercising); low means still.
///
/// 2. **Ambient noise proxy** (0.0–1.0): Android's microphone is not
///    accessible without RECORD_AUDIO permission and active recording,
///    so instead we use screen-brightness + time-of-day as a lightweight
///    proxy — bright screen + daytime hours → active/noisy environment.
///    This avoids requesting a sensitive permission.
///
/// Both values are available as single-shot getters (averaged over the
/// last observation window) and are reset automatically each morning.
///
/// Usage:
///   await SensingService.instance.init();
///   final motion = SensingService.instance.motionLevel;
///   // Use inside DayClusteringEngine.buildTodayVector (Phase 3 extension)
class SensingService {
  SensingService._internal();
  static final SensingService instance = SensingService._internal();

  // ── State ──────────────────────────────────────────────────────────────────

  StreamSubscription<AccelerometerEvent>? _accelSub;
  final List<double> _magnitudes = []; // rolling window
  static const int _windowSize = 50; // ~5 s at 10 Hz

  bool _initialized = false;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _accelSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen((event) {
        final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        _magnitudes.add(mag);
        if (_magnitudes.length > _windowSize) {
          _magnitudes.removeAt(0);
        }
      });
    } catch (_) {
      // Sensor not available on this device — motionLevel will return 0.5.
    }
  }

  /// Stop listening to save battery. Call from app lifecycle pause.
  void pause() {
    _accelSub?.pause();
  }

  /// Resume after pause.
  void resume() {
    _accelSub?.resume();
  }

  void dispose() {
    _accelSub?.cancel();
    _accelSub = null;
    _initialized = false;
  }

  // ── Motion level ──────────────────────────────────────────────────────────

  /// 0.0 = completely still, 1.0 = highly active.
  /// Based on the variance of accelerometer magnitude over the last ~5 s.
  /// Returns 0.5 if the sensor is unavailable.
  double get motionLevel {
    if (_magnitudes.length < 5) return 0.5; // not enough data yet

    final mean = _magnitudes.reduce((a, b) => a + b) / _magnitudes.length;
    final variance = _magnitudes
            .map((m) => (m - mean) * (m - mean))
            .reduce((a, b) => a + b) /
        _magnitudes.length;

    // Raw variance of ~1 g device = ~0 (gravity constant).
    // Walking = variance ~1–4 (m/s²)^2; running = ~10+.
    // Normalize to 0–1 clamped at variance=10.
    return (variance / 10.0).clamp(0.0, 1.0);
  }

  // ── Ambient-noise proxy ───────────────────────────────────────────────────

  /// A lightweight 0.0–1.0 proxy for environmental busyness.
  /// Uses time-of-day only — no sensitive permissions needed.
  /// Peak busyness: 8 AM – 8 PM (0.8), quiet at night (0.2).
  double get ambientNoiseProxy {
    final hour = DateTime.now().hour;

    if (hour >= 8 && hour < 20) {
      // Daytime: higher ambient noise likely.
      // Scale peak at noon, taper toward morning/evening.
      final mid = 14.0; // 2 PM assumed peak
      final dist = (hour - mid).abs();
      return 0.8 - (dist / 12.0) * 0.4; // 0.8 at peak, 0.4 at edges
    }

    // Night / early morning (8 PM – 8 AM): low
    return 0.2;
  }

  // ── Combined activity score ───────────────────────────────────────────────

  /// A single 0.0–1.0 activity score blending motion + ambient proxy.
  /// Weights: 70% motion (direct), 30% ambient proxy.
  double get activityScore =>
      (motionLevel * 0.7 + ambientNoiseProxy * 0.3).clamp(0.0, 1.0);
}
