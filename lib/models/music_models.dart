/// Music module models. Local files only — no streaming dependency.
library;

class MusicTrack {
  final String id;
  final String filePath;
  final String title;
  final String artist;
  final List<String> moodTags;

  MusicTrack({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.moodTags,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'filePath': filePath,
        'title': title,
        'artist': artist,
        'moodTags': moodTags.join(','),
      };

  factory MusicTrack.fromMap(Map<String, dynamic> map) => MusicTrack(
        id: map['id'] as String,
        filePath: map['filePath'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        moodTags: (map['moodTags'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
      );
}

class Playlist {
  final String id;
  String name;
  String moodTag;
  List<String> trackIds;
  bool shuffle;

  Playlist({
    required this.id,
    required this.name,
    required this.moodTag,
    required this.trackIds,
    this.shuffle = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'moodTag': moodTag,
        'trackIds': trackIds.join(','),
        'shuffle': shuffle ? 1 : 0,
      };

  factory Playlist.fromMap(Map<String, dynamic> map) => Playlist(
        id: map['id'] as String,
        name: map['name'] as String,
        moodTag: map['moodTag'] as String,
        trackIds: (map['trackIds'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
        shuffle: (map['shuffle'] as int) == 1,
      );
}

class TaskMoodMapping {
  final String taskCategory;
  final String moodTag;
  final double volumeDuringTask;
  final double duckVolumeOnVoice;

  TaskMoodMapping({
    required this.taskCategory,
    required this.moodTag,
    this.volumeDuringTask = 0.8,
    this.duckVolumeOnVoice = 0.15,
  });
}
