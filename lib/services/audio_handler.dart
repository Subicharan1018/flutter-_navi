import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'subsonic_service.dart';
import 'replay_gain_service.dart';
import '../providers/settings_provider.dart';
import '../offline_service.dart';
import 'shuffle_algorithms.dart';

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

// Shuffle algorithm isolate workers are defined in shuffle_algorithms.dart.
// They are imported above and referenced directly by name (public functions).

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

  AudioHandler(
    this.subsonicService, {
    AudioPlayer? player,
    ReplayGainService? replayGainService,
  }) : player = player ?? AudioPlayer(),
       _replayGainService = replayGainService ?? ReplayGainService() {
    // Hook into track changes so _recentlyPlayedIds stays current
    // without requiring callers to remember to call _trackRecentlyPlayed.
    player?.currentIndexStream.listen((index) {
      if (index != null && index < _currentQueue.length) {
        _trackRecentlyPlayed(_currentQueue[index].id);
      }
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
  Future<void> setQueue(
    List<Song> songs,
    int startIndex, {
    List<Song>? unshuffledSongs,
  }) async {
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

  Future<void> _rebuildSource(
    int startIndex, {
    Duration? initialPosition,
  }) async {
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
      (i) => (_playlist!.children[i] as UriAudioSource).tag is MediaItem
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

  Future<void> reorderQueue(
    int oldIndex,
    int newIndex, {
    bool isShuffleMode = false,
  }) async {
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

    final shuffled = await compute(standardShuffleIsolate, future);
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
      ditheredPositionShuffleIsolate,
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

    final result = await compute(mergeShuffleIsolate, <String, dynamic>{
      'songs': future,
      'pref': preference.index,
    });

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

    final shuffled = await compute(weightedShuffleIsolate, future);
    _currentQueue = [...pastAndPresent, ...shuffled];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 5. Album-Aware Shuffle
  // ---------------------------------------------------------------------------
  Future<void> albumAwareShuffle({
    bool shuffleTracksWithinAlbum = false,
  }) async {
    if (_currentQueue.isEmpty) return;
    debugPrint(
      '🚀 [SHUFFLE] Album-Aware (shuffleTracks=$shuffleTracksWithinAlbum)',
    );

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final result = await compute(albumAwareShuffleIsolate, <String, dynamic>{
      'songs': future,
      'shuffleTracks': shuffleTracksWithinAlbum,
    });

    debugPrint('✅ [SHUFFLE] Album-Aware result: ${result.length} songs');
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 6. Recency-Dampened Weighted Shuffle
  // ---------------------------------------------------------------------------
  Future<void> recencyDampenedWeightedShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint(
      '🚀 [SHUFFLE] Recency-Dampened Weighted Shuffle '
      '(window=$_recencyWindow, recent=${_recentlyPlayedIds.length})',
    );

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final result = await compute(
      recencyDampenedShuffleIsolate,
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
  // 7. Unshuffle (restore original queue)
  // ---------------------------------------------------------------------------
  Future<void> unshuffle() async {
    if (_currentQueue.isEmpty || _unshuffledQueue.isEmpty) return;

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final currentSong = _currentQueue[safeIndex];

    // Restore the ENTIRE original order, then seek to the current song's
    // position within it so playback continues from the right track.
    _currentQueue = List.from(_unshuffledQueue);
    final newIndex = _unshuffledQueue.indexWhere((s) => s.id == currentSong.id);
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
  }) async {
    switch (algorithm) {
      case ShuffleAlgorithm.standard:
        return compute(standardShuffleIsolate, pool);

      case ShuffleAlgorithm.spotify:
        // Now uses dithered position — replaced old round-robin.
        return compute(ditheredPositionShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'pref': preference.index,
        });

      case ShuffleAlgorithm.youtube:
        // O(n log n) — was O(n²).
        return compute(weightedShuffleIsolate, pool);

      case ShuffleAlgorithm.albumAware:
        return compute(albumAwareShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'shuffleTracks': albumShuffleTracks,
        });

      case ShuffleAlgorithm.mergeShuffle:
        return compute(mergeShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'pref': preference.index,
        });

      case ShuffleAlgorithm.recencyDampened:
        return compute(recencyDampenedShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'recentIds': _recentlyPlayedIds.toList(),
        });
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
