// ignore_for_file: deprecated_member_use, experimental_member_use

import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import 'subsonic_service.dart';

import 'transcoding_service.dart';
import 'cache_settings_service.dart';
import '../providers/settings_provider.dart';
import '../offline_service.dart';
import 'shuffle_algorithms.dart';

// ---------------------------------------------------------------------------
// AudioHandler
// ---------------------------------------------------------------------------

class NaviAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player;
  final SubsonicService subsonicService;

  final TranscodingService _transcodingService;
  List<Song> _currentQueue = [];
  List<Song> _unshuffledQueue = [];
  ConcatenatingAudioSource? _playlist;
  int _playlistOffset = 0;

  static const int _recencyWindow = 20;
  final LinkedHashSet<String> _recentlyPlayedIds = LinkedHashSet<String>();



  /// True on desktop (Linux, Windows, macOS) — ConcatenatingAudioSource is not
  /// supported by just_audio_media_kit 2.1.0 in its platform-channel message form.
  static bool get _isDesktopBridge =>
      !kIsWeb &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  /// Public getter for player_provider to coordinate completion advancement
  static bool get isDesktopBridge => _isDesktopBridge;

  // ── Desktop single-source bridge state ───────────────────────────────────────
  int _desktopIndex = 0;
  int _desktopTargetIndex = 0;
  int _desktopLoadGeneration = 0;
  StreamSubscription<PlayerState>? _desktopCompletionSub;

  /// Holds all long-lived stream subscriptions so dispose() can cancel them.
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // MEM-OPT: Cache the offline-path lookup so desktop doesn't re-stat the
  // filesystem on every track skip. Invalidated when the queue changes.
  Map<String, String?>? _offlinePathsCache;
  int _offlinePathsQueueLength = 0;

  /// Mutex: true while setAudioSource() is in progress on desktop.
  /// Prevents the dual-completion-listener race (Bug 1 + Bug 3).
  bool _desktopLoading = false;

  /// Timer to detect stuck playback in loading or buffering state.
  Timer? _stuckTimer;

  NaviAudioHandler(
    this.subsonicService, {
    AudioPlayer? player,
    TranscodingService? transcodingService,
  }) : player =
           player ??
           AudioPlayer(
             audioLoadConfiguration: const AudioLoadConfiguration(
               androidLoadControl: AndroidLoadControl(
                 minBufferDuration: Duration(seconds: 15),
                 maxBufferDuration: Duration(seconds: 30),
                 bufferForPlaybackDuration: Duration(milliseconds: 1500),
                 bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
                 prioritizeTimeOverSizeThresholds: false,
               ),
               darwinLoadControl: DarwinLoadControl(
                 preferredForwardBufferDuration: Duration(seconds: 30),
               ),
             ),
           ),
       _transcodingService = transcodingService ?? TranscodingService() {
    _listenToPlayerEvents();

    _subscriptions.add(this.player.currentIndexStream.listen((index) {
      // On desktop we manage index ourselves — ignore just_audio's index stream
      if (!_isDesktopBridge && index != null) {
        final globalIndex = _playlistOffset + index;
        if (globalIndex < _currentQueue.length) {
          _trackRecentlyPlayed(_currentQueue[globalIndex].id);
        }
      }
    }));

    _subscriptions.add(this.player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace stackTrace) {
        debugPrint('❌ [NaviAudioHandler] Stream error: $e');
        if (e is PlayerException) {
          debugPrint('   Code: ${e.code}  Message: ${e.message}');
          // Trigger immediate recovery on playback exceptions.
          _recoverStuckPlayer();
        }
      },
    ));

    _subscriptions.add(this.player.playerStateStream.listen(
      (state) {
        if (state.processingState == ProcessingState.completed) {
          debugPrint('ℹ️ [NaviAudioHandler] Processing state: completed');
        }

        final isStuckState = state.playing &&
            (state.processingState == ProcessingState.loading ||
             state.processingState == ProcessingState.buffering);

        if (isStuckState) {
          if (_stuckTimer == null) {
            debugPrint('⏳ [NaviAudioHandler] Player entered buffering/loading. Starting 45s stuck timer.');
            _stuckTimer = Timer(const Duration(seconds: 45), () async {
              _stuckTimer = null;
              final currentState = this.player.playerState;
              final stillStuck = currentState.playing &&
                  (currentState.processingState == ProcessingState.loading ||
                   currentState.processingState == ProcessingState.buffering);
              if (stillStuck) {
                await _recoverStuckPlayer();
              }
            });
          }
        } else {
          if (_stuckTimer != null) {
            debugPrint('✅ [NaviAudioHandler] Player left buffering/loading. Stuck timer cleared.');
            _stuckTimer!.cancel();
            _stuckTimer = null;
          }
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('❌ [NaviAudioHandler] Player state error: $e');
      },
    ));
  }

  void _listenToPlayerEvents() {
    // Broadcast state only on discrete player state changes (play/pause,
    // processingState). audio_service interpolates seekbar position between
    // updates, so we don't need to push on every position tick (~5/s).
    // Previously this subscribed to playbackEventStream which fires on
    // position updates and caused _broadcastState() to run 5+ times/second.
    _subscriptions.add(player.playerStateStream.listen((_) {
      _broadcastState();
    }));

    // Sync current media item when sequence or index changes
    // (non-desktop only — on desktop we push MediaItem manually via _emitDesktopMediaItem)
    if (!_isDesktopBridge) {
      _subscriptions.add(player.sequenceStateStream.listen((sequenceState) {
        if (sequenceState.currentSource == null) return;
        final source = sequenceState.currentSource!;
        if (source.tag is MediaItem) {
          mediaItem.add(source.tag as MediaItem);
        }
      }));
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

    playbackState.add(
      playbackState.value.copyWith(
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
      ),
    );
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
  Future<void> skipToNext() {
    if (_isDesktopBridge) return _desktopSkipToNext();
    return player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() {
    if (_isDesktopBridge) return _desktopSkipToPrevious();
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

  @override
  @visibleForTesting
  set currentQueue(List<Song> songs) => _currentQueue = songs;

  List<Song> get currentQueue => _currentQueue;
  List<Song> get unshuffledQueue => _unshuffledQueue;

  void _trackRecentlyPlayed(String songId) {
    _recentlyPlayedIds.remove(songId); // drop stale position if present
    _recentlyPlayedIds.add(songId);    // re-insert at the most-recent tail
    if (_recentlyPlayedIds.length > _recencyWindow) {
      _recentlyPlayedIds.remove(_recentlyPlayedIds.first); // evict least-recent
    }
  }

  AudioSource _toSource(Song song) {
    final musicCacheEnabled = CacheSettingsService().getMusicCacheEnabled();
    final localPath = musicCacheEnabled ? OfflineService().getLocalPath(song.id) : null;
    final streamUri = localPath != null
        ? Uri.file(localPath)
        : Uri.parse(subsonicService.getStreamUrl(
            song.id,
            maxBitRate: _transcodingService.getCurrentBitrate(),
            format: _transcodingService.getCurrentFormat(),
          ));

    final localCoverPath = OfflineService().getLocalCoverArtPath(song.id);
    final artUri = localCoverPath != null
        ? Uri.file(localCoverPath)
        : Uri.parse(subsonicService.getCoverArtUrl(song.coverArt));

    final tag = MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      genre: song.genre,
      artUri: artUri,
      duration: Duration(seconds: song.duration),
      extras: {'composer': song.composer, 'isLocal': localPath != null},
    );

    if (localPath != null || !musicCacheEnabled || _isDesktopBridge) {
      return AudioSource.uri(streamUri, tag: tag);
    }

    return LockCachingAudioSource(streamUri, tag: tag);
  }

  AudioSource _toSourceWithPaths(Song song, Map<String, String?> offlinePaths) {
    final musicCacheEnabled = CacheSettingsService().getMusicCacheEnabled();
    final localPath = musicCacheEnabled ? offlinePaths[song.id] : null;
    final streamUri = localPath != null
        ? Uri.file(localPath)
        : Uri.parse(subsonicService.getStreamUrl(
            song.id,
            maxBitRate: _transcodingService.getCurrentBitrate(),
            format: _transcodingService.getCurrentFormat(),
          ));

    final localCoverPath = OfflineService().getLocalCoverArtPath(song.id);
    final artUri = localCoverPath != null
        ? Uri.file(localCoverPath)
        : Uri.parse(subsonicService.getCoverArtUrl(song.coverArt));

    final tag = MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      genre: song.genre,
      artUri: artUri,
      duration: Duration(seconds: song.duration),
      extras: {'composer': song.composer, 'isLocal': localPath != null},
    );

    if (localPath != null || !musicCacheEnabled || _isDesktopBridge) {
      return AudioSource.uri(streamUri, tag: tag);
    }

    return LockCachingAudioSource(streamUri, tag: tag);
  }

  Future<Map<String, String?>> _precomputeOfflinePaths(List<Song> songs) async {
    // MEM-OPT: Return cached result if the queue hasn't changed.
    if (_offlinePathsCache != null && _offlinePathsQueueLength == songs.length) {
      return _offlinePathsCache!;
    }
    final offline = OfflineService();
    await offline.initialize(); // Ensure directory is resolved
    // Resolve all paths asynchronously (File.exists) instead of blocking the
    // main thread with existsSync per song — the prior approach janked queue
    // builds for large queues.
    final entries = await Future.wait(
      songs.map(
        (song) async =>
            MapEntry(song.id, await offline.getLocalPathAsync(song.id)),
      ),
    );
    _offlinePathsCache = Map.fromEntries(entries);
    _offlinePathsQueueLength = songs.length;
    return _offlinePathsCache!;
  }

  Future<void> setQueue(
    List<Song> songs,
    int startIndex, {
    List<Song>? unshuffledSongs,
  }) async {
    debugPrint('🎵 [NaviAudioHandler] setQueue: ${songs.length} songs, start: $startIndex');
    for (int i = 0; i < songs.length; i++) {
      debugPrint('   ${i + 1}. ${songs[i].title}');
    }
    _currentQueue = List.from(songs);
    _unshuffledQueue = List.from(unshuffledSongs ?? songs);
    // MEM-OPT: Invalidate the offline paths cache when the queue is replaced.
    _offlinePathsCache = null;
    _offlinePathsQueueLength = 0;
    await _rebuildSource(startIndex);
    player.setVolume(1.0);
  }

  /// Updates the queue dynamically while keeping the currently playing track playing
  /// seamlessly without any audio interruption or playstate change.
  Future<void> updateQueuePreservingCurrent(
    List<Song> newQueue,
    int newCurrentIndex,
  ) async {
    debugPrint('🎵 [NaviAudioHandler] updateQueuePreservingCurrent: ${newQueue.length} songs, current: $newCurrentIndex');
    
    _currentQueue = List.from(newQueue);
    if (_unshuffledQueue.isEmpty) {
      _unshuffledQueue = List.from(newQueue);
    }
    _offlinePathsCache = null;
    _offlinePathsQueueLength = 0;

    if (_isDesktopBridge) {
      _desktopIndex = newCurrentIndex;
      _desktopTargetIndex = newCurrentIndex;
      return;
    }

    if (_playlist == null) {
      await _rebuildSource(newCurrentIndex);
      return;
    }

    final oldSequenceIndex = player.currentIndex;
    if (oldSequenceIndex == null) {
      await _rebuildSource(newCurrentIndex);
      return;
    }

    final offlinePaths = await _precomputeOfflinePaths(newQueue);

    // 1. Remove all children after oldSequenceIndex
    final initialLen = _playlist!.children.length;
    if (initialLen > oldSequenceIndex + 1) {
      await _playlist!.removeRange(oldSequenceIndex + 1, initialLen);
    }

    // 2. Remove all children before oldSequenceIndex
    if (oldSequenceIndex > 0) {
      await _playlist!.removeRange(0, oldSequenceIndex);
    }

    // Now, the active item is the only item in the playlist (at index 0).

    // 3. Insert prefix items before active index (which is now at 0)
    final prefixSources = <AudioSource>[];
    for (int i = 0; i < newCurrentIndex; i++) {
      prefixSources.add(_toSourceWithPaths(newQueue[i], offlinePaths));
    }
    if (prefixSources.isNotEmpty) {
      await _playlist!.insertAll(0, prefixSources);
    }

    // 4. Append suffix items after active index (which is now at newCurrentIndex)
    final suffixSources = <AudioSource>[];
    for (int i = newCurrentIndex + 1; i < newQueue.length; i++) {
      suffixSources.add(_toSourceWithPaths(newQueue[i], offlinePaths));
    }
    if (suffixSources.isNotEmpty) {
      await _playlist!.addAll(suffixSources);
    }

    _playlistOffset = 0;
  }

  /// Clears the audio source and queue. Must be called AFTER player.stop().
  Future<void> clearQueue() async {
    _currentQueue.clear();
    _playlist = ConcatenatingAudioSource(children: []);
    _playlistOffset = 0;
    if (_isDesktopBridge) {
      _desktopCompletionSub?.cancel();
      _desktopCompletionSub = null;
      _desktopIndex = 0;
      _desktopTargetIndex = 0;
    }
  }

  Future<void> _rebuildSource(
    int startIndex, {
    Duration? initialPosition,
  }) async {
    if (_currentQueue.isEmpty) return;
    final savedLoopMode = player.loopMode;
    final offlinePaths = await _precomputeOfflinePaths(_currentQueue);

    if (_isDesktopBridge) {
      // ── Desktop: ConcatenatingAudioSource is not supported by
      // just_audio_media_kit 2.1.0. Play one track at a time and advance
      // manually on completion.
      final start = startIndex.clamp(0, _currentQueue.length - 1);
      _desktopTargetIndex = start;
      _desktopIndex = start;
      _emitDesktopMediaItem(start);
      await _desktopLoadTrack(
        start,
        offlinePaths,
        initialPosition: initialPosition,
      );
      _startDesktopCompletionListener();
      return;
    }

    // ── Non-Desktop: original ConcatenatingAudioSource path ──────────────────
    // MEM-OPT: Cap at 100 sources. With a full album or shuffle queue of 500+
    // songs, ConcatenatingAudioSource pre-buffers adjacent tracks and holds a
    // MediaItem (~1 KB) per child. 100 songs = ~100 KB of tags + buffer memory.
    // Songs beyond the cap remain in _currentQueue / PlayerState for display.
    const int maxConcatSources = 100;
    final int effectiveStart;
    final int initialIndex;
    if (_currentQueue.length <= maxConcatSources) {
      effectiveStart = 0;
      initialIndex = startIndex.clamp(0, _currentQueue.length - 1);
    } else {
      effectiveStart = startIndex.clamp(0, _currentQueue.length - 1);
      initialIndex = 0;
    }
    _playlistOffset = effectiveStart;

    // Include the start track and as many subsequent songs as fit in the cap.
    final endIdx = (effectiveStart + maxConcatSources).clamp(0, _currentQueue.length);
    final sourceSongs = _currentQueue.sublist(effectiveStart, endIdx);
    final List<AudioSource> sources = sourceSongs
        .map((song) => _toSourceWithPaths(song, offlinePaths))
        .toList();
    _playlist = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: sources,
    );
    await player.setAudioSource(
      _playlist!,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
    if (savedLoopMode != LoopMode.off) {
      await player.setLoopMode(savedLoopMode);
    }
  }

  // ---------------------------------------------------------------------------
  // Desktop single-source bridge
  // ---------------------------------------------------------------------------

  Future<void> _desktopLoadTrack(
    int index,
    Map<String, String?> offlinePaths, {
    Duration? initialPosition,
  }) async {
    if (index < 0 || index >= _currentQueue.length) return;
    final generation = ++_desktopLoadGeneration;
    _desktopLoading = true;
    try {
      final source = _toSourceWithPaths(_currentQueue[index], offlinePaths);
      await player
          .setAudioSource(source, initialPosition: initialPosition)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw TimeoutException('[Desktop] _desktopLoadTrack timed out'),
          );
      if (generation != _desktopLoadGeneration) {
        debugPrint('⚡ [Desktop] Load for track $index superseded by generation $_desktopLoadGeneration');
        return;
      }
      _desktopIndex = index;
      _emitDesktopMediaItem(index);
      _trackRecentlyPlayed(_currentQueue[index].id);
      debugPrint(
        '🎵 [Desktop] Loaded track $index: ${_currentQueue[index].title}',
      );
    } on PlayerInterruptedException {
      // Expected when a newer load supersedes this one (e.g. rapid Next press).
      // Safe to swallow — the newer load will complete instead.
      debugPrint('⚡ [Desktop] Load interrupted (superseded by newer request)');
    } on PlayerException catch (e) {
      debugPrint(
        '❌ [Desktop] PlayerException loading track $index: ${e.message}',
      );
      if (generation == _desktopLoadGeneration) {
        _handleDesktopLoadError(index, e);
      }
    } on TimeoutException catch (e) {
      debugPrint('❌ [Desktop] Timeout loading track $index: $e');
      if (generation == _desktopLoadGeneration) {
        _handleDesktopLoadError(index, e);
      }
    } finally {
      if (generation == _desktopLoadGeneration) {
        _desktopLoading = false;
      }
    }
  }

  void _handleDesktopLoadError(int failedIndex, Object error) {
    if (_currentQueue.isEmpty) return;
    debugPrint('⚠️ [Desktop] Handling load error for track $failedIndex. Attempting safe advance...');
    if (failedIndex + 1 < _currentQueue.length) {
      unawaited(_desktopSkipToNext());
    } else if (failedIndex > 0) {
      _desktopIndex = failedIndex - 1;
      _desktopTargetIndex = _desktopIndex;
      _emitDesktopMediaItem(_desktopIndex);
    }
  }

  void _emitDesktopMediaItem(int index) {
    if (index < 0 || index >= _currentQueue.length) return;
    final song = _currentQueue[index];
    final localCoverPath = OfflineService().getLocalCoverArtPath(song.id);
    final artUri = localCoverPath != null
        ? Uri.file(localCoverPath)
        : Uri.parse(subsonicService.getCoverArtUrl(song.coverArt));
    mediaItem.add(
      MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        artUri: artUri,
        duration: Duration(seconds: song.duration),
        extras: {'composer': song.composer, 'isLocal': localCoverPath != null},
      ),
    );
  }

  void _startDesktopCompletionListener() {
    _desktopCompletionSub?.cancel();
    _desktopCompletionSub = player.playerStateStream.listen((state) async {
      if (state.processingState != ProcessingState.completed) return;
      // Guard: if PlayerNotifier or a manual skip already kicked off a load,
      // don't double-advance.
      if (_desktopLoading) {
        debugPrint('⚡ [Desktop] Completion skipped (load already in progress)');
        return;
      }
      debugPrint('🏁 [Desktop] Track completed, advancing...');

      // Repeat one — restart current track
      if (player.loopMode == LoopMode.one) {
        await player.seek(Duration.zero);
        await player.play();
        return;
      }

      int next = _desktopTargetIndex + 1;
      if (next >= _currentQueue.length) {
        if (player.loopMode == LoopMode.all) {
          next = 0; // wrap around
        } else {
          return; // end of queue, stay stopped
        }
      }

      _desktopTargetIndex = next;
      _desktopIndex = next;
      _emitDesktopMediaItem(next);

      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      try {
        await _desktopLoadTrack(next, offlinePaths);
        if (!player.playing) await player.play();
      } catch (e) {
        // Network glitch or timeout loading the next track — retry once after
        // a short delay instead of silently freezing the player.
        debugPrint('❌ [Desktop] Failed to load next track ($e). Retrying in 2s…');
        await Future.delayed(const Duration(seconds: 2));
        // Re-check queue is still valid after the delay.
        if (next < _currentQueue.length) {
          try {
            final retryPaths = await _precomputeOfflinePaths(_currentQueue);
            await _desktopLoadTrack(next, retryPaths);
            if (!player.playing) await player.play();
          } catch (e2) {
            debugPrint('❌ [Desktop] Retry also failed ($e2). Skipping to next…');
            // Try the track after that to avoid permanent freeze.
            final fallback = next + 1;
            if (fallback < _currentQueue.length) {
              final fallbackPaths = await _precomputeOfflinePaths(_currentQueue);
              try {
                await _desktopLoadTrack(fallback, fallbackPaths);
                if (!player.playing) await player.play();
              } catch (_) {
                debugPrint('❌ [Desktop] Fallback also failed. Player stopped.');
              }
            }
          }
        }
      }
    });
  }

  Future<void> _desktopSkipToNext() async {
    final wasPlaying = player.playing;
    if (_currentQueue.isEmpty) return;
    int next = _desktopTargetIndex + 1;
    if (next >= _currentQueue.length) {
      if (player.loopMode == LoopMode.all) {
        next = 0;
      } else {
        return;
      }
    }
    _desktopTargetIndex = next;
    _desktopIndex = next;
    _emitDesktopMediaItem(next);

    final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
    await _desktopLoadTrack(next, offlinePaths);
    if (wasPlaying && !player.playing) await player.play();
  }

  Future<void> _desktopSkipToPrevious() async {
    final wasPlaying = player.playing;
    if (_currentQueue.isEmpty) return;
    // If more than 3 seconds in, restart current track
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      return;
    }
    int prev = _desktopTargetIndex - 1;
    if (prev < 0) {
      if (player.loopMode == LoopMode.all) {
        prev = _currentQueue.length - 1;
      } else {
        await player.seek(Duration.zero);
        return;
      }
    }
    _desktopTargetIndex = prev;
    _desktopIndex = prev;
    _emitDesktopMediaItem(prev);

    final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
    await _desktopLoadTrack(prev, offlinePaths);
    if (wasPlaying && !player.playing) await player.play();
  }

  /// Current index — Desktop uses _desktopIndex, other platforms use player.currentIndex
  int get currentIndex => _isDesktopBridge ? _desktopIndex : (_playlistOffset + (player.currentIndex ?? 0));

  /// Platform-adaptive index jump.
  /// On Desktop: loads the track at [index] via the single-source bridge.
  /// On other platforms: uses just_audio's seek(Duration.zero, index: index).
  Future<void> jumpToIndex(int index) async {
    if (index < 0 || index >= _currentQueue.length) return;
    if (_isDesktopBridge) {
      _desktopTargetIndex = index;
      _desktopIndex = index;
      _emitDesktopMediaItem(index);
      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      await _desktopLoadTrack(index, offlinePaths);
    } else {
      await player.seek(Duration.zero, index: index);
    }
  }

  /// Override BaseAudioHandler.skipToQueueItem so callers (and platform media
  /// controls) land on the correct track on Desktop single-source mode.
  @override
  Future<void> skipToQueueItem(int index) async {
    final wasPlaying = player.playing;
    if (index < 0 || index >= _currentQueue.length) return;
    if (_isDesktopBridge) {
      _desktopTargetIndex = index;
      _desktopIndex = index;
      _emitDesktopMediaItem(index);
      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      await _desktopLoadTrack(index, offlinePaths);
      if (wasPlaying && !player.playing) await player.play();
    } else {
      await player.seek(Duration.zero, index: index);
    }
  }

  Future<void> _updateQueueAfterAnchor(
    int anchorIndex, {
    bool preferMoveBasedReorder = false,
  }) async {
    if (_isDesktopBridge) {
      _desktopIndex = anchorIndex;
      _desktopTargetIndex = anchorIndex;
      _emitDesktopMediaItem(anchorIndex);
      return;
    }

    if (_playlist == null) {
      final savedPosition = player.position;
      final wasPlaying = player.playing;
      await _rebuildSource(anchorIndex, initialPosition: savedPosition);
      if (wasPlaying) await player.play();
      return;
    }

    await _moveBasedReorder(anchorIndex);
  }

  Future<void> _moveBasedReorder(int anchorIndex) async {
    debugPrint('🎵 [NaviAudioHandler] _moveBasedReorder at anchor: $anchorIndex');
    final int n = _currentQueue.length;
    final int playlistLen = _playlist!.children.length;

    // Guard: if the playlist source count diverges from the queue count,
    // move-based reorder is unsafe — fall back to a full source rebuild
    // to prevent the "Not in inclusive range 0..N: N+1" RangeError.
    if (playlistLen != n) {
      debugPrint(
        '⚠️ [Reorder] playlist.children ($playlistLen) ≠ queue ($n) — '
        'falling back to rebuildSource at anchor $anchorIndex',
      );
      final savedPosition = player.position;
      await _rebuildSource(
        anchorIndex.clamp(0, n - 1),
        initialPosition: savedPosition,
      );
      if (player.playing) player.play();
      return;
    }

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

    final currentLiveIndex = currentIndex;
    if (currentLiveIndex != anchorIndex) {
      await player.seek(player.position, index: anchorIndex);
    }
    if (player.playing) player.play();
  }

  // ---------------------------------------------------------------------------
  // Incremental queue mutations
  // ---------------------------------------------------------------------------

  Future<void> insertNext(Song song) async {
    await insertAllNext([song]);
  }

  Future<void> insertAllNext(List<Song> songs, {int? atIndex}) async {
    if (songs.isEmpty) return;
    final wasEmpty = _currentQueue.isEmpty;
    final targetIndex = (atIndex ?? (currentIndex + 1)).clamp(0, _currentQueue.length);

    _currentQueue.insertAll(targetIndex, songs);
    final unTarget = targetIndex.clamp(0, _unshuffledQueue.length);
    _unshuffledQueue.insertAll(unTarget, songs);

    if (_isDesktopBridge) {
      if (wasEmpty) {
        await _rebuildSource(0);
      } else if (targetIndex <= _desktopIndex) {
        _desktopIndex += songs.length;
        _desktopTargetIndex += songs.length;
      }
      return;
    }

    if (_playlist != null) {
      if (wasEmpty) {
        await _rebuildSource(0);
      } else if (_playlistOffset == 0) {
        final sources = songs.map(_toSource).toList();
        await _playlist!.insertAll(targetIndex, sources);
      } else {
        if (targetIndex < _playlistOffset) {
          _playlistOffset += songs.length;
        } else if (targetIndex <= _playlistOffset + _playlist!.children.length) {
          final sources = songs.map(_toSource).toList();
          await _playlist!.insertAll(targetIndex - _playlistOffset, sources);
        }
      }
    }
  }

  Future<void> addToQueue(Song song) async {
    await addAllToQueue([song]);
  }

  Future<void> addAllToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;
    final wasEmpty = _currentQueue.isEmpty;
    _currentQueue.addAll(songs);
    _unshuffledQueue.addAll(songs);

    if (_playlist != null) {
      await _playlist!.addAll(songs.map(_toSource).toList());
    } else if (wasEmpty) {
      await _rebuildSource(0);
    }
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _currentQueue.length) return;

    bool needsRebuild = true;
    if (_isDesktopBridge) {
      if (index < _desktopIndex) {
        _desktopIndex--;
        needsRebuild = false; // Currently playing track is unaffected
      } else if (index > _desktopIndex) {
        needsRebuild = false; // Currently playing track is unaffected
      }

      if (index < _desktopTargetIndex) {
        _desktopTargetIndex--;
      }
      _desktopTargetIndex = _desktopTargetIndex.clamp(
        0,
        _currentQueue.length - 2 >= 0 ? _currentQueue.length - 2 : 0,
      );
    }

    final song = _currentQueue.removeAt(index);
    final unIdx = _unshuffledQueue.indexWhere((s) => s.id == song.id);
    if (unIdx != -1) _unshuffledQueue.removeAt(unIdx);

    if (_playlist != null) {
      if (_playlistOffset == 0) {
        await _playlist!.removeAt(index);
      } else {
        if (index < _playlistOffset) {
          _playlistOffset--;
        } else if (index < _playlistOffset + _playlist!.children.length) {
          await _playlist!.removeAt(index - _playlistOffset);
        }
      }
    } else if (needsRebuild) {
      await _rebuildSource(
        currentIndex.clamp(0, _currentQueue.length - 1),
      );
    }
  }

  Future<void> pruneRange(int start, int end) async {
    if (start < 0 || end > _currentQueue.length || start >= end) return;

    final removedSongs = _currentQueue.sublist(start, end);
    _currentQueue.removeRange(start, end);
    for (final song in removedSongs) {
      _unshuffledQueue.removeWhere((s) => s.id == song.id);
    }

    if (_isDesktopBridge) {
      final prunedCount = end - start;
      if (_desktopIndex >= start && _desktopIndex < end) {
        _desktopIndex = start.clamp(0, _currentQueue.length - 1);
      } else if (_desktopIndex >= end) {
        _desktopIndex -= prunedCount;
      }

      if (_desktopTargetIndex >= start && _desktopTargetIndex < end) {
        _desktopTargetIndex = start.clamp(0, _currentQueue.length - 1);
      } else if (_desktopTargetIndex >= end) {
        _desktopTargetIndex -= prunedCount;
      }
    }

    if (_playlist != null) {
      if (_playlistOffset == 0) {
        await _playlist!.removeRange(start, end);
      } else {
        await _rebuildSource(
          currentIndex.clamp(0, _currentQueue.length - 1),
        );
      }
    }
  }

  Future<void> reorderQueue(
    int oldIndex,
    int newIndex, {
    bool isShuffleMode = false,
  }) async {
    if (oldIndex < 0 || oldIndex >= _currentQueue.length) return;
    if (newIndex < 0 || newIndex >= _currentQueue.length) return;

    if (_isDesktopBridge) {
      if (oldIndex == _desktopIndex) {
        _desktopIndex = newIndex;
      } else if (oldIndex < _desktopIndex && newIndex >= _desktopIndex) {
        _desktopIndex--;
      } else if (oldIndex > _desktopIndex && newIndex <= _desktopIndex) {
        _desktopIndex++;
      }

      if (oldIndex == _desktopTargetIndex) {
        _desktopTargetIndex = newIndex;
      } else if (oldIndex < _desktopTargetIndex && newIndex >= _desktopTargetIndex) {
        _desktopTargetIndex--;
      } else if (oldIndex > _desktopTargetIndex && newIndex <= _desktopTargetIndex) {
        _desktopTargetIndex++;
      }
    }

    final song = _currentQueue.removeAt(oldIndex);
    _currentQueue.insert(newIndex, song);

    final unIdx = _unshuffledQueue.indexWhere((s) => s.id == song.id);
    if (unIdx != -1) {
      final unSong = _unshuffledQueue.removeAt(unIdx);
      final targetUnIdx = newIndex.clamp(0, _unshuffledQueue.length);
      _unshuffledQueue.insert(targetUnIdx, unSong);
    }

    if (_playlist != null) {
      if (_playlistOffset == 0) {
        await _playlist!.move(oldIndex, newIndex);
      } else {
        final savedPosition = player.position;
        await _rebuildSource(
          currentIndex.clamp(0, _currentQueue.length - 1),
          initialPosition: savedPosition,
        );
        if (player.playing) player.play();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 1. Standard Fisher-Yates
  // ---------------------------------------------------------------------------
  Future<void> standardShuffle() async {
    if (_currentQueue.isEmpty) return;
    final currentIndex = this.currentIndex;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final currentSong = _currentQueue[safeIndex];
    final fullPool = _unshuffledQueue.isNotEmpty ? _unshuffledQueue : _currentQueue;
    final pool = fullPool.where((s) => s.id != currentSong.id).toList();
    if (pool.isEmpty) return;
    final shuffled = await compute(standardShuffleIsolate, pool);
    _currentQueue = [currentSong, ...shuffled];
    await _updateQueueAfterAnchor(0);
  }

  // ---------------------------------------------------------------------------
  // 2. Dithered Position Shuffle
  // ---------------------------------------------------------------------------
  Future<void> ditheredPositionShuffle(ShufflePreference preference) async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Dithered Position ($preference)');
    final currentIndex = this.currentIndex;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final currentSong = _currentQueue[safeIndex];
    final fullPool = _unshuffledQueue.isNotEmpty ? _unshuffledQueue : _currentQueue;
    final pool = fullPool.where((s) => s.id != currentSong.id).toList();
    if (pool.isEmpty) return;
    final result = await compute(
      ditheredPositionShuffleIsolate,
      <String, dynamic>{'songs': pool, 'pref': preference.index},
    );
    debugPrint('✅ [SHUFFLE] Dithered result: ${result.length} songs');
    _currentQueue = [currentSong, ...result];
    await _updateQueueAfterAnchor(0);
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
    final currentSong = _currentQueue[safeIndex];
    final fullPool = _unshuffledQueue.isNotEmpty ? _unshuffledQueue : _currentQueue;
    final pool = fullPool.where((s) => s.id != currentSong.id).toList();
    if (pool.isEmpty) return;
    final result = await compute(mergeShuffleIsolate, <String, dynamic>{
      'songs': pool,
      'pref': preference.index,
    });
    debugPrint('✅ [SHUFFLE] Merge result: ${result.length} songs');
    _currentQueue = [currentSong, ...result];
    await _updateQueueAfterAnchor(0);
  }

  // ---------------------------------------------------------------------------
  // 4. Weighted Shuffle
  // ---------------------------------------------------------------------------
  Future<void> youtubeWeightedShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Weighted Shuffle (O(n log n))');
    final currentIndex = this.currentIndex;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final currentSong = _currentQueue[safeIndex];
    final fullPool = _unshuffledQueue.isNotEmpty ? _unshuffledQueue : _currentQueue;
    final pool = fullPool.where((s) => s.id != currentSong.id).toList();
    if (pool.isEmpty) return;
    final shuffled = await compute(weightedShuffleIsolate, pool);
    _currentQueue = [currentSong, ...shuffled];
    await _updateQueueAfterAnchor(0);
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
    final currentSong = _currentQueue[safeIndex];
    final fullPool = _unshuffledQueue.isNotEmpty ? _unshuffledQueue : _currentQueue;
    final pool = fullPool.where((s) => s.id != currentSong.id).toList();
    if (pool.isEmpty) return;
    final result = await compute(albumAwareShuffleIsolate, <String, dynamic>{
      'songs': pool,
      'shuffleTracks': shuffleTracksWithinAlbum,
    });
    debugPrint('✅ [SHUFFLE] Album-Aware result: ${result.length} songs');
    _currentQueue = [currentSong, ...result];
    await _updateQueueAfterAnchor(0);
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
    final currentSong = _currentQueue[safeIndex];
    final fullPool = _unshuffledQueue.isNotEmpty ? _unshuffledQueue : _currentQueue;
    final pool = fullPool.where((s) => s.id != currentSong.id).toList();
    if (pool.isEmpty) return;
    final result = await compute(
      recencyDampenedShuffleIsolate,
      <String, dynamic>{
        'songs': pool,
        'recentIds': _recentlyPlayedIds.toList(),
      },
    );
    _currentQueue = [currentSong, ...result];
    await _updateQueueAfterAnchor(0);
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
    debugPrint('🎵 [NaviAudioHandler] commitSmartLocalOrder: past=${pastAndPresent.length}, future=${orderedFuture.length}');
    for (int i = 0; i < orderedFuture.length; i++) {
      debugPrint('   Next ${i + 1}. ${orderedFuture[i].title}');
    }
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
    // Clamp anchor to the unshuffled queue length — songs added/removed since
    // the last setQueue can make safeIndex exceed _unshuffledQueue.length.
    final rawIndex = _unshuffledQueue.indexWhere((s) => s.id == currentSong.id);
    final anchorIndex = (rawIndex != -1 ? rawIndex : safeIndex).clamp(
      0,
      _currentQueue.length - 1,
    );
    await _updateQueueAfterAnchor(anchorIndex);
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
    debugPrint('🎵 [NaviAudioHandler] computeShuffle: algorithm=$algorithm, poolSize=${pool.length}');
    switch (algorithm) {
      case ShuffleAlgorithm.standard:
        return compute(standardShuffleIsolate, pool);

      case ShuffleAlgorithm.spotify:
        return compute(ditheredPositionShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'pref': preference.index,
        });

      case ShuffleAlgorithm.youtube:
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

      case ShuffleAlgorithm.smartLocal:
        // Already handled externally via player_provider + v3 API.
        // Fall back to standard here if accidentally called.
        return compute(standardShuffleIsolate, pool);
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

  bool _isRecovering = false;
  int? _lastFailedIndex;

  Future<void> _recoverStuckPlayer() async {
    if (_isRecovering) {
      debugPrint('⚡ [NaviAudioHandler] Recovery already in progress. Ignoring re-entrant call.');
      return;
    }
    _isRecovering = true;
    try {
      final int index = currentIndex;
      final Duration pos = player.position;
      final bool wasPlaying = player.playing;

      debugPrint('⚠️ [NaviAudioHandler] Stuck player detected at track index $index, position $pos. Attempting recovery...');

      if (_lastFailedIndex == index) {
        debugPrint('⚠️ [NaviAudioHandler] Track $index already failed once during recovery. Skipping to next track...');
        await _safeSkipToNext(wasPlaying);
        return;
      }
      _lastFailedIndex = index;

      // 1. Stop player to close hung network connections/decoders
      await player.stop();
      await Future.delayed(const Duration(seconds: 1));

      // 2. Re-resolve paths and reload source
      if (_isDesktopBridge) {
        final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
        await _desktopLoadTrack(index, offlinePaths, initialPosition: pos);
      } else {
        await _rebuildSource(index, initialPosition: pos);
      }

      // 3. Resume if it was playing
      if (wasPlaying) {
        await player.play();
      }
      _lastFailedIndex = null;
      debugPrint('✅ [NaviAudioHandler] Stuck player recovery successful!');
    } catch (e) {
      debugPrint('❌ [NaviAudioHandler] Stuck player recovery failed: $e. Skipping to next track...');
      await _safeSkipToNext(player.playing);
    } finally {
      _isRecovering = false;
    }
  }

  Future<void> _safeSkipToNext(bool wasPlaying) async {
    try {
      await skipToNext();
      if (wasPlaying) {
        await player.play();
      }
    } catch (e2) {
      debugPrint('❌ [NaviAudioHandler] Skip to next track failed: $e2. Attempting jumpToIndex...');
      try {
        final nextIdx = (currentIndex + 1).clamp(0, _currentQueue.length - 1);
        await jumpToIndex(nextIdx);
        if (wasPlaying) await player.play();
      } catch (e3) {
        debugPrint('❌ [NaviAudioHandler] jumpToIndex fallback also failed: $e3.');
      }
    }
  }

  Future<void> dispose() async {
    _stuckTimer?.cancel();
    _stuckTimer = null;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _desktopCompletionSub?.cancel();
    _desktopCompletionSub = null;
    await player.stop();
    await player.dispose();
  }
}
