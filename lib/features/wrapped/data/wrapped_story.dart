import 'dart:math' as math;

import '../../ai_shuffle/data/models/replay_response.dart';
import 'wrapped_models.dart';

/// What the library and the catalog know about one song.
class SongFacts {
  final int? year;
  final String? composer;
  final List<String> languages;
  final String? mood;
  final double? bpm;
  const SongFacts({this.year, this.composer, this.languages = const [], this.mood, this.bpm});
}

/// An album you came back to: [cover] is the "title|artist" of its most played song.
class WrappedAlbum {
  final String name;
  final String artist;
  final int plays;
  final int songs;
  final String cover;
  const WrappedAlbum(this.name, this.artist, this.plays, this.songs, this.cover);
}

/// A song that took over a month.
class Obsession {
  final String title;
  final String artist;
  final int plays;
  final int month;
  const Obsession(this.title, this.artist, this.plays, this.month);
}

/// An artist who was there month after month.
class Loyal {
  final String name;
  final List<int> months;
  const Loyal(this.name, this.months);
}

/// An artist who left your monthly lists for [gap] months and came back in [month].
class Comeback {
  final String name;
  final int gap;
  final int month;
  const Comeback(this.name, this.gap, this.month);
}

/// When your music was made.
class Era {
  final int middle;
  final int oldest;
  final int newest;
  final String oldestTitle;
  final String newestTitle;
  const Era(this.middle, this.oldest, this.newest, this.oldestTitle, this.newestTitle);
}

class WrappedPlay {
  final String title;
  final String artist;
  final String at;
  const WrappedPlay({required this.title, required this.artist, required this.at});
  Map<String, dynamic> toJson() => {'t': title, 'a': artist, 'd': at};
  factory WrappedPlay.fromJson(Map<String, dynamic> j) => WrappedPlay(title: '${j['t'] ?? ''}', artist: '${j['a'] ?? ''}', at: '${j['d'] ?? ''}');
}

class Bookends {
  final WrappedPlay first;
  final WrappedPlay last;
  const Bookends(this.first, this.last);
}

/// The first and latest play of [year], or null unless the plays [around] the edge (newest first) prove it: the play
/// just before the first one belongs to another year, or the log [reachesEnd] there.
Bookends? bookends(int year, {required WrappedPlay? latest, required List<WrappedPlay> around, bool reachesEnd = false}) {
  bool inYear(WrappedPlay p) => p.at.startsWith('$year');
  if (latest == null || !inYear(latest)) return null;
  for (var i = 0; i < around.length; i++) {
    if (!inYear(around[i])) continue;
    final edge = i + 1 < around.length ? !inYear(around[i + 1]) : reachesEnd;
    if (edge) return Bookends(around[i], latest);
  }
  return null;
}

/// The parts of a year that need more than its totals.
class WrappedStory {
  final Obsession? obsession;

  /// Plays added up month by month (12 long) for the artists that lead.
  final Map<String, List<int>> race;
  final Loyal? loyal;
  final Comeback? comeback;

  /// Average minutes of each weekday, Monday first; empty when the days are not known.
  final List<int> week;

  /// How many of your most played songs the library knows; the next four are about those.
  final int known;
  final List<WrappedGenre> languages;
  final List<WrappedArtist> composers;
  final List<WrappedGenre> moods;
  final Era? era;
  final Bookends? ends;

  /// Albums of your most played songs, by their plays.
  final List<WrappedAlbum> albums;

  /// Beats a minute of your number one, when the server has analysed it.
  final double? bpm;

  const WrappedStory({
    this.albums = const [],
    this.bpm,
    this.obsession,
    this.race = const {},
    this.loyal,
    this.comeback,
    this.week = const [],
    this.known = 0,
    this.languages = const [],
    this.composers = const [],
    this.moods = const [],
    this.era,
    this.ends,
  });

