/// One lyric line's English translation and Latin-script pronunciation, as
/// the server's `POST /lyrics/translate` returns them. Either may be empty
/// (a line already in English, or an instrumental gap).
class LineTranslation {
  final String translation;
  final String pronunciation;

  const LineTranslation({this.translation = '', this.pronunciation = ''});

  static const empty = LineTranslation();

  factory LineTranslation.fromJson(Map<String, dynamic> json) =>
      LineTranslation(
        translation: (json['translation'] ?? '').toString().trim(),
        pronunciation: (json['pronunciation'] ?? '').toString().trim(),
      );
}

/// A whole song's translation, index-aligned with the lyric lines the app
/// sent, so timed lines keep their timestamps.
class LyricsTranslation {
  /// The sung language as the server detected it ("Tamil"); may be empty.
  final String language;

  /// True when the song is already in the target language and there is
  /// nothing to translate.
  final bool sameLanguage;
  final List<LineTranslation> lines;

  const LyricsTranslation({
    this.language = '',
    this.sameLanguage = false,
    this.lines = const [],
  });

  /// The translation for line [i], or [LineTranslation.empty] past the end.
  LineTranslation operator [](int i) =>
      i >= 0 && i < lines.length ? lines[i] : LineTranslation.empty;

  bool get hasPronunciation => lines.any((l) => l.pronunciation.isNotEmpty);
  bool get hasTranslation => lines.any((l) => l.translation.isNotEmpty);

  factory LyricsTranslation.fromJson(
    Map<String, dynamic> json, {
    required int expectedLines,
  }) {
    final raw = json['lines'];
    final parsed = <LineTranslation>[
      if (raw is List)
        for (final l in raw)
          l is Map
              ? LineTranslation.fromJson(Map<String, dynamic>.from(l))
              : LineTranslation.empty,
    ];
    // Keep alignment whatever the server did: pad or cut to the sent length.
    final aligned = [
      for (var i = 0; i < expectedLines; i++)
        i < parsed.length ? parsed[i] : LineTranslation.empty,
    ];
    return LyricsTranslation(
      language: (json['language'] ?? '').toString(),
      sameLanguage: json['same_language'] == true,
      lines: aligned,
    );
  }
}

/// A song whose lyrics contain the searched words, with the matching line.
class LyricMatch {
  final String songId;
  final String title;
  final String artist;
  final String album;

  /// The lyric line that matched, plain text.
  final String line;

  /// Where that line starts in the song, when the lyrics are timed.
  final Duration? start;

  const LyricMatch({
    required this.songId,
    required this.title,
    required this.artist,
    this.album = '',
    required this.line,
    this.start,
  });

  factory LyricMatch.fromJson(Map<String, dynamic> json) {
    final ms = json['start_ms'];
    return LyricMatch(
      songId: (json['song_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      artist: (json['artist'] ?? '').toString(),
      album: (json['album'] ?? '').toString(),
      line: (json['line'] ?? '').toString(),
      start: ms is num ? Duration(milliseconds: ms.toInt()) : null,
    );
  }
}
