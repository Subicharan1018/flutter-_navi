class Album {
  final String id;
  final String name;
  final String artist;
  final String coverArt;
  final int songCount;
  final int duration;

  Album({
    required this.id,
    required this.name,
    required this.artist,
    required this.coverArt,
    required this.songCount,
    required this.duration,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';
    final rawCover = json['coverArt']?.toString() ?? '';

    return Album(
      id: rawId,
      name: json['name']?.toString() ?? json['title']?.toString() ?? 'Unknown Album',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      coverArt: rawCover.isNotEmpty ? rawCover : rawId,
      songCount: json['songCount'] is int ? json['songCount'] : int.tryParse(json['songCount']?.toString() ?? '') ?? 0,
      duration: json['duration'] is int ? json['duration'] : int.tryParse(json['duration']?.toString() ?? '') ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          artist == other.artist &&
          coverArt == other.coverArt &&
          songCount == other.songCount &&
          duration == other.duration;

  @override
  int get hashCode =>
      Object.hash(id, name, artist, coverArt, songCount, duration);
}

