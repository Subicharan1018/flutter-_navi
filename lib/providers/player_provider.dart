import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/subsonic_service.dart';
import '../services/listening_event_collector.dart';
import 'settings_provider.dart';
import '../services/audio_handler.dart';
import '../core/hive_boxes.dart';
import '../core/app_constants.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'library_provider.dart';
import '../services/scrobble_service.dart';

// ---------------------------------------------------------------------------
// Player state — unchanged
// ---------------------------------------------------------------------------
class PlayerState {
  final List<Song> queue;
  final int currentIndex;
  final bool isPlaying;
  final bool shuffleMode;
  final bool autoplayMode;
  final LoopMode repeatMode;
  final List<String> starredIds;
  final List<Song> history;

  static const int maxHistoryLength = AppConstants.playerHistoryMaxLength;

  const PlayerState({
    required this.queue,
    required this.currentIndex,
    required this.isPlaying,
    required this.shuffleMode,
    required this.autoplayMode,
    required this.repeatMode,
    required this.starredIds,
    this.history = const [],
  });

  PlayerState copyWith({
    List<Song>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? shuffleMode,
    bool? autoplayMode,
    LoopMode? repeatMode,
    List<String>? starredIds,
    List<Song>? history,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      autoplayMode: autoplayMode ?? this.autoplayMode,
      repeatMode: repeatMode ?? this.repeatMode,
      starredIds: starredIds ?? this.starredIds,
      history: history ?? this.history,
    );
  }

  List<Song> get historySongs => history;
  Song? get currentSong => queue.isNotEmpty && currentIndex < queue.length
      ? queue[currentIndex]
      : null;
  List<Song> get upNext => queue.isNotEmpty && currentIndex + 1 < queue.length
      ? queue.sublist(currentIndex + 1)
      : const [];
}

// ---------------------------------------------------------------------------
// Player notifier
// ---------------------------------------------------------------------------
class PlayerNotifier extends StateNotifier<PlayerState> {
  final Ref _ref;
  final AudioHandler _audioHandler;
  final SubsonicService _subsonicService;
  final ListeningEventCollector _collector;
  final Set<String> _scrobbledIds = {};
  final List<StreamSubscription> _subscriptions = [];

  bool _isFetchingSimilar = false;
  String? _lastFetchedForSongId;

  Completer<void>? _queueOpLock;
  bool _suppressStreamEvents = false;
  final Set<String> _starTogglingIds = {};
  Timer? _persistTimer;
  Timer? _trackChangeTimer;
  String? _currentPlaylistName;

  Completer<void>? _smartLocalFetchCompleter;

  bool get _isFetchingSmartLocal =>
      _smartLocalFetchCompleter != null &&
      !_smartLocalFetchCompleter!.isCompleted;

  String _nextSourceContext = 'autoplay';
  String _nextTransitionType = 'autoplay';

  PlayerNotifier(
    this._ref,
    this._audioHandler,
    this._subsonicService,
    this._collector,
  ) : super(
        const PlayerState(
          queue: [],
          currentIndex: 0,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: [],
          history: [],
        ),
      ) {
    _syncShuffleUrl();
    _init();
    _loadPersistedState();
  }

  int _pendingSeekMs = 0;

  void _loadPersistedState() {
    final s = HiveBoxes.session;
    final p = HiveBoxes.prefs;
    _pendingSeekMs = s.get(HiveBoxes.kLastPositionMs, defaultValue: 0) as int;
    final shuffle =
        p.get(HiveBoxes.kShufflePreference, defaultValue: false) as bool;
    final repeatIdx = p.get('repeatMode', defaultValue: 0) as int;
    state = state.copyWith(
      shuffleMode: shuffle,
      repeatMode:
          LoopMode.values[repeatIdx.clamp(0, LoopMode.values.length - 1)],
    );
  }

