import '../../../models/song.dart';

// =============================================================================
// duplicates.dart — finds duplicate songs, albums and artists in the synced
// library. Pure functions over models: no I/O, nothing is ever deleted. The UI
// only hides extras on this device or exports a clean-up list.
// =============================================================================

/// "Don’t Stop (Believin')" and "dont stop believin" compare equal: lower case,
/// accents folded, "&" as "and", punctuation dropped, spaces collapsed.
String normalizeName(String input) {
  var s = input.toLowerCase();
  const from = 'àáâãäåāçćčèéêëēėęìíîïīłñńòóôõöøōšśùúûüūýÿžźż';
  const to = 'aaaaaaacccceeeeeeeiiiilnnooooooosssuuuuuyyzzz';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  s = b.toString().replaceAll('&', ' and ');
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Same, with a leading "the " dropped (for artist names).
String normalizeArtist(String input) {
  final n = normalizeName(input);
  return n.startsWith('the ') ? n.substring(4) : n;
}

enum DupKind { song, album, artist }

/// One candidate in a group: enough to draw a row and to pick a keeper.
class DupItem {
  final String id;
  final String title;
  final String subtitle;

  /// "FLAC · 1,411 kbps · 3:42" style line.
  final String detail;

  /// Higher is a better one to keep.
  final int score;
  const DupItem({required this.id, required this.title, required this.subtitle, required this.detail, required this.score});
}

/// Two or more entries that are the same thing.
class DupGroup {
  final DupKind kind;
  final List<DupItem> items;

  /// Best candidate to keep, by [DupItem.score] (first on ties).
  final String suggestedKeeperId;
  const DupGroup({required this.kind, required this.items, required this.suggestedKeeperId});

  String get title => items.firstWhere((i) => i.id == suggestedKeeperId).title;
}

const _lossless = {'flac', 'alac', 'wav', 'aiff', 'ape', 'wv'};

/// How good a copy is: lossless over lossy, then bitrate, then loved (starred,
/// played), then older (the original import).
int songScore(Song s) {
  var v = 0;
  if (_lossless.contains(s.suffix.toLowerCase())) v += 100000;
  v += s.bitRate.clamp(0, 5000);
  if (s.starred) v += 20000;
  v += s.playCount.clamp(0, 999) * 5;
  if (s.rating > 0) v += s.rating * 100;
  return v;
}

String _mmss(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

String _songDetail(Song s) {
  final fmt = s.suffix.isEmpty ? null : s.suffix.toUpperCase();
  return [
    ?fmt,
    if (s.bitRate > 0) '${s.bitRate} kbps',
    _mmss(s.duration),
    if (s.album.isNotEmpty) s.album,
  ].join(' · ');
}

/// Songs with the same normalized title and artist whose lengths are within
/// [toleranceSeconds] of each other (chained, so 3:40, 3:41, 3:42 are one group).
/// A live cut or a radio edit differs by more and is left alone.
List<DupGroup> findDuplicateSongs(Iterable<Song> songs, {int toleranceSeconds = 2}) {
  final buckets = <String, List<Song>>{};
  for (final s in songs) {
    final title = normalizeName(s.title);
    if (title.isEmpty) continue;
    (buckets['$title\u0000${normalizeArtist(s.artist)}'] ??= []).add(s);
  }
  final groups = <DupGroup>[];
  for (final bucket in buckets.values) {
    if (bucket.length < 2) continue;
    bucket.sort((a, b) => a.duration.compareTo(b.duration));
    var run = <Song>[bucket.first];
    void flush() {
      if (run.length >= 2) groups.add(_songGroup(run));
      run = [];
    }

    for (final s in bucket.skip(1)) {
      if (s.duration - run.last.duration <= toleranceSeconds) {
        run.add(s);
      } else {
        flush();
        run.add(s);
      }
    }
    flush();
  }
  groups.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return groups;
}

DupGroup _songGroup(List<Song> run) {
  final items = [
    for (final s in run)
      DupItem(id: s.id, title: s.title, subtitle: s.artist, detail: _songDetail(s), score: songScore(s)),
  ];
  return DupGroup(kind: DupKind.song, items: items, suggestedKeeperId: _best(items));
}

String _best(List<DupItem> items) {
  var best = items.first;
  for (final i in items.skip(1)) {
    if (i.score > best.score) best = i;
  }
  return best.id;
}

/// Albums (by id, falling back to name+artist) whose normalized name and
/// artist match but whose ids differ: "Abbey Road" / "abbey road (Remastered)"
/// is not folded, but "ABBEY ROAD" and "Abbey  Road." are.
List<DupGroup> findDuplicateAlbums(Iterable<Song> songs) {
  final albums = <String, _Agg>{};
  for (final s in songs) {
    if (s.album.trim().isEmpty) continue;
    final id = s.albumId.isNotEmpty ? s.albumId : 'n:${s.album}\u0000${s.artist}';
    final a = albums.putIfAbsent(id, () => _Agg(id, s.album, s.artist));
    a.songs++;
    a.score += songScore(s);
  }
  return _collapse(
    albums.values,
    DupKind.album,
    (a) => '${normalizeName(a.name)}\u0000${normalizeArtist(a.artist)}',
    (a) => '${a.songs} ${a.songs == 1 ? 'song' : 'songs'}',
  );
}

/// Artists whose names differ only by case, punctuation, accents or a leading
/// "The" ("AC/DC" / "AC DC", "Beyoncé" / "Beyonce").
List<DupGroup> findDuplicateArtists(Iterable<Song> songs) {
  final artists = <String, _Agg>{};
  for (final s in songs) {
    if (s.artist.trim().isEmpty) continue;
    // Songs carry artist ids when the server gave them; otherwise the name is the id.
    final id = s.artistId.isNotEmpty ? s.artistId : 'n:${s.artist}';
    final a = artists.putIfAbsent(id, () => _Agg(id, s.artist, ''));
    a.songs++;
    a.score += 1;
  }
  return _collapse(
    artists.values,
    DupKind.artist,
    (a) => normalizeArtist(a.name),
    (a) => '${a.songs} ${a.songs == 1 ? 'song' : 'songs'}',
  );
}

class _Agg {
  final String id;
  final String name;
  final String artist;
  int songs = 0;
  int score = 0;
  _Agg(this.id, this.name, this.artist);
}

List<DupGroup> _collapse(Iterable<_Agg> all, DupKind kind, String Function(_Agg) key, String Function(_Agg) detail) {
  final byKey = <String, List<_Agg>>{};
  for (final a in all) {
    final k = key(a);
    if (k.replaceAll('\u0000', '').isEmpty) continue;
    (byKey[k] ??= []).add(a);
  }
  final groups = <DupGroup>[];
  for (final list in byKey.values) {
    if (list.length < 2) continue;
    // The one with the most songs is the one to keep; then the better quality.
    list.sort((a, b) => b.songs != a.songs ? b.songs.compareTo(a.songs) : b.score.compareTo(a.score));
    final items = [
      for (final a in list)
        DupItem(id: a.id, title: a.name, subtitle: a.artist, detail: detail(a), score: a.songs * 1000000 + a.score),
    ];
    groups.add(DupGroup(kind: kind, items: items, suggestedKeeperId: _best(items)));
  }
  groups.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return groups;
}

/// The ids to hide in a group once [keeperId] is chosen: everything else.
List<String> extrasOf(DupGroup g, String keeperId) => [for (final i in g.items) if (i.id != keeperId) i.id];

/// A plain-text clean-up list for the extras the user decided against, to take
/// to the server by hand. Nothing here deletes anything.
/// [keeperByGroup] maps a group's [DupGroup.suggestedKeeperId] to the keeper the
/// user chose instead.
String buildCleanupExport(List<DupGroup> groups, Map<String, String> keeperByGroup, {DateTime? now}) {
  final b = StringBuffer('NaviVibe duplicate clean-up list\n')
    ..writeln('Generated ${(now ?? DateTime.now()).toIso8601String()}')
    ..writeln('Review each pair; nothing has been deleted.\n');
  for (final g in groups) {
    final keeper = keeperByGroup[g.suggestedKeeperId] ?? g.suggestedKeeperId;
    final k = g.items.firstWhere((i) => i.id == keeper, orElse: () => g.items.first);
    b.writeln('[${g.kind.name}] ${k.title}${k.subtitle.isEmpty ? '' : ' — ${k.subtitle}'}');
    b.writeln('  KEEP   ${k.id}  ${k.detail}');
    for (final i in g.items) {
      if (i.id != k.id) b.writeln('  EXTRA  ${i.id}  ${i.detail}');
    }
    b.writeln();
  }
  return b.toString();
}
