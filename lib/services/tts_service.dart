import 'package:flutter_tts/flutter_tts.dart';
import 'music_service.dart';

/// On-device text-to-speech. Automatically ducks music around every
/// spoken message and restores it afterward.
class TtsService {
  TtsService._internal();
  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> speak(String message, {double duckVolume = 0.15}) async {
    await _ensureInit();
    await MusicService.instance.duckForVoice(duckVolume);

    await _tts.stop();
    await _tts.speak(message);

    _tts.setCompletionHandler(() {
      MusicService.instance.restoreAfterVoice();
    });
  }

  Future<void> stop() async {
    await _tts.stop();
    await MusicService.instance.restoreAfterVoice();
  }
}
