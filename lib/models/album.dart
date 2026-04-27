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
    return Album(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['title'] as String? ?? 'Unknown Album',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      coverArt: json['coverArt'] as String? ?? '',
      songCount: json['songCount'] as int? ?? 0,
      duration: json['duration'] as int? ?? 0,
    );
  }
}
