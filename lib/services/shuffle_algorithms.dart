// ---------------------------------------------------------------------------
// shuffle_algorithms.dart
//
// Single source of truth for all shuffle isolate workers used in production
// by NaviAudioHandler (via compute()) and exercised directly by tests.
//
// ISOLATE RULES:
//   1. All functions MUST be top-level — no closures, no instance methods.
//   2. Song contains only plain value types → isolate-safe.
//   3. ShufflePreference is passed as its raw index (int).
//   4. dart:math is available in bare isolates.
// ---------------------------------------------------------------------------

import 'dart:math';
import '../models/song.dart';
import '../providers/settings_provider.dart' show ShufflePreference;

// ---------------------------------------------------------------------------
// SHARED WEIGHT HELPER
// ---------------------------------------------------------------------------

/// Computes the shuffle weight for [song].
///
/// Formula:
///   w = dynamicWeight.clamp(0.1, 10.0)
///   × 2.0   if starred
///   + (rating − 1) / 4.0   if rated  (0–1 additive bonus)
///   + (playCount / 100).clamp(0, 1)   (0–1 additive bonus)
double songWeight(Song song) {
  double w = song.dynamicWeight.clamp(0.1, 10.0);
  if (song.starred) w *= 2.0;
  if (song.rating > 0) w += (song.rating - 1) / 4.0;
  w += (song.playCount / 100.0).clamp(0.0, 1.0);
  return w;
}

// ---------------------------------------------------------------------------
// ALGORITHM 1 — Standard Fisher-Yates
// ---------------------------------------------------------------------------

/// Shuffles [rest] using a standard Fisher-Yates pass.
List<Song> standardShuffleIsolate(List<Song> rest) {
  final list = List<Song>.from(rest);
  list.shuffle();
  return list;
}

// ---------------------------------------------------------------------------
// ALGORITHM 2 — Dithered Position Shuffle
// ---------------------------------------------------------------------------

/// Worker for dithered position shuffle.
/// Args map keys:
///   'songs' → List<Song>
///   'pref'  → int  (ShufflePreference.index)
List<Song> ditheredPositionShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List);
  final prefIndex = args['pref'] as int;
  final preference = ShufflePreference.values[prefIndex];
  final random = Random();
  final int total = songs.length;

  // Group songs by key (genre or composer).
  // Null is used for empty keys to avoid colliding with a real value named "Unknown".
  final Map<String?, List<Song>> groups = {};
  for (final song in songs) {
    final key = preference == ShufflePreference.composer
        ? song.composer
        : song.genre;
    groups.putIfAbsent(key.isNotEmpty ? key : null, () => []).add(song);
  }

  // Shuffle within each group so internal order is also random.
  for (final list in groups.values) {
    list.shuffle(random);
  }

  // Assign a floating-point position score to every song.
  final List<MapEntry<Song, double>> scored = [];

  for (final bucket in groups.values) {
    final double spacing = total / bucket.length.toDouble();
    final double offset = random.nextDouble() * spacing;

    for (int i = 0; i < bucket.length; i++) {
      final double dither = (random.nextDouble() - 0.5) * spacing * 0.1;
      final double position = offset + (i * spacing) + dither;
      scored.add(MapEntry(bucket[i], position));
    }
  }

  scored.sort((a, b) => a.value.compareTo(b.value));
  return scored.map((e) => e.key).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 3 — Merge-Shuffle  (Ruud van Asseldonk, 2023)
// ---------------------------------------------------------------------------

/// Interleaves [smaller] into [larger] at evenly distributed positions.
/// This is the core primitive of merge-shuffle.
List<Song> interleave(List<Song> larger, List<Song> smaller, Random random) {
  if (larger.length < smaller.length) {
    return interleave(smaller, larger, random);
  }
  if (smaller.isEmpty) return larger;
  if (larger.isEmpty) return smaller;

  final int n = larger.length;
  final int m = smaller.length;
  final List<Song> result = [];
  int largerIndex = 0;
  final double partSize = n / (m + 1);

  for (int i = 0; i < m; i++) {
    final int end = ((i + 1) * partSize).round().clamp(largerIndex, n);
    result.addAll(larger.sublist(largerIndex, end));
    result.add(smaller[i]);
    largerIndex = end;
  }

  if (largerIndex < n) {
    result.addAll(larger.sublist(largerIndex));
  }

  return result;
}

