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
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Playlist',
      comment: json['comment'] as String? ?? '',
      songCount: json['songCount'] as int? ?? 0,
      duration: json['duration'] as int? ?? 0,
      coverArt: json['coverArt'] as String?,
    );
  }
}
