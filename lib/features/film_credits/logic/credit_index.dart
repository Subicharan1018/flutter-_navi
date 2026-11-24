import '../../../models/catalog.dart';
import '../../../models/composer.dart' show nameKey, splitComposers;
import '../../../models/song.dart';
import '../data/film_info.dart';

/// How a person is credited on a song.
enum CreditRole {
  musicDirector('Music director', 'Music Director'),
  lyricist('Lyricist', 'Lyricist'),
  singer('Singer', 'Singer');

  /// Singular, for a page's subtitle.
  final String label;

  /// Heading form.
  final String heading;
  const CreditRole(this.label, this.heading);
}

/// A film across the library: its songs and what the server knows about it.
class FilmEntry {
  /// [nameKey] of the title: the id used for navigation and lookup.
  final String key;
  final String title;
  final int? year;
  final FilmInfo? info;

  /// Songs in the library, in track order.
  final List<Song> songs;

  final List<String> _derivedMd;

  const FilmEntry({
    required this.key,
    required this.title,
    required this.year,
    required this.info,
    required this.songs,
    List<String> musicDirectorsFromSongs = const [],
  }) : _derivedMd = musicDirectorsFromSongs;

  /// Music directors credited on its songs, most songs first (the server's list wins when it has one).
  List<String> get musicDirectors => info?.musicDirectors.isNotEmpty == true ? info!.musicDirectors : _derivedMd;

  /// Soundtrack tracks that no library song matches (empty without a track list).
  List<TrackStub> get missing {
    final tl = info?.tracklist ?? const <TrackStub>[];
    if (tl.isEmpty) return const [];
    final owned = {for (final s in songs) _titleKey(s.title)};
    return [for (final t in tl) if (!owned.contains(_titleKey(t.title))) t];
  }
}

/// "Kadhal Kan Kattudhe (From “Kaaki Sattai”)" and "Kadhal Kan Kattudhe" are one song.
String _titleKey(String t) => nameKey(t.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), ''));

/// One person's work: every song grouped by role.
class PersonEntry {
  final String key;
  final String name;
  final Map<CreditRole, List<Song>> byRole;
  const PersonEntry({required this.key, required this.name, required this.byRole});

  List<CreditRole> get roles => [for (final r in CreditRole.values) if (byRole[r]?.isNotEmpty == true) r];

  /// Every song once, in library order.
  List<Song> get songs {
    final seen = <String>{};
    return [for (final l in byRole.values) for (final s in l) if (seen.add(s.id)) s];
  }
}

/// Films and people derived from the library, the catalog's credits and the
/// server's film facts. Pure: built once per library / catalog change.
class CreditIndex {
  final Map<String, FilmEntry> films;
  final Map<String, PersonEntry> people;

  /// song id → film key, for songs whose film is known.
  final Map<String, String> filmOf;

  const CreditIndex({this.films = const {}, this.people = const {}, this.filmOf = const {}});

  static const empty = CreditIndex();

