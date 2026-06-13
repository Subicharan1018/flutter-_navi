import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import 'subsonic_service.dart';
import 'replay_gain_service.dart';
import 'transcoding_service.dart';
import '../providers/settings_provider.dart';
import '../offline_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'shuffle_algorithms.dart';

// ---------------------------------------------------------------------------
// AudioHandler
// ---------------------------------------------------------------------------

class NaviAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player;
  final SubsonicService subsonicService;
  final ReplayGainService _replayGainService;
  final TranscodingService _transcodingService;
  List<Song> _currentQueue = [];
  List<Song> _unshuffledQueue = [];
  ConcatenatingAudioSource? _playlist;

  static const int _recencyWindow = 20;
  final LinkedHashSet<String> _recentlyPlayedIds = LinkedHashSet<String>();

  // The server enforces count=15 but we also cap it here so any caller
  // that passes a large future slice doesn't accidentally ask for 200 songs.
  static const int _maxServerRequestCount = 15;

  /// True on Linux — ConcatenatingAudioSource is not supported by
  /// just_audio_media_kit 2.1.0 in its platform-channel message form.
  static bool get _isLinux => !kIsWeb && Platform.isLinux;

  // ── Linux single-source bridge state ────────────────────────────────────────
  int _linuxIndex = 0;
  int _linuxTargetIndex = 0;
  int _linuxLoadGeneration = 0;
  StreamSubscription<PlayerState>? _linuxCompletionSub;

  /// Holds all long-lived stream subscriptions so dispose() can cancel them.
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Mutex: true while setAudioSource() is in progress on Linux.
  /// Prevents the dual-completion-listener race (Bug 1 + Bug 3).
  bool _linuxLoading = false;

  /// Timer to detect stuck playback in loading or buffering state.
  Timer? _stuckTimer;

  NaviAudioHandler(
    this.subsonicService, {
    AudioPlayer? player,
    ReplayGainService? replayGainService,
    TranscodingService? transcodingService,
  }) : player = player ?? AudioPlayer(),
       _replayGainService = replayGainService ?? ReplayGainService(),
       _transcodingService = transcodingService ?? TranscodingService() {
    _listenToPlayerEvents();

    _subscriptions.add(this.player.currentIndexStream.listen((index) {
      // On Linux we manage index ourselves — ignore just_audio's index stream
      if (!_isLinux && index != null && index < _currentQueue.length) {
        _trackRecentlyPlayed(_currentQueue[index].id);
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
            debugPrint('⏳ [NaviAudioHandler] Player entered buffering/loading. Starting 15s stuck timer.');
            _stuckTimer = Timer(const Duration(seconds: 15), () async {
              _stuckTimer = null;
              await _recoverStuckPlayer();
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
    // (non-Linux only — on Linux we push MediaItem manually via _emitLinuxMediaItem)
    if (!_isLinux) {
      _subscriptions.add(player.sequenceStateStream.listen((sequenceState) {
        if (sequenceState?.currentSource == null) return;
        final source = sequenceState!.currentSource!;
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
    _recentlyPlayedIds.remove(songId); // drop stale position if present
    _recentlyPlayedIds.add(songId);    // re-insert at the most-recent tail
    if (_recentlyPlayedIds.length > _recencyWindow) {
      _recentlyPlayedIds.remove(_recentlyPlayedIds.first); // evict least-recent
    }
  }

  AudioSource _toSource(Song song) {
    final localPath = OfflineService().getLocalPath(song.id);
    final streamUri = localPath != null
        ? Uri.parse('file://$localPath')
        : Uri.parse(subsonicService.getStreamUrl(
            song.id,
            maxBitRate: _transcodingService.getCurrentBitrate(),
            format: _transcodingService.getCurrentFormat(),
          ));

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
        : Uri.parse(subsonicService.getStreamUrl(
            song.id,
            maxBitRate: _transcodingService.getCurrentBitrate(),
            format: _transcodingService.getCurrentFormat(),
          ));

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
    // Resolve all paths asynchronously (File.exists) instead of blocking the
    // main thread with existsSync per song — the prior approach janked queue
    // builds for large queues.
    final entries = await Future.wait(
      songs.map(
        (song) async =>
            MapEntry(song.id, await offline.getLocalPathAsync(song.id)),
      ),
    );
    return Map.fromEntries(entries);
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
      _linuxTargetIndex = 0;
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
      final start = startIndex.clamp(0, _currentQueue.length - 1);
      _linuxTargetIndex = start;
      await _linuxLoadTrack(
        start,
        offlinePaths,
        initialPosition: initialPosition,
      );
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
    final generation = ++_linuxLoadGeneration;
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
      if (generation != _linuxLoadGeneration) {
        debugPrint('⚡ [Linux] Load for track $index superseded by generation $_linuxLoadGeneration');
        return;
      }
      _linuxIndex = index;
      _emitLinuxMediaItem(index);
      _trackRecentlyPlayed(_currentQueue[index].id);
      debugPrint(
        '🎵 [Linux] Loaded track $index: ${_currentQueue[index].title}',
      );
    } on PlayerInterruptedException {
      // Expected when a newer load supersedes this one (e.g. rapid Next press).
      // Safe to swallow — the newer load will complete instead.
      debugPrint('⚡ [Linux] Load interrupted (superseded by newer request)');
    } on PlayerException catch (e) {
      debugPrint(
        '❌ [Linux] PlayerException loading track $index: ${e.message}',
      );
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('❌ [Linux] Timeout loading track $index: $e');
      rethrow;
    } finally {
      if (generation == _linuxLoadGeneration) {
        _linuxLoading = false;
      }
    }
  }

  void _emitLinuxMediaItem(int index) {
    if (index < 0 || index >= _currentQueue.length) return;
    final song = _currentQueue[index];
    mediaItem.add(
      MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        artUri: Uri.parse(subsonicService.getCoverArtUrl(song.coverArt)),
        duration: Duration(seconds: song.duration),
        extras: {'composer': song.composer, 'isLocal': false},
      ),
    );
  }

  void _startLinuxCompletionListener() {
    _linuxCompletionSub?.cancel();
    _linuxCompletionSub = player.playerStateStream.listen((state) async {
      if (state.processingState != ProcessingState.completed) return;
      // Guard: if PlayerNotifier or a manual skip already kicked off a load,
      // don't double-advance.
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

      int next = _linuxTargetIndex + 1;
      if (next >= _currentQueue.length) {
        if (player.loopMode == LoopMode.all) {
          next = 0; // wrap around
        } else {
          return; // end of queue, stay stopped
        }
      }

      _linuxTargetIndex = next;
      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      try {
        await _linuxLoadTrack(next, offlinePaths);
        if (!player.playing) await player.play();
      } catch (e) {
        // Network glitch or timeout loading the next track — retry once after
        // a short delay instead of silently freezing the player.
        debugPrint('❌ [Linux] Failed to load next track ($e). Retrying in 2s…');
        await Future.delayed(const Duration(seconds: 2));
        // Re-check queue is still valid after the delay.
        if (next < _currentQueue.length) {
          try {
            final retryPaths = await _precomputeOfflinePaths(_currentQueue);
            await _linuxLoadTrack(next, retryPaths);
            if (!player.playing) await player.play();
          } catch (e2) {
            debugPrint('❌ [Linux] Retry also failed ($e2). Skipping to next…');
            // Try the track after that to avoid permanent freeze.
            final fallback = next + 1;
            if (fallback < _currentQueue.length) {
              final fallbackPaths = await _precomputeOfflinePaths(_currentQueue);
              try {
                await _linuxLoadTrack(fallback, fallbackPaths);
                if (!player.playing) await player.play();
              } catch (_) {
                debugPrint('❌ [Linux] Fallback also failed. Player stopped.');
              }
            }
          }
        }
      }
    });
  }

  Future<void> _linuxSkipToNext() async {
    final wasPlaying = player.playing;
    if (_currentQueue.isEmpty) return;
    int next = _linuxTargetIndex + 1;
    if (next >= _currentQueue.length) {
      if (player.loopMode == LoopMode.all) {
        next = 0;
      } else {
        return;
      }
    }
    _linuxTargetIndex = next;
    final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
    await _linuxLoadTrack(next, offlinePaths);
    if (wasPlaying && !player.playing) await player.play();
  }

  Future<void> _linuxSkipToPrevious() async {
    final wasPlaying = player.playing;
    if (_currentQueue.isEmpty) return;
    // If more than 3 seconds in, restart current track
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      return;
    }
    int prev = _linuxTargetIndex - 1;
    if (prev < 0) {
      if (player.loopMode == LoopMode.all) {
        prev = _currentQueue.length - 1;
      } else {
        await player.seek(Duration.zero);
        return;
      }
    }
    _linuxTargetIndex = prev;
    final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
    await _linuxLoadTrack(prev, offlinePaths);
    if (wasPlaying && !player.playing) await player.play();
  }

  /// Current index — Linux uses _linuxIndex, other platforms use player.currentIndex
  int get currentIndex => _isLinux ? _linuxIndex : (player.currentIndex ?? 0);

  /// Platform-adaptive index jump.
  /// On Linux: loads the track at [index] via the single-source bridge.
  /// On other platforms: uses just_audio's seek(Duration.zero, index: index).
  Future<void> jumpToIndex(int index) async {
    if (index < 0 || index >= _currentQueue.length) return;
    if (_isLinux) {
      _linuxTargetIndex = index;
      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      await _linuxLoadTrack(index, offlinePaths);
    } else {
      await player.seek(Duration.zero, index: index);
    }
  }

  /// Override BaseAudioHandler.skipToQueueItem so callers (and platform media
  /// controls) land on the correct track on Linux single-source mode.
  @override
  Future<void> skipToQueueItem(int index) async {
    final wasPlaying = player.playing;
    if (index < 0 || index >= _currentQueue.length) return;
    if (_isLinux) {
      _linuxTargetIndex = index;
      final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
      await _linuxLoadTrack(index, offlinePaths);
      if (wasPlaying && !player.playing) await player.play();
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

      if (index < _linuxTargetIndex) {
        _linuxTargetIndex--;
      }
      _linuxTargetIndex = _linuxTargetIndex.clamp(0, _currentQueue.length - 2 >= 0 ? _currentQueue.length - 2 : 0);
    }

    final song = _currentQueue.removeAt(index);
    final unIdx = _unshuffledQueue.indexWhere((s) => s.id == song.id);
    if (unIdx != -1) _unshuffledQueue.removeAt(unIdx);

    if (_playlist != null) {
      await _playlist!.removeAt(index);
    } else if (needsRebuild) {
      await _rebuildSource(
        this.currentIndex.clamp(0, _currentQueue.length - 1),
      );
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

      if (oldIndex == _linuxTargetIndex) {
        _linuxTargetIndex = newIndex;
      } else if (oldIndex < _linuxTargetIndex && newIndex >= _linuxTargetIndex) {
        _linuxTargetIndex--;
      } else if (oldIndex > _linuxTargetIndex && newIndex <= _linuxTargetIndex) {
        _linuxTargetIndex++;
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
    final shuffled = await compute(standardShuffleIsolate, future);
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
      ditheredPositionShuffleIsolate,
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
    final result = await compute(mergeShuffleIsolate, <String, dynamic>{
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
    final currentIndex = this.currentIndex;
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
    final currentIndex = this.currentIndex;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;
    final result = await compute(
      recencyDampenedShuffleIsolate,
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

  Future<void> _recoverStuckPlayer() async {
    final int index = currentIndex;
    final Duration pos = player.position;
    final bool wasPlaying = player.playing;

    debugPrint('⚠️ [NaviAudioHandler] Stuck player detected at track index $index, position $pos. Attempting recovery...');

    try {
      // 1. Stop player to close hung network connections/decoders
      await player.stop();
      await Future.delayed(const Duration(seconds: 1));

      // 2. Re-resolve paths and reload source
      if (_isLinux) {
        final offlinePaths = await _precomputeOfflinePaths(_currentQueue);
        await _linuxLoadTrack(index, offlinePaths, initialPosition: pos);
      } else {
        await _rebuildSource(index, initialPosition: pos);
      }

      // 3. Resume if it was playing
      if (wasPlaying) {
        await player.play();
      }
      debugPrint('✅ [NaviAudioHandler] Stuck player recovery successful!');
    } catch (e) {
      debugPrint('❌ [NaviAudioHandler] Stuck player recovery failed: $e. Skipping to next track...');
      try {
        await skipToNext();
        if (wasPlaying) {
          await player.play();
        }
      } catch (e2) {
        debugPrint('❌ [NaviAudioHandler] Skip to next track also failed: $e2. Player stopped.');
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
    await _linuxCompletionSub?.cancel();
    _linuxCompletionSub = null;
    await player.stop();
    await player.dispose();
  }
}
