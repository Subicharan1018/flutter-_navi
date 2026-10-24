/// A library song the server matched a recognised track to.
class LibraryHit {
  final String songId;
  final String title;
  final String artist;
  final String album;

  const LibraryHit({
    required this.songId,
    required this.title,
    required this.artist,
    this.album = '',
  });

  factory LibraryHit.fromJson(Map<String, dynamic> json) => LibraryHit(
    songId: (json['song_id'] ?? json['id'] ?? '').toString(),
    title: (json['title'] ?? '').toString(),
    artist: (json['artist'] ?? '').toString(),
    album: (json['album'] ?? '').toString(),
  );
}

/// What `POST /recognize` found. [recognized] false means the audio matched
/// nothing; the other fields are then empty.
class RecognizeResult {
  final bool recognized;
  final String title;
  final String artist;
  final String album;

  /// 0–1 confidence from the fingerprint service.
  final double score;

  /// Library songs that are this track, best first. Empty: not in the library.
  final List<LibraryHit> library;

  const RecognizeResult({
    required this.recognized,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.score = 0,
    this.library = const [],
  });

  static const notFound = RecognizeResult(recognized: false);

  bool get inLibrary => library.isNotEmpty;

  /// What to type into Search online to fetch it.
  String get searchText => [title, artist].where((s) => s.isNotEmpty).join(' ');

  factory RecognizeResult.fromJson(Map<String, dynamic> json) {
    if (json['recognized'] != true) return notFound;
    final lib = json['library'];
    return RecognizeResult(
      recognized: true,
      title: (json['title'] ?? '').toString(),
      artist: (json['artist'] ?? '').toString(),
      album: (json['album'] ?? '').toString(),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      library: [
        if (lib is List)
          for (final h in lib)
            if (h is Map) LibraryHit.fromJson(Map<String, dynamic>.from(h)),
      ].where((h) => h.songId.isNotEmpty).toList(),
    );
  }
}
