import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'subsonic_service.dart';
import 'replay_gain_service.dart';
import '../providers/settings_provider.dart';
import '../offline_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// ISOLATE RULES (apply to every top-level worker below)
//
// compute() spawns a true OS-level isolate with no shared memory:
//   1. Function MUST be top-level or static — no closures, no instance methods.
//   2. Arguments and return values are deep-copied via the message port.
//      Song contains only plain value types → isolate-safe.
//   3. ShufflePreference is passed as its raw index (int) because the enum
//      lives in a file that imports Flutter. Reconstruct with
//      ShufflePreference.values[index] inside the worker.
//   4. dart:math (Random, exp, log) is available in bare isolates — no Flutter
//      engine required.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// SHARED WEIGHT HELPER
//
// Cannot be a closure — defined at top-level so all isolate workers can call
// it without capturing anything from the enclosing scope.
// ---------------------------------------------------------------------------

/// Computes the shuffle weight for [song].
///
/// Formula:
///   w = dynamicWeight.clamp(0.1, 10.0)
///   × 2.0   if starred
///   + (rating − 1) / 4.0   if rated  (0–1 additive bonus)
///   + (playCount / 100).clamp(0, 1)   (0–1 additive bonus)
double _songWeight(Song song) {
  double w = song.dynamicWeight.clamp(0.1, 10.0);
  if (song.starred) w *= 2.0;
  if (song.rating > 0) w += (song.rating - 1) / 4.0;
  w += (song.playCount / 100.0).clamp(0.0, 1.0);
  return w;
}

// ---------------------------------------------------------------------------
// ALGORITHM 1 — Standard Fisher-Yates
// Kept as-is: pure random, O(n), useful when the user explicitly wants it.
// ---------------------------------------------------------------------------

/// Shuffles [rest] using a standard Fisher-Yates pass.
List<Song> _standardShuffleIsolate(List<Song> rest) {
  rest.shuffle();
  return rest;
}

// ---------------------------------------------------------------------------
// ALGORITHM 2 — Dithered Position Shuffle  (replaces old round-robin)
//
// WHY IT'S BETTER THAN THE OLD BALANCED SHUFFLE:
//   The old round-robin interleave collapsed into back-to-back same-category
//   runs once smaller buckets emptied. Position-score + sort enforces the
//   spread *globally* — no bucket can "run out" and cause a leak.
//
// HOW IT WORKS:
//   For each category group:
//     spacing = totalSongs / groupSize          ← ideal gap between songs
//     offset  = Random(0, spacing)              ← per-group random start
//     position[i] = offset + i×spacing + dither ← small ±5% random nudge
//   Sort all songs by their position score.
//
// RESULT: Same-category songs are mathematically guaranteed to be maximally
// spread. The offset + dither makes it feel organic, not mechanical.
// ---------------------------------------------------------------------------

/// Worker for dithered position shuffle.
/// Args map keys:
///   'songs' → List<Song>
///   'pref'  → int  (ShufflePreference.index)
List<Song> _ditheredPositionShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final prefIndex = args['pref'] as int;
  final preference = ShufflePreference.values[prefIndex];
  final random = Random();
  final int total = songs.length;

  // Group songs by key (genre or composer).
  final Map<String, List<Song>> groups = {};
  for (final song in songs) {
    final key = preference == ShufflePreference.composer
        ? song.composer
        : song.genre;
    groups.putIfAbsent(key.isNotEmpty ? key : 'Unknown', () => []).add(song);
  }

  // Shuffle within each group so internal order is also random.
  for (final list in groups.values) {
    list.shuffle(random);
  }

  // Assign a floating-point position score to every song.
  final List<MapEntry<Song, double>> scored = [];

  for (final bucket in groups.values) {
    final double spacing = total / bucket.length.toDouble();
    // Each group gets an independent random starting offset so all groups
    // don't converge at position 0.
    final double offset = random.nextDouble() * spacing;

    for (int i = 0; i < bucket.length; i++) {
      // Small ±5% dither keeps the spread feeling human rather than robotic.
      final double dither = (random.nextDouble() - 0.5) * spacing * 0.1;
      final double position = offset + (i * spacing) + dither;
      scored.add(MapEntry(bucket[i], position));
    }
  }

  // Single sort pass enforces the spread across ALL groups simultaneously.
  scored.sort((a, b) => a.value.compareTo(b.value));
  return scored.map((e) => e.key).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 3 — Merge-Shuffle  (Ruud van Asseldonk, 2023)