  /// Films A–Z.
  List<FilmEntry> get filmList =>
      films.values.toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  /// People who are credited in [role], most songs first.
  List<PersonEntry> peopleIn(CreditRole role) {
    final l = [for (final p in people.values) if (p.byRole[role]?.isNotEmpty == true) p];
    l.sort((a, b) {
      final c = b.byRole[role]!.length.compareTo(a.byRole[role]!.length);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return l;
  }

  /// The people credited on one song, per role.
  Map<CreditRole, List<String>> creditsOf(Song song, CatalogSong? meta) => _creditsOf(song, meta);
}

Map<CreditRole, List<String>> _creditsOf(Song song, CatalogSong? meta) {
  final md = meta != null && meta.musicDirectors.isNotEmpty ? meta.musicDirectors : splitComposers(song.composer);
  final ly = meta != null && meta.lyricists.isNotEmpty
      ? meta.lyricists
      : splitComposers(meta?.lyricist ?? '');
  final lyKeys = {for (final n in ly) nameKey(n)};
  // The artist tag names the singers; a name already credited as lyricist is not one.
  final sg = meta != null && meta.singers.isNotEmpty
      ? meta.singers
      : [for (final n in splitComposers(song.artist)) if (!lyKeys.contains(nameKey(n))) n];
  return {CreditRole.musicDirector: md, CreditRole.lyricist: ly, CreditRole.singer: sg};
}

CreditIndex buildCreditIndex(Iterable<Song> songs, Map<String, CatalogSong> catalog, Map<String, FilmInfo> infos) {
  final filmSongs = <String, List<Song>>{};
  final filmTitles = <String, Map<String, int>>{};
  final filmMd = <String, Map<String, int>>{};
  final filmOf = <String, String>{};
  final peopleSongs = <String, Map<CreditRole, List<Song>>>{};
  final spellings = <String, Map<String, int>>{};

  for (final song in songs) {
    final meta = catalog[song.id];
    final credits = _creditsOf(song, meta);
    for (final e in credits.entries) {
      for (final name in e.value) {
        final k = nameKey(name);
        if (k.isEmpty) continue;
        final byRole = peopleSongs.putIfAbsent(k, () => {});
        final list = byRole.putIfAbsent(e.key, () => []);
        if (list.isEmpty || list.last.id != song.id) list.add(song);
        final sp = spellings.putIfAbsent(k, () => {});
        sp[name] = (sp[name] ?? 0) + 1;
      }
    }
    final film = meta?.film?.trim() ?? '';
    final fk = nameKey(film);
    if (fk.isEmpty) continue;
    filmOf[song.id] = fk;
    filmSongs.putIfAbsent(fk, () => []).add(song);
    final titles = filmTitles.putIfAbsent(fk, () => {});
    titles[film] = (titles[film] ?? 0) + 1;
    final md = filmMd.putIfAbsent(fk, () => {});
    for (final n in credits[CreditRole.musicDirector]!) {
      md[n] = (md[n] ?? 0) + 1;
    }
  }

  final films = <String, FilmEntry>{};
  for (final e in filmSongs.entries) {
    final info = infos[e.key];
    final songsOfFilm = [...e.value]..sort((a, b) {
        final t = a.track.compareTo(b.track);
        return t != 0 ? t : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final years = [for (final s in songsOfFilm) if (s.year > 0) s.year];
    final byCount = <int, int>{};
    for (final y in years) {
      byCount[y] = (byCount[y] ?? 0) + 1;
    }
    final songYear = byCount.isEmpty ? null : (byCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final md = (filmMd[e.key]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((x) => x.key).toList();
    films[e.key] = FilmEntry(
      key: e.key,
      title: _best(filmTitles[e.key]!),
      year: info?.year ?? songYear,
      info: info,
      songs: songsOfFilm,
      musicDirectorsFromSongs: md,
    );
  }

  final people = {
    for (final e in peopleSongs.entries) e.key: PersonEntry(key: e.key, name: _best(spellings[e.key]!), byRole: e.value),
  };
  return CreditIndex(films: films, people: people, filmOf: filmOf);
}

/// The most used spelling; on a tie the longer one (it keeps the dots).
String _best(Map<String, int> counts) {
  final l = counts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : b.key.length.compareTo(a.key.length);
    });
  return l.first.key;
}

/// A person's songs grouped by film (newest film first); songs with no known film
/// are gathered under a null film, last.
List<({FilmEntry? film, List<Song> songs})> groupByFilm(CreditIndex index, List<Song> songs) {
  final groups = <String?, List<Song>>{};
  for (final s in songs) {
    groups.putIfAbsent(index.filmOf[s.id], () => []).add(s);
  }
  final out = [
    for (final e in groups.entries)
      if (e.key != null) (film: index.films[e.key]!, songs: e.value),
  ]..sort((a, b) {
      final y = (b.film.year ?? 0).compareTo(a.film.year ?? 0);
      return y != 0 ? y : a.film.title.toLowerCase().compareTo(b.film.title.toLowerCase());
    });
  final rest = groups[null];
  return [...out, if (rest != null) (film: null, songs: rest)];
}
