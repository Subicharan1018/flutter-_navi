class Album {
  final String id;
  final String name;
  final String artist;
  final String artistId;
  final String coverArt;
  final int songCount;
  final int duration;
  final int year;
  final String genre;

  Album({
    required this.id,
    required this.name,
    required this.artist,
    this.artistId = '',
    required this.coverArt,
    required this.songCount,
    required this.duration,
    this.year = 0,
    this.genre = '',
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';
    final rawCover = json['coverArt']?.toString() ?? '';

    int asInt(Object? v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

    return Album(
      id: rawId,
      name:
          json['name']?.toString() ??
          json['title']?.toString() ??
          'Unknown Album',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      artistId: json['artistId']?.toString() ?? '',
      coverArt: rawCover.isNotEmpty ? rawCover : rawId,
      songCount: asInt(json['songCount']),
      duration: asInt(json['duration']),
      year: asInt(json['year']),
      genre: json['genre']?.toString() ?? '',
    );
  }

  /// "Rock · 2019" — Apple's album detail line; empty when neither is known.
  String get detailLine => [if (genre.isNotEmpty) genre, if (year > 0) '$year'].join(' · ');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          artist == other.artist &&
          artistId == other.artistId &&
          coverArt == other.coverArt &&
          songCount == other.songCount &&
          duration == other.duration &&
          year == other.year &&
          genre == other.genre;

  @override
  int get hashCode =>
      Object.hash(id, name, artist, artistId, coverArt, songCount, duration, year, genre);
}
