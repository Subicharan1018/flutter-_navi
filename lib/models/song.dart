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

  // Audio quality metadata — reported directly by the Subsonic server.
  final int bitRate;        // kbps, 0 = unknown
  final String contentType; // e.g. 'audio/flac', 'audio/mpeg'
  final String suffix;      // e.g. 'flac', 'mp3', 'opus'

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
    this.bitRate = 0,
    this.contentType = '',
    this.suffix = '',
    this.dynamicWeight = 1.0,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';
    final rawCover = json['coverArt']?.toString() ?? '';
    
    return Song(
      id: rawId,
      title: json['title']?.toString() ?? 'Unknown Title',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      album: json['album']?.toString() ?? 'Unknown Album',
      genre: json['genre']?.toString() ?? '',
      composer: json['displayComposer']?.toString() ?? json['composer']?.toString() ?? '',
      coverArt: rawCover.isNotEmpty ? rawCover : rawId,
      duration: json['duration'] is int ? json['duration'] : int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      track: json['track'] is int ? json['track'] : int.tryParse(json['track']?.toString() ?? '') ?? 0,
      year: json['year'] is int ? json['year'] : int.tryParse(json['year']?.toString() ?? '') ?? 0,
      // 'starred' in Subsonic JSON is a timestamp string when starred, absent when not
      starred: json['starred'] != null,
      playCount: json['playCount'] is int ? json['playCount'] : int.tryParse(json['playCount']?.toString() ?? '') ?? 0,
      // Subsonic 'userRating' field (1–5)
      rating: json['userRating'] is int ? json['userRating'] : (json['rating'] is int ? json['rating'] : 0),
      created: json['created'] != null
          ? DateTime.tryParse(json['created'].toString())
          : null,
      bitRate: json['bitRate'] is int ? json['bitRate'] : int.tryParse(json['bitRate']?.toString() ?? '') ?? 0,
      contentType: json['contentType']?.toString() ?? '',
      suffix: json['suffix']?.toString() ?? '',
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
      'bitRate': bitRate,
      'contentType': contentType,
      'suffix': suffix,
    };
  }

  Song copyWith({
    String? genre,
    String? composer,
    bool? starred,
    int? playCount,
    int? rating,
    DateTime? created,
    int? bitRate,
    String? contentType,
    String? suffix,
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
      bitRate: bitRate ?? this.bitRate,
      contentType: contentType ?? this.contentType,
      suffix: suffix ?? this.suffix,
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
          created == other.created &&
          bitRate == other.bitRate &&
          contentType == other.contentType &&
          suffix == other.suffix;

  @override
  int get hashCode => Object.hash(
      id, title, artist, album, genre, composer,
      coverArt, duration, track, year, starred,
      playCount, rating, created, bitRate, contentType, suffix);
}