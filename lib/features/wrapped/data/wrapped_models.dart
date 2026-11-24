import 'dart:math' as math;

/// A song in your year.
class WrappedSong {
  final String title;
  final String artist;
  final int plays;
  final int minutes;
  const WrappedSong({required this.title, required this.artist, required this.plays, required this.minutes});

  /// The key the cover providers use ("title|artist").
  String get coverKey => '$title|$artist';

  Map<String, dynamic> toJson() => {'t': title, 'a': artist, 'p': plays, 'm': minutes};
  factory WrappedSong.fromJson(Map<String, dynamic> j) =>
      WrappedSong(title: '${j['t'] ?? ''}', artist: '${j['a'] ?? ''}', plays: _i(j['p']), minutes: _i(j['m']));
}

class WrappedArtist {
  final String name;
  final int plays;
  final int minutes;
  final int songs;
  const WrappedArtist({required this.name, required this.plays, required this.minutes, required this.songs});

  Map<String, dynamic> toJson() => {'n': name, 'p': plays, 'm': minutes, 's': songs};
  factory WrappedArtist.fromJson(Map<String, dynamic> j) => WrappedArtist(name: '${j['n'] ?? ''}', plays: _i(j['p']), minutes: _i(j['m']), songs: _i(j['s']));
}

class WrappedGenre {
  final String name;

  /// Share of your plays, 0..100.
  final double pct;
  const WrappedGenre({required this.name, required this.pct});

  Map<String, dynamic> toJson() => {'n': name, 'p': pct};
  factory WrappedGenre.fromJson(Map<String, dynamic> j) => WrappedGenre(name: '${j['n'] ?? ''}', pct: _d(j['p']));
}

class WrappedMonth {
  final int month;
  final int minutes;
  final String? topGenre;
  final String? topSong;
  const WrappedMonth({required this.month, required this.minutes, this.topGenre, this.topSong});

  Map<String, dynamic> toJson() => {'mo': month, 'm': minutes, 'g': topGenre, 's': topSong};
  factory WrappedMonth.fromJson(Map<String, dynamic> j) =>
      WrappedMonth(month: _i(j['mo']), minutes: _i(j['m']), topGenre: j['g'] as String?, topSong: j['s'] as String?);
}

/// One day with music: `date` is `yyyy-mm-dd`.
class WrappedDay {
  final String date;
  final int minutes;
  const WrappedDay({required this.date, required this.minutes});

  DateTime? get parsed => DateTime.tryParse(date);

  Map<String, dynamic> toJson() => {'d': date, 'm': minutes};
  factory WrappedDay.fromJson(Map<String, dynamic> j) => WrappedDay(date: '${j['d'] ?? ''}', minutes: _i(j['m']));
}

/// How you listen, as one of a few named kinds, with the four dials it was picked from (each 0..1).
class WrappedPersonality {
  final String id;
  final String name;
  final String line;
  final Map<String, double> traits;
  const WrappedPersonality({required this.id, required this.name, required this.line, required this.traits});
}

/// Everything the Wrapped story shows, worked out once and kept on the device.
class WrappedData {
  final int year;
  final int totalMinutes;
  final int totalPlays;
  final int uniqueSongs;
  final int uniqueArtists;
  final int listeningDays;
  final double skipRate;
  final int peakHour;

  /// Plays per hour of the day, 24 long.
  final List<int> hourly;
  final List<WrappedSong> songs;
  final List<WrappedArtist> artists;
  final List<WrappedGenre> genres;

  /// Twelve entries, January first.
  final List<WrappedMonth> months;

  /// Days with music, oldest first.
  final List<WrappedDay> days;
  final int longestStreak;
  final String? streakStart;
  final String? streakEnd;
  final WrappedDay? bestDay;

  const WrappedData({
    required this.year,
    required this.totalMinutes,
    required this.totalPlays,
    required this.uniqueSongs,
    required this.uniqueArtists,
    required this.listeningDays,
    required this.skipRate,
    required this.peakHour,
    required this.hourly,
    required this.songs,
    required this.artists,
    required this.genres,
    required this.months,
    required this.days,
    required this.longestStreak,
    this.streakStart,
    this.streakEnd,
    this.bestDay,
  });

  bool get isEmpty => totalPlays == 0;

  /// The busiest month (most minutes), or null when no month has any.
  WrappedMonth? get busiestMonth {
    WrappedMonth? best;
    for (final m in months) {
      if (m.minutes > 0 && (best == null || m.minutes > best.minutes)) best = m;
    }
    return best;
  }

  WrappedPersonality get personality => personalityOf(this);