  Map<String, dynamic> toJson() => {
    if (obsession case final o?) 'o': [o.title, o.artist, o.plays, o.month],
    'r': race,
    if (loyal case final l?) 'l': {'n': l.name, 'm': l.months},
    if (comeback case final c?) 'c': [c.name, c.gap, c.month],
    'w': week,
    'k': known,
    'la': [for (final g in languages) g.toJson()],
    'co': [for (final c in composers) c.toJson()],
    'mo': [for (final g in moods) g.toJson()],
    if (era case final e?) 'e': [e.middle, e.oldest, e.newest, e.oldestTitle, e.newestTitle],
    if (ends case final b?) 'b': [b.first.toJson(), b.last.toJson()],
    'al': [
      for (final a in albums) [a.name, a.artist, a.plays, a.songs, a.cover],
    ],
    'bpm': ?bpm,
  };

  factory WrappedStory.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) => [
      for (final e in (j[k] as List? ?? const []))
        if (e is Map) f(Map<String, dynamic>.from(e)),
    ];
    int n(Object? v) => (v as num).toInt();
    final o = j['o'] as List?, l = j['l'] as Map?, c = j['c'] as List?, e = j['e'] as List?, b = j['b'] as List?;
    return WrappedStory(
      albums: [
        for (final a in (j['al'] as List? ?? const []))
          if (a is List && a.length == 5) WrappedAlbum('${a[0]}', '${a[1]}', n(a[2]), n(a[3]), '${a[4]}'),
      ],
      bpm: (j['bpm'] as num?)?.toDouble(),
      obsession: o == null ? null : Obsession('${o[0]}', '${o[1]}', n(o[2]), n(o[3])),
      race: {for (final x in ((j['r'] as Map?) ?? const {}).entries) '${x.key}': [for (final v in x.value as List) n(v)]},
      loyal: l == null ? null : Loyal('${l['n']}', [for (final v in l['m'] as List) n(v)]),
      comeback: c == null ? null : Comeback('${c[0]}', n(c[1]), n(c[2])),
      week: [for (final v in (j['w'] as List? ?? const [])) n(v)],
      known: n(j['k'] ?? 0),
      languages: list('la', WrappedGenre.fromJson),
      composers: list('co', WrappedArtist.fromJson),
      moods: list('mo', WrappedGenre.fromJson),
      era: e == null ? null : Era(n(e[0]), n(e[1]), n(e[2]), '${e[3]}', '${e[4]}'),
      ends: b == null ? null : Bookends(WrappedPlay.fromJson(Map<String, dynamic>.from(b[0] as Map)), WrappedPlay.fromJson(Map<String, dynamic>.from(b[1] as Map))),
    );
  }
}