  void _persistState() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), () {
      final s = HiveBoxes.session;
      final p = HiveBoxes.prefs;
      if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
        s.put(HiveBoxes.kCurrentTrackId, state.queue[state.currentIndex].id);
      }
      s.put(HiveBoxes.kLastPositionMs, player.position.inMilliseconds);
      p.put(HiveBoxes.kShufflePreference, state.shuffleMode);
      p.put('repeatMode', state.repeatMode.index);
    });
  }

  AudioPlayer get player => _audioHandler.player;

  void _syncShuffleUrl() {
    final url = _ref.read(settingsProvider).localShuffleUrl;
    _audioHandler.updateShuffleBaseUrl(url);
  }

  Duration _scrobbleThreshold = Duration.zero;
  bool _hasScrobbled = false;
  String? _currentScrobbleSongId;
  Duration _scrobbleListenDuration = Duration.zero;
  DateTime? _scrobblePlayStart;
  Duration _lastKnownPosition = Duration.zero;
  int _lastKnownIndex = 0;
  bool _isShuffling = false;
  bool get isShuffling => _isShuffling;
  int _lastPersistSecond = -1;

  void _init() {
    _lastKnownIndex = player.currentIndex ?? 0;

    _subscriptions.add(
      player.currentIndexStream.listen((index) {
        if (index == null) return;
        if (_suppressStreamEvents) return;

        final prevIndex = _lastKnownIndex;
        final positionAtSwitch = _lastKnownPosition;
        final settings = _ref.read(settingsProvider);
        final analyticsEnabled = settings.dataCollectionEnabled;

        final Song? prevSong = prevIndex >= 0 && prevIndex < state.queue.length
            ? state.queue[prevIndex]
            : null;
        final Song? newSong = index >= 0 && index < state.queue.length
            ? state.queue[index]
            : null;

        if (index == prevIndex && state.repeatMode != LoopMode.one) return;

        _lastKnownIndex = index;

        if (analyticsEnabled && newSong != null) {
          final sourceCtx = _nextSourceContext;
          final transCtx = _nextTransitionType;
          _nextSourceContext = 'autoplay';
          _nextTransitionType = 'autoplay';

          _trackChangeTimer?.cancel();
          final capturedPrev = prevSong;
          final capturedNew = newSong;
          final capturedPos = positionAtSwitch;
          final capturedIdx = index;
          final capturedShuffle = state.shuffleMode;

          _trackChangeTimer = Timer(const Duration(milliseconds: 200), () {
            _collector.onSongStarted(
              song: capturedNew,
              sourceContext: sourceCtx,
              transitionType: transCtx,
              prevSong: capturedPrev,
              positionAtSwitch: capturedPos,
              queuePosition: capturedIdx,
              shuffleActive: capturedShuffle,
            );
          });

          _hasScrobbled = false;
          _currentScrobbleSongId = newSong.id;
          _scrobbleListenDuration = Duration.zero;
          _scrobblePlayStart = player.playing ? DateTime.now() : null;
          _scrobbleThreshold = Duration(seconds: newSong.duration) * 0.5;

          _ref.read(scrobbleServiceProvider).nowPlaying(newSong.id);
          _ref
              .read(recommendationProvider)
              .trackSongPlay(
                newSong,
                durationPlayed: positionAtSwitch.inSeconds,
                completed:
                    prevSong != null &&
                    positionAtSwitch.inSeconds >
                        (prevSong.duration * 0.8).toInt(),
              );
          _audioHandler.refreshReplayGain();
        }

        if (!_suppressNextHistoryPush &&
            index > prevIndex &&
            prevIndex < state.queue.length &&
            positionAtSwitch.inSeconds >= 2) {
          _pushToHistory(state.queue[prevIndex]);
        }
        _suppressNextHistoryPush = false;
        _lastKnownPosition = Duration.zero;

        state = state.copyWith(currentIndex: index);

        final isSmartLocal =
            settings.shuffleAlgorithm == ShuffleAlgorithm.smartLocal &&
            state.shuffleMode;

        if ((state.autoplayMode || isSmartLocal) && state.queue.isNotEmpty) {
          final queueLen = state.queue.length;
          if (index >= queueLen - 3) {
            if (isSmartLocal) {
              _triggerSmartLocalFetchIfNeeded();
            } else {
              _triggerAutoplayIfNeeded();
            }
          }
        }
      }),
    );

    _subscriptions.add(
      player.playingStream.listen((playing) {
        if (_suppressStreamEvents) return;

        if (playing && _scrobblePlayStart == null) {
          _scrobblePlayStart = DateTime.now();
        } else if (!playing && _scrobblePlayStart != null) {
          _scrobbleListenDuration +=
              DateTime.now().difference(_scrobblePlayStart!);
          _scrobblePlayStart = null;
        }

        state = state.copyWith(isPlaying: playing);
      }),
    );

    _subscriptions.add(
      player.loopModeStream.listen((loopMode) {
        state = state.copyWith(repeatMode: loopMode);
      }),
    );

    _subscriptions.add(
      player.processingStateStream.listen((ps) async {
        if (ps != ProcessingState.completed) return;
        if (_suppressStreamEvents) return;

        if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
          _collector.onSongEnded(
            state.queue[state.currentIndex],
            player.position,
          );
        }
        if (!state.autoplayMode) return;
        if (state.currentIndex < state.queue.length - 1) return;
        _triggerAutoplayIfNeeded();
      }),
    );

    Duration prevPosition = Duration.zero;
    _subscriptions.add(
      player.positionStream.listen((position) {
        if (player.currentIndex == _lastKnownIndex) {
          _lastKnownPosition = position;
        }
        final posSec = position.inSeconds;
        if (posSec > 0 && posSec % 5 == 0 && posSec != _lastPersistSecond) {
          _lastPersistSecond = posSec;
          _persistState();
        }

        if (state.queue.isEmpty || state.currentIndex >= state.queue.length) {
          prevPosition = position;
          return;
        }
        final currentSong = state.queue[state.currentIndex];
        final duration = currentSong.duration;

        if (state.repeatMode == LoopMode.one &&
            prevPosition.inSeconds > (duration * 0.5) &&
            position.inSeconds < 2) {
          _collector.onSongRepeated();
        }
        prevPosition = position;

        if (!_hasScrobbled && _currentScrobbleSongId != null) {
          final positionMet = position >= _scrobbleThreshold;
          Duration totalListened = _scrobbleListenDuration;
          if (state.isPlaying && _scrobblePlayStart != null) {
            totalListened += DateTime.now().difference(_scrobblePlayStart!);
          }
          final fourMinMet = totalListened >= const Duration(minutes: 4);

          if (positionMet || fourMinMet) {
            _hasScrobbled = true;
            _ref
                .read(scrobbleServiceProvider)
                .submit(_currentScrobbleSongId!, song: currentSong);
          }
        }
      }),
    );
  }

  bool _suppressNextHistoryPush = false;

  void _pushToHistory(Song song) {
    if (state.history.isNotEmpty && state.history.last.id == song.id) return;
    final updated = [...state.history, song];
    if (updated.length > PlayerState.maxHistoryLength) {
      updated.removeRange(0, updated.length - PlayerState.maxHistoryLength);
    }
    state = state.copyWith(history: updated);
  }

  Song? _popFromHistory() {
    if (state.history.isEmpty) return null;
    final updated = [...state.history];
    final song = updated.removeLast();
    state = state.copyWith(history: updated);
    return song;
  }

  void _clearHistory() {
    state = state.copyWith(history: []);
    _lastFetchedForSongId = null;
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _trackChangeTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _audioHandler.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  Future<void> setQueue(List<Song> songs, int startIndex) async {
    await _queueOpLock?.future;
    final completer = Completer<void>();
    _queueOpLock = completer;
    try {
      _clearHistory();
      _nextSourceContext = 'user_queue';
      _nextTransitionType = 'user_selected';
      _suppressStreamEvents = true;
      state = state.copyWith(queue: songs, currentIndex: startIndex);
      await _audioHandler.setQueue(songs, startIndex);
      _suppressStreamEvents = false;
      if (_pendingSeekMs > 0) {
        try {
          await player.seek(Duration(milliseconds: _pendingSeekMs));
        } catch (_) {}
        _pendingSeekMs = 0;
      }
      player.play();
    } finally {
      _suppressStreamEvents = false;
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  Future<void> playPlaylist(
    List<Song> songs, {
    bool shuffle = false,
    String? playlistName,
  }) async {
    if (songs.isEmpty) return;
    await _queueOpLock?.future;
    final completer = Completer<void>();
    _queueOpLock = completer;
    try {
      _clearHistory();
      _nextSourceContext = 'playlist';
      _nextTransitionType = 'user_selected';
      _currentPlaylistName = playlistName;

      final settings = _ref.read(settingsProvider);

      if (!shuffle) {
        _suppressStreamEvents = true;
        state = state.copyWith(
          shuffleMode: false,
          queue: songs,
          currentIndex: 0,
        );
        await _audioHandler.setQueue(songs, 0, unshuffledSongs: songs);
        _suppressStreamEvents = false;
        player.play();
        return;
      }

      state = state.copyWith(shuffleMode: true);
      _isShuffling = true;
      try {
        final startIndex = Random().nextInt(songs.length);
        final currentSong = songs[startIndex];

        if (settings.shuffleAlgorithm == ShuffleAlgorithm.smartLocal) {
          _suppressStreamEvents = true;

          final pool = List<Song>.from(songs)..removeAt(startIndex);
          final ordered = await _audioHandler.computeShuffle(
            pool,
            ShuffleAlgorithm.smartLocal,
            settings.shufflePreference,
            currentSong: currentSong,
            contextName: playlistName,
          );

          final finalQueue = [currentSong, ...ordered];
          state = state.copyWith(queue: finalQueue, currentIndex: 0);
          await _audioHandler.setQueue(finalQueue, 0, unshuffledSongs: songs);
          _suppressStreamEvents = false;
          player.play();

          _resetSmartLocalSession();
        } else {
          final pool = List<Song>.from(songs)..removeAt(startIndex);
          final shuffled = await _audioHandler.computeShuffle(
            pool,
            settings.shuffleAlgorithm,
            settings.shufflePreference,
            currentSong: currentSong,
            contextName: playlistName,
          );
          if (_queueOpLock != completer) return;
          final finalQueue = [currentSong, ...shuffled];
          _suppressStreamEvents = true;
          state = state.copyWith(queue: finalQueue, currentIndex: 0);
          await _audioHandler.setQueue(finalQueue, 0, unshuffledSongs: songs);
          _suppressStreamEvents = false;
          player.play();
        }
      } finally {
        _isShuffling = false;
      }
    } finally {
      _suppressStreamEvents = false;
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  void _resetSmartLocalSession() {
    final url = _ref.read(settingsProvider).localShuffleUrl;
    if (url.isEmpty) return;
    http
        .get(Uri.parse('$url/session/reset'))
        .catchError((_) {});
  }

  void refreshShuffleUrl() => _syncShuffleUrl();

  Future<void> playNext() async {
    await _queueOpLock?.future;
    if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
      final currentSong = state.queue[state.currentIndex];
      _pushToHistory(currentSong);
      if (_lastKnownPosition.inSeconds < 30) {
        _ref.read(recommendationProvider).trackSkip(currentSong);
      }
    }
    _suppressNextHistoryPush = true;
    _nextTransitionType = 'manual_next';
    _nextSourceContext = 'manual_next';

    try {
      if (player.hasNext) {
        await player.seekToNext();
      } else {
        await _jumpToInternal(
          state.currentIndex < state.queue.length - 1
              ? state.currentIndex + 1
              : 0,
          pushHistory: false,
        );
      }
    } catch (e, stack) {
      debugPrint('playNext failed: $e\n$stack');
      await _jumpToInternal(
        state.currentIndex < state.queue.length - 1
            ? state.currentIndex + 1
            : 0,
        pushHistory: false,
      );
    }
  }

  Future<void> stop() async {
    _hasScrobbled = false;
    _currentScrobbleSongId = null;
    _scrobbleListenDuration = Duration.zero;
    _scrobblePlayStart = null;
    await player.stop();
  }

  Future<void> playPrev() async {
    await _queueOpLock?.future;
    try {
      if (player.position.inSeconds > 3) {
        await player.seek(Duration.zero);
        return;
      }
      final historySong = _popFromHistory();
      if (historySong != null) {
        final historyIndex = state.queue
            .sublist(0, state.currentIndex)
            .lastIndexWhere((s) => s.id == historySong.id);
        if (historyIndex >= 0) {
          _suppressNextHistoryPush = true;
          await player.seek(Duration.zero, index: historyIndex);
          state = state.copyWith(currentIndex: historyIndex);
        } else {
          _suppressNextHistoryPush = true;
          final prevIdx = state.currentIndex > 0 ? state.currentIndex - 1 : 0;
          await player.seek(Duration.zero, index: prevIdx);
          state = state.copyWith(currentIndex: prevIdx);
        }
        return;
      }
      if (player.hasPrevious) {
        _suppressNextHistoryPush = true;
        await player.seekToPrevious();
      } else {
        _suppressNextHistoryPush = true;
        await _jumpToInternal(
          state.currentIndex > 0 ? state.currentIndex - 1 : 0,
          pushHistory: false,
        );
      }
    } catch (e, stack) {
      debugPrint('playPrev failed: $e\n$stack');
      _suppressNextHistoryPush = true;
      await _jumpToInternal(
        state.currentIndex > 0 ? state.currentIndex - 1 : 0,
        pushHistory: false,
      );
    }
  }

  Future<void> jumpTo(int index) async {
    _nextTransitionType = 'user_selected';
    _nextSourceContext = 'user_selected';
    await _jumpToInternal(index, pushHistory: true);
  }

  Future<void> _jumpToInternal(int index, {required bool pushHistory}) async {
    if (pushHistory &&
        state.queue.isNotEmpty &&
        state.currentIndex < state.queue.length) {
      _pushToHistory(state.queue[state.currentIndex]);
    }
    _suppressNextHistoryPush = true;
    await player.seek(Duration.zero, index: index);
    state = state.copyWith(currentIndex: index);
  }

  Future<void> addToQueue(Song song) async {
    final currentQueue = List<Song>.from(state.queue)..add(song);
    state = state.copyWith(queue: currentQueue);
    await _audioHandler.addToQueue(song);
  }

  Future<void> removeFromQueue(int index) async {
    _suppressStreamEvents = true;
    try {
      final currentQueue = List<Song>.from(state.queue)..removeAt(index);
      int newIndex = state.currentIndex;
      if (index < state.currentIndex) {
        newIndex--;
      } else if (index == state.currentIndex && currentQueue.isNotEmpty) {
        if (newIndex >= currentQueue.length) newIndex = 0;
      }
      state = state.copyWith(queue: currentQueue, currentIndex: newIndex);
      await _audioHandler.removeFromQueue(index);
    } finally {
      _suppressStreamEvents = false;
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    _suppressStreamEvents = true;
    try {
      final currentQueue = List<Song>.from(state.queue);
      final item = currentQueue.removeAt(oldIndex);
      currentQueue.insert(newIndex, item);
      int currentIndex = state.currentIndex;
      if (oldIndex == currentIndex) {
        currentIndex = newIndex;
      } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
        currentIndex--;
      } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
        currentIndex++;
      }
      state = state.copyWith(queue: currentQueue, currentIndex: currentIndex);
      await _audioHandler.reorderQueue(
        oldIndex,
        newIndex,
        isShuffleMode: state.shuffleMode,
      );
    } finally {
      _suppressStreamEvents = false;
    }
  }

  Future<void> toggleStar(String songId) async {
    if (_starTogglingIds.contains(songId)) return;
    _starTogglingIds.add(songId);
    try {
      final currentlyStarred = state.starredIds.contains(songId);
      if (currentlyStarred) {
        await _subsonicService.unstar(songId);
        state = state.copyWith(
          starredIds: state.starredIds.where((id) => id != songId).toList(),
          queue: state.queue
              .map((s) => s.id == songId ? s.copyWith(starred: false) : s)
              .toList(),
        );
      } else {
        await _subsonicService.star(songId);
        state = state.copyWith(
          starredIds: [...state.starredIds, songId],
          queue: state.queue
              .map((s) => s.id == songId ? s.copyWith(starred: true) : s)
              .toList(),
        );
      }
    } finally {
      _starTogglingIds.remove(songId);
    }
  }

  Future<void> toggleShuffle() async {
    await setShuffleMode(!state.shuffleMode);
  }

  Future<void> setShuffleMode(bool enabled) async {
    await _queueOpLock?.future;
    state = state.copyWith(shuffleMode: enabled);
    if (enabled) {
      await applyShuffleAlgorithm();
    } else {
      await unshuffleQueue();
    }
  }

  Future<void> unshuffleQueue() async {
    final completer = Completer<void>();
    _queueOpLock = completer;
    _isShuffling = true;
    _suppressStreamEvents = true;
    try {
      await _audioHandler.unshuffle();
      state = state.copyWith(
        queue: _audioHandler.currentQueue,
        currentIndex: _audioHandler.player.currentIndex ?? 0,
      );
    } finally {
      _isShuffling = false;
      _suppressStreamEvents = false;
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  // ---------------------------------------------------------------------------
  // applyShuffleAlgorithm
  //
  // FIX-LOCK-HOLD: For smartLocal, the old code held _queueOpLock for the
  // full duration of the HTTP fetch (up to 5s). This blocked playNext(),
  // removeFromQueue(), and any other op that awaits the lock.
  //
  // New flow for smartLocal:
  //   1. Snapshot anchor state (currentIndex, pastAndPresent, future, seed song).
  //   2. Release _queueOpLock.            ← player ops unblocked immediately
  //   3. Await _computeSmartLocalOrder()  ← HTTP fetch, lock-free
  //   4. Re-acquire _queueOpLock.
  //   5. commitSmartLocalOrder()          ← setAudioSource, fast
  //   6. Release lock.
  //
  // All other algorithms keep the lock for their entire duration because they
  // use compute() (isolate, fast) not a network call.
  // ---------------------------------------------------------------------------
  Future<void> applyShuffleAlgorithm() async {
    final settings = _ref.read(settingsProvider);

    if (settings.shuffleAlgorithm == ShuffleAlgorithm.smartLocal) {
      await _applySmartLocalAlgorithm(settings);
      return;
    }

    // Non-smart-local: hold lock for the full compute() duration (fast, OK).
    final completer = Completer<void>();
    _queueOpLock = completer;
    _isShuffling = true;
    _suppressStreamEvents = true;
    try {
      final savedIndex =
          _audioHandler.player.currentIndex ?? state.currentIndex;

      switch (settings.shuffleAlgorithm) {
        case ShuffleAlgorithm.spotify:
          await _audioHandler.spotifyDitherShuffle(settings.shufflePreference);
          break;
        case ShuffleAlgorithm.youtube:
          await _audioHandler.youtubeWeightedShuffle();
          break;
        case ShuffleAlgorithm.standard:
          await _audioHandler.standardShuffle();
          break;
        case ShuffleAlgorithm.albumAware:
          await _audioHandler.albumAwareShuffle();
          break;
        case ShuffleAlgorithm.mergeShuffle:
          await _audioHandler.mergeShuffle(settings.shufflePreference);
          break;
        case ShuffleAlgorithm.recencyDampened:
          await _audioHandler.recencyDampenedWeightedShuffle();
          break;
        case ShuffleAlgorithm.smartLocal:
          // Unreachable: handled above. Compiler needs exhaustiveness.
          break;
      }

      final postShuffleIndex =
          _audioHandler.player.currentIndex ?? savedIndex;
      state = state.copyWith(
        queue: _audioHandler.currentQueue,
        currentIndex: postShuffleIndex,
      );
    } finally {
      _isShuffling = false;
      _suppressStreamEvents = false;
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  /// Smart Local variant of applyShuffleAlgorithm.
  ///
  /// Releases _queueOpLock before the HTTP fetch so that playNext() and
  /// other player ops are not blocked during the network wait.
  Future<void> _applySmartLocalAlgorithm(SettingsState settings) async {
    // --- Phase 1: snapshot while we may still hold a prior lock ---
    await _queueOpLock?.future;

    _isShuffling = true;
    _suppressStreamEvents = true;

    // Snapshot the anchor state synchronously before releasing any lock.
    final safeIndex = (_audioHandler.player.currentIndex ?? state.currentIndex)
        .clamp(0, _audioHandler.currentQueue.length - 1);
    final pastAndPresent =
        List<Song>.from(_audioHandler.currentQueue.sublist(0, safeIndex + 1));
    final future =
        List<Song>.from(_audioHandler.currentQueue.sublist(safeIndex + 1));
    final currentSong = _audioHandler.currentQueue[safeIndex];

    if (future.isEmpty) {
      _isShuffling = false;
      _suppressStreamEvents = false;
      return;
    }

    // No lock held here — HTTP fetch is lock-free.
    // _suppressStreamEvents stays true so index-change events during the
    // fetch don't fire autoplay triggers mid-reorder.

    List<Song>? ordered;
    try {
      ordered = await _audioHandler.computeSmartLocalOrder(
        currentSong: currentSong,
        future: future,
        contextName: _currentPlaylistName,
      );
    } catch (_) {
      // computeSmartLocalOrder never throws (internal try/catch), but guard.
    }

    if (ordered == null) {
      // Fallback: standard shuffle, which uses compute() and is fast.
      // Re-use the normal lock path for this.
      _isShuffling = false;
      _suppressStreamEvents = false;
      // Patch algorithm temporarily to standard and recurse once.
      // Simpler: just call standardShuffle directly.
      final completer = Completer<void>();
      _queueOpLock = completer;
      _isShuffling = true;
      _suppressStreamEvents = true;
      try {
        await _audioHandler.standardShuffle();
        final postShuffleIndex =
            _audioHandler.player.currentIndex ?? safeIndex;
        state = state.copyWith(
          queue: _audioHandler.currentQueue,
          currentIndex: postShuffleIndex,
        );
      } finally {
        _isShuffling = false;
        _suppressStreamEvents = false;
        completer.complete();
        if (_queueOpLock == completer) _queueOpLock = null;
      }
      return;
    }

    // --- Phase 2: commit — re-acquire lock for setAudioSource ---
    final commitCompleter = Completer<void>();
    _queueOpLock = commitCompleter;
    try {
      // Re-read the live index: the player may have advanced during the fetch.
      final liveIndex = _audioHandler.player.currentIndex ?? safeIndex;
      if (liveIndex != safeIndex) {
        // Player moved while we were fetching. The computed order is now stale
        // relative to the buffer state. Discard it; the lookahead trigger will
        // schedule a fresh fetch if needed.
        debugPrint(
          '⚠️ [applyShuffleAlgorithm] Smart Local: player advanced '
          'during fetch ($safeIndex→$liveIndex), discarding stale order',
        );
        state = state.copyWith(queue: _audioHandler.currentQueue,
            currentIndex: liveIndex);
        return;
      }

      await _audioHandler.commitSmartLocalOrder(
        pastAndPresent: pastAndPresent,
        orderedFuture: ordered,
        anchorIndex: safeIndex,
      );
      _resetSmartLocalSession();

      final postShuffleIndex =
          _audioHandler.player.currentIndex ?? safeIndex;
      state = state.copyWith(
        queue: _audioHandler.currentQueue,
        currentIndex: postShuffleIndex,
      );
    } finally {
      _isShuffling = false;
      _suppressStreamEvents = false;
      commitCompleter.complete();
      if (_queueOpLock == commitCompleter) _queueOpLock = null;
    }
  }

  Future<void> cycleRepeat() async {
    final LoopMode nextMode;
    switch (state.repeatMode) {
      case LoopMode.off:
        nextMode = LoopMode.all;
        break;
      case LoopMode.all:
        nextMode = LoopMode.one;
        break;
      case LoopMode.one:
        nextMode = LoopMode.off;
        break;
    }
    await player.setLoopMode(nextMode);
  }

  Future<void> handleSuggestAction(Song song, bool isMore) async {
    if (isMore) {
      if (!song.starred) await toggleStar(song.id);
      await _subsonicService.setRating(song.id, 5);
    } else {
      if (song.starred) await toggleStar(song.id);
      await _subsonicService.setRating(song.id, 1);
    }
    final settings = _ref.read(settingsProvider);
    if (settings.dataCollectionEnabled) {
      _collector.recordSuggestFeedback(song, isMore);
    }
    _audioHandler.updateSongWeight(song, isMore);
    final updatedSong = _audioHandler.currentQueue
        .where((s) => s.id == song.id)
        .firstOrNull;
    if (updatedSong != null) {
      _collector.persistWeight(updatedSong.id, updatedSong.dynamicWeight);
    }
    state = state.copyWith(queue: _audioHandler.currentQueue);
  }

  Future<void> toggleAutoplay() async {
    final newMode = !state.autoplayMode;
    state = state.copyWith(autoplayMode: newMode);
    if (newMode && state.queue.isNotEmpty) {
      _triggerAutoplayIfNeeded();
    }
  }

  // ---------------------------------------------------------------------------
  // Autoplay — Subsonic similar songs
  // ---------------------------------------------------------------------------

  void _triggerAutoplayIfNeeded() {
    if (!state.autoplayMode || _isFetchingSimilar || state.queue.isEmpty)
      return;

    final currentSong = state.currentSong;
    if (currentSong == null) return;
    if (_lastFetchedForSongId == currentSong.id) return;

    _lastFetchedForSongId = currentSong.id;
    _fetchAndAppendSimilar(currentSong);
  }

  Future<void> _fetchAndAppendSimilar(Song seedSong) async {
    _isFetchingSimilar = true;
    try {
      debugPrint('[AUTOPLAY] Fetching similar songs for: ${seedSong.title}');

      final indexBeforeFetch = state.currentIndex;
      final queueLenBeforeFetch = state.queue.length;

      final similar = await _subsonicService.getSimilarSongs(
        seedSong.id,
        count: 10,
      );
      if (similar.isEmpty) {
        debugPrint('[AUTOPLAY] No similar songs found');
        return;
      }

      final existingIds = state.queue.map((s) => s.id).toSet();
      final fresh = similar.where((s) => !existingIds.contains(s.id)).toList();
      if (fresh.isEmpty) {
        debugPrint('[AUTOPLAY] All similar songs already in queue');
        return;
      }

      final newQueue = [...state.queue, ...fresh];
      state = state.copyWith(queue: newQueue);
      await _audioHandler.addAllToQueue(fresh);

      debugPrint(
        '[AUTOPLAY] Appended ${fresh.length} songs. Queue: ${newQueue.length}',
      );

      final currentIndexNow = state.currentIndex;
      final wasAtEnd = currentIndexNow >= queueLenBeforeFetch - 1;
      final userNavigatedAway = currentIndexNow < indexBeforeFetch;

      if (wasAtEnd &&
          !userNavigatedAway &&
          (player.processingState == ProcessingState.completed ||
              !player.playing)) {
        final nextIndex = queueLenBeforeFetch;
        if (nextIndex < state.queue.length) {
          await player.seek(Duration.zero, index: nextIndex);
          await player.play();
          state = state.copyWith(currentIndex: nextIndex);
        }
      }
    } catch (e) {
      debugPrint('[AUTOPLAY] Failed: $e');
    } finally {
      _isFetchingSimilar = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Smart Local — lookahead feed
  //
  // FIX-CONCURRENT-FETCH: The old flow was two sequential awaited calls:
  //   1. addAllToQueue(candidates)         ← platform channel (~50ms)
  //   2. smartLocalShuffle()               ← HTTP 0–5s + setAudioSource
  //
  // These can partially overlap. The HTTP fetch does not need the candidates
  // to be in the player yet — it only needs the Song list to build the
  // futureMap. So we restructure as:
  //
  //   [concurrent]:
  //     A. _computeSmartLocalOrder(future: [...existingFuture, ...candidates])
  //        ← HTTP fetch, no platform channel
  //     B. addAllToQueue(candidates)
  //        ← platform channel, no HTTP
  //
  //   [after both complete]:
  //     C. commitSmartLocalOrder(...)
  //        ← single setAudioSource with move-based reorder (no rebuffer)
  //
  // This reduces the wall-clock time from
  //   (addAllToQueue latency) + (HTTP latency) + (setAudioSource latency)
  // to
  //   max(addAllToQueue latency, HTTP latency) + (setAudioSource latency).
  //
  // For a 200ms addAllToQueue and 1s HTTP fetch, that is ~1.3s → ~1.2s.
  // For a cold-start 5s HTTP fetch, that is ~5.2s → ~5.05s.
  // The real gain is removing setAudioSource from the hot path by using
  // preferMoveBasedReorder=true, which avoids the anchor rebuffer entirely.
  // ---------------------------------------------------------------------------

  void _triggerSmartLocalFetchIfNeeded() {
    if (_isFetchingSmartLocal || state.queue.isEmpty) return;

    final currentSong = state.currentSong;
    if (currentSong == null) return;
    if (_lastFetchedForSongId == currentSong.id) return;

    _lastFetchedForSongId = currentSong.id;
    _fetchAndReorderSmartLocal(currentSong);
  }

  Future<void> _fetchAndReorderSmartLocal(Song seedSong) async {
    final fetchCompleter = Completer<void>();
    _smartLocalFetchCompleter = fetchCompleter;
    try {
      debugPrint('[SMART LOCAL] Reordering queue for: ${seedSong.title}');

      // Snapshot the anchor state synchronously.
      final safeIndex = (player.currentIndex ?? state.currentIndex)
          .clamp(0, _audioHandler.currentQueue.length - 1);
      final pastAndPresent = List<Song>.from(
        _audioHandler.currentQueue.sublist(0, safeIndex + 1),
      );
      final existingFuture = List<Song>.from(
        _audioHandler.currentQueue.sublist(safeIndex + 1),
      );

      // Build the candidate list: songs from unshuffledQueue not yet in queue.
      final existingIds = state.queue.map((s) => s.id).toSet();
      final candidates = _audioHandler.unshuffledQueue
          .where((s) => !existingIds.contains(s.id))
          .take(20)
          .toList();

      // The full future the model will order = existing future + candidates.
      final fullFuture = [...existingFuture, ...candidates];

      if (fullFuture.isEmpty) {
        debugPrint('[SMART LOCAL] No candidates to add or reorder');
        return;
      }

      // FIX-CONCURRENT-FETCH: run HTTP fetch and playlist append concurrently.
      // _computeSmartLocalOrder only needs fullFuture (a List<Song> snapshot);
      // it does not touch the player. addAllToQueue only touches the playlist
      // append; it does not need the HTTP result. They are independent.
      final results = await Future.wait([
        // A: HTTP fetch — returns List<Song>? (null = fallback needed)
        _audioHandler.computeSmartLocalOrder(
          currentSong: seedSong,
          future: fullFuture,
          contextName: _currentPlaylistName,
        ),
        // B: Incremental append — returns void, cast to Object? for Future.wait
        candidates.isNotEmpty
            ? _audioHandler.addAllToQueue(candidates).then((_) {
                // Mirror the state update that was previously done after addAllToQueue.
                final newQueue = [...state.queue, ...candidates];
                state = state.copyWith(queue: newQueue);
                debugPrint('[SMART LOCAL] Appended ${candidates.length} candidates');
                return null;
              })
            : Future.value(null),
      ]);

      final ordered = results[0] as List<Song>?;

      if (ordered == null) {
        // HTTP failed. The candidates are already appended. Queue is longer
        // but unordered past the current position — acceptable fallback.
        debugPrint('[SMART LOCAL] HTTP fetch failed; candidates appended, no reorder');
        return;
      }

      // FIX: Check if the player has moved while we were fetching.
      final liveIndex = player.currentIndex ?? safeIndex;
      if (liveIndex != safeIndex) {
        debugPrint(
          '[SMART LOCAL] Player advanced during fetch '
          '($safeIndex→$liveIndex), discarding stale order',
        );
        // Update state to reflect the appended candidates even if we skip reorder.
        state = state.copyWith(queue: _audioHandler.currentQueue);
        return;
      }

      // Phase 2: commit with move-based reorder to avoid anchor rebuffer.
      // The candidates are already in _playlist via addAllToQueue above, so
      // the move-based reorder only shuffles existing playlist entries —
      // no setAudioSource call needed.
      await _audioHandler.commitSmartLocalOrder(
        pastAndPresent: pastAndPresent,
        orderedFuture: ordered,
        anchorIndex: safeIndex,
        preferMoveBasedReorder: true, // no rebuffer while audio is live
      );

      state = state.copyWith(queue: _audioHandler.currentQueue);
      debugPrint(
        '[SMART LOCAL] Reorder complete. Queue: ${state.queue.length}',
      );
    } catch (e) {
      debugPrint('[SMART LOCAL] Failed: $e');
    } finally {
      fetchCompleter.complete();
    }
  }

  void clearHistory() => _clearHistory();
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final audioHandlerProvider = Provider<AudioHandler>((ref) {
  final service = ref.watch(subsonicServiceProvider);
  final replayGain = ref.watch(replayGainProvider);
  return AudioHandler(service, replayGainService: replayGain);
});

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((
  ref,
) {
  final handler = ref.watch(audioHandlerProvider);
  final service = ref.watch(subsonicServiceProvider);
  final collector = ref.watch(listenerCollectorProvider);
  return PlayerNotifier(ref, handler, service, collector);
});