import 'dart:math';

import '../../../models/catalog.dart';
import '../../../models/song.dart';
import 'smart_rules.dart';

/// Everything a rule can ask about one song, gathered once so evaluating
/// thousands of songs touches no database.
class SongFacts {
  final Song song;

  /// ISO 639-1 codes, primary first (2+ means multilingual). Empty = unknown.
  final List<String> languages;
  final String? mood;

  /// Epoch milliseconds of each finished play (skips before halfway left out).
  final List<int> playTimes;

  const SongFacts({required this.song, this.languages = const [], this.mood, this.playTimes = const []});

  DateTime? get lastPlayed {
    if (playTimes.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(playTimes.reduce(max));
  }

  int playsSince(DateTime from) {
    final cut = from.millisecondsSinceEpoch;
    var n = 0;
    for (final t in playTimes) {
      if (t >= cut) n++;
    }
    return n;
  }
}

/// A mood label for a song, read from the words in the catalog's genre and
/// genre bucket ("tamil__melody__calm", "Kuthu / Dance"). Null when nothing
/// there suggests one — the server doesn't tag mood directly.
String? moodFromCatalog(CatalogSong? meta) {
  if (meta == null) return null;
  final text = '${meta.bucket ?? ''} ${meta.genre ?? ''}'.toLowerCase();
  for (final (mood, words) in _moodWords) {
    if (words.any(text.contains)) return mood;
  }
  return null;
}

/// Order matters: the first mood with a matching word wins.
const _moodWords = <(String, List<String>)>[
  ('sad', ['sad', 'melanchol', 'sorrow', 'heartbreak', 'pathos', 'lonely']),
  ('romantic', ['romantic', 'romance', 'love']),
  ('energetic', ['kuthu', 'dance', 'party', 'mass', 'energ', 'rock', 'hip hop', 'edm']),
  ('happy', ['happy', 'upbeat', 'feel good', 'feel-good', 'joy']),
  ('calm', ['calm', 'chill', 'soothing', 'peaceful', 'melody', 'ambient', 'lofi', 'lo-fi']),
];

const moodLabels = ['sad', 'calm', 'romantic', 'happy', 'energetic'];

/// Runs smart-playlist rules over a library. Pure: [now] and [random] are
/// passed in, so results are repeatable in tests.
class SmartEvaluator {
  const SmartEvaluator._();

  static List<SongFacts> evaluate(
    SmartPlaylist playlist,
    Iterable<SongFacts> library, {
    required DateTime now,
    Random? random,
  }) {
    final matches = [for (final f in library) if (matchesGroup(playlist.rules, f, now)) f];
    _sort(matches, playlist.sort, playlist.ascending, now, random ?? Random());
    final limit = playlist.limit;
    return limit != null && limit > 0 && matches.length > limit ? matches.sublist(0, limit) : matches;
  }

  static bool matchesGroup(SmartGroup g, SongFacts f, DateTime now) {
    // An empty group matches everything, like "all songs".
    final active = [
      for (final c in g.children)
        if (c is SmartGroup ? c.ruleCount > 0 : (c as SmartRule).isComplete) c,
    ];
    if (active.isEmpty) return true;
    bool test(SmartNode n) => n is SmartGroup ? matchesGroup(n, f, now) : matchesRule(n as SmartRule, f, now);
    return g.matchAll ? active.every(test) : active.any(test);
  }

  static bool matchesRule(SmartRule r, SongFacts f, DateTime now) {
    if (!r.isComplete) return true;
    return switch (r.field.kind) {
      SmartFieldKind.text => _text(r, _texts(r.field, f)),
      SmartFieldKind.number => _number(r, _numberOf(r, f, now)),
      SmartFieldKind.days => _days(r, _daysSince(r.field, f, now)),
      SmartFieldKind.flag => f.song.starred == (r.value != 'false'),
    };
  }

