import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:collection/collection.dart';
import '../models/song.dart';
import '../services/subsonic_service.dart';
import '../services/listening_event_collector.dart';
import 'settings_provider.dart';
import '../services/navi_audio_handler.dart';
import '../core/hive_boxes.dart';
import '../core/app_constants.dart';
import '../utils/platform_utils.dart';

import '../services/scrobble_service.dart';
import '../main.dart';
import '../features/ai_shuffle/logic/shuffle_providers.dart';
import '../features/ai_shuffle/data/models/recommended_song.dart';
import '../features/ai_shuffle/data/models/feedback_request.dart';

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
  final NaviAudioHandler _audioHandler;
  final SubsonicService _subsonicService;
  final ListeningEventCollector _collector;
  final Set<String> _scrobbledIds = {};
  final List<StreamSubscription> _subscriptions = [];

  bool _isFetchingSimilar = false;
  String? _lastFetchedForSongId;

  Completer<void>? _queueOpLock;
  // RC-2: replaced single bool with two concerns:
  // _suppressDepth: reentrant counter for synchronous suppress blocks.
  // _shuffleSettling: single logical 500ms post-shuffle window.
  int _suppressDepth = 0;
  bool _shuffleSettling = false;
  bool get _suppressEvents => _suppressDepth > 0 || _shuffleSettling;

  int? _pendingIndexAfterShuffle;
  Timer? _shuffleGuardTimer;

  final Set<String> _starTogglingIds = {};
  Timer? _persistTimer;
  Timer? _trackChangeTimer;
  String? _currentPlaylistName;

  // ─── Smart-local playlist pool ───────────────────────────────────────────
  // Holds the remaining songs from the active playlist that have NOT yet been
  // queued. Populated on playPlaylist() and drained by
  // _fetchAndReorderSmartLocal() as batches of 16 are appended to the queue.
  //
  // Rules:
  //   • Only songs whose id is in this list will ever be appended.
  //   • The server orders them; it never injects songs from outside the pool.
  //   • When the pool is empty no more fetches are triggered.
  List<Song> _playlistPool = [];

  // How many songs to load initially and per refill batch.
  static const int _smartLocalBatchSize = 16;
  // Refill when this many songs remain ahead of the current position.
  static const int _smartLocalRefillThreshold = 3;

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
    _init();
    unawaited(_loadPersistedState());
  }

  int _pendingSeekMs = 0;

  Future<void> _loadPersistedState() async {
    final s = HiveBoxes.session;
    final p = HiveBoxes.prefs;
    _pendingSeekMs = s.get(HiveBoxes.kLastPositionMs, defaultValue: 0) as int;
    final shuffle =
        p.get(HiveBoxes.kShufflePreference, defaultValue: false) as bool;
    final repeatIdx = p.get('repeatMode', defaultValue: 0) as int;
    final loopMode =
        LoopMode.values[repeatIdx.clamp(0, LoopMode.values.length - 1)];
    state = state.copyWith(shuffleMode: shuffle, repeatMode: loopMode);
    // Apply to the just_audio player so audio behavior matches persisted UI
    // state. Without this, the player stays on LoopMode.off after a restart
    // even though the notification + UI correctly show repeat-one/all.
    if (loopMode != LoopMode.off) {
      await player.setLoopMode(loopMode);
    }
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

  Duration _scrobbleThreshold = Duration.zero;
  bool _hasScrobbled = false;
  String? _currentScrobbleSongId;
  Duration _scrobbleListenDuration = Duration.zero;
  DateTime? _scrobblePlayStart;
  Duration _lastKnownPosition = Duration.zero;
  int _lastKnownIndex = 0;
  // Ordering-independent listen ratio snapshot.
  // Updated on every positionStream tick for the currently tracked index.
  // Consumed (then reset) in the completion/skip handler — NOT in the media
  // item listener — so callback ordering between streams is irrelevant.
  Duration _positionAtCompletion = Duration.zero;
  int _trackedIndexForCompletion = -1;
  // True after processingState==completed sends natural-completion feedback.
  // Prevents double-fire in mediaItem.listen when the completed-state handler
  // already covered the song (Linux all tracks; non-Linux last track/edge cases).
  bool _naturalFeedbackSent = false;
  bool _isShuffling = false;
  bool get isShuffling => _isShuffling;
  int _lastPersistSecond = -1;

  void _init() {
    _lastKnownIndex = _audioHandler.currentIndex;

    _subscriptions.add(
      _audioHandler.mediaItem.listen((mediaItem) {
        if (mediaItem == null) return;
        final index = state.queue.indexWhere((s) => s.id == mediaItem.id);
        if (index == -1) return;

        if (_pendingIndexAfterShuffle != null) {
          if (index == _pendingIndexAfterShuffle) {
            _pendingIndexAfterShuffle = null;
            _shuffleGuardTimer?.cancel();
            _shuffleGuardTimer = null;
            _shuffleSettling = false;
            // BUG-004 FIX (Change 3): Sync internal tracking variable when the
            // guard resolves early (player emits the correct index before the
            // 500ms timer fires). Without this, _lastKnownIndex stays at a
            // pre-shuffle value and the next stream event is processed with
            // stale prevIndex, causing the UI to accept a transient index=0.
            _lastKnownIndex = index;
          } else {
            return; // Drop transient event
          }
        }

        if (_suppressEvents) return;

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
        // Track the new index for the completion snapshot.
        // Do NOT reset _positionAtCompletion here — it must still hold the
        // previous song's last position until the completion handler consumes it.
        _trackedIndexForCompletion = index;

        if (analyticsEnabled && newSong != null) {
          final sourceCtx = _nextSourceContext;
          final transCtx = _nextTransitionType;
          _nextSourceContext = 'autoplay';
          _nextTransitionType = 'autoplay';

          // ── Natural-completion feedback (autoplay transition) ──────────────
          // Two-path architecture:
          //   PRIMARY:  processingState==completed handler fires first and sets
          //             _naturalFeedbackSent=true. This covers:
          //               • Linux — all tracks (single-source bridge always goes
          //                 through completed).
          //               • All platforms — last track in queue.
          //               • Non-Linux — any edge case where completed fires.
          //   FALLBACK: This block, for Android mid-queue tracks where
          //             ConcatenatingAudioSource advances WITHOUT emitting
          //             ProcessingState.completed, so the primary path never
          //             runs. The _naturalFeedbackSent guard prevents
          //             double-firing when the primary path already fired.
          if (transCtx == 'autoplay' && prevSong != null && !_naturalFeedbackSent) {
            final listenRatio = prevSong.duration > 0
                ? (positionAtSwitch.inSeconds / prevSong.duration).clamp(0.0, 1.0)
                : 1.0;
            final shuffleNotifier = _ref.read(shuffleQueueProvider.notifier);
            shuffleNotifier.recordPlay(
              title: prevSong.title,
              listenRatio: listenRatio,
              endReason: 'natural',
            );
            sendShuffleFeedback(_ref, FeedbackRequest(
              title:        prevSong.title,
              filePath:     prevSong.id,
              genreBucket:  prevSong.genre.isNotEmpty ? prevSong.genre : 'unknown',
              composer:     prevSong.composer.isNotEmpty ? prevSong.composer : prevSong.artist,
              listenRatio:  listenRatio,
              endReason:    'natural',
              sessionId:    shuffleNotifier.sessionId,
              sessionDepth: shuffleNotifier.state.sessionDepth,
            ));
          }
          // Reset for the next track regardless of which path fired.
          _naturalFeedbackSent = false;

          _trackChangeTimer?.cancel();
          final capturedPrev = prevSong;
          final capturedNew = newSong;
          final capturedPos = positionAtSwitch;
          final capturedIdx = index;
          final capturedShuffle = state.shuffleMode;

          _trackChangeTimer = Timer(const Duration(milliseconds: 200), () {
            if (!mounted) return;
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

        if (state.queue.isNotEmpty) {
          final remainingAhead = state.queue.length - 1 - index;
          if (isSmartLocal && remainingAhead <= _smartLocalRefillThreshold) {
            // Only refill if there are songs left in the pool.
            if (_playlistPool.isNotEmpty) {
              _triggerSmartLocalFetchIfNeeded();
            }
          } else if (state.autoplayMode && !isSmartLocal) {
            final queueLen = state.queue.length;
            if (index >= queueLen - 3) {
              _triggerAutoplayIfNeeded();
            }
          }
        }
      }),
    );

    bool? _lastPlaying;
    LoopMode? _lastLoopMode;
    AudioProcessingState? _lastProcessingState;

    _subscriptions.add(
      _audioHandler.playbackState.listen((ps) async {
        if (_suppressEvents) return;

        // 1. Handle playing state changes
        final playing = ps.playing;
        if (playing != _lastPlaying) {
          _lastPlaying = playing;
          if (playing && _scrobblePlayStart == null) {
            _scrobblePlayStart = DateTime.now();
          } else if (!playing && _scrobblePlayStart != null) {
            _scrobbleListenDuration += DateTime.now().difference(
              _scrobblePlayStart!,
            );
            _scrobblePlayStart = null;
          }
          state = state.copyWith(isPlaying: playing);
        }

        // 2. Handle loop mode changes
        final loopMode =
            const {
              AudioServiceRepeatMode.none: LoopMode.off,
              AudioServiceRepeatMode.one: LoopMode.one,
              AudioServiceRepeatMode.all: LoopMode.all,
              AudioServiceRepeatMode.group: LoopMode.all,
            }[ps.repeatMode] ??
            LoopMode.off;

        if (loopMode != _lastLoopMode) {
          _lastLoopMode = loopMode;
          state = state.copyWith(repeatMode: loopMode);
        }

        // 3. Handle processing state changes
        final processingState = ps.processingState;
        if (processingState != _lastProcessingState) {
          _lastProcessingState = processingState;
          if (processingState == AudioProcessingState.completed) {
            // ── Natural completion feedback ───────────────────────────────────
            // Send shuffle feedback for ALL natural track completions here,
            // regardless of position in queue. This is the only safe location
            // because on non-Linux the subsequent skipToNext() call is wrapped
            // in _suppressDepth++, which causes mediaItem.listen (the previous
            // home for mid-queue feedback) to be suppressed and silently skip
            // the sendShuffleFeedback call.
            if (state.queue.isNotEmpty &&
                state.currentIndex < state.queue.length) {
              final completedSong = state.queue[state.currentIndex];

              // Consume the ordering-safe snapshot, then reset it.
              // Reading _positionAtCompletion here is safe regardless of which
              // stream (mediaItem vs processingState) fired first — the snapshot
              // is only zeroed AFTER we read it, not in the media item listener.
              final snapshot = _positionAtCompletion;
              _positionAtCompletion = Duration.zero;
              _trackedIndexForCompletion = -1;

              final listenRatio = completedSong.duration > 0
                  ? (snapshot.inSeconds / completedSong.duration).clamp(0.0, 1.0)
                  : 1.0;
              final shuffleNotifier = _ref.read(shuffleQueueProvider.notifier);

              // Primary path: send feedback and mark it sent so the
              // mediaItem.listen fallback path skips this song.
              _naturalFeedbackSent = true;
              _collector.onSongEnded(completedSong, player.position);
              shuffleNotifier.recordPlay(
                title: completedSong.title,
                listenRatio: listenRatio,
                endReason: 'natural',
              );
              sendShuffleFeedback(_ref, FeedbackRequest(
                title:        completedSong.title,
                filePath:     completedSong.id,
                genreBucket:  completedSong.genre.isNotEmpty ? completedSong.genre : 'unknown',
                composer:     completedSong.composer.isNotEmpty ? completedSong.composer : completedSong.artist,
                listenRatio:  listenRatio,
                endReason:    'natural',
                sessionId:    shuffleNotifier.sessionId,
                sessionDepth: shuffleNotifier.state.sessionDepth,
              ));
            }

            // BUG-001 FIX: If there are more songs ahead, explicitly advance.
            // On Linux, the NaviAudioHandler._startLinuxCompletionListener handles
            // advancement via the single-source bridge. Calling skipToNext() here
            // would cause a race with _linuxLoadTrack ("Loading interrupted").
            if (!PlatformUtils.isLinux &&
                state.currentIndex < state.queue.length - 1) {
              _suppressDepth++;
              try {
                await _audioHandler.skipToNext();
              } finally {
                _suppressDepth--;
              }
              return;
            }

            // We're on the last track — attempt autoplay (fetch similar songs).
            if (!state.autoplayMode) return;
            _triggerAutoplayIfNeeded();
          }
        }
      }),
    );

    Duration prevPosition = Duration.zero;
    _subscriptions.add(
      AudioService.position.listen((position) {
        if (_audioHandler.currentIndex == _lastKnownIndex) {
          _lastKnownPosition = position;
        }
        // Update the ordering-safe completion snapshot using integer index
        // comparison (O(1), no string allocation, no Riverpod state read).
        if (_audioHandler.currentIndex == _trackedIndexForCompletion &&
            _trackedIndexForCompletion >= 0) {
          _positionAtCompletion = position;
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
          Duration totalListened = _scrobbleListenDuration;
          if (state.isPlaying && _scrobblePlayStart != null) {
            totalListened += DateTime.now().difference(_scrobblePlayStart!);
          }
          final positionMet = totalListened >= _scrobbleThreshold;
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
    _ref.read(shuffleQueueProvider.notifier).clearQueue();
  }

  // ── Playlist pool helpers ─────────────────────────────────────────────────

  /// Initialise the pool with all playlist songs except the seed song.
  /// Shuffles the pool so the server sees variety across refill batches.
  void _initPlaylistPool(List<Song> allSongs, String seedId) {
    _playlistPool = List<Song>.from(allSongs)
      ..removeWhere((s) => s.id == seedId)
      ..shuffle(Random());
  }

  /// Remove songs already in the queue from the pool (called after each
  /// successful commit so we never re-queue a song).
  void _drainPoolOfQueuedSongs() {
    final queuedIds = state.queue.map((s) => s.id).toSet();
    _playlistPool.removeWhere((s) => queuedIds.contains(s.id));
  }

  /// Take up to [_smartLocalBatchSize] songs from the front of the pool.
  /// Returns an empty list when the pool is exhausted.
  List<Song> _takeFromPool([int? count]) {
    final n = min(count ?? _smartLocalBatchSize, _playlistPool.length);
    if (n == 0) return [];
    final batch = _playlistPool.sublist(0, n);
    _playlistPool = _playlistPool.sublist(n);
    return batch;
  }

  @override
  void dispose() {
    _shuffleGuardTimer?.cancel();
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
    debugPrint('🎵 [PlayerProvider] setQueue called with ${songs.length} songs, start: $startIndex');
    await _queueOpLock?.future;
    final completer = Completer<void>();
    _queueOpLock = completer;
    try {
      _clearHistory(); // also calls shuffleNotifier.clearQueue() → _sessionId = null
      _ref.read(shuffleQueueProvider.notifier).initSession(); // start session so feedback fires
      _playlistPool = []; // clear pool — not a playlist-shuffle context
      _nextSourceContext = 'user_queue';
      _nextTransitionType = 'user_selected';
      _suppressDepth++;
      try {
        state = state.copyWith(queue: songs, currentIndex: startIndex);
        await _audioHandler.setQueue(songs, startIndex);
        // Fix 2: init completion tracking for the first song, which doesn't
        // arrive via the media item change callback.
        if (songs.isNotEmpty) {
          _trackedIndexForCompletion = startIndex;
          _positionAtCompletion = Duration.zero;
        }
      } finally {
        _suppressDepth--;
      }
      if (_pendingSeekMs > 0) {
        try {
          await player.seek(Duration(milliseconds: _pendingSeekMs));
        } catch (_) {}
        _pendingSeekMs = 0;
      }
      player.play();
    } finally {
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  // ---------------------------------------------------------------------------
  // playPlaylist
  //
  // FIX-SHUFFLE-LAG + 16-song smart queue:
  //
  // OLD: load ALL songs → HTTP fetch for full count → setAudioSource(all)
  //      → lag = HTTP wait + building N audio sources
  //
  // NEW (smartLocal):
  //   1. Pick random start song.
  //   2. Build _playlistPool from remaining songs (shuffled).
  //   3. Take first batch (up to 16) from pool.
  //   4. HTTP fetch: ask server to order those 16 relative to seed.
  //      count=16 instead of count=N — much faster response.
  //   5. setAudioSource with only [seed + 16] = 17 sources total.
  //      Playback starts immediately.
  //   6. When song 13 starts, _triggerSmartLocalFetchIfNeeded() fires,
  //      takes next 16 from pool, fetches ordering, appends silently.
  //
  // The pool enforces client-side playlist isolation — songs outside the
  // original playlist.songs list never enter the queue.
  // ---------------------------------------------------------------------------
  Future<void> playPlaylist(
    List<Song> songs, {
    bool shuffle = false,
    String? playlistName,
  }) async {
    debugPrint('🎵 [PlayerProvider] playPlaylist called with ${songs.length} songs, shuffle: $shuffle, name: $playlistName');
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

      // ── Non-shuffle: load all songs, play from index 0 ──────────────────
      if (!shuffle) {
        _playlistPool = [];
        _suppressDepth++;
        _ref.read(shuffleQueueProvider.notifier).initSession(); // session for feedback
        try {
          state = state.copyWith(
            shuffleMode: false,
            queue: songs,
            currentIndex: 0,
          );
          await _audioHandler.setQueue(songs, 0, unshuffledSongs: songs);
        } finally {
          _suppressDepth--;
        }
        player.play();
        return;
      }

      // Suppress stream events BEFORE emitting shuffleMode:true.
      // Without this, Riverpod listeners that watch shuffleMode react to the
      // state change and call applyShuffleAlgorithm(), firing a second /next
      // request with the wrong playlist context (kuthu instead of melody).
      _shuffleSettling = true;
      _isShuffling = true;

      try {
        final startIndex = Random().nextInt(songs.length);
        final currentSong = songs[startIndex];

        // ── Smart Local: 16-song initial load, pool-based refill ──────────
        if (settings.shuffleAlgorithm == ShuffleAlgorithm.smartLocal) {
          // 1. Initialise pool with all songs except the seed.
          _initPlaylistPool(songs, currentSong.id);

          // 2. Take the first batch from the pool (up to 16).
          final firstBatch = _takeFromPool(_smartLocalBatchSize);

          // 3. Ask server to order the first batch relative to seed.
          final shuffleNotifier = _ref.read(shuffleQueueProvider.notifier);
          shuffleNotifier.initSession(); // Fix: Ensure session exists for feedback
          List<Song>? ordered;
          try {
            final candidateTitles = firstBatch.map((s) => s.title).toList();

            shuffleNotifier.recordPlay(
              title: currentSong.title,
              listenRatio: 1.0,
              endReason: 'natural',
            );

            debugPrint('🎵 [PlayerProvider] shuffleNotifier.fetchNext(source: smart, candidates: ${candidateTitles.length})');
            // source: 'smart' because playPlaylist has no Navidrome playlistId.
            // candidates constrains the server to score only the pool batch.
            final response = await shuffleNotifier.fetchNext(
              source: 'smart',
              playlistName: playlistName,
              candidates: candidateTitles,
              count: firstBatch.length,
            );
            if (!mounted) return;

            // Map recommendations back to local Songs using title+artist compound key
            // to handle same-title remixes common in Tamil film music.
            final resolved = <Song>[];
            for (final rec in response.queue) {
              final match = songs.firstWhereOrNull(
                (s) =>
                    s.title.toLowerCase() == rec.title.toLowerCase() &&
                    s.artist.toLowerCase() == rec.composer.toLowerCase(),
              ) ?? songs.firstWhereOrNull(
                // Fallback to title-only if artist mismatch (e.g. various-artists albums)
                (s) => s.title.toLowerCase() == rec.title.toLowerCase(),
              );
              if (match != null && !resolved.contains(match)) {
                resolved.add(match);
              }
            }

            // Pad with any unmatched firstBatch songs to guarantee ~16 songs
            for (final s in firstBatch) {
              if (!resolved.contains(s) && resolved.length < firstBatch.length) {
                resolved.add(s);
              }
            }
            ordered = resolved;
          } catch (e) {
            debugPrint('[Smart Local Init] API Error: $e');
            ordered = null;
          }

          // 4. Build initial queue: seed + ordered batch (or raw batch on
          //    server failure). Pool songs not in this batch stay in pool.
          final initialQueue = [currentSong, ...(ordered ?? firstBatch)];

          // Emit shuffleMode:true together with the ready queue in one
          // copyWith so no intermediate state is ever broadcast.
          state = state.copyWith(
            shuffleMode: true,
            queue: initialQueue,
            currentIndex: 0,
          );
          await _audioHandler.setQueue(initialQueue, 0, unshuffledSongs: songs);
          // Fix 2: init completion tracking for the first song (seed at index 0).
          _trackedIndexForCompletion = 0;
          _positionAtCompletion = Duration.zero;
          _shuffleSettling = false;
          player.play();

          // 5. Remove anything we just queued from the pool (safety drain).
          _drainPoolOfQueuedSongs();

          // v3.0.0: session reset is handled server-side; no client call needed.
        } else {
          // ── Other algorithms: original behaviour, full pool ──────────────
          _playlistPool = [];
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
          // Emit shuffleMode:true + queue in one copyWith — same guard as
          // the smartLocal branch above to prevent double applyShuffleAlgorithm.
          state = state.copyWith(
            shuffleMode: true,
            queue: finalQueue,
            currentIndex: 0,
          );
          await _audioHandler.setQueue(finalQueue, 0, unshuffledSongs: songs);
          _shuffleSettling = false;
          player.play();
        }
      } finally {
        _isShuffling = false;
        // Safety: ensure _shuffleSettling is cleared if any branch exited early
        // (e.g. !mounted or stale lock check) without explicitly clearing it.
        _shuffleSettling = false;
      }
    } finally {
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  void refreshShuffleUrl() {}

  Future<void> playNext() async {
    debugPrint('🎵 [PlayerProvider] playNext');
    await _queueOpLock?.future;
    if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
      final currentSong = state.queue[state.currentIndex];
      _pushToHistory(currentSong);
      if (_lastKnownPosition.inSeconds < 30) {
        _ref.read(recommendationProvider).trackSkip(currentSong);
      }

      // Consume the ordering-safe position snapshot, then reset it.
      final snapshot = _positionAtCompletion;
      _positionAtCompletion = Duration.zero;
      _trackedIndexForCompletion = -1;

      final listenRatio = currentSong.duration > 0
          ? (snapshot.inSeconds / currentSong.duration).clamp(0.0, 1.0)
          : 0.0;
      final shuffleNotifier = _ref.read(shuffleQueueProvider.notifier);
      shuffleNotifier.recordPlay(
        title: currentSong.title,
        listenRatio: listenRatio,
        endReason: 'fwdbtn',
      );
      sendShuffleFeedback(_ref, FeedbackRequest(
        title:        currentSong.title,
        filePath:     currentSong.id,
        genreBucket:  currentSong.genre.isNotEmpty ? currentSong.genre : 'unknown',
        composer:     currentSong.composer.isNotEmpty ? currentSong.composer : currentSong.artist,
        listenRatio:  listenRatio,
        endReason:    'fwdbtn',
        sessionId:    shuffleNotifier.sessionId,
        sessionDepth: shuffleNotifier.state.sessionDepth,
      ));
    }

    _suppressNextHistoryPush = true;
    _nextTransitionType = 'manual_next';
    _nextSourceContext = 'manual_next';

    // Always route through the handler — on Linux it calls _linuxSkipToNext()
    // which loads the next track via the single-source bridge. On other platforms
    // it calls player.seekToNext() as before.
    await _audioHandler.skipToNext();
  }

  Future<void> stop() async {
    _hasScrobbled = false;
    _currentScrobbleSongId = null;
    _scrobbleListenDuration = Duration.zero;
    _scrobblePlayStart = null;
    await player.stop();
  }

  Future<void> playPrev() async {
    debugPrint('🎵 [PlayerProvider] playPrev');
    await _queueOpLock?.future;
    try {
      if (player.position.inSeconds > 3) {
        await player.seek(Duration.zero);
        return;
      }
      final historySong = _popFromHistory();
      if (historySong != null) {
        // historyIndex is a resolved queue index (sublist search by song id),
        // so passing it to jumpToIndex is safe on all platforms.
        final historyIndex = state.queue
            .sublist(0, state.currentIndex)
            .lastIndexWhere((s) => s.id == historySong.id);
        _suppressNextHistoryPush = true;
        if (historyIndex >= 0) {
          await _audioHandler.jumpToIndex(historyIndex);
          state = state.copyWith(currentIndex: historyIndex);
        } else {
          final prevIdx = state.currentIndex > 0 ? state.currentIndex - 1 : 0;
          await _audioHandler.jumpToIndex(prevIdx);
          state = state.copyWith(currentIndex: prevIdx);
        }
        return;
      }
      // No history — fall back to handler's skipToPrevious (Linux-aware).
      _suppressNextHistoryPush = true;
      await _audioHandler.skipToPrevious();
    } catch (e, stack) {
      debugPrint('playPrev failed: $e\n$stack');
      _suppressNextHistoryPush = true;
      final prevIdx = state.currentIndex > 0 ? state.currentIndex - 1 : 0;
      await _audioHandler.jumpToIndex(prevIdx);
    }
  }

  Future<void> jumpTo(int index) async {
    debugPrint('🎵 [PlayerProvider] jumpTo: $index');
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
    // On Linux, player.seek(Duration.zero, index: index) is silently ignored
    // because only one source is loaded at a time. Route through the handler
    // which calls _linuxLoadTrack and updates _linuxIndex correctly.
    await _audioHandler.jumpToIndex(index);
    state = state.copyWith(currentIndex: index);
  }

  Future<void> addToQueue(Song song) async {
    debugPrint('🎵 [PlayerProvider] addToQueue: ${song.title}');
    await _queueOpLock?.future;
    final completer = Completer<void>();
    _queueOpLock = completer;
    try {
      final currentQueue = List<Song>.from(state.queue)..add(song);
      state = state.copyWith(queue: currentQueue);
      await _audioHandler.addToQueue(song);
    } finally {
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  /// Batch-add multiple songs — single state update → single UI rebuild.
  /// Uses the handler's batch method for a single platform-channel round trip.
  Future<void> addAllToQueue(List<Song> songs) async {
    debugPrint('🎵 [PlayerProvider] addAllToQueue: ${songs.length} songs');
    if (songs.isEmpty) return;
    await _queueOpLock?.future;
    final completer = Completer<void>();
    _queueOpLock = completer;
    try {
      final currentQueue = List<Song>.from(state.queue)..addAll(songs);
      state = state.copyWith(queue: currentQueue);
      await _audioHandler.addAllToQueue(songs);
    } finally {
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  Future<void> removeFromQueue(int index) async {
    debugPrint('🎵 [PlayerProvider] removeFromQueue at index: $index');
    await _queueOpLock?.future;
    final completer = Completer<void>();
    _queueOpLock = completer;
    _suppressDepth++;
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
      _suppressDepth--;
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    await _queueOpLock?.future;
    final completer = Completer<void>();
    _queueOpLock = completer;
    _suppressDepth++;
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
      _suppressDepth--;
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
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
    _shuffleGuardTimer?.cancel();
    final completer = Completer<void>();
    _queueOpLock = completer;
    _isShuffling = true;
    _shuffleSettling = true;
    _playlistPool = []; // clear pool on unshuffle
    try {
      await _audioHandler.unshuffle();
      final postIndex = _audioHandler.currentIndex;
      state = state.copyWith(
        queue: _audioHandler.currentQueue,
        currentIndex: postIndex,
      );
      // BUG-004 FIX (Change 1): Keep internal tracking in sync after unshuffle
      // so the stream handler uses the correct prevIndex when events resume.
      _lastKnownIndex = postIndex;

      _pendingIndexAfterShuffle = postIndex;
      _shuffleGuardTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _pendingIndexAfterShuffle = null;
        // BUG-004 FIX (Change 2): Sync _lastKnownIndex when the guard timer
        // fires so that the first stream event processed after suppression ends
        // has a correct prevIndex. Without this, a transient index=0 from
        // just_audio is accepted as a legitimate track change.
        //
        // ACCEPTED TRADE-OFF: _shuffleSettling stays true for 500ms after
        // unshuffle. Any play/pause taps within that window are dropped. This
        // is intentional to prevent stale just_audio stream events from racing
        // with the new queue order. The 500ms window is imperceptible to users.
        _lastKnownIndex = state.currentIndex;
        _shuffleSettling = false;
      });
    } finally {
      _isShuffling = false;
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  Future<void> applyShuffleAlgorithm() async {
    final settings = _ref.read(settingsProvider);

    if (settings.shuffleAlgorithm == ShuffleAlgorithm.smartLocal) {
      await _applySmartLocalAlgorithm(settings);
      return;
    }

    _shuffleGuardTimer?.cancel();
    final completer = Completer<void>();
    _queueOpLock = completer;
    _isShuffling = true;
    _shuffleSettling = true;
    try {
      // BUG-004 FIX: Capture the current song by ID before shuffle, not by
      // integer index. After the shuffle await completes, the integer index
      // is stale because the queue has been reordered.
      final preShuffleIndex = _audioHandler.currentIndex;
      final currentSongId = preShuffleIndex < _audioHandler.currentQueue.length
          ? _audioHandler.currentQueue[preShuffleIndex].id
          : null;

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
          break;
      }

      // BUG-004 FIX: Find the current song in the new shuffled queue by ID.
      // The player's currentIndex after shuffle may be null or unreliable,
      // so we look up the song we were playing before shuffle by its ID.
      int postShuffleIndex = _audioHandler.currentIndex;
      if (currentSongId != null) {
        final foundIndex = _audioHandler.currentQueue.indexWhere(
          (s) => s.id == currentSongId,
        );
        if (foundIndex != -1) {
          postShuffleIndex = foundIndex;
        }
      }
      state = state.copyWith(
        queue: _audioHandler.currentQueue,
        currentIndex: postShuffleIndex,
      );
      // BUG-004 FIX (Change 1): Keep internal tracking in sync after
      // non-smartLocal shuffle so the stream handler uses the correct prevIndex
      // when events resume after the suppression window closes.
      _lastKnownIndex = postShuffleIndex;

      _pendingIndexAfterShuffle = postShuffleIndex;
      _shuffleGuardTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _pendingIndexAfterShuffle = null;
        // BUG-004 FIX (Change 2): Sync _lastKnownIndex on timer expiry.
        // ACCEPTED TRADE-OFF: _shuffleSettling stays true for 500ms after
        // each shuffle algorithm runs. This suppresses play/pause events in
        // that window — intentional to block transient just_audio emissions
        // that arrive while move-based reordering settles.
        _lastKnownIndex = state.currentIndex;
        _shuffleSettling = false;
      });
    } finally {
      _isShuffling = false;
      completer.complete();
      if (_queueOpLock == completer) _queueOpLock = null;
    }
  }

  Future<void> _applySmartLocalAlgorithm(SettingsState settings) async {
    await _queueOpLock?.future;

    _shuffleGuardTimer?.cancel();

    // BUG-FIX: Acquire the lock BEFORE the HTTP fetch so no concurrent queue
    // operation (e.g. user tapping next) can race in during computeSmartLocalOrder.
    final outerCompleter = Completer<void>();
    _queueOpLock = outerCompleter;
    _isShuffling = true;
    _shuffleSettling = true;

    final safeIndex = (_audioHandler.currentIndex).clamp(
      0,
      _audioHandler.currentQueue.length - 1,
    );
    final pastAndPresent = List<Song>.from(
      _audioHandler.currentQueue.sublist(0, safeIndex + 1),
    );
    final future = List<Song>.from(
      _audioHandler.currentQueue.sublist(safeIndex + 1),
    );
    final currentSong = _audioHandler.currentQueue[safeIndex];

    if (future.isEmpty) {
      _isShuffling = false;
      _shuffleSettling = false;
      outerCompleter.complete();
      if (_queueOpLock == outerCompleter) _queueOpLock = null;
      return;
    }

    List<Song>? ordered;
    try {
      final shuffleNotifier = _ref.read(shuffleQueueProvider.notifier);
      final candidateTitles = future.map((s) => s.title).toList();
      debugPrint('🎵 [PlayerProvider] shuffleNotifier.fetchNext(source: smart, candidates: ${candidateTitles.length})');

      // source is always 'smart': the app has no Navidrome playlist_id here, so
      // playlist isolation is enforced by `candidates`. playlist_name only sets the
      // server-side genre streak and is passed regardless of mode.
      final response = await shuffleNotifier.fetchNext(
        source: 'smart',
        playlistName: _currentPlaylistName,
        candidates: candidateTitles,
        count: candidateTitles.length,
      );
      if (!mounted) return;

      final resolved = <Song>[];
      for (final rec in response.queue) {
        final match = future.firstWhereOrNull(
          (s) =>
              s.title.toLowerCase() == rec.title.toLowerCase() &&
              s.artist.toLowerCase() == rec.composer.toLowerCase(),
        ) ?? future.firstWhereOrNull(
          (s) => s.title.toLowerCase() == rec.title.toLowerCase(),
        );
        if (match != null && !resolved.contains(match)) {
          resolved.add(match);
        }
      }

      for (final s in future) {
        if (!resolved.contains(s)) resolved.add(s);
      }
      ordered = resolved;
    } catch (e) {
      debugPrint('[Smart Local Shuffle] API Error: $e');
      ordered = null;
    }

    if (ordered == null) {
      // Server unavailable — fall back to standard shuffle.
      try {
        await _audioHandler.standardShuffle();
        // Use ID-based lookup to find current song's new position.
        int postShuffleIndex = safeIndex;
        final foundIdx = _audioHandler.currentQueue.indexWhere(
          (s) => s.id == currentSong.id,
        );
        if (foundIdx != -1) postShuffleIndex = foundIdx;
        // BUG-004 FIX (Change 1 – fallback path): sync _lastKnownIndex after
        // the fallback standardShuffle so the stream handler is not stale.
        _lastKnownIndex = postShuffleIndex;
        _pendingIndexAfterShuffle = postShuffleIndex;
        _shuffleGuardTimer = Timer(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          _pendingIndexAfterShuffle = null;
          // BUG-004 FIX (Change 2 – fallback timer): re-sync on expiry.
          _lastKnownIndex = state.currentIndex;
          _shuffleSettling = false;
        });
      } finally {
        _isShuffling = false;
        outerCompleter.complete();
        if (_queueOpLock == outerCompleter) _queueOpLock = null;
      }
      return;
    }

    try {
      final liveIndex = _audioHandler.currentIndex;
      if (liveIndex != safeIndex) {
        debugPrint(
          '⚠️ [applyShuffleAlgorithm] Smart Local: player advanced '
          'during fetch ($safeIndex→$liveIndex), discarding stale order',
        );
        state = state.copyWith(
          queue: _audioHandler.currentQueue,
          currentIndex: liveIndex,
        );
        return;
      }

      await _audioHandler.commitSmartLocalOrder(
        pastAndPresent: pastAndPresent,
        orderedFuture: ordered,
        anchorIndex: safeIndex,
      );
      // v3.0.0: session reset is handled server-side.

      // BUG-FIX: Do NOT read _audioHandler.currentIndex here — just_audio updates it
      // asynchronously via its stream and may still reflect the old position
      // (typically 0) immediately after commitSmartLocalOrder returns.
      // safeIndex IS the anchor and the current song stays at that position
      // after a move-based reorder, so use it directly.
      state = state.copyWith(
        queue: _audioHandler.currentQueue,
        currentIndex: safeIndex,
      );
      // BUG-004 FIX (Change 1 – smartLocal success path): sync _lastKnownIndex
      // immediately after the queue is committed and state is written. This is
      // the primary fix: without it, _lastKnownIndex stays at a pre-shuffle
      // value and the guard timer's expiry allows transient index=0 events to
      // be accepted as legitimate track changes, desyncing the UI tile.
      _lastKnownIndex = safeIndex;

      _pendingIndexAfterShuffle = safeIndex;
      _shuffleGuardTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _pendingIndexAfterShuffle = null;
        // BUG-004 FIX (Change 2 – smartLocal timer): re-sync _lastKnownIndex
        // on guard expiry. state.currentIndex is the authoritative value here
        // because it was set from safeIndex (the anchor) and not mutated during
        // the suppression window.
        _lastKnownIndex = state.currentIndex;
        _shuffleSettling = false;
      });
    } finally {
      _isShuffling = false;
      outerCompleter.complete();
      if (_queueOpLock == outerCompleter) _queueOpLock = null;
    }
  }

  Future<void> cycleRepeat() async {
    final LoopMode nextMode;
    switch (state.repeatMode) {
      case LoopMode.off:
        nextMode = LoopMode.one; // first tap → repeat single song
        break;
      case LoopMode.one:
        nextMode = LoopMode.all; // second tap → repeat playlist
        break;
      case LoopMode.all:
        nextMode = LoopMode.off; // third tap → off
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
    HiveBoxes.prefs.put(HiveBoxes.kAutoplayPreference, newMode);
    state = state.copyWith(autoplayMode: newMode);
    if (newMode && state.queue.isNotEmpty) {
      _triggerAutoplayIfNeeded();
    }
  }

  /// Clears all queued songs and stops playback. Used when the user explicitly
  /// wants to exit AI Shuffle and start fresh.
  ///
  /// IMPORTANT: This method resets shuffleMode to false. If the intent is to
  /// stay in shuffle mode but clear the queue, the caller should re-enable it.
  Future<void> clearAiShuffleQueue() async {
    // 1. Pause to prevent autoplay/lookahead from racing
    await player.pause();

    // 2. Drain the pool completely
    _playlistPool = [];

    // 3. Cancel any pending shuffle guards
    _shuffleGuardTimer?.cancel();
    _shuffleGuardTimer = null;
    _pendingIndexAfterShuffle = null;
    // Hard player reset — clear both suppression mechanisms.
    _suppressDepth = 0;
    _shuffleSettling = false;

    // 4. Stop the player
    await player.stop();

    // 5. Clear the audio handler's source
    await _audioHandler.clearQueue();

    // 6. Reset state
    _lastKnownIndex = 0;
    _lastFetchedForSongId = null;
    state = state.copyWith(
      queue: [],
      currentIndex: 0,
      shuffleMode: false,
      isPlaying: false,
      history: [],
    );

    // 7. Persist cleared state
    _persistState();
  }

  // ---------------------------------------------------------------------------
  // Active-playback Reshuffle — POST /next with reshuffle:true
  //
  // Collects every song title currently in the player queue (played + upcoming),
  // sends them as excluded_titles to the server so none are repeated, and
  // replaces the entire player queue with the fresh batch.
  //
  // Session context (depth, playedTitles, listenRatios) is preserved in
  // ShuffleQueueNotifier — no clearQueue() is called here.
  //
  // [allSongs] — the caller must pass ref.read(allSongsProvider.future) so
  //              this pure-Dart notifier doesn't need to hold a Riverpod ref
  //              to an async provider.
  // ---------------------------------------------------------------------------

  /// Returns true if a reshuffle is currently in progress.
  bool _isReshuffling = false;
  bool get isReshuffling => _isReshuffling;

  /// Replaces the active playback queue with a fresh 16-song batch from the
  /// server, banning every song title that is currently in the queue.
  ///
  /// Throws on API or resolution failure — callers should catch and show a
  /// snack-bar. On success, the new queue starts playing from index 0.
  Future<void> reshuffleActiveQueue(List<Song> allSongs) async {
    if (_isReshuffling) return;
    _isReshuffling = true;
    try {
      // Ban everything in the queue so the server returns fully fresh songs.
      final excludedTitles = state.queue.map((s) => s.title).toList();
      if (excludedTitles.isEmpty) return;

      final shuffleNotifier = _ref.read(shuffleQueueProvider.notifier);

      // POST /next with reshuffle:true — session depth + played_titles preserved.
      final recommendations = await shuffleNotifier.reshuffle(
        source: 'smart',
        playlistName: _currentPlaylistName,
        excludedTitlesOverride: excludedTitles,
      );

      if (!mounted) return;

      // Resolve RecommendedSongs → local Song objects.
      final resolved = <Song>[];
      for (final rec in recommendations) {
        final match = allSongs.firstWhereOrNull(
              (s) =>
          s.title.toLowerCase() == rec.title.toLowerCase() &&
              s.artist.toLowerCase() == rec.composer.toLowerCase(),
        ) ??
            allSongs.firstWhereOrNull(
                  (s) => s.title.toLowerCase() == rec.title.toLowerCase(),
            );
        if (match != null && !resolved.contains(match)) {
          resolved.add(match);
        }
      }

      if (resolved.isEmpty) {
        throw Exception('No reshuffled songs found in local library');
      }

      await _queueOpLock?.future;
      final completer = Completer<void>();
      _queueOpLock = completer;
      _suppressDepth++;
      try {
        // Keep the currently playing song — only replace everything after it.
        final currentIdx = state.currentIndex;
        final currentSong = state.queue.isNotEmpty
            ? state.queue[currentIdx]
            : null;

        // New queue = [current song] + fresh batch.
        final newQueue = [
          if (currentSong != null) currentSong,
          ...resolved,
        ];
        final newCurrentIndex = currentSong != null ? 0 : 0;

        state = state.copyWith(queue: newQueue, currentIndex: newCurrentIndex);

        // Replace audio sources but seek back to current song so it keeps playing.
        await _audioHandler.setQueue(newQueue, newCurrentIndex);
        // The current song is now at index 0 — seek to the saved position so
        // there is no audible gap or restart.
        final savedPosition = player.position;
        await player.seek(savedPosition, index: newCurrentIndex);
        player.play();
      } finally {
        _suppressDepth--;
        completer.complete();
        if (_queueOpLock == completer) _queueOpLock = null;
      }
    } finally {
      _isReshuffling = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Autoplay — Subsonic similar songs
  // ---------------------------------------------------------------------------

  void _triggerAutoplayIfNeeded() {
    if (!state.autoplayMode || _isFetchingSimilar || state.queue.isEmpty) {
      return;
    }

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
        _lastFetchedForSongId = null; // ← Allow retry with different seed
        return;
      }

      // Capture boundary synchronously at append time (same tick as newQueue
      // construction) so it accurately reflects the first freshly-appended
      // song regardless of any concurrent queue mutations during the fetch.
      final lenBeforeAppend = state.queue.length;
      final newQueue = [...state.queue, ...fresh];
      state = state.copyWith(queue: newQueue);
      await _audioHandler.addAllToQueue(fresh);

      debugPrint(
        '[AUTOPLAY] Appended ${fresh.length} songs. Queue: ${newQueue.length}',
      );

      final currentIndexNow = state.currentIndex;
      final wasAtEnd = currentIndexNow >= lenBeforeAppend - 1;
      final userNavigatedAway = currentIndexNow < indexBeforeFetch;

      if (wasAtEnd && !userNavigatedAway) {
        // Give just_audio a frame to process the new source items
        await Future.delayed(const Duration(milliseconds: 50));
        final nextIndex = lenBeforeAppend;
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
  // Smart Local — pool-based refill at song 13
  //
  // How it works:
  //   Triggered from currentIndexStream when remainingAhead <= 3 AND
  //   _playlistPool is not empty.
  //
  //   1. Snapshot anchor (safeIndex, pastAndPresent).
  //   2. Take next batch (up to 16) from _playlistPool.
  //   3. Concurrently:
  //      A. HTTP fetch: ask server to order the batch from current song.
  //      B. addAllToQueue(batch): append sources to ConcatenatingAudioSource.
  //   4. commitSmartLocalOrder with move-based reorder (no rebuffer).
  //   5. Drain pool of anything now in queue.
  //
  // Pool enforcement: only songs originally in playlist.songs ever appear.
  // The server cannot inject outside songs because the candidate list
  // (fullFuture) is built entirely from _playlistPool + existingFuture,
  // both of which came from the original playlist.
  // ---------------------------------------------------------------------------

  void _triggerSmartLocalFetchIfNeeded() {
    if (_isFetchingSmartLocal) return;
    if (_playlistPool.isEmpty) return;

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
      debugPrint(
        '[SMART LOCAL] Refilling queue for: ${seedSong.title} '
        '(pool remaining: ${_playlistPool.length})',
      );

      // Snapshot anchor synchronously.
      final safeIndex = (_audioHandler.currentIndex).clamp(
        0,
        _audioHandler.currentQueue.length - 1,
      );
      final pastAndPresent = List<Song>.from(
        _audioHandler.currentQueue.sublist(0, safeIndex + 1),
      );
      final existingFuture = List<Song>.from(
        _audioHandler.currentQueue.sublist(safeIndex + 1),
      );

      // Take next batch from pool — strictly from the original playlist.
      final batch = _takeFromPool(_smartLocalBatchSize);
      if (batch.isEmpty) {
        debugPrint('[SMART LOCAL] Pool exhausted — no more songs to queue');
        return;
      }

      // Full future = songs already ahead + new batch.
      final fullFuture = [...existingFuture, ...batch];

      // Concurrent: HTTP ordering fetch + playlist append.
      final results = await Future.wait([
        // A: HTTP — order fullFuture relative to seedSong.
        () async {
          try {
            final shuffleNotifier = _ref.read(shuffleQueueProvider.notifier);
            final candidateTitles = fullFuture.map((s) => s.title).toList();
            debugPrint('🎵 [PlayerProvider] shuffleNotifier.fetchNext(source: smart, candidates: ${candidateTitles.length})');

            // source is always 'smart': the app has no Navidrome playlist_id here, so
            // playlist isolation is enforced by `candidates`. playlist_name only sets the
            // server-side genre streak and is passed regardless of mode.
            final response = await shuffleNotifier.fetchNext(
              source: 'smart',
              playlistName: _currentPlaylistName,
              candidates: candidateTitles,
              count: candidateTitles.length,
            );
            if (!mounted) return [];

            final resolved = <Song>[];
            for (final rec in response.queue) {
              final match = fullFuture.firstWhereOrNull(
                (s) =>
                    s.title.toLowerCase() == rec.title.toLowerCase() &&
                    s.artist.toLowerCase() == rec.composer.toLowerCase(),
              ) ?? fullFuture.firstWhereOrNull(
                (s) => s.title.toLowerCase() == rec.title.toLowerCase(),
              );
              if (match != null && !resolved.contains(match)) {
                resolved.add(match);
              }
            }

            for (final s in fullFuture) {
              if (!resolved.contains(s)) resolved.add(s);
            }
            return resolved;
          } catch (e) {
            debugPrint('[Smart Local Refill] API Error: $e');
            return null;
          }
        }(),
        // B: Append new batch to ConcatenatingAudioSource.
        // State is NOT written here — the handler is the single source of truth
        // for the queue during concurrent fetch. State is synced from
        // _audioHandler.currentQueue in the success path and fallback below.
        _audioHandler.addAllToQueue(batch).then((_) {
          debugPrint('[SMART LOCAL] Appended ${batch.length} songs from pool');
          return null;
        }),
      ]);

      final ordered = results[0] as List<Song>?;

      if (ordered == null) {
        // Server unreachable: batch already appended in random pool order.
        // Acceptable fallback — Markov ordering will apply on next rebuild.
        debugPrint('[SMART LOCAL] HTTP failed; batch appended unordered');
        // Sync state from the handler since branch B no longer writes state.
        state = state.copyWith(queue: _audioHandler.currentQueue);
        _drainPoolOfQueuedSongs();
        return;
      }

      // Check player hasn't moved past our snapshot.
      final liveIndex = _audioHandler.currentIndex;
      if (liveIndex != safeIndex) {
        debugPrint(
          '[SMART LOCAL] Player advanced during fetch '
          '($safeIndex→$liveIndex), skipping reorder',
        );
        state = state.copyWith(queue: _audioHandler.currentQueue);
        _drainPoolOfQueuedSongs();
        return;
      }

      // Commit with move-based reorder (no anchor rebuffer).
      await _audioHandler.commitSmartLocalOrder(
        pastAndPresent: pastAndPresent,
        orderedFuture: ordered,
        anchorIndex: safeIndex,
        preferMoveBasedReorder: true,
      );

      state = state.copyWith(queue: _audioHandler.currentQueue);
      _drainPoolOfQueuedSongs();

      debugPrint(
        '[SMART LOCAL] Refill complete. '
        'Queue: ${state.queue.length}  Pool: ${_playlistPool.length}',
      );
    } catch (e) {
      debugPrint('[SMART LOCAL] Refill failed: $e');
    } finally {
      fetchCompleter.complete();
    }
  }

  void clearHistory() => _clearHistory();
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final audioHandlerProvider = Provider<NaviAudioHandler>((ref) {
  return globalAudioHandler;
});

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((
  ref,
) {
  final handler = ref.watch(audioHandlerProvider);
  final service = ref.watch(subsonicServiceProvider);
  final collector = ref.watch(listenerCollectorProvider);
  return PlayerNotifier(ref, handler, service, collector);
});