//
// WHY IT'S BETTER THAN DITHERED POSITION FOR BACK-TO-BACK AVOIDANCE:
//   Dithered position gives perceptual spread — it feels good but doesn't
//   offer a hard mathematical guarantee. Merge-Shuffle *proves* optimality:
//   same-category songs are never consecutive if it was possible to avoid it.
//
// HOW IT WORKS:
//   1. Group songs by category, shuffle each bucket internally.
//   2. Sort groups by size ascending (fewest songs first).
//   3. Incrementally fold: start with the smallest group, then interleave
//      each next group into the running result using the interleave() helper.
//   interleave(larger, smaller):
//     Split larger into (smaller.length + 1) equal parts.
//     Insert one element of smaller between each part.
//
// TRADE-OFF vs DITHERED:
//   Merge-Shuffle guarantees no back-to-back; Dithered feels more organic.
//   Expose both — let the user choose.
// ---------------------------------------------------------------------------

/// Interleaves [smaller] into [larger] at evenly distributed positions.
/// This is the core primitive of merge-shuffle.
List<Song> _interleave(List<Song> larger, List<Song> smaller, Random random) {
  if (larger.length < smaller.length) {
    return _interleave(smaller, larger, random);
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

  // Append any remaining songs from the larger list.
  if (largerIndex < n) {
    result.addAll(larger.sublist(largerIndex));
  }

  return result;
}

/// Worker for merge-shuffle.
/// Args map keys:
///   'songs' → List<Song>
///   'pref'  → int  (ShufflePreference.index)
List<Song> _mergeShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final prefIndex = args['pref'] as int;
  final preference = ShufflePreference.values[prefIndex];
  final random = Random();

  // Group and shuffle internally.
  final Map<String, List<Song>> groups = {};
  for (final song in songs) {
    final key = preference == ShufflePreference.composer
        ? song.composer
        : song.genre;
    groups.putIfAbsent(key.isNotEmpty ? key : 'Unknown', () => []).add(song);
  }
  for (final list in groups.values) {
    list.shuffle(random);
  }

  // Sort groups ascending by size — merge smallest first (key to optimality).
  final buckets = groups.values.toList()
    ..sort((a, b) => a.length.compareTo(b.length));

  if (buckets.isEmpty) return songs;

  // Incrementally interleave: fold all buckets into one result.
  List<Song> result = List<Song>.from(buckets[0]);
  for (int i = 1; i < buckets.length; i++) {
    result = _interleave(result, List<Song>.from(buckets[i]), random);
  }

  return result;
}

// ---------------------------------------------------------------------------
// ALGORITHM 4 — Weighted Shuffle  (O(n log n) — Efraimidis-Spirakis)
//
// BUG FIX from original: The old implementation used removeAt() inside a
// loop — O(n) per removal → O(n²) total. For 1000+ songs this was slow even
// in an isolate.
//
// NEW APPROACH — Efraimidis-Spirakis weighted reservoir key trick:
//   key = r ^ (1/w)  =  exp(ln(r) / w)   where r = Random(0,1), w = weight
//   Sort songs descending by key.
//
// This is mathematically equivalent to weighted draws without replacement,
// but requires only a single O(n log n) sort — no inner loop, no mutation.
// ---------------------------------------------------------------------------

