import 'dart:convert';

import '../../../models/composer.dart' show nameKey;

/// What the server knows about a film beyond its songs (GET /credits/films):
/// year, director, music director and lyricists from Wikidata, and the
/// soundtrack's full track list from MusicBrainz. Every field can be absent:
/// unknown stays unknown.
class FilmInfo {
  final String title;
  final int? year;
  final List<String> directors;
  final List<String> musicDirectors;
  final List<String> lyricists;

  /// The soundtrack's tracks, when the server found the release.
  final List<TrackStub> tracklist;

  const FilmInfo({
    required this.title,
    this.year,
    this.directors = const [],
    this.musicDirectors = const [],
    this.lyricists = const [],
    this.tracklist = const [],
  });

  factory FilmInfo.fromJson(Map<String, dynamic> j) => FilmInfo(
        title: (j['title'] as String?) ?? '',
        year: (j['year'] as num?)?.toInt(),
        directors: _names(j['directors']),
        musicDirectors: _names(j['music_directors']),
        lyricists: _names(j['lyricists']),
        tracklist: [
          for (final t in (j['tracklist'] as List? ?? const []))
            if (t is Map && (t['title'] as String?)?.trim().isNotEmpty == true)
              TrackStub(title: (t['title'] as String).trim(), artist: ((t['artist'] as String?) ?? '').trim()),
        ],
      );
}

/// A track on a soundtrack release: a title and who is credited on it.
class TrackStub {
  final String title;
  final String artist;
  const TrackStub({required this.title, this.artist = ''});
}

List<String> _names(Object? v) =>
    [for (final n in (v as List? ?? const [])) if (n is String && n.trim().isNotEmpty) n.trim()];

/// The document as a map keyed by [nameKey] of the title (the app's own film
/// key, so it never depends on how the server spells keys).
Map<String, FilmInfo> parseFilmInfos(String body) {
  final doc = jsonDecode(body);
  final out = <String, FilmInfo>{};
  for (final f in (doc is Map ? doc['films'] as List? ?? const [] : const [])) {
    if (f is! Map) continue;
    final info = FilmInfo.fromJson(f.cast<String, dynamic>());
    final key = nameKey(info.title);
    if (key.isNotEmpty) out[key] = info;
  }
  return out;
}
