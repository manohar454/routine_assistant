import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../models/music_models.dart';

/// Handles task-linked playback and automatic ducking.
class MusicService {
  MusicService._internal();
  static final MusicService instance = MusicService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _manuallyPaused = false;
  double _normalVolume = 0.8;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  Future<void> startForTask({
    required Playlist playlist,
    required List<MusicTrack> tracks,
    required double volume,
  }) async {
    _manuallyPaused = false;
    _normalVolume = volume;

    if (tracks.isEmpty) return;

    final ordered = playlist.shuffle ? (List.of(tracks)..shuffle()) : tracks;
    final source = ConcatenatingAudioSource(
      children:
          ordered.map((t) => AudioSource.uri(Uri.file(t.filePath))).toList(),
    );

    await _player.setAudioSource(source);
    await _player.setVolume(_normalVolume);
    await _player.setLoopMode(LoopMode.all);
    await _player.play();
  }

  Future<void> duckForVoice(double duckVolume) async {
    if (!_player.playing) return;
    await _player.setVolume(duckVolume);
  }

  Future<void> restoreAfterVoice() async {
    if (_manuallyPaused) return;
    if (!_player.playing) return;
    await _player.setVolume(_normalVolume);
  }

  Future<void> manualPause() async {
    _manuallyPaused = true;
    await _player.pause();
  }

  Future<void> manualResume() async {
    _manuallyPaused = false;
    await _player.play();
  }

  Future<void> stopForTaskEnd() async {
    await _player.stop();
  }

  bool get isPlaying => _player.playing;
  Stream<Duration> get positionStream => _player.positionStream;
}