/// Worker for weighted shuffle — O(n log n).
/// Receives [pool] (all songs except current) and returns them in weighted
/// random order using the Efraimidis-Spirakis key trick.
List<Song> _weightedShuffleIsolate(List<Song> pool) {
  final random = Random();

  final keyed = pool.map((song) {
    final w = _songWeight(song);
    // Clamp away from 0 to avoid log(0) = -Infinity.
    final r = random.nextDouble().clamp(1e-10, 1.0);
    final key = exp(log(r) / w);
    return MapEntry(song, key);
  }).toList();

  // Descending sort: higher key → earlier position.
  keyed.sort((a, b) => b.value.compareTo(a.value));
  return keyed.map((e) => e.key).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 5 — Album-Aware Shuffle
//
// WHY IT'S UNIQUE:
//   No mainstream Subsonic client offers this cleanly. Albums are treated as
//   atomic units: the album sequence is randomised, but each album's internal
//   track order is preserved (or optionally shuffled within the album).
//   Perfect for listeners who want artist variety but respect album flow.
//
// USES EXISTING DATA: song.album and song.track — zero extra API calls.
// ---------------------------------------------------------------------------

/// Worker for album-aware shuffle.
/// Args map keys:
///   'songs'         → List<Song>
///   'shuffleTracks' → bool  (shuffle tracks within each album if true)
List<Song> _albumAwareShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final shuffleTracks = args['shuffleTracks'] as bool? ?? false;
  final random = Random();

  // Group by album name.
  final Map<String, List<Song>> albums = {};
  for (final song in songs) {
    final key = song.album.isNotEmpty ? song.album : 'Unknown';
    albums.putIfAbsent(key, () => []).add(song);
  }

  // Sort each album by track number ascending (preserves intended order),
  // or shuffle within album if the user opted in.
  for (final list in albums.values) {
    if (shuffleTracks) {
      list.shuffle(random);
    } else {
      list.sort((a, b) => a.track.compareTo(b.track));
    }
  }

  // Shuffle the album sequence.
  final albumKeys = albums.keys.toList()..shuffle(random);

  // Flatten albums into a single ordered list.
  return albumKeys.expand((key) => albums[key]!).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 6 — Recency-Dampened Weighted Shuffle
//
// WHY IT'S USEFUL:
//   During long sessions the weighted shuffle can still surface recently
//   played songs because weights don't decay within a session. This variant
//   applies a 10× penalty to songs in the recency window, making them
//   statistically unlikely to appear again for ~[window] songs.
//
// NO ML REQUIRED: The recency window is a plain Set<String> of song IDs
// maintained in AudioHandler and passed to the isolate as a List<String>.
// ---------------------------------------------------------------------------

/// Worker for recency-dampened weighted shuffle.
/// Args map keys:
///   'songs'     → List<Song>
///   'recentIds' → List<String>  (song IDs played recently in this session)
List<Song> _recencyDampenedShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final recentIds = Set<String>.from(args['recentIds'] as List);
  final random = Random();

  final keyed = songs.map((song) {
    double w = _songWeight(song);
    // Recently played songs are 10× less likely to appear soon.
    if (recentIds.contains(song.id)) w *= 0.1;
    // Clamp after penalty so weight never drops to 0.
    w = w.clamp(0.01, 100.0);
    final r = random.nextDouble().clamp(1e-10, 1.0);
    final key = exp(log(r) / w);
    return MapEntry(song, key);
  }).toList();

  keyed.sort((a, b) => b.value.compareTo(a.value));
  return keyed.map((e) => e.key).toList();
}

// ---------------------------------------------------------------------------
// AudioHandler
// ---------------------------------------------------------------------------

class AudioHandler {
  final AudioPlayer player;
  final SubsonicService subsonicService;
  final ReplayGainService _replayGainService;
  List<Song> _currentQueue = [];
  List<Song> _unshuffledQueue = [];

  // Kept alive between queue mutations so we can use incremental APIs
  // (add / removeAt / move) instead of rebuilding the entire source.
  ConcatenatingAudioSource? _playlist;

  // ---------------------------------------------------------------------------
  // Recency tracking — used by recencyDampenedWeightedShuffle.
  // Stores the IDs of the last [_recencyWindow] songs played this session.
  // Maintained on the main thread; serialised to List<String> before
  // passing to the isolate (plain type — isolate-safe).
  // ---------------------------------------------------------------------------
  static const int _recencyWindow = 20;

