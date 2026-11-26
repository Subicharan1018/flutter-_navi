import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../utils/history_title_key.dart';
import '../../../widgets/mascot/microduck_pose.dart' show cacheBpm;
import '../data/models/recommended_song.dart';

/// Matches Smart Shuffle recommendations and listening-history rows (title +
/// artist from the server) to songs in the local library. Order of trust:
/// exact title + artist, exact title, then the title with film/language tags
/// removed (artist breaks ties). Distinct versions never merge: only tags
/// like "(From "X")" and "(Tamil)" are ignored. Builds its lookup once, so
/// resolving a whole mix is O(n).
/// The resolver for the current library mirror, built once per library
/// (indexing thousands of titles costs tens of ms; doing it in `build` made
/// opening the Shuffle tab drop frames).
final recommendationResolverProvider = Provider<RecommendationResolver>((ref) {
  final library = ref.watch(allSongsProvider).asData?.value ?? const <Song>[];
  return RecommendationResolver(library);
});

class RecommendationResolver {
  final Map<String, Song> _byTitleArtist = {};
  final Map<String, Song> _byTitle = {};
  final List<Song> _library;

  /// Tag-stripped title → songs. Stripping runs regexes per song, so it is
  /// built on the first lookup that misses the exact maps, not up front.
  late final Map<String, List<Song>> _byKey = _indexByKey();

  RecommendationResolver(List<Song> library) : _library = library {
    for (final s in library) {
      final title = s.title.toLowerCase();
      _byTitleArtist.putIfAbsent('$title|${s.artist.toLowerCase()}', () => s);
      _byTitle.putIfAbsent(title, () => s);
    }
  }

  Map<String, List<Song>> _indexByKey() {
    final out = <String, List<Song>>{};
    for (final s in _library) {
      final key = historyTitleKey(s.title);
      if (key.isNotEmpty) (out[key] ??= []).add(s);
    }
    return out;
  }

  Song? resolve(RecommendedSong rec) => match(rec.title, rec.composer);

  /// Any server-side (title, artist) pair — Replay and stats rows use this.
  Song? match(String title, String artist) {
    final t = title.toLowerCase();
    final a = artist.toLowerCase();
    final exact = _byTitleArtist['$t|$a'] ?? _byTitle[t];
    if (exact != null) return exact;

    final candidates = _byKey[historyTitleKey(title)];
    if (candidates == null) return null;
    if (candidates.length == 1) return candidates.first;
    if (a.isNotEmpty) {
      for (final s in candidates) {
        final sa = s.artist.toLowerCase();
        if (sa.isNotEmpty && (sa.contains(a) || a.contains(sa))) return s;
      }
    }
    return candidates.first;
  }

  /// Library songs for [recs], in order, skipping ones not in the library,
  /// each with its recommendation (audio features and scores) beside it for
  /// the taste field.
  ///
  /// Each recommendation carries the song's measured tempo; it is kept in the
  /// BPM cache so Microduck can dance to the song's beat.
  List<(Song, RecommendedSong)> resolvePairs(Iterable<RecommendedSong> recs) {
    final out = <(Song, RecommendedSong)>[];
    for (final r in recs) {
      final s = resolve(r);
      if (s == null) continue;
      final tempo = r.tempo;
      if (tempo != null) cacheBpm(s.id, tempo);
      out.add((s, r));
    }
    return out;
  }
}
