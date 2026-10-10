import '../../../models/song.dart';
import '../data/models/recommended_song.dart';

/// Matches Smart Shuffle recommendations (title + composer from the server)
/// to songs in the local library: exact title + artist first, then title
/// alone. Builds its lookup once, so resolving a whole mix is O(n).
class RecommendationResolver {
  final Map<String, Song> _byTitleArtist = {};
  final Map<String, Song> _byTitle = {};

  RecommendationResolver(List<Song> library) {
    for (final s in library) {
      final title = s.title.toLowerCase();
      _byTitleArtist.putIfAbsent('$title|${s.artist.toLowerCase()}', () => s);
      _byTitle.putIfAbsent(title, () => s);
    }
  }

  Song? resolve(RecommendedSong rec) => match(rec.title, rec.composer);

  /// Any server-side (title, artist) pair — Replay and stats rows use this.
  Song? match(String title, String artist) {
    final t = title.toLowerCase();
    return _byTitleArtist['$t|${artist.toLowerCase()}'] ?? _byTitle[t];
  }

  /// Library songs for [recs], in order, skipping ones not in the library.
  List<Song> resolveAll(Iterable<RecommendedSong> recs) => [
        for (final r in recs) ?resolve(r),
      ];
}
