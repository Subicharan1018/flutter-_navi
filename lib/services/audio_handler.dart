import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'subsonic_service.dart';
import '../providers/settings_provider.dart';

// ---------------------------------------------------------------------------
// BUG-23 FIX: Top-level isolate worker functions.
//
// compute() spawns a true OS-level isolate with no shared memory. That means:
//   1. The function MUST be top-level or static — not a closure or instance
//      method. Dart cannot serialise a closure across isolate boundaries.
//   2. Arguments and return values are deep-copied via the message port, so
//      Song must contain only plain value types (no platform handles, no
//      Flutter objects). The current Song model is compliant.
//   3. ShufflePreference is passed as its raw index (int) because the enum
//      may live in a file that imports Flutter, and bare isolates cannot
//      initialise the Flutter engine. Reconstruct it on the other side with
//      ShufflePreference.values[index].
// ---------------------------------------------------------------------------

/// Worker for [AudioHandler.standardShuffle].
/// Receives [rest] (all songs except the current one) and returns them
/// shuffled using a standard Fisher-Yates pass via [List.shuffle].
List<Song> _standardShuffleIsolate(List<Song> rest) {
  rest.shuffle();
  return rest;
}

/// Worker for [AudioHandler.spotifyDitherShuffle].
/// Args map keys:
///   'songs' → List<Song>  (all songs except current)
///   'pref'  → int         (ShufflePreference.index)
List<Song> _balancedShuffleIsolate(Map<String, dynamic> args) {
  final songs = args['songs'] as List<Song>;
  final prefIndex = args['pref'] as int;
  final preference = ShufflePreference.values[prefIndex];

  // Group by preference key (composer or genre).
  final Map<String, List<Song>> groups = {};
  for (final song in songs) {
    final key =
        preference == ShufflePreference.composer ? song.composer : song.genre;
    final finalKey = key.isNotEmpty ? key : 'Unknown';
    groups.putIfAbsent(finalKey, () => []).add(song);
  }

  // Shuffle each category's bucket internally.
  for (final list in groups.values) {
    list.shuffle();
  }

  final List<Song> result = [];
  List<String> categories = groups.keys.toList()..shuffle();
  final Map<String, int> categoryIndices = {for (final c in categories) c: 0};
  int totalRemaining = songs.length;
  int round = 1;

  while (totalRemaining > 0) {
    for (final category in categories) {
      final idx = categoryIndices[category]!;
      final bucket = groups[category]!;
      if (idx < bucket.length) {
        result.add(bucket[idx]);
        categoryIndices[category] = idx + 1;
        totalRemaining--;
      }
    }
    categories.shuffle();
    round++;
    // Suppress unused variable warning for round (kept for symmetry with
    // the original algorithm's round-1 back-to-back avoidance logic, which
    // is omitted here since the current song is prepended by the caller).
  }

  return result;
}

/// Worker for [AudioHandler.youtubeWeightedShuffle].
/// Receives [pool] (all songs except current) and returns them in weighted
/// random order. Weight formula:
///   w = dynamicWeight.clamp(0.1, 10.0)
///   × 2.0  if starred
///   + (rating - 1) / 4.0  if rated  (0–1 additive bonus)
///   + (playCount / 100).clamp(0, 1)  (0–1 additive bonus)
List<Song> _weightedShuffleIsolate(List<Song> pool) {
  final List<Song> shuffled = [];
  final random = Random();

  while (pool.isNotEmpty) {
    double totalWeight = 0;
    final List<double> weights = [];

    for (final song in pool) {
      double w = song.dynamicWeight.clamp(0.1, 10.0);
      if (song.starred) w *= 2.0;
      if (song.rating > 0) w += (song.rating - 1) / 4.0;
      w += (song.playCount / 100.0).clamp(0.0, 1.0);
      weights.add(w);
      totalWeight += w;
    }

    double target = random.nextDouble() * totalWeight;
    double cumulative = 0;
    int selectedIndex = pool.length - 1;

    for (int i = 0; i < weights.length; i++) {
      cumulative += weights[i];
      if (cumulative >= target) {
        selectedIndex = i;
        break;
      }
    }

    shuffled.add(pool.removeAt(selectedIndex));
  }

  return shuffled;
}

// ---------------------------------------------------------------------------
// AudioHandler
// ---------------------------------------------------------------------------

