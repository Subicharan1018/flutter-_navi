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
// Player state
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
  Song? get currentSong =>
      queue.isNotEmpty && currentIndex < queue.length
          ? queue[currentIndex]
          : null;
  List<Song> get upNext =>
      queue.isNotEmpty && currentIndex + 1 < queue.length
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
  final Set<String> _autoplayTriggeredFor = {};

  // Serialization lock for queue/shuffle operations.
  Completer<void>? _queueOpLock;

  // Suppresses stream listener processing during audio source rebuilds.
  bool _suppressStreamEvents = false;

  // Prevents concurrent toggleStar calls for the same song ID.
  final Set<String> _starTogglingIds = {};

  // Debounce timer for _persistState to avoid Hive write races.
  Timer? _persistTimer;

  // ── Analytics: debounced track-change timer ──────────────────────────────
  // CRITICAL FIX: We must snapshot prevSong, newSong, sourceCtx, transCtx,
  // and positionAtSwitch SYNCHRONOUSLY inside the index-change handler —
  // before _lastKnownPosition is zeroed — then fire the collector call after
  // the debounce window.  The old code captured _lastKnownPosition inside the
  // timer callback, by which time it had already been reset to Duration.zero.
  Timer? _trackChangeTimer;
  String? _currentPlaylistName;
  bool _isFetchingSmartLocal = false;
  String _nextSourceContext = 'autoplay';
  String _nextTransitionType = 'autoplay';

  PlayerNotifier(
      this._ref, this._audioHandler, this._subsonicService, this._collector)
      : super(const PlayerState(
          queue: [],
          currentIndex: 0,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: [],
          history: [],
        )) {
    _init();
    _loadPersistedState();
  }

  int _pendingSeekMs = 0;

  void _loadPersistedState() {
    final s = HiveBoxes.session;
    final p = HiveBoxes.prefs;

    _pendingSeekMs =
        s.get(HiveBoxes.kLastPositionMs, defaultValue: 0) as int;
    final shuffle =
        p.get(HiveBoxes.kShufflePreference, defaultValue: false) as bool;
    final repeatIdx = p.get('repeatMode', defaultValue: 0) as int;

    state = state.copyWith(
      shuffleMode: shuffle,
      repeatMode: LoopMode.values[
          repeatIdx.clamp(0, LoopMode.values.length - 1)],
    );
  }

  void _persistState() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), () {
      final s = HiveBoxes.session;
      final p = HiveBoxes.prefs;

      if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
        final currentSong = state.queue[state.currentIndex];
        s.put(HiveBoxes.kCurrentTrackId, currentSong.id);
      }
      s.put(HiveBoxes.kLastPositionMs, player.position.inMilliseconds);
      p.put(HiveBoxes.kShufflePreference, state.shuffleMode);
      p.put('repeatMode', state.repeatMode.index);
    });
  }

  AudioPlayer get player => _audioHandler.player;
  
  // SCROBBLE: Track playback position for threshold
  Duration _scrobbleThreshold = Duration.zero;
  bool _hasScrobbled = false;
  String? _currentScrobbleSongId;
  
  Duration _lastKnownPosition = Duration.zero;
  int _lastKnownIndex = 0;
  bool _isShuffling = false;
  bool get isShuffling => _isShuffling;

  void _init() {
    _lastKnownIndex = player.currentIndex ?? 0;

    _subscriptions.add(player.currentIndexStream.listen((index) {
      if (index == null) return;
      if (_suppressStreamEvents) return;

      final prevIndex = _lastKnownIndex;

      // ── CRITICAL FIX: snapshot everything BEFORE mutating state ──────────
      // _lastKnownPosition is reset to Duration.zero at the bottom of this
      // block.  All analytics calls must capture it NOW, synchronously.
      final positionAtSwitch = _lastKnownPosition;

      final settings = _ref.read(settingsProvider);
      final analyticsEnabled = settings.dataCollectionEnabled;

      final Song? prevSong =
          prevIndex >= 0 && prevIndex < state.queue.length ? state.queue[prevIndex] : null;
      final Song? newSong =
          index >= 0 && index < state.queue.length ? state.queue[index] : null;

      // Ignore no-op index events (same index, not a repeat-one scenario).
      if (index == prevIndex && state.repeatMode != LoopMode.one) {
        return;
      }

      _lastKnownIndex = index;

      // ── Analytics ────────────────────────────────────────────────────────
      if (!analyticsEnabled) {
        debugPrint('[Analytics] ⏭ Collection disabled — skipping event');
      } else if (newSong == null) {
        debugPrint('[Analytics] ⚠ New song is null at index $index — skipping');
      } else {
        // Snapshot context labels before they might be overwritten by a
        // concurrent operation.
        final sourceCtx = _nextSourceContext;
        final transCtx = _nextTransitionType;
        _nextSourceContext = 'autoplay';
        _nextTransitionType = 'autoplay';

        // Debounce: cancel any pending timer from a rapid sequence of index
        // changes.  All values are captured HERE (synchronously) so the timer
        // callback uses the correct snapshot, not stale state.
        _trackChangeTimer?.cancel();
        final capturedPrev = prevSong;
        final capturedNew = newSong;
        final capturedPos = positionAtSwitch; // already snapshotted above
        final capturedIdx = index;
        final capturedShuffle = state.shuffleMode;

        _trackChangeTimer = Timer(const Duration(milliseconds: 200), () {
          // SCROBBLE-MIGRATED: Local storage disabled.
          // _collector.onSongStarted(
          //   song: capturedNew,
          //   sourceContext: sourceCtx,
          //   transitionType: transCtx,
          //   prevSong: capturedPrev,
          //   positionAtSwitch: capturedPos,
          //   queuePosition: capturedIdx,
          //   shuffleActive: capturedShuffle,
          // );
        });
        
        // SCROBBLE: track position and notify server
        _hasScrobbled = false;
        _currentScrobbleSongId = newSong.id;
        
        final total = Duration(seconds: newSong.duration);
        final half = total * 0.5;
        const fourMinutes = Duration(minutes: 4);
        _scrobbleThreshold = half < fourMinutes ? half : fourMinutes;
        
        _ref.read(scrobbleServiceProvider).nowPlaying(newSong.id);

        _ref.read(recommendationProvider).trackSongPlay(
              newSong,
              durationPlayed: positionAtSwitch.inSeconds,
              completed: prevSong != null &&
                  positionAtSwitch.inSeconds >
                      (prevSong.duration * 0.8).toInt(),
            );

        _audioHandler.refreshReplayGain();
      }

      // ── History ──────────────────────────────────────────────────────────
      // Push to history only when moving forward and the previous song was
      // actually playing for a meaningful time (>= 2 s).
      if (!_suppressNextHistoryPush &&
          index > prevIndex &&
          prevIndex < state.queue.length &&
          positionAtSwitch.inSeconds >= 2) {
        _pushToHistory(state.queue[prevIndex]);
      }
      _suppressNextHistoryPush = false;

      // ── Reset position tracker for the new track ─────────────────────────
      _lastKnownPosition = Duration.zero;

      // ── Update state ─────────────────────────────────────────────────────
      state = state.copyWith(currentIndex: index);

      // ── Autoplay lookahead ───────────────────────────────────────────────
      final isSmartLocal = settings.shuffleAlgorithm == ShuffleAlgorithm.smartLocal && state.shuffleMode;

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

      // ── Scrobble tracking ────────────────────────────────────────────────
      // Migrated to ScrobbleService
    }));

    _subscriptions.add(player.playingStream.listen((playing) {
      if (_suppressStreamEvents) return;
      state = state.copyWith(isPlaying: playing);
    }));

    _subscriptions.add(player.loopModeStream.listen((loopMode) {
      state = state.copyWith(repeatMode: loopMode);
    }));

    _subscriptions.add(player.processingStateStream.listen((ps) async {
      if (ps != ProcessingState.completed) return;
      if (_suppressStreamEvents) return;

      if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
        final song = state.queue[state.currentIndex];
        _collector.onSongEnded(song, player.position);
      }

      if (!state.autoplayMode) return;
      if (state.currentIndex < state.queue.length - 1) return;

      _triggerAutoplayIfNeeded();
    }));

    Duration prevPosition = Duration.zero;
    _subscriptions.add(player.positionStream.listen((position) {
      // Only update _lastKnownPosition when the player is on the expected
      // track. Guards against position events firing on the old source while
      // the index has already moved (common during gapless transitions).
      if (player.currentIndex == _lastKnownIndex) {
        _lastKnownPosition = position;
      }

      if (position.inSeconds > 0 && position.inSeconds % 5 == 0) {
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

      if (!_hasScrobbled &&
          _currentScrobbleSongId != null &&
          position >= _scrobbleThreshold) {
        _hasScrobbled = true;
        _ref.read(scrobbleServiceProvider).submit(_currentScrobbleSongId!);
      }
    }));
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
    _autoplayTriggeredFor.clear();
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

  Future<void> playPlaylist(List<Song> songs, {bool shuffle = false, String? playlistName}) async {
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
        state =
            state.copyWith(shuffleMode: false, queue: songs, currentIndex: 0);
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
          state = state.copyWith(queue: [currentSong], currentIndex: 0);
          await _audioHandler.setQueue([currentSong], 0, unshuffledSongs: songs);
          _suppressStreamEvents = false;
          player.play();
          _triggerSmartLocalFetchIfNeeded();
        } else {
          final pool = List<Song>.from(songs)..removeAt(startIndex);
          final shuffled = await _audioHandler.computeShuffle(
              pool, settings.shuffleAlgorithm, settings.shufflePreference,
              currentSong: currentSong, contextName: playlistName);
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
            pushHistory: false);
      }
    } catch (e, stack) {
      debugPrint('playNext failed: $e\n$stack');
      await _jumpToInternal(
          state.currentIndex < state.queue.length - 1
              ? state.currentIndex + 1
              : 0,
          pushHistory: false);
    }
  }

  Future<void> stop() async {
    _hasScrobbled = false;
    _currentScrobbleSongId = null;
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
          final prevIdx =
              state.currentIndex > 0 ? state.currentIndex - 1 : 0;
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
            pushHistory: false);
      }
    } catch (e, stack) {
      debugPrint('playPrev failed: $e\n$stack');
      _suppressNextHistoryPush = true;
      await _jumpToInternal(
          state.currentIndex > 0 ? state.currentIndex - 1 : 0,
          pushHistory: false);
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
      await _audioHandler.reorderQueue(oldIndex, newIndex,
          isShuffleMode: state.shuffleMode);
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
          currentIndex: _audioHandler.player.currentIndex ?? 0);
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
        case ShuffleAlgorithm.smartLocal:
          final currentSong = state.queue[state.currentIndex];
          final unshuffled = _audioHandler.unshuffledQueue;
          await _audioHandler.setQueue([currentSong], 0, unshuffledSongs: unshuffled);
          state = state.copyWith(queue: [currentSong], currentIndex: 0);
          _triggerSmartLocalFetchIfNeeded();
          break;
      }
      if (settings.shuffleAlgorithm != ShuffleAlgorithm.smartLocal) {
        state = state.copyWith(
            queue: _audioHandler.currentQueue, currentIndex: savedIndex);
      }
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
  // Autoplay
  // ---------------------------------------------------------------------------

  void _triggerAutoplayIfNeeded() {
    if (!state.autoplayMode || _isFetchingSimilar || state.queue.isEmpty) {
      return;
    }

    final lastSong = state.queue.last;
    if (_autoplayTriggeredFor.contains(lastSong.id)) return;

    _autoplayTriggeredFor.add(lastSong.id);
    _fetchAndAppendSimilar(lastSong);
  }

  Future<void> _fetchAndAppendSimilar(Song seedSong) async {
    _isFetchingSimilar = true;
    try {
      debugPrint('[AUTOPLAY] Fetching similar songs for: ${seedSong.title}');

      final indexBeforeFetch = state.currentIndex;
      final queueLenBeforeFetch = state.queue.length;

      final similar =
          await _subsonicService.getSimilarSongs(seedSong.id, count: 10);

      if (similar.isEmpty) {
        debugPrint('[AUTOPLAY] No similar songs found for ${seedSong.title}');
        return;
      }

      final existingIds = state.queue.map((s) => s.id).toSet();
      final fresh =
          similar.where((s) => !existingIds.contains(s.id)).toList();

      if (fresh.isEmpty) {
        debugPrint('[AUTOPLAY] All similar songs already in queue');
        return;
      }

      final newQueue = [...state.queue, ...fresh];
      state = state.copyWith(queue: newQueue);
      await _audioHandler.addAllToQueue(fresh);

      debugPrint(
          '[AUTOPLAY] Appended ${fresh.length} songs. Queue now ${newQueue.length}');

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
          debugPrint('[AUTOPLAY] Resumed at index $nextIndex');
        }
      }
    } catch (e) {
      debugPrint('[AUTOPLAY] Failed to fetch similar songs: $e');
    } finally {
      _isFetchingSimilar = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Smart Local
  // ---------------------------------------------------------------------------

  void _triggerSmartLocalFetchIfNeeded() {
    if (_isFetchingSmartLocal || state.queue.isEmpty) {
      return;
    }

    final lastSong = state.queue.last;
    if (_autoplayTriggeredFor.contains(lastSong.id)) return;

    _autoplayTriggeredFor.add(lastSong.id);
    _fetchAndAppendSmartLocal(lastSong);
  }

  Future<void> _fetchAndAppendSmartLocal(Song seedSong) async {
    _isFetchingSmartLocal = true;
    try {
      debugPrint('[SMART LOCAL] Fetching similar songs to append for: ${seedSong.title}');

      final similar = await _subsonicService.getSimilarSongs(seedSong.id, count: 10);

      if (similar.isEmpty) {
        debugPrint('[SMART LOCAL] No similar songs found for ${seedSong.title}');
        return;
      }

      final existingIds = state.queue.map((s) => s.id).toSet();
      final fresh = similar.where((s) => !existingIds.contains(s.id)).toList();

      if (fresh.isEmpty) {
        debugPrint('[SMART LOCAL] All fetched songs already in queue');
        return;
      }

      final newQueue = [...state.queue, ...fresh];
      state = state.copyWith(queue: newQueue);
      await _audioHandler.addAllToQueue(fresh);

      debugPrint('[SMART LOCAL] Appended ${fresh.length} songs. Triggering Smart Local Shuffle sort.');
      
      await _audioHandler.smartLocalShuffle();
      
      state = state.copyWith(queue: _audioHandler.currentQueue);
    } catch (e) {
      debugPrint('[SMART LOCAL] Failed to fetch/append: $e');
    } finally {
      _isFetchingSmartLocal = false;
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

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final service = ref.watch(subsonicServiceProvider);
  final collector = ref.watch(listenerCollectorProvider);
  return PlayerNotifier(ref, handler, service, collector);
});