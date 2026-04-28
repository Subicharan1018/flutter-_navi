class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String composer;
  final String coverArt;
  final int duration;
  final int track;
  final int year;
  final bool starred;
  final int playCount;
  final int rating;
  final DateTime? created;

  // Local weight for smart shuffle algorithms — immutable, updated via copyWith.
  final double dynamicWeight;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.genre = '',
    this.composer = '',
    required this.coverArt,
    required this.duration,
    required this.track,
    required this.year,
    this.starred = false,
    this.playCount = 0,
    this.rating = 0,
    this.created,
    this.dynamicWeight = 1.0,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? 'Unknown Album',
      genre: json['genre'] as String? ?? '',
      composer: (json['displayComposer'] as String?) ?? (json['composer'] as String?) ?? '',
      coverArt: json['coverArt'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      track: json['track'] as int? ?? 0,
      year: json['year'] as int? ?? 0,
      // 'starred' in Subsonic JSON is a timestamp string when starred, absent when not
      starred: json['starred'] != null,
      playCount: json['playCount'] as int? ?? 0,
      // Subsonic 'userRating' field (1–5)
      rating: (json['userRating'] as int?) ?? (json['rating'] as int?) ?? 0,
      created: json['created'] != null
          ? DateTime.tryParse(json['created'] as String)
          : null,
    );
  }

  /// Serialise to a plain map for SQLite storage.
  /// Uses the same field names as [Song.fromJson] so round-tripping is trivial.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'composer': composer,
      'coverArt': coverArt,
      'duration': duration,
      'track': track,
      'year': year,
      'starred': starred ? 1 : 0,
      'playCount': playCount,
      'userRating': rating,
      'created': created?.toIso8601String(),
    };
  }

  Song copyWith({
    String? genre,
    String? composer,
    bool? starred,
    int? playCount,
    int? rating,
    DateTime? created,
    double? dynamicWeight,
  }) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      genre: genre ?? this.genre,
      composer: composer ?? this.composer,
      coverArt: coverArt,
      duration: duration,
      track: track,
      year: year,
      starred: starred ?? this.starred,
      playCount: playCount ?? this.playCount,
      rating: rating ?? this.rating,
      created: created ?? this.created,
      dynamicWeight: dynamicWeight ?? this.dynamicWeight,
    );
  }

  // ---------------------------------------------------------------------------
  // Equality — based on all value fields except [dynamicWeight], which is a
  // local mutable shuffle weight and not part of the song's data identity.
  // Correct equality lets Riverpod select() suppress unnecessary rebuilds and
  // makes Set<Song> / List.contains() work after copyWith.
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          genre == other.genre &&
          composer == other.composer &&
          coverArt == other.coverArt &&
          duration == other.duration &&
          track == other.track &&
          year == other.year &&
          starred == other.starred &&
          playCount == other.playCount &&
          rating == other.rating &&
          created == other.created;

  @override
  int get hashCode => Object.hash(
      id, title, artist, album, genre, composer,
      coverArt, duration, track, year, starred,
      playCount, rating, created);
}