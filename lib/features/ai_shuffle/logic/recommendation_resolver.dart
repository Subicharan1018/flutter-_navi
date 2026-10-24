import '../../../models/song.dart';
import '../../../widgets/mascot/microduck_pose.dart' show cacheBpm;
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
  ///
  /// Each recommendation carries the song's measured tempo; it is kept in the
  /// BPM cache so Microduck can dance to the song's beat.
  List<Song> resolveAll(Iterable<RecommendedSong> recs) {
    final out = <Song>[];
    for (final r in recs) {
      final s = resolve(r);
      if (s == null) continue;
      final tempo = r.tempo;
      if (tempo != null) cacheBpm(s.id, tempo);
      out.add(s);
    }
    return out;
  }
}
