import 'dart:async';
import 'dart:io' show Platform, ProcessInfo;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' hide PlaybackState;
import 'package:collection/collection.dart';
import '../models/song.dart';
import '../services/subsonic_service.dart';
import '../services/listening_event_collector.dart';
import 'settings_provider.dart';
import '../services/navi_audio_handler.dart';
import '../core/hive_boxes.dart';
import '../core/app_constants.dart';

import '../services/scrobble_service.dart';
import '../main.dart';
import '../features/ai_shuffle/logic/shuffle_providers.dart';
import '../features/ai_shuffle/data/models/feedback_request.dart';
import '../features/ai_shuffle/data/models/recommended_song.dart';
import 'library_provider.dart';
import '../services/session_sync_service.dart';
import 'session_sync_provider.dart';
import '../features/local_library/logic/local_models.dart' show isLocalSongId;
import '../utils/async_lock.dart';
import '../utils/device_utils.dart';

// ---------------------------------------------------------------------------
// Sync mode enum
// ---------------------------------------------------------------------------
enum SyncMode {
  /// Offline / reconnecting: local playback continues, no active-device enforcement
  standalone,

  /// This device is authoritative and active
  activeHere,

  /// Another device is active; local playback engine is stopped
  passive,

  /// No active device on the server; idle session
  idle,
}

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

  // Session sync state fields (Step 5)
  final SyncMode syncMode;
  final String? remoteTrackId;
  final String? remoteTrackTitle;
  final String? remoteArtist;
  final int remotePositionMs;
  final bool remoteIsPlaying;
  final DateTime? remoteUpdatedAt;
  final String? remoteActiveDeviceName;

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
    this.syncMode = SyncMode.idle,
    this.remoteTrackId,
    this.remoteTrackTitle,
    this.remoteArtist,
    this.remotePositionMs = 0,
    this.remoteIsPlaying = false,
    this.remoteUpdatedAt,
    this.remoteActiveDeviceName,
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
    SyncMode? syncMode,
    String? remoteTrackId,
    String? remoteTrackTitle,
    String? remoteArtist,
    int? remotePositionMs,
    bool? remoteIsPlaying,
    DateTime? remoteUpdatedAt,
    String? remoteActiveDeviceName,
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
      syncMode: syncMode ?? this.syncMode,
      remoteTrackId: remoteTrackId ?? this.remoteTrackId,
      remoteTrackTitle: remoteTrackTitle ?? this.remoteTrackTitle,
      remoteArtist: remoteArtist ?? this.remoteArtist,
      remotePositionMs: remotePositionMs ?? this.remotePositionMs,
      remoteIsPlaying: remoteIsPlaying ?? this.remoteIsPlaying,
      remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
      remoteActiveDeviceName:
          remoteActiveDeviceName ?? this.remoteActiveDeviceName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerState &&
          runtimeType == other.runtimeType &&
          const ListEquality<Song>().equals(queue, other.queue) &&
          currentIndex == other.currentIndex &&
          isPlaying == other.isPlaying &&
          shuffleMode == other.shuffleMode &&
          autoplayMode == other.autoplayMode &&
          repeatMode == other.repeatMode &&
          const ListEquality<String>().equals(starredIds, other.starredIds) &&
          const ListEquality<Song>().equals(history, other.history) &&
          syncMode == other.syncMode &&
          remoteTrackId == other.remoteTrackId &&
          remoteTrackTitle == other.remoteTrackTitle &&
          remoteArtist == other.remoteArtist &&
          remotePositionMs == other.remotePositionMs &&
          remoteIsPlaying == other.remoteIsPlaying &&
          remoteUpdatedAt == other.remoteUpdatedAt &&
          remoteActiveDeviceName == other.remoteActiveDeviceName;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(queue),
        currentIndex,
        isPlaying,
        shuffleMode,
        autoplayMode,
        repeatMode,
        Object.hashAll(starredIds),
        Object.hashAll(history),
        syncMode,
        remoteTrackId,
        remoteTrackTitle,
        remoteArtist,
        remotePositionMs,
        remoteIsPlaying,
        remoteUpdatedAt,
        remoteActiveDeviceName,
      );

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
/// What a Smart Reshuffle did.
enum ReshuffleOutcome {
  /// The server picked a fresh Up Next.
  smart,

  /// The server couldn't answer; Up Next was shuffled randomly instead.
  random,

  /// The queue changed while waiting (another action won); nothing applied.
  superseded,

  /// Nothing is playing or there is nothing else to pick from.
  nothingToShuffle,
}

/// True while a Smart Reshuffle request is out — the button shows a spinner.
class SmartReshuffleBusy extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool busy) => state = busy;
}

final smartReshuffleBusyProvider = NotifierProvider<SmartReshuffleBusy, bool>(SmartReshuffleBusy.new);

class PlayerNotifier extends StateNotifier<PlayerState> {
  final Ref _ref;
  final NaviAudioHandler _audioHandler;
  final SubsonicService _subsonicService;
  final ListeningEventCollector _collector;
  final List<StreamSubscription> _subscriptions = [];

  bool _isFetchingSimilar = false;
  String? _lastFetchedForSongId;

  /// Serialises every queue mutation (see [AsyncLock]). Network calls happen
  /// outside it; results are validated against [_queueEpoch] on commit.
  final AsyncLock _queueLock = AsyncLock();

  /// Bumped by every user-initiated queue change. An async result computed
  /// for an older epoch is stale — a later action superseded it — and is
  /// dropped instead of overwriting what the listener just did. Natural track
  /// advances don't bump it; commits rebase onto the live current song.
  int _queueEpoch = 0;

  /// The in-flight Smart Reshuffle, shared by every tap until it settles.
  Future<ReshuffleOutcome>? _smartReshuffleInFlight;
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
  static const int _maxQueueSize = 50;

  Completer<void>? _smartLocalFetchCompleter;

  bool get _isFetchingSmartLocal =>
      _smartLocalFetchCompleter != null &&
      !_smartLocalFetchCompleter!.isCompleted;

  String _nextSourceContext = 'autoplay';
  String _nextTransitionType = 'autoplay';

  /// The queue index [_nextTransitionType] was set for, when known. The type
  /// is consumed by the next track-change event; if that event is for a
  /// different index, the marked change never surfaced (its event was dropped
  /// or never emitted) and this one is a natural advance, so a stale
  /// 'user_selected' can't leak onto it and block autoplay or Smart Shuffle
  /// refills.
  int? _nextTransitionIndex;