/// Worker for merge-shuffle.
/// Args map keys:
///   'songs' → List<Song>
///   'pref'  → int  (ShufflePreference.index)
List<Song> mergeShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List);
  final prefIndex = args['pref'] as int;
  final preference = ShufflePreference.values[prefIndex];
  final random = Random();

  // Group and shuffle internally.
  // Null is used for empty keys to avoid colliding with a real value named "Unknown".
  final Map<String?, List<Song>> groups = {};
  for (final song in songs) {
    final key = preference == ShufflePreference.composer
        ? song.composer
        : song.genre;
    groups.putIfAbsent(key.isNotEmpty ? key : null, () => []).add(song);
  }
  for (final list in groups.values) {
    list.shuffle(random);
  }

  // Sort groups ascending by size.
  final buckets = groups.values.toList()
    ..sort((a, b) => a.length.compareTo(b.length));

  if (buckets.isEmpty) return songs;

  List<Song> result = List<Song>.from(buckets[0]);
  for (int i = 1; i < buckets.length; i++) {
    result = interleave(result, List<Song>.from(buckets[i]), random);
  }

  return result;
}

// ---------------------------------------------------------------------------
// ALGORITHM 4 — Weighted Shuffle  (O(n log n) — Efraimidis-Spirakis)
// ---------------------------------------------------------------------------

/// Worker for weighted shuffle — O(n log n).
/// Receives [pool] (all songs except current) and returns them in weighted
/// random order using the Efraimidis-Spirakis key trick.
List<Song> weightedShuffleIsolate(List<Song> pool) {
  final random = Random();

  final keyed = pool.map((song) {
    final w = songWeight(song);
    final r = random.nextDouble().clamp(1e-10, 1.0);
    // Log-space key: log(r)/w == log(r^(1/w)); monotonic with exp(...), so
    // sort order is identical but distinct keys avoid underflow to 0.0.
    final key = log(r) / w;
    return MapEntry(song, key);
  }).toList();

  keyed.sort((a, b) => b.value.compareTo(a.value));
  return keyed.map((e) => e.key).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 5 — Album-Aware Shuffle
// ---------------------------------------------------------------------------

/// Worker for album-aware shuffle.
/// Args map keys:
///   'songs'         → List<Song>
///   'shuffleTracks' → bool  (shuffle tracks within each album if true)
List<Song> albumAwareShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List);
  final shuffleTracks = args['shuffleTracks'] as bool? ?? false;
  final random = Random();

  // Group by album name.
  // Null is used for empty album to avoid colliding with a real album named "Unknown".
  final Map<String?, List<Song>> albums = {};
  for (final song in songs) {
    albums.putIfAbsent(song.album.isNotEmpty ? song.album : null, () => []).add(song);
  }

  for (final list in albums.values) {
    if (shuffleTracks) {
      list.shuffle(random);
    } else {
      list.sort((a, b) => a.track.compareTo(b.track));
    }
  }

  final albumKeys = albums.keys.toList()..shuffle(random);

  return albumKeys.expand((key) => albums[key]!).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 6 — Recency-Dampened Weighted Shuffle
// ---------------------------------------------------------------------------

/// Worker for recency-dampened weighted shuffle.
/// Args map keys:
///   'songs'     → List<Song>
///   'recentIds' → List<String>  (song IDs played recently in this session)
List<Song> recencyDampenedShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List);
  final recentIds = Set<String>.from(args['recentIds'] as List);
  final random = Random();

  final keyed = songs.map((song) {
    double w = songWeight(song);
    if (recentIds.contains(song.id)) w *= 0.1;
    w = w.clamp(0.01, 100.0);
    final r = random.nextDouble().clamp(1e-10, 1.0);
    // Log-space key: log(r)/w == log(r^(1/w)); monotonic with exp(...), so
    // sort order is identical but distinct keys avoid underflow to 0.0.
    final key = log(r) / w;
    return MapEntry(song, key);
  }).toList();

  keyed.sort((a, b) => b.value.compareTo(a.value));
  return keyed.map((e) => e.key).toList();
}
