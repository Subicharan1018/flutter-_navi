class Playlist {
  final String id;
  final String name;
  final String comment;
  final int songCount;
  final int duration;
  final String? coverArt;

  Playlist({
    required this.id,
    required this.name,
    required this.comment,
    required this.songCount,
    required this.duration,
    this.coverArt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Playlist',
      comment: json['comment']?.toString() ?? '',
      songCount: json['songCount'] is int ? json['songCount'] : int.tryParse(json['songCount']?.toString() ?? '') ?? 0,
      duration: json['duration'] is int ? json['duration'] : int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      coverArt: json['coverArt']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          comment == other.comment &&
          songCount == other.songCount &&
          duration == other.duration &&
          coverArt == other.coverArt;

  @override
  int get hashCode =>
      Object.hash(id, name, comment, songCount, duration, coverArt);
}

