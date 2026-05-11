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

  // FIX-RACE-1: Replaced _autoplayTriggeredFor Set with a single
  // _lastFetchedForSongId. The old Set grew forever and never got cleared
  // properly across sessions, which meant autoplay could silently stop
  // triggering after a queue clear. A single ID is easier to reason about.
  String? _lastFetchedForSongId;

  Completer<void>? _queueOpLock;
  bool _suppressStreamEvents = false;
  final Set<String> _starTogglingIds = {};
  Timer? _persistTimer;
  Timer? _trackChangeTimer;
  String? _currentPlaylistName;

  // FIX-RACE-2: _isFetchingSmartLocal moved to a Completer so callers can
  // await it, preventing the race where _isFetchingSmartLocal was set to
  // false in finally before the state update that follows it completes.
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

  /// Reads the current shuffle server URL from settings and pushes it into
  /// [AudioHandler]. Call after settings change to reflect the new URL
  /// without rebuilding the entire provider.
  void _syncShuffleUrl() {
    final url = _ref.read(settingsProvider).localShuffleUrl;
    _audioHandler.updateShuffleBaseUrl(url);
  }

  Duration _scrobbleThreshold = Duration.zero;
  bool _hasScrobbled = false;
  String? _currentScrobbleSongId;
  // BUG-2 FIX: Replaced per-tick DateTime accumulation with play/pause
  // transition tracking. _scrobbleListenDuration tracks wall-clock time
  // the player was actually in the Playing state (for the 4-min rule).
  // _scrobblePlayStart is set when play starts, nulled when paused/stopped.
  Duration _scrobbleListenDuration = Duration.zero;
  DateTime? _scrobblePlayStart;
  Duration _lastKnownPosition = Duration.zero;
  int _lastKnownIndex = 0;
  bool _isShuffling = false;
  bool get isShuffling => _isShuffling;
  // BUG-5 FIX: Deduplicate _persistState() calls — only fire once per
  // 5-second boundary instead of on every position tick within that second.
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

          // BUG-1 FIX: Wire the timer callback to actually call
          // _collector.onSongStarted(). The 200ms debounce prevents
          // counting rapid index changes (e.g. during seek) as separate
          // song transitions.
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
          // BUG-2 FIX: Reset accumulated listen time for the new song.
          _scrobbleListenDuration = Duration.zero;
          // BUG-2 GAPLESS FIX: Use player.playing (not state.isPlaying)
          // because in gapless auto-advance the player is already playing when
          // this index-change fires, but state.isPlaying may not reflect that
          // yet (the state update from playingStream could arrive later).
          _scrobblePlayStart = player.playing ? DateTime.now() : null;

          // BUG-2 FIX (REVISED): _scrobbleThreshold is purely 50% of track
          // duration. The 4-minute rule is handled separately via
          // _scrobbleListenDuration in the positionStream listener.
          // Do NOT restore the old min(50%, 4min) logic here.
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

        // ---------------------------------------------------------------------------
        // FIX-AUTOPLAY: Lookahead trigger
        //
        // OLD: Used _autoplayTriggeredFor.contains(lastSong.id) to guard, but
        //      lastSong = queue.last which changes after every smartLocal fetch
        //      because the queue gets reordered. This caused the guard to always
        //      miss, triggering a new fetch on every track change near the end.
        //
        // NEW: Use _lastFetchedForSongId which tracks the SEED song ID used in
        //      the most recent fetch, not the last song in the queue.
        // ---------------------------------------------------------------------------
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

        // BUG-2 FIX: Track play/pause transitions for the scrobble
        // 4-minute actual-listening-time rule. Accumulate wall-clock
        // time only on pause (or stop) events — not on every position tick.
        //
        // Use _scrobblePlayStart != null as the "was playing" check instead
        // of state.isPlaying. state.isPlaying is updated by this same
        // listener after this block — so reading it here gives the *new*
        // value only if Dart's event loop has already applied it, which is
        // not guaranteed on the very first emission (app init / unpause).
        if (playing && _scrobblePlayStart == null) {
          // Transition: paused → playing. Start the clock.
          _scrobblePlayStart = DateTime.now();
        } else if (!playing && _scrobblePlayStart != null) {
          // Transition: playing → paused. Accumulate elapsed time.
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
        // BUG-5 FIX: Only call _persistState() once per 5-second boundary.
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

        // BUG-2 FIX: Hybrid scrobble check per Last.fm spec.
        // Scrobble fires when EITHER condition is met first:
        //   A) player.position >= 50% of track duration
        //   B) actual listening time >= 4 minutes
        // Condition A uses the player's reported position (handles seeks).
        // Condition B uses wall-clock accumulation via play/pause transitions
        // (avoids per-tick drift from the old DateTime.now() approach).
        if (!_hasScrobbled && _currentScrobbleSongId != null) {
          // Condition A: position-based (50% check)
          final positionMet = position >= _scrobbleThreshold;

          // Condition B: actual listening time (4-min check)
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
    // FIX-RACE-1: Reset the fetch guard on queue clear so autoplay/smartLocal
    // can trigger fresh fetches for the new queue.
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
          // ---------------------------------------------------------------------------
          // FIX-SMART-LOCAL-FLOW:
          //
          // OLD flow (broken):
          //   1. setQueue([currentSong], 0)         ← 1-song queue
          //   2. player.play()
          //   3. _triggerSmartLocalFetchIfNeeded()  ← fetches Subsonic similar songs
          //   4. _fetchAndAppendSmartLocal()        ← appends them
          //   5. smartLocalShuffle()                ← tries to match Subsonic songs
          //                                            against Python model → always fails
          //
          // NEW flow (correct):
          //   1. Compute the smart local ordered queue BEFORE setting it
          //   2. Use the full songs list as the pool for the Python model
          //   3. setQueue with the ordered result
          //   4. No separate fetch needed — the model already picked from the full library
          // ---------------------------------------------------------------------------
          _suppressStreamEvents = true;

          // Remove startIndex song from pool and pass rest to model
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

          // Notify Python server to reset session exclusions for this new queue
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

  /// Reset the Python server's session exclusion list for this client.
  /// Called when a new queue is loaded so the model doesn't block songs
  /// from the previous session.
  void _resetSmartLocalSession() {
    final url = _ref.read(settingsProvider).localShuffleUrl;
    if (url.isEmpty) return;
    http
        .get(Uri.parse('$url/session/reset'))
        .catchError((_) {}); // fire and forget, non-critical
  }

  /// Re-syncs the shuffle server URL into [AudioHandler].
  /// Call this whenever the relevant settings change at runtime.
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

  Future<void> applyShuffleAlgorithm() async {
    final completer = Completer<void>();
    _queueOpLock = completer;
    _isShuffling = true;
    _suppressStreamEvents = true;
    try {
      final savedIndex =
          _audioHandler.player.currentIndex ?? state.currentIndex;
      final settings = _ref.read(settingsProvider);

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
        // FIX-SMART-LOCAL-TOGGLE: When toggling smart local shuffle on from
        // the now-playing screen (not from playPlaylist), we reorder the
        // EXISTING queue using the model rather than dropping it to 1 song
        // and triggering a separate fetch. This means the user gets an
        // immediately reordered queue rather than a jarring single-song flash.
        case ShuffleAlgorithm.smartLocal:
          await _audioHandler.smartLocalShuffle();
          _resetSmartLocalSession();
          break;
      }

      // BUG-4 FIX: Read the player's currentIndex AFTER shuffle completes,
      // not the stale savedIndex captured before the shuffle. The shuffle
      // reorders the queue so the old index points to the wrong song.
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

    // FIX-RACE-1: Guard on the current song, not the last song in the queue.
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
  // FIX-SMART-LOCAL-LOOKAHEAD:
  //
  // OLD: _fetchAndAppendSmartLocal() called getSimilarSongs() (Subsonic) to
  //      get candidates, then called smartLocalShuffle() to order them.
  //      This was wrong because:
  //        a) The Subsonic similar-songs list is different from the Python
  //           model's song index — song keys don't match.
  //        b) smartLocalShuffle() reorders the FUTURE slice, not the appended
  //           songs specifically, causing double-reordering.
  //
  // NEW: The lookahead just appends more songs from the full unshuffled
  //      library (via _audioHandler.unshuffledQueue) and then calls
  //      smartLocalShuffle() once to reorder the whole future queue.
  //      The model picks the best order from whatever songs are present.
  // ---------------------------------------------------------------------------

  void _triggerSmartLocalFetchIfNeeded() {
    if (_isFetchingSmartLocal || state.queue.isEmpty) return;

    // FIX-RACE-1: Guard on current song, not queue.last
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

      // Get songs from the unshuffled library that aren't in the queue yet
      final existingIds = state.queue.map((s) => s.id).toSet();
      final unshuffled = _audioHandler.unshuffledQueue;
      final candidates = unshuffled
          .where((s) => !existingIds.contains(s.id))
          .take(20) // add up to 20 more songs as fresh candidates
          .toList();

      if (candidates.isNotEmpty) {
        // Append fresh candidates first
        final newQueue = [...state.queue, ...candidates];
        state = state.copyWith(queue: newQueue);
        await _audioHandler.addAllToQueue(candidates);
        debugPrint('[SMART LOCAL] Appended ${candidates.length} candidates');
      }

      // Now reorder the whole future using the Python model
      // smartLocalShuffle() handles the network call with a 5s timeout
      await _audioHandler.smartLocalShuffle();
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
