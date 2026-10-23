import 'song.dart';

// Composer credits. In a library of film songs the music director is the main
// identity of a track and the singers vary, so the composer leads wherever a
// song is described. Everything that interprets a composer string lives here:
// splitting credits, matching spelling variants, the row/credit line, and the
// grouping behind the Composers page.

/// Separators between several composers in one credit: "A, B", "A & B",
/// "A / B", "A; B", "A and B".
final _splitter = RegExp(r'\s*(?:[,;/&+]|\band\b)\s*', caseSensitive: false);

/// Letters and digits of any script — everything else (dots, spaces, hyphens,
/// apostrophes) is ignored when comparing names.
final _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}\p{M}]', unicode: true);

/// The comparison key for a name: "A. R. Rahman", "A.R. Rahman" and
/// "AR Rahman" all become `arrahman`.
String nameKey(String name) => name.toLowerCase().replaceAll(_notLetterOrDigit, '');

/// The separate composers in a credit, in order, without duplicates:
/// "Harris Jayaraj, Yuvan Shankar Raja" → two names.
List<String> splitComposers(String credit) {
  final seen = <String>{};
  return [
    for (final part in credit.split(_splitter))
      if (part.trim().isNotEmpty && seen.add(nameKey(part))) part.trim(),
  ];
}

/// The secondary line of a song row: composer first, then the artist when it
/// is someone else — "Anirudh Ravichander · Dhanush". With no composer, or
/// when the artist is the composer (or one of several), just one of them.
String songCreditLine({required String composer, required String artist}) {
  final c = composer.trim();
  final a = artist.trim();
  if (c.isEmpty) return a;
  if (a.isEmpty) return c;
  final composerKeys = {for (final n in splitComposers(c)) nameKey(n)};
  final artistKeys = {for (final n in splitComposers(a)) nameKey(n)};
  // Every artist is already credited as a composer: nothing to add.
  if (artistKeys.isNotEmpty && artistKeys.every(composerKeys.contains)) return c;
  return '$c · $a';
}

/// The composer line for Now Playing, or null when there is none to show
/// (no composer, or the artist line already says the same).
String? composerLineFor(Song song) {
  final c = song.composer.trim();
  if (c.isEmpty) return null;
  final composerKeys = {for (final n in splitComposers(c)) nameKey(n)};
  final artistKeys = {for (final n in splitComposers(song.artist)) nameKey(n)};
  if (artistKeys.isNotEmpty && artistKeys.every(composerKeys.contains)) return null;
  return c;
}

/// One composer across the library: every spelling folded into one entry.
class Composer {
  /// [nameKey] of the name — the stable id used for navigation and lookup.
  final String key;

  /// The spelling shown (the most common one in the library).
  final String name;

  /// Songs, in library order.
  final List<Song> songs;

  const Composer({required this.key, required this.name, required this.songs});

  int get songCount => songs.length;
}

/// A film/album within one composer's songs.
class ComposerAlbum {
  final String name;
  final List<Song> songs;
  const ComposerAlbum({required this.name, required this.songs});
}

/// Every composer in [songs], A–Z by name. A song with several composers
/// appears under each of them.
List<Composer> buildComposers(Iterable<Song> songs) {
  final byKey = <String, List<Song>>{};
  final spellings = <String, Map<String, int>>{};
  for (final song in songs) {
    for (final name in splitComposers(song.composer)) {
      final key = nameKey(name);
      if (key.isEmpty) continue;
      byKey.putIfAbsent(key, () => []).add(song);
      final counts = spellings.putIfAbsent(key, () => {});
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  final composers = [
    for (final e in byKey.entries) Composer(key: e.key, name: _bestSpelling(spellings[e.key]!), songs: e.value),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return composers;
}

/// The most used spelling; on a tie the longer one (it keeps the dots).
String _bestSpelling(Map<String, int> counts) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : b.key.length.compareTo(a.key.length);
    });
  return entries.first.key;
}

/// A composer's songs grouped by film/album, newest first, each group in
/// track order — the order Play and Shuffle use too.
List<ComposerAlbum> groupByAlbum(List<Song> songs) {
  final groups = <String, List<Song>>{};
  final names = <String, String>{};
  for (final s in songs) {
    final name = s.album.trim().isEmpty ? 'Singles' : s.album.trim();
    final key = name.toLowerCase();
    names.putIfAbsent(key, () => name);
    groups.putIfAbsent(key, () => []).add(s);
  }
  int year(List<Song> l) => l.fold(0, (m, s) => s.year > m ? s.year : m);
  final albums = [
    for (final e in groups.entries)
      ComposerAlbum(
        name: names[e.key]!,
        songs: [...e.value]..sort((a, b) {
            final byTrack = a.track.compareTo(b.track);
            return byTrack != 0 ? byTrack : a.title.toLowerCase().compareTo(b.title.toLowerCase());
          }),
      ),
  ];
  albums.sort((a, b) {
    final byYear = year(b.songs).compareTo(year(a.songs));
    return byYear != 0 ? byYear : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return albums;
}

/// Composers whose name matches a search [query] (spelling-insensitive),
/// best matches (prefix) first.
List<Composer> matchComposers(List<Composer> all, String query, {int limit = 5}) {
  final q = nameKey(query);
  if (q.isEmpty) return const [];
  final starts = <Composer>[];
  final contains = <Composer>[];
  for (final c in all) {
    if (c.key.startsWith(q)) {
      starts.add(c);
    } else if (c.key.contains(q)) {
      contains.add(c);
    }
  }
  return [...starts, ...contains].take(limit).toList();
}