  /// Insertion-ordered set so we can efficiently remove the oldest entry
  /// when the window fills. LinkedHashSet preserves insertion order.
  final Set<String> _recentlyPlayedIds = {};

  AudioHandler(this.subsonicService,
      {AudioPlayer? player, ReplayGainService? replayGainService})
      : player = player ?? AudioPlayer(),
        _replayGainService = replayGainService ?? ReplayGainService() {
    // Hook into track changes so _recentlyPlayedIds stays current
    // without requiring callers to remember to call _trackRecentlyPlayed.
    this.player.currentIndexStream.listen((index) {
      if (index != null && index < _currentQueue.length) {
        _trackRecentlyPlayed(_currentQueue[index].id);
      }
    });

    // Add detailed error logging to catch streaming failures
    // (especially GStreamer plugin/HTTP errors on Linux)
    this.player.playbackEventStream.listen((event) {}, onError: (Object e, StackTrace stackTrace) {
      debugPrint('❌ [AudioHandler] A stream error occurred: $e');
      if (e is PlayerException) {
        debugPrint('   Error code: ${e.code}');
        debugPrint('   Error message: ${e.message}');
      }
    });

    this.player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        debugPrint('ℹ️ [AudioHandler] Processing state: completed');
      }
    }, onError: (Object e, StackTrace stackTrace) {
      debugPrint('❌ [AudioHandler] Player state error: $e');
    });
  }

  @visibleForTesting
  set currentQueue(List<Song> songs) => _currentQueue = songs;

  List<Song> get currentQueue => _currentQueue;

  // ---------------------------------------------------------------------------
  // Recency helper
  // ---------------------------------------------------------------------------

  /// Records [songId] as recently played. Evicts the oldest entry once
  /// the window exceeds [_recencyWindow] to bound memory use.
  void _trackRecentlyPlayed(String songId) {
    _recentlyPlayedIds.add(songId);
    if (_recentlyPlayedIds.length > _recencyWindow) {
      _recentlyPlayedIds.remove(_recentlyPlayedIds.first);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  AudioSource _toSource(Song song) {
    // FIX (Offline-1): Prioritise local file when song has been downloaded.
    // OfflineService.getLocalPath() returns the on-disk path synchronously
    // (it just calls File.existsSync), so this is safe on the UI thread.
    final localPath = OfflineService().getLocalPath(song.id);
    final streamUri = localPath != null
        ? Uri.parse('file://$localPath')
        : Uri.parse(subsonicService.getStreamUrl(song.id));

    return AudioSource.uri(
      streamUri,
      tag: MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        artUri: Uri.parse(subsonicService.getCoverArtUrl(song.coverArt)),
        duration: Duration(seconds: song.duration),
        extras: {'composer': song.composer, 'isLocal': localPath != null},
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Full rebuild — only called when the entire queue is replaced (setQueue /
  // shuffle). For incremental changes use addToQueue / removeFromQueue /
  // reorderQueue below.
  // ---------------------------------------------------------------------------
  Future<void> setQueue(List<Song> songs, int startIndex,
      {List<Song>? unshuffledSongs}) async {
    _currentQueue = List.from(songs);
    _unshuffledQueue = List.from(unshuffledSongs ?? songs);
    await _rebuildSource(startIndex);
    _applyReplayGain();
  }

  // ---------------------------------------------------------------------------
  // Replay Gain
  // ---------------------------------------------------------------------------
  void _applyReplayGain() {
    final multiplier = _replayGainService.calculateVolumeMultiplier();
    player.setVolume(multiplier);
  }

  /// Recalculate and apply replay gain volume — call when track changes
  /// or when the user changes replay gain settings.
  void refreshReplayGain() => _applyReplayGain();

  Future<void> _rebuildSource(int startIndex,
      {Duration? initialPosition}) async {
    if (_currentQueue.isEmpty) return;
    final savedLoopMode = player.loopMode;
    final sources = _currentQueue.map(_toSource).toList();
    _playlist = ConcatenatingAudioSource(children: sources);
    await player.setAudioSource(
      _playlist!,
      initialIndex: startIndex,
      initialPosition: initialPosition,
    );
    if (savedLoopMode != LoopMode.off) {
      await player.setLoopMode(savedLoopMode);
    }
  }

  /// Reorders the ConcatenatingAudioSource in-place after a shuffle so that
  /// audio continues without a gap.
  ///
  /// v2 FIX (Shuffle-Gap): The old approach called setAudioSource() which
  /// tears down and rebuilds the entire decoding pipeline, causing a ~1 second
  /// silence. The new approach uses ConcatenatingAudioSource.move() to reorder
  /// existing AudioSource children — the decoder keeps running and the
  /// currently-playing track is never interrupted.
  ///
  /// Uses a selection-sort pass over the live playlist, moving one source per
  /// iteration until it matches _currentQueue. Only seeks if the anchor index
  /// changed (avoids an unnecessary mute).
  ///
  /// Falls back to a full rebuild only on cold start (when _playlist is null).
  Future<void> _updateQueueAfterAnchor(int anchorIndex) async {
    if (_playlist == null) {
      // Cold-start fallback: no existing source to reuse.
      final savedPosition = player.position;
      await _rebuildSource(anchorIndex, initialPosition: savedPosition);
      if (player.playing) player.play();
      return;
    }

    // The _currentQueue already holds the desired final order (set by the
    // caller before invoking this method). We need to reorder _playlist's
    // children to match _currentQueue using incremental moves.
    //
    // We track the "live" positions of each source via a mutable index list
    // that gets updated after every move.
    final int n = _currentQueue.length;


    // ── O(n²) selection-sort on the live playlist ────────────────────────
    final List<String> liveIds = List.generate(
      n,
      (i) => (_playlist!.children[i] as UriAudioSource)
          .tag is MediaItem
          ? ((_playlist!.children[i] as UriAudioSource).tag as MediaItem).id
          : '',
    );

    for (int targetIdx = 0; targetIdx < n; targetIdx++) {
      final wantedId = _currentQueue[targetIdx].id;
      if (liveIds[targetIdx] == wantedId) continue; // already in place

      // Find the live position of the song we want.
      final fromIdx = liveIds.indexOf(wantedId, targetIdx + 1);
      if (fromIdx == -1) continue; // safety: not found

      // Move in the real ConcatenatingAudioSource.
      await _playlist!.move(fromIdx, targetIdx);

      // Update our tracking list to reflect the move.
      final moved = liveIds.removeAt(fromIdx);
      liveIds.insert(targetIdx, moved);
    }

    // Seek to ensure the anchor song is current (it should already be).
    // Only seek if the player is not already at the anchor — avoids
    // an unnecessary seek that would briefly mute the audio.
    final currentLiveIndex = player.currentIndex ?? 0;
    if (currentLiveIndex != anchorIndex) {
      await player.seek(player.position, index: anchorIndex);
    }

    if (player.playing) player.play();
  }

  // ---------------------------------------------------------------------------
  // Incremental queue mutations
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

  /// Batch-adds all [songs] to the end of the queue in a single
  /// ConcatenatingAudioSource.addAll() call. Critical for autoplay.
  Future<void> addAllToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;
    _currentQueue.addAll(songs);
    _unshuffledQueue.addAll(songs);
    if (_playlist != null) {
      await _playlist!.addAll(songs.map(_toSource).toList());
    } else {
      await _rebuildSource(_currentQueue.length - songs.length);
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

  Future<void> reorderQueue(int oldIndex, int newIndex,
      {bool isShuffleMode = false}) async {
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
  // SHARED ANCHOR LOGIC
  //
  // All shuffle methods share identical boilerplate:
  //   1. Guard empty queue.
  //   2. Split into pastAndPresent / future at the current index.
  //   3. Offload future to isolate.
  //   4. Reassemble and rebuild source.
  //
  // _shuffleFuture() centralises steps 2–4 so each public method is a
  // one-liner that just supplies the isolate worker and its arguments.
  // ---------------------------------------------------------------------------

  /// Splits the queue at [currentIndex], runs [worker] on the future slice
  /// via compute(), reassembles, and rebuilds the audio source.
  Future<void> _shuffleFuture<T>(
    int currentIndex,
    ComputeCallback<T, List<Song>> worker,
    T args,
  ) async {
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final shuffled = await compute(worker, args);
    _currentQueue = [...pastAndPresent, ...shuffled];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 1. Standard Fisher-Yates
  // ---------------------------------------------------------------------------
  Future<void> standardShuffle() async {
    if (_currentQueue.isEmpty) return;
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final shuffled = await compute(_standardShuffleIsolate, future);
    _currentQueue = [...pastAndPresent, ...shuffled];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 2. Dithered Position Shuffle  (replaces spotifyDitherShuffle)
  // ---------------------------------------------------------------------------
  Future<void> ditheredPositionShuffle(ShufflePreference preference) async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Dithered Position ($preference)');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final result = await compute(
      _ditheredPositionShuffleIsolate,
      <String, dynamic>{'songs': future, 'pref': preference.index},
    );

    debugPrint('✅ [SHUFFLE] Dithered result: ${result.length} songs');
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  /// Kept for backwards compatibility — delegates to ditheredPositionShuffle.
  /// Callers that used spotifyDitherShuffle will continue to work unchanged.
  Future<void> spotifyDitherShuffle(ShufflePreference preference) =>
      ditheredPositionShuffle(preference);

  // ---------------------------------------------------------------------------
  // 3. Merge-Shuffle
  // ---------------------------------------------------------------------------
  Future<void> mergeShuffle(ShufflePreference preference) async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Merge-Shuffle ($preference)');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final result = await compute(
      _mergeShuffleIsolate,
      <String, dynamic>{'songs': future, 'pref': preference.index},
    );

    debugPrint('✅ [SHUFFLE] Merge result: ${result.length} songs');
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 4. Weighted Shuffle  (O(n log n) fix)
  // ---------------------------------------------------------------------------
  Future<void> youtubeWeightedShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Weighted Shuffle (O(n log n))');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final shuffled = await compute(_weightedShuffleIsolate, future);
    _currentQueue = [...pastAndPresent, ...shuffled];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 5. Album-Aware Shuffle
  // ---------------------------------------------------------------------------
  Future<void> albumAwareShuffle({bool shuffleTracksWithinAlbum = false}) async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Album-Aware (shuffleTracks=$shuffleTracksWithinAlbum)');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final result = await compute(
      _albumAwareShuffleIsolate,
      <String, dynamic>{
        'songs': future,
        'shuffleTracks': shuffleTracksWithinAlbum,
      },
    );

    debugPrint('✅ [SHUFFLE] Album-Aware result: ${result.length} songs');
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 6. Recency-Dampened Weighted Shuffle
  // ---------------------------------------------------------------------------
  Future<void> recencyDampenedWeightedShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Recency-Dampened Weighted Shuffle '
        '(window=$_recencyWindow, recent=${_recentlyPlayedIds.length})');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final result = await compute(
      _recencyDampenedShuffleIsolate,
      <String, dynamic>{
        'songs': future,
        // Snapshot the set as a plain List<String> — isolate-safe.
        'recentIds': _recentlyPlayedIds.toList(),
      },
    );

    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 7. Smart Local Model Shuffle
  // ---------------------------------------------------------------------------
  Future<void> smartLocalShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Smart Local Model Shuffle');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final currentSong = _currentQueue[safeIndex];

    try {
      final count = future.length;
      final uri = Uri.parse('http://100.99.105.51:5000/next').replace(queryParameters: {
        'current': currentSong.title,
        'artist': currentSong.artist,
        'count': count.toString(),
      });
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<String> serverSongKeys = data.map((e) => e['song_key'].toString()).toList();
        
        final futureMap = {for (var song in future) song.title.toLowerCase().trim(): song};
        List<Song> shuffled = [];
        
        for (var key in serverSongKeys) {
          if (futureMap.containsKey(key)) {
            shuffled.add(futureMap[key]!);
            futureMap.remove(key);
          }
        }
        
        // Add remaining songs from the pool that the server didn't return
        final remaining = futureMap.values.toList()..shuffle();
        shuffled.addAll(remaining);
        
        _currentQueue = [...pastAndPresent, ...shuffled];
        await _updateQueueAfterAnchor(safeIndex);
        debugPrint('✅ [SHUFFLE] Smart Local Model result: ${shuffled.length} songs');
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [SHUFFLE] Smart Local Model Shuffle failed: $e, falling back to standard');
      await standardShuffle();
    }
  }

  // ---------------------------------------------------------------------------
  // 8. Unshuffle (restore original queue)
  // ---------------------------------------------------------------------------
  Future<void> unshuffle() async {
    if (_currentQueue.isEmpty || _unshuffledQueue.isEmpty) return;

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final currentSong = _currentQueue[safeIndex];

    // Restore the ENTIRE original order, then seek to the current song's
    // position within it so playback continues from the right track.
    _currentQueue = List.from(_unshuffledQueue);
    final newIndex =
        _unshuffledQueue.indexWhere((s) => s.id == currentSong.id);
    await _updateQueueAfterAnchor(newIndex != -1 ? newIndex : safeIndex);
  }

  // ---------------------------------------------------------------------------
  // computeShuffle — direct access for initial playlist playback
  // ---------------------------------------------------------------------------

  /// Applies [algorithm] to [pool] and returns the reordered list.
  /// Called before [setQueue] when the user hits "Shuffle Play" on a
  /// playlist/album screen — the queue hasn't been loaded yet.
  Future<List<Song>> computeShuffle(
    List<Song> pool,
    ShuffleAlgorithm algorithm,
    ShufflePreference preference, {
    bool albumShuffleTracks = false,
    Song? currentSong,
    String? contextName,
  }) async {
    switch (algorithm) {
      case ShuffleAlgorithm.standard:
        return compute(_standardShuffleIsolate, pool);

      case ShuffleAlgorithm.spotify:
        // Now uses dithered position — replaced old round-robin.
        return compute(_ditheredPositionShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'pref': preference.index,
        });

      case ShuffleAlgorithm.youtube:
        // O(n log n) — was O(n²).
        return compute(_weightedShuffleIsolate, pool);

      case ShuffleAlgorithm.albumAware:
        return compute(_albumAwareShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'shuffleTracks': albumShuffleTracks,
        });

      case ShuffleAlgorithm.mergeShuffle:
        return compute(_mergeShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'pref': preference.index,
        });

      case ShuffleAlgorithm.recencyDampened:
        return compute(_recencyDampenedShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'recentIds': _recentlyPlayedIds.toList(),
        });

      case ShuffleAlgorithm.smartLocal:
        try {
          final queryParams = <String, String>{
            'count': pool.length.toString(),
          };
          if (currentSong != null) {
            queryParams['current'] = currentSong.title;
            queryParams['artist'] = currentSong.artist;
          }
          if (contextName != null) {
            queryParams['playlist'] = contextName;
          }
          final uri = Uri.parse('http://100.99.105.51:5000/next').replace(queryParameters: queryParams);
          final response = await http.get(uri);
          
          if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            final List<String> serverSongKeys = data.map((e) => e['song_key'].toString()).toList();
            
            final poolMap = {for (var song in pool) song.title.toLowerCase().trim(): song};
            List<Song> shuffled = [];
            
            for (var key in serverSongKeys) {
              if (poolMap.containsKey(key)) {
                shuffled.add(poolMap[key]!);
                poolMap.remove(key);
              }
            }
            
            final remaining = poolMap.values.toList()..shuffle();
            shuffled.addAll(remaining);
            return shuffled;
          } else {
            return compute(_standardShuffleIsolate, pool);
          }
        } catch (e) {
          return compute(_standardShuffleIsolate, pool);
        }
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
        final newWeight = suggestMore
            ? (current * 1.5).clamp(0.1, 10.0)
            : (current * 0.5).clamp(0.1, 10.0);
        _currentQueue[i] = _currentQueue[i].copyWith(dynamicWeight: newWeight);
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