import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import 'subsonic_service.dart';
import 'replay_gain_service.dart';
import '../providers/settings_provider.dart';
import '../offline_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// ISOLATE HELPERS — pure functions, no platform-channel contact
// ---------------------------------------------------------------------------

double _songWeight(Song song) {
  double w = song.dynamicWeight.clamp(0.1, 10.0);
  if (song.starred) w *= 2.0;
  if (song.rating > 0) w += (song.rating - 1) / 4.0;
  w += (song.playCount / 100.0).clamp(0.0, 1.0);
  return w;
}

// ---------------------------------------------------------------------------
// ALGORITHM 1 — Standard Fisher-Yates
// ---------------------------------------------------------------------------
List<Song> _standardShuffleIsolate(List<Song> rest) {
  rest.shuffle();
  return rest;
}

// ---------------------------------------------------------------------------
// ALGORITHM 2 — Dithered Position Shuffle
// ---------------------------------------------------------------------------
List<Song> _ditheredPositionShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final prefIndex = args['pref'] as int;
  final preference = ShufflePreference.values[prefIndex];
  final random = Random();
  final int total = songs.length;

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
// ALGORITHM 3 — Merge-Shuffle
// ---------------------------------------------------------------------------
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
  if (largerIndex < n) result.addAll(larger.sublist(largerIndex));
  return result;
}

List<Song> _mergeShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final prefIndex = args['pref'] as int;
  final preference = ShufflePreference.values[prefIndex];
  final random = Random();

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

  final buckets = groups.values.toList()
    ..sort((a, b) => a.length.compareTo(b.length));
  if (buckets.isEmpty) return songs;

  List<Song> result = List<Song>.from(buckets[0]);
  for (int i = 1; i < buckets.length; i++) {
    result = _interleave(result, List<Song>.from(buckets[i]), random);
  }
  return result;
}

