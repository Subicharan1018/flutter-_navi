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

  /// Returns the best available cover-art ID for this playlist.
  ///
  /// Prefers the playlist's own [coverArt] field (populated by the server
  /// for server-side playlists). Falls back to the first non-empty
  /// [coverArt] from [songs] — used for user playlists that have songs
  /// but no explicit cover art set.
  ///
  /// Returns `null` only when neither the playlist nor any song has art
  /// (e.g. an empty user-created playlist) — callers should show a placeholder.
  String? resolvedCoverArtId([List<dynamic>? songs]) {
    if (coverArt != null && coverArt!.isNotEmpty) return coverArt;
    if (songs == null || songs.isEmpty) return null;
    for (final s in songs) {
      final art = (s as dynamic).coverArt as String?;
      if (art != null && art.isNotEmpty) return art;
    }
    return null;
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