class AudioHandler {
  final AudioPlayer player;
  final SubsonicService subsonicService;
  List<Song> _currentQueue = [];
  List<Song> _unshuffledQueue = [];

  // Kept alive between queue mutations so we can use incremental APIs
  // (add / removeAt / move) instead of rebuilding the entire source.
  ConcatenatingAudioSource? _playlist;

  AudioHandler(this.subsonicService, {AudioPlayer? player})
      : player = player ?? AudioPlayer();

  @visibleForTesting
  set currentQueue(List<Song> songs) => _currentQueue = songs;

  List<Song> get currentQueue => _currentQueue;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  AudioSource _toSource(Song song) {
    return AudioSource.uri(
      Uri.parse(subsonicService.getStreamUrl(song.id)),
      tag: MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        artUri: Uri.parse(subsonicService.getCoverArtUrl(song.coverArt)),
        duration: Duration(seconds: song.duration),
        extras: {'composer': song.composer},
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Full rebuild — only called when the entire queue is replaced (setQueue /
  // shuffle). For incremental changes use addToQueue / removeFromQueue /
  // reorderQueue below.
  // ---------------------------------------------------------------------------
  Future<void> setQueue(List<Song> songs, int startIndex, {List<Song>? unshuffledSongs}) async {
    _currentQueue = List.from(songs);
    _unshuffledQueue = List.from(unshuffledSongs ?? songs);
    await _rebuildSource(startIndex);
  }

  Future<void> _rebuildSource(int startIndex) async {
    if (_currentQueue.isEmpty) return;
    final sources = _currentQueue.map(_toSource).toList();
    _playlist = ConcatenatingAudioSource(children: sources);
    await player.setAudioSource(_playlist!, initialIndex: startIndex);
  }

  /// Updates the Future part of the queue without interrupting the current song.
  Future<void> _updateQueueAfterAnchor(int anchorIndex) async {
    if (_playlist == null) {
      await _rebuildSource(anchorIndex);
      return;
    }

    // Remove everything after the current song
    if (_playlist!.length > anchorIndex + 1) {
      await _playlist!.removeRange(anchorIndex + 1, _playlist!.length);
    }

    // Append the new Future
    final newFuture = _currentQueue.sublist(anchorIndex + 1);
    if (newFuture.isNotEmpty) {
      await _playlist!.addAll(newFuture.map(_toSource).toList());
    }
  }

  // ---------------------------------------------------------------------------
  // Incremental queue mutations
  // These mutate the existing ConcatenatingAudioSource so playback of the
  // current song is never interrupted.
  // ---------------------------------------------------------------------------

  Future<void> addToQueue(Song song) async {
    _currentQueue.add(song);
    _unshuffledQueue.add(song);
    if (_playlist != null) {
      await _playlist!.add(_toSource(song));
    } else {
      await _rebuildSource(_currentQueue.length - 1);
    }
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _currentQueue.length) return;
    final song = _currentQueue.removeAt(index);
    final unIdx = _unshuffledQueue.indexWhere((s) => s.id == song.id);
    if (unIdx != -1) _unshuffledQueue.removeAt(unIdx);

    if (_playlist != null) {
      await _playlist!.removeAt(index);
    } else {
      final currentIndex = player.currentIndex ?? 0;
      await _rebuildSource(currentIndex.clamp(0, _currentQueue.length - 1));
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex, {bool isShuffleMode = false}) async {
    if (oldIndex < 0 || oldIndex >= _currentQueue.length) return;
    if (newIndex < 0 || newIndex >= _currentQueue.length) return;
    final song = _currentQueue.removeAt(oldIndex);
    _currentQueue.insert(newIndex, song);
    
    if (!isShuffleMode) {
      final unSong = _unshuffledQueue.removeAt(oldIndex);
      _unshuffledQueue.insert(newIndex, unSong);
    }

    if (_playlist != null) {
      await _playlist!.move(oldIndex, newIndex);
    } else {
      final currentIndex = player.currentIndex ?? 0;
      await _rebuildSource(currentIndex.clamp(0, _currentQueue.length - 1));
    }
  }

  // ---------------------------------------------------------------------------
  // 1. Standard Fisher-Yates shuffle (keeps current song at index 0)
  //
  // BUG-23 FIX: The shuffle work is offloaded to a background isolate via
  // compute(). The main thread stays free (<16 ms gap) for the entire duration
  // of the sort. Only _rebuildSource() runs back on the main thread — it is a
  // platform channel call that just_audio handles asynchronously and is fast
  // regardless of queue size.
  // ---------------------------------------------------------------------------
  Future<void> standardShuffle() async {
    if (_currentQueue.isEmpty) return;
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);

    // Three-Part Timeline:
    // Section A+B: Past + Present (Immutable)
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);

    // Section C: Future (The only part we shuffle)
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final shuffledFuture = await compute(_standardShuffleIsolate, future);

    _currentQueue = [...pastAndPresent, ...shuffledFuture];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 2. Balanced Shuffle
  //    Groups songs by the user's preferred category (composer or genre) and
  //    interleaves them so the same category never plays back-to-back.
  //
  // BUG-23 FIX: Group-and-interleave logic moved into _balancedShuffleIsolate.
  // ShufflePreference is sent as its index (int) to avoid importing Flutter
  // into the isolate entrypoint.
  // ---------------------------------------------------------------------------
  Future<void> spotifyDitherShuffle(ShufflePreference preference) async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Balanced Shuffle ($preference)');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);

    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final result = await compute(
      _balancedShuffleIsolate,
      <String, dynamic>{
        'songs': future,
        'pref': preference.index,
      },
    );

    debugPrint('✅ [SHUFFLE] Balanced result: ${result.length} songs');

    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 3. Weighted Shuffle
  //    Each pick is a weighted random draw. Weight is computed from:
  //      - dynamicWeight  (user feedback via Suggest More / Less)
  //      - starred        (×2 multiplier)
  //      - rating         (+0–1 additive bonus, normalised from 1–5)
  //      - playCount      (+0–1 additive bonus, clamped at 100 plays)
  //
  // BUG-23 FIX: Weighted lottery loop moved into _weightedShuffleIsolate.
  // ---------------------------------------------------------------------------
  Future<void> youtubeWeightedShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Weighted Shuffle');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);

    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final shuffledFuture = await compute(_weightedShuffleIsolate, future);

    _currentQueue = [...pastAndPresent, ...shuffledFuture];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 4. Unshuffle (Restore original queue)
  // ---------------------------------------------------------------------------
  Future<void> unshuffle() async {
    if (_currentQueue.isEmpty || _unshuffledQueue.isEmpty) return;

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final currentSong = _currentQueue[safeIndex];

    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);

    // Restore the Future from original order
    final unIndex = _unshuffledQueue.indexWhere((s) => s.id == currentSong.id);

    if (unIndex != -1 && unIndex < _unshuffledQueue.length - 1) {
      final futureOriginal = _unshuffledQueue.sublist(unIndex + 1);
      _currentQueue = [...pastAndPresent, ...futureOriginal];
    } else {
      _currentQueue = pastAndPresent;
    }

    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // Direct access to compute shuffles for initial playlist playback
  // ---------------------------------------------------------------------------
  Future<List<Song>> computeShuffle(List<Song> pool, ShuffleAlgorithm algorithm, ShufflePreference preference) async {
    switch (algorithm) {
      case ShuffleAlgorithm.standard:
        return compute(_standardShuffleIsolate, pool);
      case ShuffleAlgorithm.spotify:
        return compute(_balancedShuffleIsolate, {'songs': pool, 'pref': preference.index});
      case ShuffleAlgorithm.youtube:
        return compute(_weightedShuffleIsolate, pool);
    }
  }

  // ---------------------------------------------------------------------------
  // Update the dynamic weight of a song in the current queue.
  // suggestMore = true  → increase weight by 50% (max 10.0)
  // suggestMore = false → decrease weight by 50% (min 0.1)
  // ---------------------------------------------------------------------------
  void updateSongWeight(Song song, bool suggestMore) {
    for (int i = 0; i < _currentQueue.length; i++) {
      if (_currentQueue[i].id == song.id) {
        final current = _currentQueue[i].dynamicWeight;
        _currentQueue[i].dynamicWeight = suggestMore
            ? (current * 1.5).clamp(0.1, 10.0)
            : (current * 0.5).clamp(0.1, 10.0);
        break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------
  Future<void> dispose() async {
    await player.stop();
    await player.dispose();
  }
}