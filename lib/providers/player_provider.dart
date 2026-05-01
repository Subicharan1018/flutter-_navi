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

  static const int maxHistoryLength = 50;

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

  // FIX (Autoplay-1): Track which song IDs we have already used as the seed
  // for an autoplay fetch. When similar songs are appended, the new last song
  // gets a fresh entry — so autoplay continues indefinitely rather than
  // stopping after the first batch.
  final Set<String> _autoplayTriggeredFor = {};

  // RC-1/RC-9/RC-12: Serialization lock for queue/shuffle operations.
  // Ensures only one setQueue/shuffle/unshuffle runs at a time.
  Completer<void>? _queueOpLock;

  // RC-9: Suppresses stream listener processing during audio source rebuilds.
  bool _suppressStreamEvents = false;

  // RC-4: Prevents concurrent toggleStar calls for the same song ID.
  final Set<String> _starTogglingIds = {};

  // RC-10: Debounce timer for _persistState to avoid Hive write races.
  Timer? _persistTimer;

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

  // RC-15 FIX: Only restore persisted preferences here. The seek is deferred
  // to after setQueue() is called, because seeking on a player with no audio
  // source throws on some Android versions.
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
    // Seek deferred — applied in setQueue() when audio source is ready.
  }

  // RC-10 FIX: Debounced persist — avoids Hive write races from rapid
  // position stream events. All fields written together for atomicity.
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
  String? _lastScrobbleSongId;
  Duration _lastKnownPosition = Duration.zero;
  int _lastKnownIndex = 0;
  bool _isShuffling = false;
  bool get isShuffling => _isShuffling;

  void _init() {
    _lastKnownIndex = player.currentIndex ?? 0;

    _subscriptions.add(player.currentIndexStream.listen((index) {
      if (index == null) return;
      // RC-3/RC-9: Skip processing during source rebuilds to avoid ghost events.
      if (_suppressStreamEvents) return;

      final prevIndex = _lastKnownIndex;
      _lastKnownIndex = index;

      final settings = _ref.read(settingsProvider);
      if (!settings.dataCollectionEnabled) {
        debugPrint('[Analytics] ⏭ Collection disabled — skipping event');
      } else if (state.queue.isEmpty) {
        debugPrint('[Analytics] ⚠ Queue empty — cannot record event');
      } else {
        final Song? prevSong =
            prevIndex < state.queue.length ? state.queue[prevIndex] : null;
        final Song? newSong =
            index < state.queue.length ? state.queue[index] : null;

        if (newSong != null) {
          final sourceCtx = _nextSourceContext;
          final transCtx = _nextTransitionType;
          _nextSourceContext = 'autoplay';
          _nextTransitionType = 'autoplay';

          _collector.onSongStarted(
            song: newSong,
            sourceContext: sourceCtx,
            transitionType: transCtx,
            prevSong: prevSong,
            positionAtSwitch: _lastKnownPosition,
            queuePosition: index,
            shuffleActive: state.shuffleMode,
          );

          _ref.read(recommendationProvider).trackSongPlay(
            newSong,
            durationPlayed: _lastKnownPosition.inSeconds,
            completed: prevSong != null &&
                _lastKnownPosition.inSeconds >
                    (prevSong.duration * 0.8).toInt(),
          );

          _audioHandler.refreshReplayGain();
        }
      }

      if (!_suppressNextHistoryPush &&
          index > prevIndex &&
          prevIndex < state.queue.length &&
          _lastKnownPosition.inSeconds >= 2) {
        _pushToHistory(state.queue[prevIndex]);
      }
      _suppressNextHistoryPush = false;
      _lastKnownPosition = Duration.zero;

      state = state.copyWith(currentIndex: index);

      // FIX (Autoplay-2): Trigger autoplay when approaching the end of queue.
      // We trigger one song early (at second-to-last) so new songs are ready
      // before the queue actually runs out, eliminating the gap.
      // Also trigger at last song as a safety net.
      if (state.autoplayMode && state.queue.isNotEmpty) {
        final queueLen = state.queue.length;
        if (index >= queueLen - 2) {
          _triggerAutoplayIfNeeded();
        }
      }

      if (index < state.queue.length) {
        final songId = state.queue[index].id;
        if (songId != _lastScrobbleSongId) {
          _scrobbledIds.clear();
          _lastScrobbleSongId = songId;
        }
      }
    }));

    _subscriptions.add(player.playingStream.listen((playing) {
      // RC-9: Skip during source rebuilds (setAudioSource emits playing=false).
      if (_suppressStreamEvents) return;
      state = state.copyWith(isPlaying: playing);
    }));

    _subscriptions.add(player.loopModeStream.listen((loopMode) {
      state = state.copyWith(repeatMode: loopMode);
    }));

    // FIX (Autoplay-3): processingStateStream — when the entire audio pipeline
    // hits ProcessingState.completed it means just_audio exhausted its source
    // list. At this point state.currentIndex is still at the last item.
    // We must NOT call _triggerAutoplayIfNeeded() here as well as from
    // currentIndexStream — that caused a double-fetch race. Instead we only
    // handle the case where autoplay hasn't kicked in yet (e.g. autoplay was
    // toggled on AFTER the queue finished) and try to resume playback.
    _subscriptions.add(player.processingStateStream.listen((ps) async {
      if (ps != ProcessingState.completed) return;
      // RC-9: Skip during source rebuilds.
      if (_suppressStreamEvents) return;

      if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
        final song = state.queue[state.currentIndex];
        _collector.onSongEnded(song, player.position);
      }

      if (!state.autoplayMode) return;

      // If we already have more tracks buffered past the current index,
      // just_audio should advance automatically — don't interfere.
      if (state.currentIndex < state.queue.length - 1) return;

      // Queue is truly exhausted. Trigger a fetch if not already in progress.
      // currentIndexStream won't fire again (no new index), so this is the
      // only place that can rescue a completed queue.
      _triggerAutoplayIfNeeded();

      // If a fetch was already in progress, wait briefly and then try to play.
      // _fetchAndAppendSimilar will call player.play() itself when done.
    }));

    Duration prevPosition = Duration.zero;
    _subscriptions.add(player.positionStream.listen((position) {
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

      if (duration > 0 && position.inSeconds > (duration * 0.5)) {
        if (!_scrobbledIds.contains(currentSong.id)) {
          _scrobbledIds.add(currentSong.id);
          scrobble(currentSong.id);
        }
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
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _audioHandler.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  // RC-12/RC-15 FIX: Serialized queue operation with deferred seek support.
  Future<void> setQueue(List<Song> songs, int startIndex) async {
    // Wait for any in-flight queue/shuffle operation to finish first.
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
      // RC-15: Apply deferred seek from cold start if present.
      if (_pendingSeekMs > 0) {
        try {
          await player.seek(Duration(milliseconds: _pendingSeekMs));
        } catch (_) {
          // Seek may fail if source is not ready — ignore.
        }
        _pendingSeekMs = 0;
      }
      player.play();
    } finally {
      _suppressStreamEvents = false;
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  // RC-12 FIX: Serialized with _queueOpLock to prevent interleaving with
  // setQueue or other shuffle operations.
  Future<void> playPlaylist(List<Song> songs, {bool shuffle = false}) async {
    if (songs.isEmpty) return;
    // Wait for any in-flight queue/shuffle operation.
    await _queueOpLock?.future;
    final completer = Completer<void>();
    _queueOpLock = completer;
    try {
      _clearHistory();
      _nextSourceContext = 'playlist';
      _nextTransitionType = 'user_selected';

      if (!shuffle) {
        _suppressStreamEvents = true;
        state = state.copyWith(shuffleMode: false, queue: songs, currentIndex: 0);
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
        final pool = List<Song>.from(songs)..removeAt(startIndex);
        final settings = _ref.read(settingsProvider);
        final shuffled = await _audioHandler.computeShuffle(
            pool, settings.shuffleAlgorithm, settings.shufflePreference);
        // RC-12: After long compute, check if another setQueue already ran.
        if (_queueOpLock != completer) return; // superseded — bail out
        final finalQueue = [currentSong, ...shuffled];
        _suppressStreamEvents = true;
        state = state.copyWith(queue: finalQueue, currentIndex: 0);
        await _audioHandler.setQueue(finalQueue, 0, unshuffledSongs: songs);
        _suppressStreamEvents = false;
        player.play();
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
    } catch (_) {
      await _jumpToInternal(
          state.currentIndex < state.queue.length - 1
              ? state.currentIndex + 1
              : 0,
          pushHistory: false);
    }
  }

  Future<void> playPrev() async {
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
    } catch (_) {
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

  Future<void> _jumpToInternal(int index,
      {required bool pushHistory}) async {
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

  // RC-3 FIX: Suppress stream events during structural queue mutations
  // to prevent the index listener from seeing a stale queue.
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

  // RC-3 FIX: Suppress stream events during reorder.
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
      state =
          state.copyWith(queue: currentQueue, currentIndex: currentIndex);
      await _audioHandler.reorderQueue(oldIndex, newIndex,
          isShuffleMode: state.shuffleMode);
    } finally {
      _suppressStreamEvents = false;
    }
  }

  // RC-4 FIX: Guard against concurrent toggleStar calls for the same songId.
  Future<void> toggleStar(String songId) async {
    if (_starTogglingIds.contains(songId)) return; // already in flight
    _starTogglingIds.add(songId);
    try {
      final currentlyStarred = state.starredIds.contains(songId);
      if (currentlyStarred) {
        await _subsonicService.unstar(songId);
        state = state.copyWith(
          starredIds:
              state.starredIds.where((id) => id != songId).toList(),
          queue: state.queue
              .map((s) =>
                  s.id == songId ? s.copyWith(starred: false) : s)
              .toList(),
        );
      } else {
        await _subsonicService.star(songId);
        state = state.copyWith(
          starredIds: [...state.starredIds, songId],
          queue: state.queue
              .map((s) =>
                  s.id == songId ? s.copyWith(starred: true) : s)
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

  // RC-1 FIX: Serialize shuffle operations with _queueOpLock.
  Future<void> setShuffleMode(bool enabled) async {
    // Wait for any in-flight queue/shuffle operation.
    await _queueOpLock?.future;
    state = state.copyWith(shuffleMode: enabled);
    if (enabled) {
      await applyShuffleAlgorithm();
    } else {
      await unshuffleQueue();
    }
  }

  // RC-1 FIX: Serialized unshuffle. Removed artificial 50ms delay that
  // caused UI lag. _suppressStreamEvents prevents ghost index events.
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

  // RC-1 FIX: Serialized shuffle. Removed artificial 50ms delay.
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
          await _audioHandler.spotifyDitherShuffle(
              settings.shufflePreference);
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
      }
      state = state.copyWith(
          queue: _audioHandler.currentQueue, currentIndex: savedIndex);
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

  Future<void> scrobble(String songId) async {
    await _subsonicService.scrobble(songId);
  }

  Future<void> toggleAutoplay() async {
    final newMode = !state.autoplayMode;
    state = state.copyWith(autoplayMode: newMode);
    if (newMode && state.queue.isNotEmpty) {
      // If the queue already finished before autoplay was toggled on,
      // processingState will be completed — kick off a fetch immediately.
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

    // FIX (Autoplay-1): Use the *current* last song in the queue as seed.
    // After _fetchAndAppendSimilar appends songs, state.queue.last changes,
    // so the next trigger (when those songs run out) uses a different seed
    // and the Set guard correctly allows a new fetch.
    final lastSong = state.queue.last;
    if (_autoplayTriggeredFor.contains(lastSong.id)) return;

    _autoplayTriggeredFor.add(lastSong.id);
    _fetchAndAppendSimilar(lastSong);
  }

  // RC-13 FIX: Snapshot currentIndex BEFORE the network call. After the await,
  // re-check if the user is still at the end before seeking.
  Future<void> _fetchAndAppendSimilar(Song seedSong) async {
    _isFetchingSimilar = true;
    try {
      debugPrint('[AUTOPLAY] Fetching similar songs for: ${seedSong.title}');

      // RC-13: Snapshot state before the network call.
      final indexBeforeFetch = state.currentIndex;
      final queueLenBeforeFetch = state.queue.length;

      final similar =
          await _subsonicService.getSimilarSongs(seedSong.id, count: 10);

      if (similar.isEmpty) {
        debugPrint('[AUTOPLAY] No similar songs found for ${seedSong.title}');
        return;
      }

      // Filter out songs already in the queue to avoid duplicates.
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
          '[AUTOPLAY] Appended ${fresh.length} songs. Queue now ${newQueue.length}');

      // RC-13: Re-read currentIndex AFTER the await. Only auto-resume if:
      // 1. The user is still at or past where they were before the fetch
      // 2. The user is actually at the end of the *original* queue
      // 3. Playback has stopped
      // This prevents hijacking if the user navigated away during the fetch.
      final currentIndexNow = state.currentIndex;
      final wasAtEnd = currentIndexNow >= queueLenBeforeFetch - 1;
      final userNavigatedAway = currentIndexNow < indexBeforeFetch;

      if (wasAtEnd &&
          !userNavigatedAway &&
          (player.processingState == ProcessingState.completed ||
              !player.playing)) {
        final nextIndex = queueLenBeforeFetch; // first fresh song
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