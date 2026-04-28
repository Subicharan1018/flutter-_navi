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

  // ---------------------------------------------------------------------------
  // History
  //
  // Apple Music model:
  //   • history  — songs that have *already* finished playing, oldest → newest.
  //                Pressing "previous" pops from here rather than from the queue.
  //   • queue    — songs yet to be played, index 0 = now playing.
  //
  // The two lists are kept separate so the Queue screen can display them with
  // a clear visual divider ("History" header above, "Next Up" header below the
  // now-playing row).  History is capped at [maxHistoryLength] to prevent
  // unbounded memory growth on long listening sessions.
  // ---------------------------------------------------------------------------
  final List<Song> history;

  /// Maximum number of songs retained in history.
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

  // ---------------------------------------------------------------------------
  // Convenience views used by the Queue/History screen
  // ---------------------------------------------------------------------------

  /// Songs that have already played (oldest first).
  List<Song> get historySongs => history;

  /// The song currently playing (null if queue is empty).
  Song? get currentSong =>
      queue.isNotEmpty && currentIndex < queue.length ? queue[currentIndex] : null;

  /// Songs *after* the current index — i.e. "Next Up".
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

  // Infinity (Autoplay) State
  bool _isFetchingSimilar = false;
  final Set<String> _autoplayTriggeredFor = {};

  // ---------------------------------------------------------------------------
  // Source / transition context tracking
  //
  // Set BEFORE each explicit navigation action so the currentIndexStream
  // listener can record the correct context.  Reset to defaults after
  // consumption (auto-advance keeps the default 'autoplay' / 'autoplay').
  // ---------------------------------------------------------------------------
  String _nextSourceContext = 'autoplay';
  String _nextTransitionType = 'autoplay';

  PlayerNotifier(this._ref, this._audioHandler, this._subsonicService, this._collector)
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
  }

  AudioPlayer get player => _audioHandler.player;

  // BUG-5: track the last song id we used to detect a song change and clear
  // _scrobbledIds so the same song can be scrobbled again in a new playthrough.
  String? _lastScrobbleSongId;

  // Tracks the last playback position emitted by positionStream.
  // currentIndexStream uses this to enforce the 2-second history gate:
  // a song is only pushed onto history if it was audibly played for at
  // least 2 seconds. Quick skips (< 2 s) are excluded from history.
  Duration _lastKnownPosition = Duration.zero;

  // ---------------------------------------------------------------------------
  // BUG-13 FIX — isShuffling guard
  //
  // During the async gap between setQueue() and the completion of
  // applyShuffleAlgorithm() the queue may briefly appear "changed" while the
  // audio source is being rebuilt.  The NowPlayingScreen's queue.isEmpty guard
  // would show a black Scaffold during that window.
  //
  // Solution: expose a flag that the NowPlayingScreen can read.  While true,
  // the screen suppresses the empty-queue fallback and keeps the last-rendered
  // content visible (the album art / mesh gradient are already on screen from
  // the previous frame).
  // ---------------------------------------------------------------------------
  bool _isShuffling = false;
  bool get isShuffling => _isShuffling;

  void _init() {
    // ---------------------------------------------------------------------------
    // History tracking
    //
    // When currentIndex advances we push the *previous* song onto history.
    // We intentionally do NOT push when the user manually seeks backwards
    // via playPrev() — that method handles its own history pop.
    //
    // 2-second rule: _lastKnownPosition (updated by positionStream) must be
    // ≥ 2 s at the moment the index changes, otherwise the song was skipped
    // too quickly to count as "played" and is excluded from history.
    //
    // Shuffle guard: while _isShuffling is true, just_audio emits spurious
    // currentIndexStream events as the ConcatenatingAudioSource is rebuilt.
    // We ignore those entirely; applyShuffleAlgorithm syncs state afterwards.
    // ---------------------------------------------------------------------------
    int _lastKnownIndex = 0;

    _subscriptions.add(player.currentIndexStream.listen((index) {
      if (index == null) return;

      // ── Shuffle guard ──────────────────────────────────────────────────────
      if (_isShuffling) {
        _lastKnownIndex = index;
        return;
      }

      final prevIndex = _lastKnownIndex;
      _lastKnownIndex = index;

      // ── Analytics: close the previous event and open a new one ─────────────
      final settings = _ref.read(settingsProvider);
      if (settings.dataCollectionEnabled && state.queue.isNotEmpty) {
        final Song? prevSong =
            prevIndex < state.queue.length ? state.queue[prevIndex] : null;
        final Song? newSong =
            index < state.queue.length ? state.queue[index] : null;

        if (newSong != null) {
          // Consume and reset context so auto-advance defaults to 'autoplay'.
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
          );
        }
      }

      // ── History push (2-second gate) ───────────────────────────────────────
      // _lastKnownPosition holds the position of the *previous* song at the
      // instant positionStream last fired — i.e. just before the track changed.
      // Only songs audibly played for ≥ 2 s are added to history.
      if (!_suppressNextHistoryPush &&
          index > prevIndex &&
          prevIndex < state.queue.length &&
          _lastKnownPosition.inSeconds >= 2) {
        _pushToHistory(state.queue[prevIndex]);
      }
      _suppressNextHistoryPush = false;
      _lastKnownPosition = Duration.zero; // reset for the incoming song

      state = state.copyWith(currentIndex: index);

      // --- INFINITY (AUTOPLAY) LOGIC ---
      if (state.autoplayMode && !_isFetchingSimilar && index == state.queue.length - 1) {
        final lastSong = state.queue[index];
        if (!_autoplayTriggeredFor.contains(lastSong.id)) {
          _autoplayTriggeredFor.add(lastSong.id);
          _fetchAndAppendSimilar(lastSong);
        }
      }

      // BUG-5: clear scrobble cache on song change
      if (index < state.queue.length) {
        final songId = state.queue[index].id;
        if (songId != _lastScrobbleSongId) {
          _scrobbledIds.clear();
          _lastScrobbleSongId = songId;
        }
      }
    }));

    _subscriptions.add(player.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    }));

    // BUG-13: removed shuffleModeEnabledStream listener; shuffle state is now
    // driven solely by our custom algorithms, not just_audio's internal shuffle.

    _subscriptions.add(player.loopModeStream.listen((loopMode) {
      state = state.copyWith(repeatMode: loopMode);
    }));

    _subscriptions.add(player.positionStream.listen((position) {
      // Always track position so currentIndexStream can apply the 2-second
      // history gate when the track changes.
      _lastKnownPosition = position;

      if (state.queue.isEmpty || state.currentIndex >= state.queue.length) {
        return;
      }
      final currentSong = state.queue[state.currentIndex];
      final duration = currentSong.duration;
      if (duration > 0 && position.inSeconds > (duration * 0.5)) {
        if (!_scrobbledIds.contains(currentSong.id)) {
          _scrobbledIds.add(currentSong.id);
          scrobble(currentSong.id);
        }
      }
    }));
  }

  // Set this to true immediately before any navigation that should NOT push a
  // history entry (playPrev, manual jumpTo).  The currentIndexStream listener
  // clears it after reading it once.
  bool _suppressNextHistoryPush = false;

  // ---------------------------------------------------------------------------
  // History helpers
  // ---------------------------------------------------------------------------

  /// Push [song] onto history, capping at [PlayerState.maxHistoryLength].
  void _pushToHistory(Song song) {
    if (state.history.isNotEmpty && state.history.last.id == song.id) {
      return;
    }
    final updated = [...state.history, song];
    if (updated.length > PlayerState.maxHistoryLength) {
      updated.removeRange(0, updated.length - PlayerState.maxHistoryLength);
    }
    state = state.copyWith(history: updated);
  }

  /// Pop the most-recently-played song from history and return it.
  /// Returns null if history is empty.
  Song? _popFromHistory() {
    if (state.history.isEmpty) return null;
    final updated = [...state.history];
    final song = updated.removeLast();
    state = state.copyWith(history: updated);
    return song;
  }

  /// Clear history (used when a brand-new queue is loaded).
  void _clearHistory() {
    state = state.copyWith(history: []);
    _autoplayTriggeredFor.clear();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    // BUG-14: dispose the AudioHandler (stops playback, releases native resources)
    _audioHandler.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  Future<void> setQueue(List<Song> songs, int startIndex) async {
    _clearHistory();
    _nextSourceContext = 'user_queue';
    _nextTransitionType = 'user_selected';
    state = state.copyWith(queue: songs, currentIndex: startIndex);
    await _audioHandler.setQueue(songs, startIndex);
    player.play();
  }

  // BUG-19 FIX: A dedicated method to start a playlist that handles shuffle
  // elegantly without double-rebuilding the audio source or forcing song[0].
  Future<void> playPlaylist(List<Song> songs, {bool shuffle = false}) async {
    if (songs.isEmpty) return;
    _clearHistory();
    _nextSourceContext = 'playlist';
    _nextTransitionType = 'user_selected';

    if (!shuffle) {
      state = state.copyWith(shuffleMode: false);
      state = state.copyWith(queue: songs, currentIndex: 0);
      await _audioHandler.setQueue(songs, 0, unshuffledSongs: songs);
      player.play();
      return;
    }

    // Shuffle requested:
    state = state.copyWith(shuffleMode: true);
    _isShuffling = true;
    try {
      // Pick a random starting song so the first track is unpredictable
      final startIndex = Random().nextInt(songs.length);
      final currentSong = songs[startIndex];
      final pool = List<Song>.from(songs)..removeAt(startIndex);

      final settings = _ref.read(settingsProvider);
      
      // Shuffle the rest of the pool using the chosen algorithm directly via the handler
      final shuffled = await _audioHandler.computeShuffle(
        pool,
        settings.shuffleAlgorithm,
        settings.shufflePreference,
      );

      final finalQueue = [currentSong, ...shuffled];
      state = state.copyWith(queue: finalQueue, currentIndex: 0);
      
      // Only one rebuild/play call!
      await _audioHandler.setQueue(finalQueue, 0, unshuffledSongs: songs);
      player.play();
    } finally {
      _isShuffling = false;
    }
  }

  Future<void> playNext() async {
    // Push current song to history before advancing
    if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
      _pushToHistory(state.queue[state.currentIndex]);
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

  // ---------------------------------------------------------------------------
  // BUG-13 FIX — playPrev() now uses history
  //
  // Apple Music behaviour:
  //   1. If position > 3 s → seek to start of current song.
  //   2. Else if history is non-empty → pop from history and play that song.
  //   3. Else if there is a previous track in the queue → seek to it.
  //   4. Else stay on track 0.
  //
  // Crucially, when we pop from history we must NOT push the current song
  // back onto history (that would create an infinite "previous" loop).
  // ---------------------------------------------------------------------------
  Future<void> playPrev() async {
    try {
      if (player.position.inSeconds > 3) {
        // Just restart the current track — no history change
        await player.seek(Duration.zero);
        return;
      }

      final historySong = _popFromHistory();
      if (historySong != null) {
        // Jump to the song from history.
        // We need to find it in the queue.  History songs are always past
        // entries so they exist at indices < currentIndex.
        final historyIndex = state.queue
            .sublist(0, state.currentIndex)
            .lastIndexWhere((s) => s.id == historySong.id);

        if (historyIndex >= 0) {
          _suppressNextHistoryPush = true;
          await player.seek(Duration.zero, index: historyIndex);
          state = state.copyWith(currentIndex: historyIndex);
        } else {
          // Song was removed from queue after being played — just go back one
          // position conventionally.
          _suppressNextHistoryPush = true;
          final prevIdx =
              state.currentIndex > 0 ? state.currentIndex - 1 : 0;
          await player.seek(Duration.zero, index: prevIdx);
          state = state.copyWith(currentIndex: prevIdx);
        }
        return;
      }

      // No history → fall back to previous queue index
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

  /// Internal jump.  [pushHistory] controls whether the current song is pushed
  /// before navigating (false for prev, true for tapping a song in the list).
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
    // BUG-1: use incremental API — no full source rebuild
    final currentQueue = List<Song>.from(state.queue)..add(song);
    state = state.copyWith(queue: currentQueue);
    await _audioHandler.addToQueue(song);
  }

  Future<void> removeFromQueue(int index) async {
    // BUG-1: use incremental API — no full source rebuild
    final currentQueue = List<Song>.from(state.queue)..removeAt(index);
    int newIndex = state.currentIndex;
    if (index < state.currentIndex) {
      newIndex--;
    } else if (index == state.currentIndex && currentQueue.isNotEmpty) {
      if (newIndex >= currentQueue.length) newIndex = 0;
    }
    state = state.copyWith(queue: currentQueue, currentIndex: newIndex);
    await _audioHandler.removeFromQueue(index);
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    // BUG-1: use incremental API — no full source rebuild
    // BUG-12: ReorderableListView passes pre-adjusted newIndex; no extra -1 needed.
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
    await _audioHandler.reorderQueue(oldIndex, newIndex, isShuffleMode: state.shuffleMode);
  }

  // ---------------------------------------------------------------------------
  // Starring
  // ---------------------------------------------------------------------------

  Future<void> toggleStar(String songId) async {
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
  }

  // ---------------------------------------------------------------------------
  // Shuffle — respects the algorithm setting from SettingsProvider
  // ---------------------------------------------------------------------------

  Future<void> toggleShuffle() async {
    final nextMode = !state.shuffleMode;
    await setShuffleMode(nextMode);
  }

  Future<void> setShuffleMode(bool enabled) async {
    debugPrint('🔘 [UI] Set Shuffle Mode: $enabled');
    // BUG-13: do NOT call player.setShuffleModeEnabled — our custom algorithms
    // already reorder _currentQueue, so using just_audio's internal shuffle on
    // top causes a double-shuffle and a race condition that flashes black.
    state = state.copyWith(shuffleMode: enabled);

    if (enabled) {
      await applyShuffleAlgorithm();
    } else {
      await unshuffleQueue();
    }
  }

  Future<void> unshuffleQueue() async {
    _isShuffling = true;
    try {
      await Future.delayed(const Duration(milliseconds: 50));
      await _audioHandler.unshuffle();
      state = state.copyWith(
        queue: _audioHandler.currentQueue,
        currentIndex: _audioHandler.player.currentIndex ?? 0,
      );
    } finally {
      _isShuffling = false;
    }
  }

  // ---------------------------------------------------------------------------
  // BUG-13 FIX — applyShuffleAlgorithm is fully awaited before state update.
  //
  // The _isShuffling flag is raised for the entire async duration so that the
  // NowPlayingScreen's empty-queue guard can be suppressed during the rebuild
  // gap (see now_playing_screen.dart).
  //
  // BUG-19 FIX — when called from _playAll(shuffle:true) the queue has just
  // been set to the raw playlist at index 0.  The shuffle algorithms all keep
  // the current song at position 0 and shuffle the rest, so song[0] is always
  // played first — not a random song — which matches Spotify/Apple behaviour.
  // No random startIndex is ever passed; the shuffle itself provides variety.
  // ---------------------------------------------------------------------------
  Future<void> applyShuffleAlgorithm() async {
    _isShuffling = true;
    try {
      // Yield to event loop to allow UI animations to complete smoothly
      await Future.delayed(const Duration(milliseconds: 50));

      // ── Capture currentIndex BEFORE any audio-source manipulation ──────────
      // Reading player.currentIndex AFTER _updateQueueAfterAnchor is unreliable:
      // just_audio can shift the internal index during removeRange / addAll on
      // ConcatenatingAudioSource, returning 0 even though nothing moved.
      // Saving here (after the 50 ms yield but before the algorithm runs) gives
      // us the stable, correct position of the song that is playing.
      final savedIndex = _audioHandler.player.currentIndex ?? state.currentIndex;

      final settings = _ref.read(settingsProvider);
      final algorithm = settings.shuffleAlgorithm;
      switch (algorithm) {
        case ShuffleAlgorithm.spotify:
          await _audioHandler.spotifyDitherShuffle(settings.shufflePreference);
          break;
        case ShuffleAlgorithm.youtube:
          await _audioHandler.youtubeWeightedShuffle();
          break;
        case ShuffleAlgorithm.standard:
          await _audioHandler.standardShuffle();
          break;
      }
      // Sync state using the SAVED index — not whatever the player reports
      // after the source rebuild (which can be 0 due to the just_audio bug).
      state = state.copyWith(
        queue: _audioHandler.currentQueue,
        currentIndex: savedIndex,
      );
    } finally {
      _isShuffling = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Repeat
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Suggest More / Less
  // Syncs star + rating with Navidrome, then updates the local dynamic weight
  // so the next weighted shuffle reflects the user's preference immediately.
  // ---------------------------------------------------------------------------

  /// [isMore] = true  → "Suggest More"  (star + rate 5 + boost weight)
  /// [isMore] = false → "Suggest Less"  (unstar + rate 1 + reduce weight)
  Future<void> handleSuggestAction(Song song, bool isMore) async {
    if (isMore) {
      // Star the song if not already
      if (!song.starred) await toggleStar(song.id);
      await _subsonicService.setRating(song.id, 5);
    } else {
      // Remove star if currently starred
      if (song.starred) await toggleStar(song.id);
      await _subsonicService.setRating(song.id, 1);
    }

    // Update the in-memory dynamic weight for this queue session
    _audioHandler.updateSongWeight(song, isMore);

    // Sync state so the UI can reflect any queue/weight changes
    state = state.copyWith(queue: _audioHandler.currentQueue);
  }

  // ---------------------------------------------------------------------------
  // Scrobble
  // ---------------------------------------------------------------------------

  Future<void> scrobble(String songId) async {
    await _subsonicService.scrobble(songId);
  }

  // ---------------------------------------------------------------------------
  // Infinity / Autoplay
  // ---------------------------------------------------------------------------

  Future<void> toggleAutoplay() async {
    state = state.copyWith(autoplayMode: !state.autoplayMode);
  }

  Future<void> _fetchAndAppendSimilar(Song lastSong) async {
    debugPrint('♾️ [AUTOPLAY] Fetching similar songs for: ${lastSong.title}');
    _isFetchingSimilar = true;
    try {
      final similar = await _subsonicService.getSimilarSongs(lastSong.id);
      if (similar.isNotEmpty) {
        debugPrint('♾️ [AUTOPLAY] Appending ${similar.length} songs in one batch.');

        // Update Riverpod state first so the queue length is correct before
        // the audio source grows (prevents a brief "no next track" state).
        final newQueue = [...state.queue, ...similar];
        state = state.copyWith(queue: newQueue);

        // Single batch call — avoids the timing gap where the player stops
        // because the last song ended before the next one was appended.
        await _audioHandler.addAllToQueue(similar);

        // If the player reached the end and stopped while we were fetching,
        // resume from the first newly appended song.
        if (!player.playing && state.currentIndex >= state.queue.length - similar.length - 1) {
          final nextIndex = state.currentIndex + 1;
          if (nextIndex < state.queue.length) {
            await player.seek(Duration.zero, index: nextIndex);
            await player.play();
            state = state.copyWith(currentIndex: nextIndex);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [AUTOPLAY] Failed to fetch similar songs: $e');
    } finally {
      _isFetchingSimilar = false;
    }
  }

  // ---------------------------------------------------------------------------
  // History management — exposed for the queue/history screen
  // ---------------------------------------------------------------------------

  /// Manually clear playback history.
  void clearHistory() => _clearHistory();
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final audioHandlerProvider = Provider<AudioHandler>((ref) {
  final service = ref.watch(subsonicServiceProvider);
  return AudioHandler(service);
});

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final service = ref.watch(subsonicServiceProvider);
  final collector = ref.watch(listenerCollectorProvider);
  return PlayerNotifier(ref, handler, service, collector);
});