  void _markTransition(String type, {int? index}) {
    _nextTransitionType = type;
    _nextTransitionIndex = index;
  }

  String? _myDeviceId;
  Timer? _positionTickTimer;
  StreamSubscription<PlaybackState>? _syncSub;
  final Future<String> Function() _deviceIdProvider;

  PlayerNotifier(
    this._ref,
    this._audioHandler,
    this._subsonicService,
    this._collector, {
    Future<String> Function()? deviceIdProvider,
  })  : _deviceIdProvider = deviceIdProvider ?? getOrCreateDeviceId,
        super(
          const PlayerState(
            queue: [],
            currentIndex: 0,
            isPlaying: false,
            shuffleMode: false,
            autoplayMode: false,
            repeatMode: LoopMode.off,
            starredIds: [],
            history: [],
            syncMode: SyncMode.idle,
          ),
        ) {
    _init();
    unawaited(_initSync());
    unawaited(_loadPersistedState());
  }

  Future<void> _initSync() async {
    try {
      _myDeviceId = await _deviceIdProvider();
      final syncService = _ref.read(sessionSyncServiceProvider);
      _syncSub = syncService.stateStream.listen(_onSyncStateChanged);
      _onSyncStateChanged(syncService.currentState);
    } catch (e) {
      debugPrint('[PlayerNotifier] ℹ️ SessionSyncService init note: $e');
    }
  }

  Future<void> claimActiveDevice() async {
    if (state.syncMode != SyncMode.passive) return; // only meaningful when stealing from another active device
    _myDeviceId ??= await _deviceIdProvider();
    if (_myDeviceId != null) {
      try {
        _ref.read(sessionSyncServiceProvider).transferPlayback(_myDeviceId!);
      } catch (e) {
        debugPrint('[PlayerNotifier] ⚠️ Failed to claim active device: $e');
      }
    }
    // Do NOT start local playback here. Wait for the confirming broadcast.
    // Unlike Step 5's play(), this device is stealing from something actively
    // playing elsewhere — starting the engine optimistically risks a longer
    // double-audio window since the other device is mid-playback, not idle.
  }

  void _onSyncStateChanged(PlaybackState syncState) {
    final wasPassive = state.syncMode == SyncMode.passive;
    final isMineNow = syncState.activeDevice != null &&
        syncState.activeDevice == _myDeviceId;

    if (syncState.syncUnknown) {
      // Outage / reconnecting: degrade to standalone mode.
      // Local playback continues uninterrupted, no active-device enforcement.
      state = state.copyWith(syncMode: SyncMode.standalone);
      return;
    }

    // A broadcast for another device that predates our own claim is stale:
    // keep playing until the server confirms (or the grace runs out).
    if (!isMineNow && syncState.activeDevice != null && _claimPending) return;

    if (isMineNow) {
      _claimedAt = null;
      if (wasPassive) {
        // Transfer just confirmed — resume from the state we were tracking as passive.
        _resumeFromRemoteState(syncState);
      }
      state = state.copyWith(syncMode: SyncMode.activeHere);
    } else if (syncState.activeDevice != null) {
      // Another device is active — this device goes passive.
      // Stop local playback if it was running; UI rendering handled in Step 7.
      if (state.isPlaying) {
        _stopLocalPlaybackOnly();
      }
      _stopPositionTick();
      state = state.copyWith(
        syncMode: SyncMode.passive,
        remoteTrackId: syncState.trackId,
        remoteTrackTitle: syncState.trackTitle,
        remoteArtist: syncState.artist,
        remotePositionMs: syncState.positionMs,
        remoteIsPlaying: syncState.isPlaying,
        remoteUpdatedAt: syncState.updatedAt,
        remoteActiveDeviceName: syncState.activeDeviceName,
      );
    } else {
      // activeDevice == null, nobody active — fresh/idle session
      state = state.copyWith(syncMode: SyncMode.idle);
    }
  }

  Future<void> _resumeFromRemoteState(PlaybackState syncState) async {
    if (syncState.trackId == null) return;

    // Interpolate position the same way passive-mode UI would have shown it,
    // so resume lands close to where the other device actually was.
    final elapsed = syncState.updatedAt != null && syncState.isPlaying
        ? DateTime.now().difference(syncState.updatedAt!).inMilliseconds
        : 0;
    final resumePositionMs = syncState.positionMs + elapsed;

    await _loadAndSeekTrack(
      syncState.trackId!,
      resumePositionMs,
      title: syncState.trackTitle,
      artist: syncState.artist,
      album: syncState.album,
    );
    if (syncState.isPlaying) {
      await _audioHandler.play();
    }
    _startPositionTick();
  }

  Future<void> _loadAndSeekTrack(
    String trackId,
    int positionMs, {
    String? title,
    String? artist,
    String? album,
  }) async {
    final existingIndex = state.queue.indexWhere((s) => s.id == trackId);
    if (existingIndex != -1) {
      if (state.currentIndex != existingIndex) {
        await _audioHandler.jumpToIndex(existingIndex);
        state = state.copyWith(currentIndex: existingIndex);
      }
      await _audioHandler.seek(Duration(milliseconds: positionMs));
    } else {
      final song = Song(
        id: trackId,
        title: title ?? 'Unknown Title',
        artist: artist ?? 'Unknown Artist',
        album: album ?? '',
        genre: '',
        composer: '',
        coverArt: '',
        duration: (positionMs / 1000).ceil() + 60,
        track: 1,
        year: 0,
      );
      await setQueue([song], 0);
      await _audioHandler.seek(Duration(milliseconds: positionMs));
    }
  }

  Future<void> _stopLocalPlaybackOnly() async {
    _stopPositionTick();
    await _audioHandler.pause();
  }

  void _pushUpdate({
    String? trackId,
    int? positionMs,
    bool? isPlaying,
    List<String>? queue,
  }) {
    if (state.syncMode == SyncMode.passive) return; // never push from a passive device
    try {
      _ref.read(sessionSyncServiceProvider).pushStateUpdate(
        trackId: trackId,
        positionMs: positionMs,
        isPlaying: isPlaying,
        queue: queue,
      );
    } catch (e) {
      debugPrint('[PlayerNotifier] ⚠️ Failed to push sync update: $e');
    }
  }