  Map<String, dynamic> toJson() => {
    'y': year,
    'tm': totalMinutes,
    'tp': totalPlays,
    'us': uniqueSongs,
    'ua': uniqueArtists,
    'ld': listeningDays,
    'sk': skipRate,
    'ph': peakHour,
    'h': hourly,
    'songs': [for (final s in songs) s.toJson()],
    'artists': [for (final a in artists) a.toJson()],
    'genres': [for (final g in genres) g.toJson()],
    'months': [for (final m in months) m.toJson()],
    'days': [for (final d in days) d.toJson()],
    'ls': longestStreak,
    'ss': streakStart,
    'se': streakEnd,
    'bd': bestDay?.toJson(),
  };

  factory WrappedData.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) => [
      for (final e in (j[k] as List? ?? const []))
        if (e is Map) f(Map<String, dynamic>.from(e)),
    ];
    final hourly = [for (final e in (j['h'] as List? ?? const [])) _i(e)];
    while (hourly.length < 24) {
      hourly.add(0);
    }
    return WrappedData(
      year: _i(j['y']),
      totalMinutes: _i(j['tm']),
      totalPlays: _i(j['tp']),
      uniqueSongs: _i(j['us']),
      uniqueArtists: _i(j['ua']),
      listeningDays: _i(j['ld']),
      skipRate: _d(j['sk']),
      peakHour: _i(j['ph']),
      hourly: hourly.take(24).toList(),
      songs: list('songs', WrappedSong.fromJson),
      artists: list('artists', WrappedArtist.fromJson),
      genres: list('genres', WrappedGenre.fromJson),
      months: list('months', WrappedMonth.fromJson),
      days: list('days', WrappedDay.fromJson),
      longestStreak: _i(j['ls']),
      streakStart: j['ss'] as String?,
      streakEnd: j['se'] as String?,
      bestDay: j['bd'] is Map ? WrappedDay.fromJson(Map<String, dynamic>.from(j['bd'] as Map)) : null,
    );
  }
}

/// A year nothing is known about yet: enough to light the intro while the rest is on its way.
WrappedData emptyWrapped(int year) => WrappedData(
  year: year,
  totalMinutes: 0,
  totalPlays: 0,
  uniqueSongs: 0,
  uniqueArtists: 0,
  listeningDays: 0,
  skipRate: 0,
  peakHour: 0,
  hourly: List.filled(24, 0),
  songs: const [],
  artists: const [],
  genres: const [],
  months: [for (var m = 1; m <= 12; m++) WrappedMonth(month: m, minutes: 0)],
  days: const [],
  longestStreak: 0,
);

/// Picks the archetype from four dials: how much is new (explorer), how much is one artist
/// (devotee), how much is after 10 pm (night) and how big your biggest day is next to a usual one (marathon).
WrappedPersonality personalityOf(WrappedData d) {
  double clamp(double v) => v.isNaN || v.isInfinite ? 0 : math.max(0, math.min(1, v));
  final plays = math.max(1, d.totalPlays);
  final heat = d.hourly.fold<int>(0, (a, b) => a + b);
  final late = [22, 23, 0, 1, 2, 3, 4].fold<int>(0, (a, h) => a + d.hourly[h]);
  final topArtist = d.artists.isEmpty ? 0 : d.artists.first.plays;
  final avgDay = d.days.isEmpty ? 0 : d.days.fold<int>(0, (a, b) => a + b.minutes) / d.days.length;
  final traits = {
    'explorer': clamp(d.uniqueSongs / plays * 1.6),
    'devotee': clamp(topArtist / plays * 2.5),
    'night': clamp(heat == 0 ? 0 : late / heat * 2),
    'marathon': clamp(avgDay == 0 || d.bestDay == null ? 0 : (d.bestDay!.minutes / avgDay) / 6),
  };
  var id = 'easy';
  var top = 0.45; // below this nothing stands out
  traits.forEach((k, v) {
    if (v > top) {
      id = k;
      top = v;
    }
  });
  const names = {
    'explorer': ('The Pathfinder', 'You were always chasing the next song nobody told you about.'),
    'devotee': ('The Devotee', 'When you love an artist, you go all the way.'),
    'night': ('The Night Shift', 'Your best listening starts when everyone else is asleep.'),
    'marathon': ('The Marathoner', 'Some days you just press play and do not stop.'),
    'easy': ('The Easy Listener', 'Steady, relaxed, and always in the mood for music.'),
  };
  final n = names[id]!;
  // The ids a caller sees: devotee, explorer, night, marathon, easy.
  return WrappedPersonality(id: id, name: n.$1, line: n.$2, traits: traits);
}

int _i(Object? v) => v is int
    ? v
    : v is num
    ? v.round()
    : int.tryParse('$v') ?? 0;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