/// Works the story out. Pure. [pool] is your most played songs, [facts] what is known of them by "title|artist".
WrappedStory buildStory({
  required List<MonthlyReplayResponse> months,
  List<WrappedDay> days = const [],
  List<WrappedSong> pool = const [],
  Map<String, SongFacts> facts = const {},
  Bookends? ends,
}) {
  final sorted = [...months]..sort((a, b) => a.month.compareTo(b.month));

  Obsession? obsession;
  final gained = <String, List<int>>{};
  final seen = <String, List<int>>{};
  for (final m in sorted) {
    for (final t in m.topTracks) {
      if (t.playCount >= 8 && t.playCount > (obsession?.plays ?? 0)) obsession = Obsession(t.title, t.artist, t.playCount, m.month);
    }
    for (final a in m.topArtists) {
      if (a.artist.isEmpty) continue;
      (gained[a.artist] ??= List.filled(12, 0))[m.month - 1] += a.playCount;
      (seen[a.artist] ??= []).add(m.month);
    }
  }

  final totals = gained.map((k, v) {
    var sum = 0;
    return MapEntry(k, [for (final x in v) sum += x]);
  });
  final leaders = totals.keys.toList()..sort((a, b) => totals[b]!.last.compareTo(totals[a]!.last));
  final race = {for (final k in leaders.take(8)) k: totals[k]!};

  Loyal? loyal;
  Comeback? comeback;
  final listed = [for (final m in sorted) m.month];
  for (final k in leaders) {
    final at = seen[k]!;
    if (at.length >= 3 && at.length > (loyal?.months.length ?? 0)) loyal = Loyal(k, at);
    for (var i = 1; i < at.length; i++) {
      // only months that have a list of their own count as away
      final away = listed.where((x) => x > at[i - 1] && x < at[i]).length;
      if (away >= 2 && away > (comeback?.gap ?? 0)) comeback = Comeback(k, away, at[i]);
    }
  }

  var week = const <int>[];
  if (days.isNotEmpty) {
    final sum = List.filled(7, 0), n = List.filled(7, 0);
    for (final d in days) {
      final t = d.parsed;
      if (t == null) continue;
      sum[t.weekday - 1] += d.minutes;
      n[t.weekday - 1]++;
    }
    week = [for (var i = 0; i < 7; i++) n[i] == 0 ? 0 : (sum[i] / n[i]).round()];
  }

  final byAlbum = <String, (String, int, int, String, int)>{}; // name -> artist, plays, songs, cover, cover plays
  for (final s in pool) {
    if (s.album.trim().isEmpty) continue;
    final was = byAlbum[s.album];
    byAlbum[s.album] = was == null
        ? (s.artist, s.plays, 1, s.coverKey, s.plays)
        : (was.$1, was.$2 + s.plays, was.$3 + 1, s.plays > was.$5 ? s.coverKey : was.$4, math.max(was.$5, s.plays));
  }
  final albumNames = byAlbum.keys.toList()..sort((a, b) => byAlbum[b]!.$2.compareTo(byAlbum[a]!.$2));
  final albums = [
    for (final k in albumNames.take(8)) WrappedAlbum(k, byAlbum[k]!.$1, byAlbum[k]!.$2, byAlbum[k]!.$3, byAlbum[k]!.$4),
  ];
  final bpm = pool.isEmpty ? null : facts[pool.first.coverKey]?.bpm;

  final known = [
    for (final s in pool)
      if (facts[s.coverKey] case final f?) (s, f),
  ];
  if (known.length < 3) {
    return WrappedStory(obsession: obsession, race: race, loyal: loyal, comeback: comeback, week: week, ends: ends, albums: albums, bpm: bpm);
  }

  List<WrappedGenre> shares(String? Function(SongFacts) of) {
    final by = <String, int>{};
    var total = 0;
    for (final (s, f) in known) {
      final k = of(f);
      if (k == null || k.isEmpty) continue;
      by[k] = (by[k] ?? 0) + s.plays;
      total += s.plays;
    }
    final keys = by.keys.toList()..sort((a, b) => by[b]!.compareTo(by[a]!));
    return [for (final k in keys) WrappedGenre(name: k, pct: 100 * by[k]! / math.max(1, total))];
  }

  final byComposer = <String, int>{}, songsOf = <String, int>{};
  for (final (s, f) in known) {
    final c = f.composer?.trim();
    if (c == null || c.isEmpty) continue;
    byComposer[c] = (byComposer[c] ?? 0) + s.plays;
    songsOf[c] = (songsOf[c] ?? 0) + 1;
  }
  final composers = byComposer.keys.toList()..sort((a, b) => byComposer[b]!.compareTo(byComposer[a]!));

  Era? era;
  final dated = [
    for (final (s, f) in known)
      if ((f.year ?? 0) > 1900) (s, f.year!),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  if (dated.length >= 3) {
    final half = dated.fold<int>(0, (a, x) => a + x.$1.plays) / 2;
    var run = 0;
    var middle = dated.last.$2;
    for (final (s, year) in dated) {
      run += s.plays;
      if (run >= half) {
        middle = year;
        break;
      }
    }
    era = Era(middle, dated.first.$2, dated.last.$2, dated.first.$1.title, dated.last.$1.title);
  }

  return WrappedStory(
    obsession: obsession,
    race: race,
    loyal: loyal,
    comeback: comeback,
    week: week,
    known: known.length,
    languages: shares((f) => f.languages.firstOrNull),
    composers: [for (final c in composers.take(8)) WrappedArtist(name: c, plays: byComposer[c]!, minutes: 0, songs: songsOf[c]!)],
    moods: shares((f) => f.mood),
    era: era,
    ends: ends,
    albums: albums,
    bpm: bpm,
  );
}