  /// When this device last claimed playback because the listener started
  /// something here. Until the server confirms the claim, a broadcast naming
  /// another device is stale (sent before the transfer was processed); acting
  /// on it paused this phone, then the confirmation reloaded and re-seeked
  /// the track — the one-second drop on every change.
  DateTime? _claimedAt;
  static const Duration _claimGrace = Duration(seconds: 4);

  bool get _claimPending =>
      _claimedAt != null && DateTime.now().difference(_claimedAt!) < _claimGrace;

  Future<void> _ensureActiveDevice() async {
    // Starting playback here means "play here", even if another device was
    // active: claim it, so the server doesn't keep the other device.
    if (state.syncMode == SyncMode.activeHere) return;
    _myDeviceId ??= await _deviceIdProvider();
    if (_myDeviceId != null) {
      _claimedAt = DateTime.now();
      try {
        _ref.read(sessionSyncServiceProvider).transferPlayback(_myDeviceId!);
      } catch (e) {
        debugPrint('[PlayerNotifier] ⚠️ Failed to transfer playback: $e');
      }
    }
  }

  void _startPositionTick() {
    _positionTickTimer?.cancel();
    _positionTickTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (state.isPlaying && state.syncMode == SyncMode.activeHere) {
        _pushUpdate(positionMs: player.position.inMilliseconds);
      }
    });
  }

  void _stopPositionTick() {
    _positionTickTimer?.cancel();
    _positionTickTimer = null;
  }

  Future<void> play() async {
    await _ensureActiveDevice();
    await _audioHandler.play();
    state = state.copyWith(isPlaying: true, syncMode: SyncMode.activeHere);
    _pushUpdate(
      trackId: state.currentSong?.id,
      positionMs: player.position.inMilliseconds,
      isPlaying: true,
      queue: state.queue.map((s) => s.id).toList(),
    );
    _startPositionTick();
  }

  Future<void> pause() async {
    await _audioHandler.pause();
    state = state.copyWith(isPlaying: false);
    _pushUpdate(
      isPlaying: false,
      positionMs: player.position.inMilliseconds,
    );
    _stopPositionTick();
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    await _audioHandler.seek(position);
    _pushUpdate(positionMs: position.inMilliseconds);
  }

  Future<void> seekMs(int ms) async {
    await seek(Duration(milliseconds: ms));
  }

  int _pendingSeekMs = 0;

  Future<void> _loadPersistedState() async {
    try {
      final s = HiveBoxes.session;
      final p = HiveBoxes.prefs;
      _pendingSeekMs =
          s.get(HiveBoxes.kLastPositionMs, defaultValue: 0) as int;
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
        await _audioHandler.applyRepeatMode(loopMode);
      }
    } catch (_) {}
  }

  void _persistState() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), () {
      try {
        final s = HiveBoxes.session;
        final p = HiveBoxes.prefs;
        if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
          s.put(HiveBoxes.kCurrentTrackId, state.queue[state.currentIndex].id);
        }
        s.put(HiveBoxes.kLastPositionMs, player.position.inMilliseconds);
        p.put(HiveBoxes.kShufflePreference, state.shuffleMode);
        p.put('repeatMode', state.repeatMode.index);
      } catch (_) {}
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
  int _actionSequenceToken = 0;

  void _init() {
    _lastKnownIndex = _audioHandler.currentIndex;

    _subscriptions.add(
      _audioHandler.mediaItem.listen((mediaItem) {
        if (mediaItem == null) return;

        // The audio handler owns the authoritative playback index. Looking up
        // the index by media-item ID in Riverpod's queue can return a stale
        // position while Smart Shuffle is appending/reordering a batch (and is
        // ambiguous if a song was deliberately queued twice).
        final liveQueue = _audioHandler.currentQueue;
        final index = _audioHandler.currentIndex;
        if (index < 0 || index >= liveQueue.length) return;
        if (liveQueue[index].id != mediaItem.id) return;

        if (!_suppressEvents &&
            (state.queue.length != liveQueue.length ||
                !const ListEquality<Song>().equals(state.queue, liveQueue))) {
          state = state.copyWith(
            queue: List<Song>.from(liveQueue),
            currentIndex: index,
          );
        }

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

        // Capture source/transition context in the outer scope and reset to
        // 'autoplay' here — UNCONDITIONALLY. The autoplay guard below needs the
        // transition type, and the reset must happen even when analytics is off
        // (otherwise a 'user_selected' start would never clear, permanently
        // suppressing autoplay on natural advancement for analytics-off users).
        final marked = _nextTransitionIndex == null || _nextTransitionIndex == index;
        final sourceContext = marked ? _nextSourceContext : 'autoplay';
        final transitionType = marked ? _nextTransitionType : 'autoplay';
        _nextSourceContext = 'autoplay';
        _markTransition('autoplay');

        if (analyticsEnabled && newSong != null) {
          final sourceCtx = sourceContext;
          final transCtx = transitionType;

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
              durationS:    prevSong.duration,
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
            final rssMb = ProcessInfo.currentRss / (1024 * 1024);
            debugPrint('⚡ [Memory] RSS: ${rssMb.toStringAsFixed(2)} MB (Song: ${capturedNew.title})');
            _collector.onSongStarted(
              song: capturedNew,
              sourceContext: sourceCtx,
              prevSong: capturedPrev,
              positionAtSwitch: capturedPos,
              queuePosition: capturedIdx,
              shuffleActive: capturedShuffle,
            );
            // Refresh the home screen recently-played carousel.
            _ref.invalidate(recentlyPlayedSongsProvider);
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
        }

        if (!_suppressNextHistoryPush &&
            index > prevIndex &&
            prevIndex >= 0 &&
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
            // Only refill on natural playback advancement — NOT when the user
            // jumps directly to a song near the end (jumpTo sets the transition
            // type to 'user_selected'). Without this guard, tapping the last
            // song in Up Next instantly regenerates the queue and reorders the
            // songs that were already sitting ahead of it. Refill resumes when
            // the jumped-to song finishes naturally.
            if (_playlistPool.isNotEmpty && transitionType != 'user_selected') {
              _triggerSmartLocalFetchIfNeeded();
            } else if (_playlistPool.isEmpty &&
                state.autoplayMode &&
                transitionType != 'user_selected') {
              // FIX 3: Autoplay handoff on Smart Shuffle pool exhaustion.
              // When the playlist pool has been fully queued and remainingAhead <= 3,
              // seamlessly fetch Subsonic similar songs so music doesn't stop.
              _triggerAutoplayIfNeeded();
            }
          } else if (state.autoplayMode && !isSmartLocal) {
            // Only pre-fetch on natural playback advancement — NOT when the user
            // jumps directly to a song (setQueue / jumpTo set the transition type
            // to 'user_selected'). Without this guard, tapping the last song in a
            // list instantly appends a freshly-generated radio queue right after it.
            final queueLen = state.queue.length;
            if (index >= queueLen - 3 && transitionType != 'user_selected') {
              _triggerAutoplayIfNeeded();
            }
          }
        }
      }),
    );

    bool? lastPlaying;
    LoopMode? lastLoopMode;
    AudioProcessingState? lastProcessingState;

    _subscriptions.add(
      _audioHandler.playbackState.listen((ps) async {
        if (_suppressEvents) return;

        // 1. Handle playing state changes
        final playing = ps.playing;
        if (playing != lastPlaying) {
          lastPlaying = playing;
          if (playing && _scrobblePlayStart == null) {
            _scrobblePlayStart = DateTime.now();
          } else if (!playing && _scrobblePlayStart != null) {
            _scrobbleListenDuration += DateTime.now().difference(
              _scrobblePlayStart!,
            );
            _scrobblePlayStart = null;
          }
          state = state.copyWith(isPlaying: playing);

          if (playing) {
            if (state.syncMode == SyncMode.activeHere) {
              _startPositionTick();
              _pushUpdate(
                isPlaying: true,
                positionMs: player.position.inMilliseconds,
              );
            }
          } else {
            _stopPositionTick();
            if (state.syncMode == SyncMode.activeHere) {
              _pushUpdate(
                isPlaying: false,
                positionMs: player.position.inMilliseconds,
              );
            }
          }
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

        if (loopMode != lastLoopMode) {
          lastLoopMode = loopMode;
          state = state.copyWith(repeatMode: loopMode);
        }

        // 3. Handle processing state changes
        final processingState = ps.processingState;
        if (processingState != lastProcessingState) {
          lastProcessingState = processingState;
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
                durationS:    completedSong.duration,
                sessionId:    shuffleNotifier.sessionId,
                sessionDepth: shuffleNotifier.state.sessionDepth,
              ));
            }

            // On Desktop (Linux/Windows/macOS), the NaviAudioHandler._startLinuxCompletionListener handles
            // advancement via the single-source bridge. Calling skipToNext() here
            // would cause a race with _linuxLoadTrack ("Loading interrupted").
            if (!NaviAudioHandler.isDesktopBridge &&
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
    final positionStream = (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'))
        ? player.positionStream
        : AudioService.position;
    _subscriptions.add(
      positionStream.listen((position) {
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
          final positionMet = position >= _scrobbleThreshold;
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
    _lastKnownIndex = -1;
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

  void _syncQueueFromAudioHandler() {
    final liveQueue = List<Song>.from(_audioHandler.currentQueue);
    final liveIndex = liveQueue.isEmpty
        ? 0
        : _audioHandler.currentIndex.clamp(0, liveQueue.length - 1);

    state = state.copyWith(
      queue: liveQueue,
      currentIndex: liveIndex,
    );
    _lastKnownIndex = liveIndex;
    _trackedIndexForCompletion = liveQueue.isEmpty ? -1 : liveIndex;
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
    _syncSub?.cancel();
    _positionTickTimer?.cancel();
    _shuffleGuardTimer?.cancel();
    _persistTimer?.cancel();
    _trackChangeTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _audioHandler.dispose();
    super.dispose();
  }

  String? get currentPlaylistName => _currentPlaylistName;

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  Future<void> setQueue(
    List<Song> songs,
    int startIndex, {
    String? playlistName,
    List<Song>? unshuffledSongs,
  }) async {
    debugPrint('🎵 [PlayerProvider] setQueue called with ${songs.length} songs, start: $startIndex, playlist: $playlistName');
    await _queueLock.run(() async {
      _queueEpoch++;
      await _ensureActiveDevice();
      _clearHistory(); // also calls shuffleNotifier.clearQueue() → _sessionId = null
      _ref.read(shuffleQueueProvider.notifier).initSession(); // start session so feedback fires
      _playlistPool = []; // clear pool — not a playlist-shuffle context
      _currentPlaylistName = playlistName;
      _nextSourceContext = playlistName != null ? 'playlist' : 'user_queue';
      _markTransition('user_selected');
      _suppressDepth++;
      try {
        state = state.copyWith(
          queue: songs,
          currentIndex: startIndex,
          syncMode: SyncMode.activeHere,
        );
        await _audioHandler.setQueue(
          songs,
          startIndex,
          unshuffledSongs: unshuffledSongs ?? songs,
        );
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
      _pushUpdate(
        trackId: songs.isNotEmpty && startIndex < songs.length
            ? songs[startIndex].id
            : null,
        positionMs: _pendingSeekMs,
        isPlaying: true,
        queue: songs.map((s) => s.id).toList(),
      );
      _startPositionTick();
      player.play();
    });
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
    await _queueLock.run(() async {
      _queueEpoch++;
      await _ensureActiveDevice();
      _clearHistory();
      _nextSourceContext = 'playlist';
      _markTransition('user_selected');
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
            syncMode: SyncMode.activeHere,
          );
          await _audioHandler.setQueue(songs, 0, unshuffledSongs: songs);
        } finally {
          _suppressDepth--;
        }
        _pushUpdate(
          trackId: songs.isNotEmpty ? songs[0].id : null,
          positionMs: 0,
          isPlaying: true,
          queue: songs.map((s) => s.id).toList(),
        );
        _startPositionTick();
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
            syncMode: SyncMode.activeHere,
          );
          await _audioHandler.setQueue(initialQueue, 0, unshuffledSongs: songs);
          // Fix 2: init completion tracking for the first song (seed at index 0).
          _trackedIndexForCompletion = 0;
          _positionAtCompletion = Duration.zero;
          _shuffleSettling = false;
          _pushUpdate(
            trackId: currentSong.id,
            positionMs: 0,
            isPlaying: true,
            queue: initialQueue.map((s) => s.id).toList(),
          );
          _startPositionTick();
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
          if (!mounted) return;
          final finalQueue = [currentSong, ...shuffled];
          // Emit shuffleMode:true + queue in one copyWith — same guard as
          // the smartLocal branch above to prevent double applyShuffleAlgorithm.
          state = state.copyWith(
            shuffleMode: true,
            queue: finalQueue,
            currentIndex: 0,
            syncMode: SyncMode.activeHere,
          );
          await _audioHandler.setQueue(finalQueue, 0, unshuffledSongs: songs);
          _shuffleSettling = false;
          _pushUpdate(
            trackId: currentSong.id,
            positionMs: 0,
            isPlaying: true,
            queue: finalQueue.map((s) => s.id).toList(),
          );
          _startPositionTick();
          player.play();
        }
      } finally {
        _isShuffling = false;
        // Safety: ensure _shuffleSettling is cleared if any branch exited early
        // (e.g. !mounted) without explicitly clearing it.
        _shuffleSettling = false;
      }
    });
  }

  void refreshShuffleUrl() {}

  Future<void> playNext() async {
    debugPrint('🎵 [PlayerProvider] playNext');
    await _queueLock.run(_playNextLocked);
  }

  Future<void> _playNextLocked() async {
    final actionToken = ++_actionSequenceToken;
    final originalIdx = state.currentIndex;

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
        durationS:    currentSong.duration,
        sessionId:    shuffleNotifier.sessionId,
        sessionDepth: shuffleNotifier.state.sessionDepth,
      ));
    }

    _suppressNextHistoryPush = true;
    _markTransition('manual_next');
    _nextSourceContext = 'manual_next';

    // Optimistic index switch on Desktop
    if (NaviAudioHandler.isDesktopBridge && state.queue.isNotEmpty) {
      int nextIdx = state.currentIndex + 1;
      if (nextIdx >= state.queue.length) {
        if (state.repeatMode == LoopMode.all) {
          nextIdx = 0;
        } else {
          return;
        }
      }
      state = state.copyWith(currentIndex: nextIdx);
    }

    try {
      await _audioHandler.skipToNext();
    } catch (e) {
      if (actionToken == _actionSequenceToken && mounted) {
        state = state.copyWith(currentIndex: originalIdx);
      }
    }
  }

  Future<void> stop() async {
    _stopPositionTick();
    _hasScrobbled = false;
    _currentScrobbleSongId = null;
    _scrobbleListenDuration = Duration.zero;
    _scrobblePlayStart = null;
    await player.stop();
    _pushUpdate(isPlaying: false, positionMs: 0);
  }

  Future<void> playPrev() async {
    debugPrint('🎵 [PlayerProvider] playPrev');
    await _queueLock.run(_playPrevLocked);
  }

  Future<void> _playPrevLocked() async {
    final actionToken = ++_actionSequenceToken;
    final originalIdx = state.currentIndex;
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
          state = state.copyWith(currentIndex: historyIndex);
          await _audioHandler.jumpToIndex(historyIndex);
        } else {
          final prevIdx = state.currentIndex > 0 ? state.currentIndex - 1 : 0;
          state = state.copyWith(currentIndex: prevIdx);
          await _audioHandler.jumpToIndex(prevIdx);
        }
        return;
      }
      // No history — fall back to handler's skipToPrevious (Desktop-aware).
      _suppressNextHistoryPush = true;
      if (NaviAudioHandler.isDesktopBridge && state.queue.isNotEmpty) {
        int prevIdx = state.currentIndex - 1;
        if (prevIdx < 0) {
          if (state.repeatMode == LoopMode.all) {
            prevIdx = state.queue.length - 1;
          } else {
            prevIdx = 0;
          }
        }
        state = state.copyWith(currentIndex: prevIdx);
      }
      await _audioHandler.skipToPrevious();
    } catch (e, stack) {
      debugPrint('playPrev failed: $e\n$stack');
      _suppressNextHistoryPush = true;
      if (actionToken == _actionSequenceToken && mounted) {
        state = state.copyWith(currentIndex: originalIdx);
      }
      final prevIdx = state.currentIndex > 0 ? state.currentIndex - 1 : 0;
      await _audioHandler.jumpToIndex(prevIdx);
    }
  }

  /// An explicit jump supersedes the post-shuffle guard. The guard waits for
  /// the reshuffled anchor index and drops every other index event; if the
  /// listener jumps inside that window, the jump's own event would be dropped
  /// too, leaving its 'user_selected' transition to leak onto the next
  /// natural track change (which then skipped the Smart Shuffle refill).
  void _releaseShuffleGuard() {
    if (_pendingIndexAfterShuffle == null) return;
    _shuffleGuardTimer?.cancel();
    _shuffleGuardTimer = null;
    _pendingIndexAfterShuffle = null;
    _shuffleSettling = false;
  }

  Future<void> jumpTo(int index) async {
    debugPrint('🎵 [PlayerProvider] jumpTo: $index');
    _markTransition('user_selected', index: index);
    _nextSourceContext = 'user_selected';
    await _queueLock.run(() => _jumpToInternal(index, pushHistory: true));
  }

  Future<void> _jumpToInternal(int index, {required bool pushHistory}) async {
    final actionToken = ++_actionSequenceToken;
    final originalIdx = state.currentIndex;
    if (pushHistory &&
        state.queue.isNotEmpty &&
        state.currentIndex < state.queue.length) {
      _pushToHistory(state.queue[state.currentIndex]);
    }
    _suppressNextHistoryPush = true;
    _releaseShuffleGuard();
    state = state.copyWith(currentIndex: index);
    try {
      await _audioHandler.jumpToIndex(index);
    } catch (e) {
      if (actionToken == _actionSequenceToken && mounted) {
        state = state.copyWith(currentIndex: originalIdx);
      }
    }
  }

  Future<void> insertNext(Song song) async {
    await insertAllNext([song]);
  }

  Future<void> insertAllNext(List<Song> songs, {int? atIndex}) async {
    debugPrint('🎵 [PlayerProvider] insertAllNext: ${songs.length} songs');
    if (songs.isEmpty) return;
    await _queueLock.run(() async {
    _queueEpoch++;
    _suppressDepth++;
    try {
      final currentQueue = List<Song>.from(state.queue);
      final insertIndex = atIndex ??
          (currentQueue.isEmpty
              ? 0
              : (state.currentIndex + 1).clamp(0, currentQueue.length));
      currentQueue.insertAll(insertIndex, songs);

      int newIndex = state.currentIndex;
      if (state.queue.isNotEmpty && insertIndex <= state.currentIndex) {
        newIndex += songs.length;
      }
      state = state.copyWith(queue: currentQueue, currentIndex: newIndex);
      await _audioHandler.insertAllNext(songs, atIndex: insertIndex);
    } finally {
      _suppressDepth--;
    }
    });
  }

  Future<void> addToQueue(Song song) async {
    debugPrint('🎵 [PlayerProvider] addToQueue: ${song.title}');
    await _queueLock.run(() async {
      _queueEpoch++;
      final currentQueue = List<Song>.from(state.queue)..add(song);
      state = state.copyWith(queue: currentQueue);
      await _audioHandler.addToQueue(song);
    });
  }

  /// Batch-add multiple songs — single state update → single UI rebuild.
  /// Uses the handler's batch method for a single platform-channel round trip.
  Future<void> addAllToQueue(List<Song> songs) async {
    debugPrint('🎵 [PlayerProvider] addAllToQueue: ${songs.length} songs');
    if (songs.isEmpty) return;
    await _queueLock.run(() async {
      _queueEpoch++;
      final currentQueue = List<Song>.from(state.queue)..addAll(songs);
      state = state.copyWith(queue: currentQueue);
      await _audioHandler.addAllToQueue(songs);
    });
  }

  Future<void> removeFromQueue(int index) async {
    debugPrint('🎵 [PlayerProvider] removeFromQueue at index: $index');
    await _queueLock.run(() async {
    if (index < 0 || index >= state.queue.length) return;
    _queueEpoch++;
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
    }
    });
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    await _queueLock.run(() async {
    final len = state.queue.length;
    if (oldIndex < 0 || oldIndex >= len || newIndex < 0 || newIndex >= len) return;
    _queueEpoch++;
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
    }
    });
  }

  Future<void> toggleStar(String songId) async {
    // Songs from Settings > Local music have no server entry to star.
    if (isLocalSongId(songId) || _starTogglingIds.contains(songId)) return;
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

  // ---------------------------------------------------------------------------
  // Shuffle — two different actions
  //
  //   Shuffle (toggle)   local and instant: a random order in the listener's
  //                      shuffle style; off restores the original order. Never
  //                      calls the server.
  //   Smart Reshuffle    POST /next with reshuffle:true — the server picks a
  //                      fresh run for right now. See [smartReshuffle].
  // ---------------------------------------------------------------------------

  Future<void> toggleShuffle() => setShuffleMode(!state.shuffleMode);

  Future<void> setShuffleMode(bool enabled) => _queueLock.run(() async {
        _queueEpoch++;
        state = state.copyWith(shuffleMode: enabled);
        if (enabled) {
          await _localShuffleLocked();
        } else {
          await _unshuffleLocked();
        }
      });

  /// Re-randomises Up Next in the current local shuffle style (the queue
  /// sheet's "Shuffle Up Next", and after the style changes).
  Future<void> applyShuffleAlgorithm() => _queueLock.run(() async {
        _queueEpoch++;
        state = state.copyWith(shuffleMode: true);
        await _localShuffleLocked();
      });

  /// Starts the post-shuffle guard: index events from the reorder are dropped
  /// until the player settles on [anchor] (or 500 ms pass).
  void _armShuffleGuard(int anchor) {
    _shuffleGuardTimer?.cancel();
    _lastKnownIndex = anchor;
    _pendingIndexAfterShuffle = anchor;
    _shuffleGuardTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _pendingIndexAfterShuffle = null;
      // BUG-004: resync so the first event after the window has a correct
      // prevIndex. Play/pause taps inside the 500 ms window are dropped on
      // purpose — they would race the transient just_audio emissions.
      _lastKnownIndex = state.currentIndex;
      _shuffleSettling = false;
    });
  }

  Future<void> _unshuffleLocked() async {
    _shuffleGuardTimer?.cancel();
    _isShuffling = true;
    _shuffleSettling = true;
    _playlistPool = []; // the original order holds every song
    try {
      await _audioHandler.unshuffle();
      final postIndex = _audioHandler.currentIndex;
      state = state.copyWith(queue: _audioHandler.currentQueue, currentIndex: postIndex);
      _armShuffleGuard(postIndex);
    } finally {
      _isShuffling = false;
    }
  }

  /// Local shuffle in the chosen style. Smart Shuffle as a *style* applies to
  /// shuffle-playing a playlist; this toggle is the plain random one, so it
  /// uses a standard shuffle then — the smart one is [smartReshuffle].
  Future<void> _localShuffleLocked() async {
    final settings = _ref.read(settingsProvider);
    _shuffleGuardTimer?.cancel();
    _isShuffling = true;
    _shuffleSettling = true;
    try {
      // BUG-004: track the current song by id; indexes go stale on reorder.
      final pre = _audioHandler.currentIndex;
      final currentSongId =
          pre < _audioHandler.currentQueue.length ? _audioHandler.currentQueue[pre].id : null;

      switch (settings.shuffleAlgorithm) {
        case ShuffleAlgorithm.spotify:
          await _audioHandler.spotifyDitherShuffle(settings.shufflePreference);
        case ShuffleAlgorithm.youtube:
          await _audioHandler.youtubeWeightedShuffle();
        case ShuffleAlgorithm.albumAware:
          await _audioHandler.albumAwareShuffle();
        case ShuffleAlgorithm.mergeShuffle:
          await _audioHandler.mergeShuffle(settings.shufflePreference);
        case ShuffleAlgorithm.recencyDampened:
          await _audioHandler.recencyDampenedWeightedShuffle();
        case ShuffleAlgorithm.standard:
        case ShuffleAlgorithm.smartLocal:
          await _audioHandler.standardShuffle();
      }

      var post = _audioHandler.currentIndex;
      if (currentSongId != null) {
        final found = _audioHandler.currentQueue.indexWhere((s) => s.id == currentSongId);
        if (found != -1) post = found;
      }
      state = state.copyWith(queue: _audioHandler.currentQueue, currentIndex: post);
      _armShuffleGuard(post);
    } finally {
      _isShuffling = false;
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
    // Through the handler, which owns repeat (desktop wraps the queue itself)
    // and re-broadcasts immediately; update + persist our state optimistically
    // so the button responds on the same frame.
    await _audioHandler.applyRepeatMode(nextMode);
    state = state.copyWith(repeatMode: nextMode);
    _persistState();
  }

  Future<void> handleSuggestAction(Song song, bool isMore) async {
    if (isMore) {
      if (!song.starred) await toggleStar(song.id);
      await _subsonicService.setRating(song.id, 5);
    } else {
      if (song.starred) await toggleStar(song.id);
      await _subsonicService.setRating(song.id, 1);
    }
    _audioHandler.updateSongWeight(song, isMore);
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
  Future<void> clearAiShuffleQueue() => _queueLock.run(_clearAiShuffleQueueLocked);

  Future<void> _clearAiShuffleQueueLocked() async {
    _queueEpoch++;
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
  // Smart Reshuffle — POST /next with reshuffle:true
  //
  // Race-free by construction:
  //   • single-flight: taps while a request is out join it (no request bursts);
  //   • the network call runs OUTSIDE the queue lock, so skips stay instant;
  //   • the commit runs INSIDE it and checks the queue epoch: if the listener
  //     changed the queue meanwhile (shuffle toggle, new album, reorder…), the
  //     answer is stale and is dropped; a natural track advance is fine — the
  //     result is rebased onto whatever is playing now;
  //   • songs are matched by Navidrome id (server-provided), title as fallback.
  // ---------------------------------------------------------------------------

  /// Whether a Smart Reshuffle is running (drives the button's spinner).
  bool get isSmartReshuffling => _smartReshuffleInFlight != null;

  /// A fresh, server-picked Up Next for this moment. Turns shuffle on.
  /// Falls back to a random shuffle when the server can't answer, and says so
  /// through the returned outcome.
  Future<ReshuffleOutcome> smartReshuffle({List<Song>? library}) {
    final running = _smartReshuffleInFlight;
    if (running != null) return running;
    _setSmartBusy(true);
    final run = _smartReshuffle(library).whenComplete(() {
      _smartReshuffleInFlight = null;
      _setSmartBusy(false);
    });
    _smartReshuffleInFlight = run;
    return run;
  }

  void _setSmartBusy(bool busy) {
    try {
      _ref.read(smartReshuffleBusyProvider.notifier).set(busy);
    } catch (_) {
      // The provider container is gone (disposal) — nothing to show.
    }
  }

  Future<ReshuffleOutcome> _smartReshuffle(List<Song>? library) async {
    // Let queued operations land first so the snapshot is current.
    await _queueLock.idle;
    final epoch = _queueEpoch;
    final current = state.currentSong;
    if (current == null) return ReshuffleOutcome.nothingToShuffle;

    // The candidates: what's being played — the playlist/album's original
    // order, plus any pool not queued yet — else the queue itself; only a
    // lone song reshuffles across the whole library.
    final List<Song>? context = _audioHandler.unshuffledQueue.isNotEmpty
        ? [..._audioHandler.unshuffledQueue, ..._playlistPool]
        : (_playlistPool.isNotEmpty || state.queue.length > 1)
            ? [...state.queue, ..._playlistPool]
            : null;
    final fromLibrary = context == null;
    final pool = context ??
        library ??
        await _ref.read(allSongsProvider.future).catchError((Object _) => const <Song>[]);
    final candidates = <String, Song>{
      for (final s in pool)
        if (s.id != current.id) s.id: s,
    };
    if (candidates.isEmpty) return ReshuffleOutcome.nothingToShuffle;

    List<Song>? picks;
    try {
      final recs = await _ref.read(shuffleQueueProvider.notifier).reshuffle(
            source: 'smart',
            playlistName: _currentPlaylistName,
            // A library-wide reshuffle needs no list: the server's catalog
            // is this library. A playlist/album is sent so picks stay in it.
            candidates: fromLibrary ? const [] : [for (final s in candidates.values) s.title],
            excludedTitlesOverride: [current.title],
          );
      picks = _resolveRecommendations(recs, candidates);
      if (picks.isEmpty) picks = null;
    } catch (e) {
      debugPrint('[SmartReshuffle] server unavailable: $e');
    }
    if (!mounted) return ReshuffleOutcome.superseded;

    return _queueLock.run(() async {
      if (_queueEpoch != epoch) {
        debugPrint('[SmartReshuffle] queue changed while waiting — dropping stale picks');
        return ReshuffleOutcome.superseded;
      }
      if (picks == null) {
        // Offline / server error: still give the listener a new order.
        _queueEpoch++;
        state = state.copyWith(shuffleMode: true);
        await _localShuffleLocked();
        return ReshuffleOutcome.random;
      }
      final live = state.currentSong;
      if (live == null) return ReshuffleOutcome.superseded;

      // Rebase onto the song playing now (the track may have advanced).
      final upNext = [for (final s in picks) if (s.id != live.id) s];
      final used = {live.id, for (final s in upNext) s.id};
      final rest = [for (final s in candidates.values) if (!used.contains(s.id)) s]..shuffle();

      final smartStyle = _ref.read(settingsProvider).shuffleAlgorithm == ShuffleAlgorithm.smartLocal;
      if (smartStyle) {
        // Keep the rest in the pool: refills keep asking the server as the
        // listener nears the end, so the queue stays smart.
        _playlistPool = rest;
      } else {
        // Plain styles have no refill: append the rest in random order. A
        // library-wide reshuffle is capped so the queue never holds thousands.
        _playlistPool = [];
        const libraryCap = 200;
        upNext.addAll(fromLibrary ? rest.take(libraryCap - upNext.length.clamp(0, libraryCap)) : rest);
      }

      final newQueue = [live, ...upNext];
      _queueEpoch++;
      _lastFetchedForSongId = null; // allow the next refill
      _suppressDepth++;
      try {
        state = state.copyWith(queue: newQueue, currentIndex: 0, shuffleMode: true);
        _trackedIndexForCompletion = 0;
        await _audioHandler.updateQueuePreservingCurrent(newQueue, 0);
      } finally {
        _suppressDepth--;
      }
      // Hold the anchor against stale index events from the old order.
      _shuffleSettling = true;
      _armShuffleGuard(0);
      _persistState();
      return ReshuffleOutcome.smart;
    });
  }

  /// Server picks → local songs: by Navidrome id first (exact), then by
  /// title + artist, then title. Duplicates are dropped.
  List<Song> _resolveRecommendations(List<RecommendedSong> recs, Map<String, Song> candidates) {
    final byTitle = <String, List<Song>>{};
    for (final s in candidates.values) {
      byTitle.putIfAbsent(s.title.toLowerCase(), () => []).add(s);
    }
    final out = <Song>[];
    final seen = <String>{};
    for (final rec in recs) {
      Song? match = rec.navidromeId != null ? candidates[rec.navidromeId] : null;
      if (match == null) {
        final same = byTitle[rec.title.toLowerCase()] ?? const <Song>[];
        final artist = (rec.artist ?? rec.composer).toLowerCase();
        match = same.firstWhereOrNull((s) => s.artist.toLowerCase() == artist) ?? same.firstOrNull;
      }
      if (match != null && seen.add(match.id)) out.add(match);
    }
    return out;
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
  // The server cannot inject outside songs because the candidate list (batch)
  // is taken entirely from _playlistPool, which came from the original
  // playlist. Songs already queued ahead (existingFuture) are preserved in
  // place and never sent to the server for reordering.
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

      // Phase 1 (locked): snapshot, take the next batch from the pool and
      // append it, so it's playable even if the server never answers.
      final snap = await _queueLock.run(() async {
        final batch = _takeFromPool(_smartLocalBatchSize);
        if (batch.isEmpty) return null;
        final queue = _audioHandler.currentQueue;
        final anchor = _audioHandler.currentIndex.clamp(0, queue.length - 1);
        final ahead = queue.length > anchor + 1 ? queue.sublist(anchor + 1) : const <Song>[];
        await _audioHandler.addAllToQueue(batch);
        _syncQueueFromAudioHandler();
        // Order the batch off the last song already queued, so transitions
        // chain from what the listener will actually hear next.
        return (batch: batch, epoch: _queueEpoch, seed: ahead.isNotEmpty ? ahead.last : seedSong);
      });
      if (snap == null) {
        debugPrint('[SMART LOCAL] Pool exhausted — no more songs to queue');
        return;
      }

      // Phase 2 (unlocked): ask the server to order the batch.
      List<Song>? orderedBatch;
      try {
        final response = await _ref.read(shuffleQueueProvider.notifier).fetchNext(
              source: 'smart',
              playlistName: _currentPlaylistName,
              candidates: [for (final s in snap.batch) s.title],
              count: snap.batch.length,
              seedTitle: snap.seed.title,
            );
        final byId = {for (final s in snap.batch) s.id: s};
        orderedBatch = _resolveRecommendations(response.queue, byId);
        final placed = {for (final s in orderedBatch) s.id};
        orderedBatch.addAll(snap.batch.where((s) => !placed.contains(s.id)));
      } catch (e) {
        debugPrint('[Smart Local Refill] API Error: $e — batch stays in pool order');
      }
      if (!mounted || orderedBatch == null) return;

      // Phase 3 (locked): commit the order if nothing superseded it.
      await _queueLock.run(() async {
        final liveQueue = List<Song>.from(_audioHandler.currentQueue);
        final liveIds = {for (final s in liveQueue) s.id};
        if (_queueEpoch != snap.epoch) {
          // The listener replaced/reshuffled the queue meanwhile. Songs from
          // this batch that are no longer queued go back to the pool.
          _playlistPool.addAll(snap.batch.where((s) => !liveIds.contains(s.id)));
          return;
        }
        final anchor = _audioHandler.currentIndex.clamp(0, liveQueue.length - 1);
        final batchIds = {for (final s in snap.batch) s.id};
        // Everything after the live song that isn't from this batch (earlier
        // queue + anything inserted meanwhile) keeps its place, ahead of it.
        final userUpcoming = [for (final s in liveQueue.sublist(anchor + 1)) if (!batchIds.contains(s.id)) s];
        final stillAhead = [for (final s in orderedBatch!) if (liveQueue.indexWhere((q) => q.id == s.id) > anchor) s];
        _suppressDepth++;
        try {
          await _audioHandler.commitSmartLocalOrder(
            pastAndPresent: liveQueue.sublist(0, anchor + 1),
            orderedFuture: [...userUpcoming, ...stillAhead],
            anchorIndex: anchor,
            preferMoveBasedReorder: true,
          );
          _syncQueueFromAudioHandler();
          _drainPoolOfQueuedSongs();
          _prunePlayedSongs();
        } finally {
          _suppressDepth--;
        }
        debugPrint('[SMART LOCAL] Refill complete. Queue: ${state.queue.length}  Pool: ${_playlistPool.length}');
      });
    } catch (e) {
      debugPrint('[SMART LOCAL] Refill failed: $e');
    } finally {
      fetchCompleter.complete();
    }
  }

  void _prunePlayedSongs() {
    if (state.queue.length <= _maxQueueSize) return;

    final targetPruneCount = state.queue.length - _maxQueueSize;
    final maxPrunableIndex = state.currentIndex - 5;
    if (maxPrunableIndex <= 0) return;

    final pruneCount = targetPruneCount < maxPrunableIndex ? targetPruneCount : maxPrunableIndex;
    if (pruneCount <= 0) return;

    debugPrint('[PRUNING] Pruning $pruneCount songs from queue of size ${state.queue.length}');

    unawaited(_audioHandler.pruneRange(0, pruneCount));

    final newQueue = List<Song>.from(state.queue)..removeRange(0, pruneCount);
    final newIndex = state.currentIndex - pruneCount;

    state = state.copyWith(
      queue: newQueue,
      currentIndex: newIndex,
    );

    _lastKnownIndex = newIndex;
    if (_trackedIndexForCompletion >= 0) {
      _trackedIndexForCompletion = (_trackedIndexForCompletion - pruneCount).clamp(0, newQueue.length - 1);
    }
    if (_pendingIndexAfterShuffle != null) {
      _pendingIndexAfterShuffle = (_pendingIndexAfterShuffle! - pruneCount).clamp(0, newQueue.length - 1);
    }
  }

  void clearHistory() => _clearHistory();
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final audioHandlerProvider = Provider<NaviAudioHandler>((ref) {
  NaviAudioHandler handler;
  try {
    handler = globalAudioHandler;
  } catch (_) {
    handler = NaviAudioHandler(ref.read(subsonicServiceProvider));
  }
  // The global handler outlives any one SubsonicService: keep it on the live
  // one without rebuilding this provider (which would tear down playback).
  handler.subsonicService = ref.read(subsonicServiceProvider);
  ref.listen<SubsonicService>(
    subsonicServiceProvider,
    (_, next) => handler.subsonicService = next,
  );
  return handler;
});

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((
  ref,
) {
  final handler = ref.watch(audioHandlerProvider);
  final service = ref.watch(subsonicServiceProvider);
  final collector = ref.watch(listenerCollectorProvider);
  ref.listen(
    settingsProvider.select(
      (s) => (s.replayGainMode, s.crossfadeSeconds, s.playbackSpeed),
    ),
    (_, t) => handler.configureTuning(
      replayGainMode: t.$1,
      crossfadeSeconds: t.$2,
      speed: t.$3,
    ),
    fireImmediately: true,
  );
  return PlayerNotifier(ref, handler, service, collector);
});