  static List<String> _texts(SmartField field, SongFacts f) {
    final s = f.song;
    final raw = switch (field) {
      SmartField.title => [s.title],
      SmartField.artist => [s.artist],
      SmartField.album => [s.album],
      SmartField.genre => [s.genre],
      SmartField.composer => [s.composer],
      SmartField.language => f.languages,
      SmartField.mood => [f.mood ?? ''],
      _ => const <String>[],
    };
    return [for (final t in raw) if (t.trim().isNotEmpty) t.trim().toLowerCase()];
  }

  static bool _text(SmartRule r, List<String> values) {
    final want = r.value.trim().toLowerCase();
    return switch (r.op) {
      SmartOp.isOp => values.contains(want),
      SmartOp.isNot => !values.contains(want),
      SmartOp.contains => values.any((v) => v.contains(want)),
      SmartOp.notContains => !values.any((v) => v.contains(want)),
      _ => true,
    };
  }

  static double? _numberOf(SmartRule r, SongFacts f, DateTime now) {
    final s = f.song;
    return switch (r.field) {
      SmartField.year => s.year > 0 ? s.year.toDouble() : null,
      SmartField.length => s.duration / 60,
      SmartField.playCount => s.playCount.toDouble(),
      SmartField.rating => s.rating.toDouble(),
      SmartField.recentPlays => f.playsSince(now.subtract(Duration(days: r.window))).toDouble(),
      _ => null,
    };
  }

  static bool _number(SmartRule r, double? have) {
    final want = double.tryParse(r.value.trim().replaceAll(',', '.'));
    if (have == null || want == null) return false;
    // Lengths are fractional minutes: "= 3" means a song of 3:00–3:59.
    if (r.field == SmartField.length) {
      return switch (r.op) {
        SmartOp.eq => have >= want && have < want + 1,
        SmartOp.neq => !(have >= want && have < want + 1),
        SmartOp.gt => have >= want + 1,
        SmartOp.gte => have >= want,
        SmartOp.lt => have < want,
        SmartOp.lte => have < want + 1,
        _ => true,
      };
    }
    return switch (r.op) {
      SmartOp.eq => have == want,
      SmartOp.neq => have != want,
      SmartOp.gt => have > want,
      SmartOp.gte => have >= want,
      SmartOp.lt => have < want,
      SmartOp.lte => have <= want,
      _ => true,
    };
  }

  /// Whole days since the song was added / last played; null when unknown.
  static int? _daysSince(SmartField field, SongFacts f, DateTime now) {
    final at = field == SmartField.added ? f.song.created : f.lastPlayed;
    if (at == null) return null;
    final d = now.difference(at).inHours ~/ 24;
    return d < 0 ? 0 : d;
  }

  static bool _days(SmartRule r, int? since) {
    final n = int.tryParse(r.value.trim());
    if (n == null) return true;
    final within = since != null && since <= n;
    // Never played / unknown date counts as "not in the last N days".
    return r.op == SmartOp.notWithin ? !within : within;
  }

  static void _sort(List<SongFacts> list, SmartSort sort, bool asc, DateTime now, Random random) {
    if (sort == SmartSort.random) {
      list.shuffle(random);
      return;
    }
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final monthAgo = now.subtract(const Duration(days: 30));
    Comparable key(SongFacts f) => switch (sort) {
          SmartSort.title => f.song.title.toLowerCase(),
          SmartSort.artist => f.song.artist.toLowerCase(),
          SmartSort.year => f.song.year,
          SmartSort.added => (f.song.created ?? epoch).millisecondsSinceEpoch,
          SmartSort.lastPlayed => (f.lastPlayed ?? epoch).millisecondsSinceEpoch,
          SmartSort.playCount => f.song.playCount,
          SmartSort.recentPlays => f.playsSince(monthAgo),
          SmartSort.length => f.song.duration,
          SmartSort.random => 0,
        };
    list.sort((a, b) {
      final c = key(a).compareTo(key(b));
      final ordered = asc ? c : -c;
      return ordered != 0 ? ordered : a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase());
    });
  }
}
