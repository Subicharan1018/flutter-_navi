import 'dart:convert';
import 'dart:math';

import '../core/hive_boxes.dart';
import '../models/song.dart';

/// True Shuffle's memory: for each list you shuffle (a playlist, an album, the
/// library), which songs have already played in the current "bag". A shuffle
/// of the same list later puts the unheard songs first, so every song plays
/// once before any plays twice, across sessions. When the whole list has been
/// heard the bag empties and starts again.
///
/// Nothing here looks at ratings, plays, favourites or the recommender.
class ShuffleBag {
  /// Lists remembered at once; the least recently used is forgotten first.
  static const maxLists = 16;

  final ShuffleBagStore _store;
  Map<String, List<String>>? _cache;

  ShuffleBag([ShuffleBagStore? store]) : _store = store ?? HiveShuffleBagStore();

  /// A stable name for a list: the same songs in any order give the same key
  /// (FNV-1a over the sorted ids, so it never changes between runs).
  static String keyFor(Iterable<String> ids) {
    final sorted = ids.toList()..sort();
    var h = 0x811c9dc5;
    for (final unit in '${sorted.length}|${sorted.join('\u0000')}'.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  Map<String, List<String>> get _bags {
    final cached = _cache;
    if (cached != null) return cached;
    final out = <String, List<String>>{};
    try {
      final raw = jsonDecode(_store.read() ?? '{}');
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is List) out['$k'] = [for (final id in v) '$id'];
        });
      }
    } catch (_) {
      // A damaged store is an empty one: the worst case is some repeats.
    }
    return _cache = out;
  }

  /// The ids of [source] already heard in its current bag.
  Set<String> heard(Iterable<Song> source) {
    final ids = {for (final s in source) s.id};
    final seen = _bags[keyFor(ids)];
    return seen == null ? <String>{} : seen.where(ids.contains).toSet();
  }

  /// Notes that [songId] played from [source]. When that was the last unheard
  /// song the bag starts over.
  void markHeard(Iterable<Song> source, String songId) {
    final ids = {for (final s in source) s.id};
    if (ids.isEmpty || !ids.contains(songId)) return;
    final key = keyFor(ids);
    final bags = _bags;
    final seen = (bags.remove(key) ?? <String>[]).where(ids.contains).toList();
    if (!seen.contains(songId)) seen.add(songId);
    if (seen.length >= ids.length) {
      bags.remove(key); // a full bag: the next shuffle is a fresh one
    } else {
      bags[key] = seen; // re-inserted last: most recently used
    }
    while (bags.length > maxLists) {
      bags.remove(bags.keys.first);
    }
    _store.write(jsonEncode(bags));
  }

  /// A random song of [songs] that is not in the current bag yet (any song
  /// when all have been heard), for the one a shuffle starts on.
  Song pickStart(List<Song> songs, [Random? random]) {
    final seen = heard(songs);
    final fresh = [for (final s in songs) if (!seen.contains(s.id)) s];
    final from = fresh.isEmpty ? songs : fresh;
    return from[(random ?? Random()).nextInt(from.length)];
  }
}

/// Where the bags are kept.
abstract class ShuffleBagStore {
  String? read();
  void write(String json);
}

class HiveShuffleBagStore implements ShuffleBagStore {
  static const key = 'shuffleBags';

  @override
  String? read() => HiveBoxes.prefs.get(key)?.toString();

  @override
  void write(String json) => HiveBoxes.prefs.put(key, json);
}

/// Unheard songs first, heard ones after, each group in a uniform random
/// order. Runs on an isolate: [args] holds `songs` (a list of songs) and
/// `heard` (a list of song ids).
List<Song> bagShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List);
  final heard = {for (final id in (args['heard'] as List)) '$id'};
  final fresh = [for (final s in songs) if (!heard.contains(s.id)) s]..shuffle();
  final seen = [for (final s in songs) if (heard.contains(s.id)) s]..shuffle();
  return [...fresh, ...seen];
}
