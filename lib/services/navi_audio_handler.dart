import 'dart:async';
import 'dart:io' show Platform;
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



  /// True on Linux — ConcatenatingAudioSource is not supported by
  /// just_audio_media_kit 2.1.0 in its platform-channel message form.
  static bool get _isLinux => !kIsWeb && Platform.isLinux;

  // ── Linux single-source bridge state ────────────────────────────────────────
  int _linuxIndex = 0;
  StreamSubscription<PlayerState>? _linuxCompletionSub;
  /// Mutex: true while setAudioSource() is in progress on Linux.
  /// Prevents the dual-completion-listener race (Bug 1 + Bug 3).
  bool _linuxLoading = false;

  NaviAudioHandler(
    this.subsonicService, {
    AudioPlayer? player,
    ReplayGainService? replayGainService,
  }) : player = player ?? AudioPlayer(),
       _replayGainService = replayGainService ?? ReplayGainService() {
    
    _listenToPlayerEvents();

    this.player.currentIndexStream.listen((index) {
      // On Linux we manage index ourselves — ignore just_audio's index stream
      if (!_isLinux && index != null && index < _currentQueue.length) {
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
    // (non-Linux only — on Linux we push MediaItem manually via _emitLinuxMediaItem)
    if (!_isLinux) {
      player.sequenceStateStream.listen((sequenceState) {
        if (sequenceState?.currentSource == null) return;
        final source = sequenceState!.currentSource!;
        if (source.tag is MediaItem) {
          mediaItem.add(source.tag as MediaItem);
        }
      });
    }
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
  Future<void> skipToNext() {
    if (_isLinux) return _linuxSkipToNext();
    return player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() {
    if (_isLinux) return _linuxSkipToPrevious();
    return player.seekToPrevious();
  }

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
    if (_isLinux) {
      _linuxCompletionSub?.cancel();
      _linuxCompletionSub = null;
      _linuxIndex = 0;
    }
  }

  Future<void> _rebuildSource(
    int startIndex, {
    Duration? initialPosition,
  }) async {
    if (_currentQueue.isEmpty) return;
    final savedLoopMode = player.loopMode;
    final offlinePaths = await _precomputeOfflinePaths(_currentQueue);

    if (_isLinux) {
      // ── Linux: ConcatenatingAudioSource is not supported by
      // just_audio_media_kit 2.1.0. Play one track at a time and advance
      // manually on completion.
      _linuxIndex = startIndex.clamp(0, _currentQueue.length - 1);
      await _linuxLoadTrack(_linuxIndex, offlinePaths,
          initialPosition: initialPosition);
      _startLinuxCompletionListener();
      return;
    }

    // ── Non-Linux: original ConcatenatingAudioSource path ────────────────────
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

  // ---------------------------------------------------------------------------
  // Linux single-source bridge
  // ---------------------------------------------------------------------------

  Future<void> _linuxLoadTrack(
    int index,
    Map<String, String?> offlinePaths, {
    Duration? initialPosition,
  }) async {
    if (index < 0 || index >= _currentQueue.length) return;
    // Mutex: if a load is already in progress, cancel this one.
    // This prevents the dual-completion-listener race.
    if (_linuxLoading) {
      debugPrint('⚡ [Linux] Load skipped (already loading track $_linuxIndex)');
      return;
    }
    _linuxLoading = true;
    try {
      final source = _toSourceWithPaths(_currentQueue[index], offlinePaths);
      await player
          .setAudioSource(source, initialPosition: initialPosition)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw TimeoutException('[Linux] _linuxLoadTrack timed out'),
          );
      _emitLinuxMediaItem(index);
      _trackRecentlyPlayed(_currentQueue[index].id);
      debugPrint('🎵 [Linux] Loaded track $index: ${_currentQueue[index].title}');
    } on PlayerInterruptedException {
      // Expected when a newer load supersedes this one (e.g. rapid Next press).
      // Safe to swallow — the newer load will complete instead.
      debugPrint('⚡ [Linux] Load interrupted (superseded by newer request)');
    } on PlayerException catch (e) {
      debugPrint('❌ [Linux] PlayerException loading track $index: ${e.message}');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('❌ [Linux] Timeout loading track $index: $e');
      rethrow;
    } finally {
      _linuxLoading = false;
    }
  }

  void _emitLinuxMediaItem(int index) {
    if (index < 0 || index >= _currentQueue.length) return;
    final song = _currentQueue[index];
    mediaItem.add(MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      genre: song.genre,
      artUri: Uri.parse(subsonicService.getCoverArtUrl(song.coverArt)),
      duration: Duration(seconds: song.duration),
      extras: {'composer': song.composer, 'isLocal': false},
    ));
  }

  void _startLinuxCompletionListener() {
    _linuxCompletionSub?.cancel();
    _linuxCompletionSub = player.playerStateStream.listen((state) async {
      if (state.processingState != ProcessingState.completed) return;
      // Guard: if PlayerNotifier or a manual skip already kicked off a load,
      // don't double-advance. The mutex in _linuxLoadTrack will reject the
      // second call anyway, but checking here avoids the index increment.
      if (_linuxLoading) {
        debugPrint('⚡ [Linux] Completion skipped (load already in progress)');
        return;
      }
      debugPrint('🏁 [Linux] Track completed, advancing...');

      // Repeat one — restart current track
      if (player.loopMode == LoopMode.one) {
        await player.seek(Duration.zero);
        await player.play();
        return;
      }

      int next = _linuxIndex + 1;
      if (next >= _currentQueue.length) {
        if (player.loopMode == LoopMode.all) {
          next = 0; // wrap around
        } else {
          return; // end of queue, stay stopped
        }
      }

      _linuxIndex = next;
      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      await _linuxLoadTrack(_linuxIndex, offlinePaths);
      if (!player.playing) await player.play();
    });
  }

  Future<void> _linuxSkipToNext() async {
    if (_currentQueue.isEmpty) return;
    int next = _linuxIndex + 1;
    if (next >= _currentQueue.length) {
      if (player.loopMode == LoopMode.all) {
        next = 0;
      } else {
        return;
      }
    }
    _linuxIndex = next;
    final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
    await _linuxLoadTrack(_linuxIndex, offlinePaths);
    if (player.playing) await player.play();
  }

  Future<void> _linuxSkipToPrevious() async {
    if (_currentQueue.isEmpty) return;
    // If more than 3 seconds in, restart current track
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      return;
    }
    int prev = _linuxIndex - 1;
    if (prev < 0) {
      if (player.loopMode == LoopMode.all) {
        prev = _currentQueue.length - 1;
      } else {
        await player.seek(Duration.zero);
        return;
      }
    }
    _linuxIndex = prev;
    final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
    await _linuxLoadTrack(_linuxIndex, offlinePaths);
    if (player.playing) await player.play();
  }

  /// Current index — Linux uses _linuxIndex, other platforms use player.currentIndex
  int get currentIndex => _isLinux ? _linuxIndex : (player.currentIndex ?? 0);

  /// Platform-adaptive index jump.
  /// On Linux: loads the track at [index] via the single-source bridge.
  /// On other platforms: uses just_audio's seek(Duration.zero, index: index).
  Future<void> jumpToIndex(int index) async {
    if (index < 0 || index >= _currentQueue.length) return;
    if (_isLinux) {
      _linuxIndex = index;
      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      await _linuxLoadTrack(_linuxIndex, offlinePaths);
    } else {
      await player.seek(Duration.zero, index: index);
    }
  }

  /// Override BaseAudioHandler.skipToQueueItem so callers (and platform media
  /// controls) land on the correct track on Linux single-source mode.
  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _currentQueue.length) return;
    if (_isLinux) {
      _linuxIndex = index;
      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      await _linuxLoadTrack(_linuxIndex, offlinePaths);
      if (player.playing) await player.play();
    } else {
      await player.seek(Duration.zero, index: index);
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

    // FIX-SHUFFLE-GAP: Always prefer move-based reorder when the playlist is
    // already loaded (i.e. _playlist != null). On Linux we don't use _playlist
    // so we always fall back to _rebuildSource.
    if (_isLinux) {

      final savedPosition = player.position;
      await _rebuildSource(anchorIndex, initialPosition: savedPosition);
      if (player.playing) player.play();
      return;
    }

    final int n = _currentQueue.length;

    if (n <= 5 && !preferMoveBasedReorder) {
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

    final currentLiveIndex = this.currentIndex;
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
    
    bool needsRebuild = true;
    if (_isLinux) {
      if (index < _linuxIndex) {
        _linuxIndex--;
        needsRebuild = false; // Currently playing track is unaffected
      } else if (index > _linuxIndex) {
        needsRebuild = false; // Currently playing track is unaffected
      }
    }

    final song = _currentQueue.removeAt(index);
    final unIdx = _unshuffledQueue.indexWhere((s) => s.id == song.id);
    if (unIdx != -1) _unshuffledQueue.removeAt(unIdx);

    if (_playlist != null) {
      await _playlist!.removeAt(index);
    } else if (needsRebuild) {
      await _rebuildSource(this.currentIndex.clamp(0, _currentQueue.length - 1));
    }
  }

  Future<void> reorderQueue(
    int oldIndex,
    int newIndex, {
    bool isShuffleMode = false,
  }) async {
    if (oldIndex < 0 || oldIndex >= _currentQueue.length) return;
    if (newIndex < 0 || newIndex >= _currentQueue.length) return;
    
    if (_isLinux) {
      if (oldIndex == _linuxIndex) {
        _linuxIndex = newIndex;
      } else if (oldIndex < _linuxIndex && newIndex >= _linuxIndex) {
        _linuxIndex--;
      } else if (oldIndex > _linuxIndex && newIndex <= _linuxIndex) {
        _linuxIndex++;
      }
    }

    final song = _currentQueue.removeAt(oldIndex);
    _currentQueue.insert(newIndex, song);

    if (!isShuffleMode) {
      final unSong = _unshuffledQueue.removeAt(oldIndex);
      _unshuffledQueue.insert(newIndex, unSong);
    }

    if (_playlist != null) {
      await _playlist!.move(oldIndex, newIndex);
    }
  }



  // ---------------------------------------------------------------------------
  // 1. Standard Fisher-Yates
  // ---------------------------------------------------------------------------
  Future<void> standardShuffle() async {
    if (_currentQueue.isEmpty) return;
    final currentIndex = this.currentIndex;
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
    final currentIndex = this.currentIndex;
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
    final currentIndex = this.currentIndex;
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
    final currentIndex = this.currentIndex;
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
    final currentIndex = this.currentIndex;
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
    final currentIndex = this.currentIndex;
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

  // ---------------------------------------------------------------------------
  // 8. Unshuffle
  // ---------------------------------------------------------------------------
  Future<void> unshuffle() async {
    if (_currentQueue.isEmpty || _unshuffledQueue.isEmpty) return;
    final currentIndex = this.currentIndex;
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
        // Already handled externally via player_provider + v3 API. 
        // Fall back to standard here if accidentally called.
        return compute(_standardShuffleIsolate, pool);
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



  Future<void> dispose() async {
    await player.stop();
    await player.dispose();
  }
}