// ---------------------------------------------------------------------------
// ALGORITHM 4 — Weighted Shuffle (Efraimidis-Spirakis)
// ---------------------------------------------------------------------------
List<Song> _weightedShuffleIsolate(List<Song> pool) {
  final random = Random();
  final keyed = pool.map((song) {
    final w = _songWeight(song);
    final r = random.nextDouble().clamp(1e-10, 1.0);
    final key = exp(log(r) / w);
    return MapEntry(song, key);
  }).toList();
  keyed.sort((a, b) => b.value.compareTo(a.value));
  return keyed.map((e) => e.key).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 5 — Album-Aware Shuffle
// ---------------------------------------------------------------------------
List<Song> _albumAwareShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final shuffleTracks = args['shuffleTracks'] as bool? ?? false;
  final random = Random();

  final Map<String, List<Song>> albums = {};
  for (final song in songs) {
    final key = song.album.isNotEmpty ? song.album : 'Unknown';
    albums.putIfAbsent(key, () => []).add(song);
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
List<Song> _recencyDampenedShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final recentIds = Set<String>.from(args['recentIds'] as List);
  final random = Random();

  final keyed = songs.map((song) {
    double w = _songWeight(song);
    if (recentIds.contains(song.id)) w *= 0.1;
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

class NaviAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player;
  final SubsonicService subsonicService;
  final ReplayGainService _replayGainService;
  List<Song> _currentQueue = [];
  List<Song> _unshuffledQueue = [];
  ConcatenatingAudioSource? _playlist;

  static const int _recencyWindow = 20;
  final Set<String> _recentlyPlayedIds = {};

  // The server enforces count=15 but we also cap it here so any caller
  // that passes a large future slice doesn't accidentally ask for 200 songs.
  static const int _maxServerRequestCount = 15;

  String _shuffleBaseUrl = '';

  NaviAudioHandler(
    this.subsonicService, {
    AudioPlayer? player,
    ReplayGainService? replayGainService,
  }) : player = player ?? AudioPlayer(),
       _replayGainService = replayGainService ?? ReplayGainService() {
    
    _listenToPlayerEvents();

    this.player.currentIndexStream.listen((index) {
      if (index != null && index < _currentQueue.length) {
        _trackRecentlyPlayed(_currentQueue[index].id);
      }
    });

    this.player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace stackTrace) {
        debugPrint('❌ [NaviAudioHandler] Stream error: $e');
        if (e is PlayerException) {
          debugPrint('   Code: ${e.code}  Message: ${e.message}');
        }
      },
    );

    this.player.playerStateStream.listen(
      (state) {
        if (state.processingState == ProcessingState.completed) {
          debugPrint('ℹ️ [NaviAudioHandler] Processing state: completed');
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('❌ [NaviAudioHandler] Player state error: $e');
      },
    );
  }

  void _listenToPlayerEvents() {
    player.playbackEventStream.listen((event) {
      _broadcastState();
    });
    
    // Sync current media item when sequence or index changes
    player.sequenceStateStream.listen((sequenceState) {
      if (sequenceState?.currentSource == null) return;
      final source = sequenceState!.currentSource!;
      if (source.tag is MediaItem) {
        mediaItem.add(source.tag as MediaItem);
      }
    });
  }

  void _broadcastState() {
    final playing = player.playing;
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[player.processingState]!;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        _shuffleAction,
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _repeatAction,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [1, 2, 3],
      processingState: processingState,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      repeatMode: const {
        LoopMode.off: AudioServiceRepeatMode.none,
        LoopMode.one: AudioServiceRepeatMode.one,
        LoopMode.all: AudioServiceRepeatMode.all,
      }[player.loopMode]!,
      shuffleMode: player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  static const _shuffleAction = MediaControl(
    androidIcon: 'drawable/ic_shuffle',
    label: 'Shuffle',
    action: MediaAction.setShuffleMode,
  );

  static const _repeatAction = MediaControl(
    androidIcon: 'drawable/ic_repeat',
    label: 'Repeat',
    action: MediaAction.setRepeatMode,
  );

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.seekToNext();

  @override
  Future<void> skipToPrevious() => player.seekToPrevious();

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    await player.setShuffleModeEnabled(enabled);
    _broadcastState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    // REPEAT-ONCE BUG FIX: Ensure AudioServiceRepeatMode.one explicitly maps
    // to LoopMode.one. The previously broken logic or mismatch caused infinite repeats.
    // AudioServiceRepeatMode.none => LoopMode.off
    // AudioServiceRepeatMode.one  => LoopMode.one
    // AudioServiceRepeatMode.all  => LoopMode.all
    final next = switch (player.loopMode) {
      LoopMode.off => LoopMode.one,
      LoopMode.one => LoopMode.all,
      LoopMode.all => LoopMode.off,
    };
    await player.setLoopMode(next);
    _broadcastState();
  }

  @visibleForTesting
  set currentQueue(List<Song> songs) => _currentQueue = songs;

  List<Song> get currentQueue => _currentQueue;
  List<Song> get unshuffledQueue => _unshuffledQueue;

  void _trackRecentlyPlayed(String songId) {
    _recentlyPlayedIds.add(songId);
    if (_recentlyPlayedIds.length > _recencyWindow) {
      _recentlyPlayedIds.remove(_recentlyPlayedIds.first);
    }
  }

  AudioSource _toSource(Song song) {
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

  AudioSource _toSourceWithPaths(Song song, Map<String, String?> offlinePaths) {
    final localPath = offlinePaths[song.id];
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

  Future<Map<String, String?>> _precomputeOfflinePaths(List<Song> songs) async {
    final offline = OfflineService();
    await offline.initialize(); // Ensure directory is resolved
    return {for (final song in songs) song.id: offline.getLocalPath(song.id)};
  }


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

  void _applyReplayGain() {
    final multiplier = _replayGainService.calculateVolumeMultiplier();
    player.setVolume(multiplier);
  }

  void refreshReplayGain() => _applyReplayGain();

  /// Clears the audio source and queue. Must be called AFTER player.stop().
  Future<void> clearQueue() async {
    _currentQueue.clear();
    _playlist = ConcatenatingAudioSource(children: []);
  }

  Future<void> _rebuildSource(
    int startIndex, {
    Duration? initialPosition,
  }) async {
    if (_currentQueue.isEmpty) return;
    final savedLoopMode = player.loopMode;
    final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
    final List<AudioSource> sources = _currentQueue
        .map((song) => _toSourceWithPaths(song, offlinePaths))
        .toList();
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

  Future<void> _updateQueueAfterAnchor(
    int anchorIndex, {
    bool preferMoveBasedReorder = false,
  }) async {
    if (_playlist == null) {
      final savedPosition = player.position;
      await _rebuildSource(anchorIndex, initialPosition: savedPosition);
      if (player.playing) player.play();
      return;
    }

    final int n = _currentQueue.length;

    // FIX-SHUFFLE-GAP: Always prefer move-based reorder when the playlist is
    // already loaded (i.e. _playlist != null).  The old threshold of 5 caused
    // setAudioSource() to be called for large queues, which interrupts the
    // current track and causes a 1-2 s silence.
    //
    // _moveBasedReorder uses ConcatenatingAudioSource.move() which is O(n)
    // but gapless — the current track keeps playing throughout.  Only fall
    // back to setAudioSource when the caller explicitly opts out AND the queue
    // is tiny (≤ 5 songs), because for tiny queues setAudioSource is faster.
    if (n <= 5 && !preferMoveBasedReorder) {
      // Tiny queue: full rebuild is cheaper than many move() calls and the
      // gap is imperceptible at these lengths.
      final savedPosition = player.position;
      final wasPlaying = player.playing;
      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      final List<AudioSource> sources = _currentQueue
          .map((song) => _toSourceWithPaths(song, offlinePaths))
          .toList();
      _playlist = ConcatenatingAudioSource(children: sources);
      await player.setAudioSource(
        _playlist!,
        initialIndex: anchorIndex,
        initialPosition: savedPosition,
      );

      if (wasPlaying) player.play();
      return;
    }

    await _moveBasedReorder(anchorIndex);
  }


  Future<void> _moveBasedReorder(int anchorIndex) async {
    final int n = _currentQueue.length;
    final List<String> liveIds = List.generate(n, (i) {
      final src = _playlist!.children[i];
      if (src is UriAudioSource && src.tag is MediaItem) {
        return (src.tag as MediaItem).id;
      }
      return '';
    });

    for (int targetIdx = 0; targetIdx < n; targetIdx++) {
      final wantedId = _currentQueue[targetIdx].id;
      if (liveIds[targetIdx] == wantedId) continue;
      final fromIdx = liveIds.indexOf(wantedId, targetIdx + 1);
      if (fromIdx == -1) continue;
      await _playlist!.move(fromIdx, targetIdx);
      final moved = liveIds.removeAt(fromIdx);
      liveIds.insert(targetIdx, moved);
    }

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
  // 2. Dithered Position Shuffle
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
    final result = await compute(_mergeShuffleIsolate, <String, dynamic>{
      'songs': future,
      'pref': preference.index,
    });
    debugPrint('✅ [SHUFFLE] Merge result: ${result.length} songs');
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 4. Weighted Shuffle
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
    final result = await compute(_albumAwareShuffleIsolate, <String, dynamic>{
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
      _recencyDampenedShuffleIsolate,
      <String, dynamic>{
        'songs': future,
        'recentIds': _recentlyPlayedIds.toList(),
      },
    );
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 7. Smart Local Shuffle
  //
  // FIX-LAG: count is now capped at _maxServerRequestCount (15).
  //
  // computeSmartLocalOrder() — Phase 1: HTTP fetch only, no platform channel.
  // commitSmartLocalOrder()  — Phase 2: apply order to player.
  // smartLocalShuffle()      — convenience wrapper (compute + commit).
  //
  // The count cap means:
  //   • Initial load: server receives count=15 instead of count=N.
  //     Response time drops from proportional-to-N to flat ~200ms.
  //   • setAudioSource: called with 16 sources (seed + 15) not N sources.
  //     Platform channel work drops by ~(N-16)/N.
  //   • Pool-based refill: each batch is also 15 songs max.
  // ---------------------------------------------------------------------------

  /// Phase 1: HTTP fetch + list reorder. No platform channel contact.
  /// [future] must already be the capped batch (caller's responsibility to
  /// pass ≤15 songs). We additionally clamp here as a safety net.
  Future<List<Song>?> computeSmartLocalOrder({
    required Song currentSong,
    required List<Song> future,
    String? contextName,
  }) async {
    if (_shuffleBaseUrl.isEmpty) return null;

    // Safety cap: never ask server for more than _maxServerRequestCount songs.
    final cappedFuture = future.length > _maxServerRequestCount
        ? future.sublist(0, _maxServerRequestCount)
        : future;

    final futureMap = <String, Song>{};
    for (final song in cappedFuture) {
      futureMap.putIfAbsent(song.title.toLowerCase().trim(), () => song);
    }

    try {
      final queryParams = <String, String>{
        'current': currentSong.title,
        'artist': currentSong.artist,
        'count': cappedFuture.length.toString(),
        // Send the exact batch titles so the server can only return songs
        // from this playlist batch — nothing outside can appear in results.
        'candidates': cappedFuture
            .map((s) => s.title.toLowerCase().trim())
            .join('|'),
      };
      if (contextName != null && contextName.isNotEmpty) {
        queryParams['playlist'] = contextName;
      }
      final uri = Uri.parse('$_shuffleBaseUrl/next')
          .replace(queryParameters: queryParams);

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        debugPrint(
          '⚠️ [SHUFFLE] Smart Local: server ${response.statusCode}',
        );
        return null;
      }

      final List<dynamic> data = jsonDecode(response.body);
      final serverKeys =
          data.map((e) => e['song_key'].toString()).toList();

      final List<Song> ordered = [];
      final Set<String> matched = {};
      for (final key in serverKeys) {
        final song = futureMap[key];
        if (song != null && !matched.contains(song.id)) {
          ordered.add(song);
          matched.add(song.id);
        }
      }
      // Append any songs the server didn't mention (unmatched by key).
      for (final song in cappedFuture) {
        if (!matched.contains(song.id)) ordered.add(song);
      }

      debugPrint(
        '✅ [SHUFFLE] Smart Local order computed: ${ordered.length} songs, '
        '${matched.length} matched by model',
      );
      return ordered;
    } catch (e) {
      debugPrint('❌ [SHUFFLE] Smart Local compute failed: $e');
      return null;
    }
  }

  /// Phase 2: apply pre-computed order to _currentQueue and the player.
  Future<void> commitSmartLocalOrder({
    required List<Song> pastAndPresent,
    required List<Song> orderedFuture,
    required int anchorIndex,
    bool preferMoveBasedReorder = false,
  }) async {
    _currentQueue = [...pastAndPresent, ...orderedFuture];
    await _updateQueueAfterAnchor(
      anchorIndex,
      preferMoveBasedReorder: preferMoveBasedReorder,
    );
  }

  /// Convenience wrapper: compute + commit in one call.
  Future<void> smartLocalShuffle({String? contextName}) async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Smart Local (inline)');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final rawFuture = _currentQueue.sublist(safeIndex + 1);
    if (rawFuture.isEmpty) return;

    // Cap the future slice to _maxServerRequestCount.
    final future = rawFuture.length > _maxServerRequestCount
        ? rawFuture.sublist(0, _maxServerRequestCount)
        : rawFuture;

    final currentSong = _currentQueue[safeIndex];

    final ordered = await computeSmartLocalOrder(
      currentSong: currentSong,
      future: future,
      contextName: contextName,
    );

    if (ordered == null) {
      debugPrint('⚠️ [SHUFFLE] Smart Local: falling back to standard shuffle');
      await standardShuffle();
      return;
    }

    await commitSmartLocalOrder(
      pastAndPresent: pastAndPresent,
      orderedFuture: ordered,
      anchorIndex: safeIndex,
    );
  }

  // ---------------------------------------------------------------------------
  // 8. Unshuffle
  // ---------------------------------------------------------------------------
  Future<void> unshuffle() async {
    if (_currentQueue.isEmpty || _unshuffledQueue.isEmpty) return;
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final currentSong = _currentQueue[safeIndex];
    _currentQueue = List.from(_unshuffledQueue);
    final newIndex = _unshuffledQueue.indexWhere((s) => s.id == currentSong.id);
    await _updateQueueAfterAnchor(newIndex != -1 ? newIndex : safeIndex);
  }

  // ---------------------------------------------------------------------------
  // computeShuffle — for initial playlist shuffle play (non-smartLocal algos)
  //
  // FIX-LAG for smartLocal: count is capped to _maxServerRequestCount (15).
  // The pool-based design in PlayerNotifier means [pool] passed here for
  // smartLocal is already ≤15 songs; this cap is an additional safety net.
  // ---------------------------------------------------------------------------
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
        return compute(_ditheredPositionShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'pref': preference.index,
        });

      case ShuffleAlgorithm.youtube:
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
        if (pool.isEmpty) return pool;
        if (_shuffleBaseUrl.isEmpty) {
          debugPrint(
            '⚠️ [computeShuffle] Smart Local: no server URL, falling back',
          );
          return compute(_standardShuffleIsolate, pool);
        }

        // Cap to _maxServerRequestCount — pool should already be ≤15 when
        // called from playPlaylist(), but guard here too.
        final cappedPool = pool.length > _maxServerRequestCount
            ? pool.sublist(0, _maxServerRequestCount)
            : pool;

        try {
          final queryParams = <String, String>{
            'count': cappedPool.length.toString(),
            // Send candidate titles so server only scores within this batch.
            'candidates': cappedPool
                .map((s) => s.title.toLowerCase().trim())
                .join('|'),
          };
          if (currentSong != null) {
            queryParams['current'] = currentSong.title;
            queryParams['artist'] = currentSong.artist;
          }
          if (contextName != null) {
            queryParams['playlist'] = contextName;
          }

          final uri = Uri.parse('$_shuffleBaseUrl/next')
              .replace(queryParameters: queryParams);
          final response = await http
              .get(uri)
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            final serverKeys =
                data.map((e) => e['song_key'].toString()).toList();

            final poolMap = <String, Song>{};
            for (final song in cappedPool) {
              poolMap.putIfAbsent(
                  song.title.toLowerCase().trim(), () => song);
            }

            final List<Song> ordered = [];
            final Set<String> matched = {};
            for (final key in serverKeys) {
              final song = poolMap[key];
              if (song != null && !matched.contains(song.id)) {
                ordered.add(song);
                matched.add(song.id);
              }
            }
            for (final song in cappedPool) {
              if (!matched.contains(song.id)) ordered.add(song);
            }

            debugPrint(
              '✅ [computeShuffle] Smart Local: '
              '${matched.length}/${cappedPool.length} matched',
            );
            return ordered;
          }
        } catch (e) {
          debugPrint('❌ [computeShuffle] Smart Local failed: $e');
        }
        return compute(_standardShuffleIsolate, cappedPool);
    }
  }

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

  void updateShuffleBaseUrl(String url) {
    _shuffleBaseUrl = url;
    debugPrint(
      '[AudioHandler] Shuffle server URL updated: '
      '${url.isEmpty ? "(empty — fallback mode)" : url}',
    );
  }

  Future<void> dispose() async {
    await player.stop();
    await player.dispose();
  }
}