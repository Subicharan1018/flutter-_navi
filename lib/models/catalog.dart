// The shuffle server's view of each song (GET /catalog/songs): what file tags
// on Navidrome don't carry — detected language(s), a clean genre, the film,
// composer and year — plus the browse categories built from it.

/// One song's catalog metadata. Any field can be absent.
class CatalogSong {
  final String id;
  final String? language; // ISO 639-1 primary language ('ta', 'en', …)
  final List<String> languages; // primary first; 2+ means multilingual
  final String? genre; // readable genre ("Kuthu / Dance", "Film Soundtrack")
  final String? bucket; // the listener's genre category, when the song has one
  final String? film;
  final String? composer;
  final String? lyricist;
  final int? year;
  final String? titleNative;

  /// Tempo and where the first beat falls, when the server has analysed the
  /// song (`bpm`, `beat_offset` in seconds). Microduck dances to these.
  final double? bpm;
  final double? beatOffset;

  const CatalogSong({
    required this.id,
    this.language,
    this.languages = const [],
    this.genre,
    this.bucket,
    this.film,
    this.composer,
    this.lyricist,
    this.year,
    this.titleNative,
    this.bpm,
    this.beatOffset,
  });

  bool get isMultilingual => languages.length > 1;

  factory CatalogSong.fromJson(Map<String, dynamic> j) => CatalogSong(
        id: j['id'].toString(),
        language: j['language'] as String?,
        languages: [for (final l in (j['languages'] as List? ?? const [])) l.toString()],
        genre: j['genre'] as String?,
        bucket: j['bucket'] as String?,
        film: j['film'] as String?,
        composer: j['composer'] as String?,
        lyricist: j['lyricist'] as String?,
        year: (j['year'] as num?)?.toInt(),
        titleNative: j['title_native'] as String?,
        bpm: (j['bpm'] as num?)?.toDouble(),
        beatOffset: (j['beat_offset'] as num?)?.toDouble(),
      );
}

/// A browse category: a language, the multilingual set, or a genre.
class CatalogCategory {
  final CategoryKind kind;
  final String key; // language code, 'multi', or genre name
  final String name; // what people read
  final int count;

  const CatalogCategory({required this.kind, required this.key, required this.name, required this.count});

  bool contains(CatalogSong s) => switch (kind) {
        CategoryKind.language => s.language == key,
        CategoryKind.multilingual => s.isMultilingual,
        CategoryKind.genre => s.bucket == key,
      };

  @override
  bool operator ==(Object other) => other is CatalogCategory && other.kind == kind && other.key == key;

  @override
  int get hashCode => Object.hash(kind, key);
}

enum CategoryKind { language, multilingual, genre }

class CatalogDocument {
  final Map<String, CatalogSong> songs;
  final List<CatalogCategory> languages; // Tamil, English, then by size
  final CatalogCategory? multilingual;
  final List<CatalogCategory> genres;

  const CatalogDocument({
    this.songs = const {},
    this.languages = const [],
    this.multilingual,
    this.genres = const [],
  });

  static const empty = CatalogDocument();

  factory CatalogDocument.fromJson(Map<String, dynamic> j) {
    final cats = (j['categories'] as Map?)?.cast<String, dynamic>() ?? const {};
    final multi = (cats['multilingual'] as num?)?.toInt() ?? 0;
    return CatalogDocument(
      songs: {
        for (final s in (j['songs'] as List? ?? const []))
          if (s is Map) (s['id'].toString()): CatalogSong.fromJson(s.cast<String, dynamic>()),
      },
      languages: [
        for (final l in (cats['languages'] as List? ?? const []))
          CatalogCategory(
            kind: CategoryKind.language,
            key: l['code'].toString(),
            name: l['name'].toString(),
            count: (l['count'] as num?)?.toInt() ?? 0,
          ),
      ],
      multilingual: multi > 0
          ? CatalogCategory(kind: CategoryKind.multilingual, key: 'multi', name: 'Multilingual', count: multi)
          : null,
      genres: [
        for (final g in (cats['genres'] as List? ?? const []))
          CatalogCategory(
            kind: CategoryKind.genre,
            key: g['name'].toString(),
            name: g['name'].toString(),
            count: (g['count'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  }
}

/// Display names for language codes the catalog can return.
const languageNames = <String, String>{
  'ta': 'Tamil', 'en': 'English', 'te': 'Telugu', 'ml': 'Malayalam', 'hi': 'Hindi',
  'kn': 'Kannada', 'ko': 'Korean', 'ja': 'Japanese', 'es': 'Spanish', 'fr': 'French',
  'ru': 'Russian', 'vi': 'Vietnamese', 'ar': 'Arabic', 'pa': 'Punjabi', 'bn': 'Bengali',
  'zh': 'Chinese', 'de': 'German', 'it': 'Italian', 'pt': 'Portuguese',
};
