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
import '../features/local_library/logic/local_index.dart';
import '../offline_service.dart';
import 'shuffle_algorithms.dart';
import 'playback_tuning.dart';
import '../core/hive_boxes.dart';
import 'auto/browse_tree.dart';
import 'auto/car_browser.dart';
import 'open_intent.dart';

// ---------------------------------------------------------------------------
// AudioHandler
// ---------------------------------------------------------------------------

class NaviAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player;

  /// Replaced when the signed-in credentials change (audioHandlerProvider).
  /// The handler is created in main() before sign-in, so a final field pinned
  /// it to an empty-password service and stream URLs failed until restart.
  SubsonicService subsonicService;

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

  /// Android system equalizer, or null on other platforms (and when a test
  /// injects its own [AudioPlayer]).
  final AndroidEqualizer? equalizer;

  // ── ReplayGain / crossfade / speed ──────────────────────────────────────────
  ReplayGainMode _replayGainMode = ReplayGainMode.off;
  int _fadeSeconds = 0;
  double _replayVolume = 1.0;
  double _fadeFactor = 1.0;
  bool _fadeInActive = false;
  double _speed = 1.0;
  double _appliedSpeed = 1.0;
  double _appliedVolume = 1.0;
  Song? _tunedSong;
  StreamSubscription<Duration>? _fadeSub;

  NaviAudioHandler(
    SubsonicService subsonicService, {
    AudioPlayer? player,
    TranscodingService? transcodingService,
  }) : this._(
         subsonicService,
         player,
         transcodingService,
         player == null && !kIsWeb && Platform.isAndroid
             ? AndroidEqualizer()
             : null,
       );

  NaviAudioHandler._(
    this.subsonicService,
    AudioPlayer? player,
    TranscodingService? transcodingService,
    this.equalizer,
  ) : player =
           player ??
           AudioPlayer(
             audioPipeline: equalizer == null
                 ? null
                 : AudioPipeline(androidAudioEffects: [equalizer]),
             // Lossless over a shared home uplink: read far ahead (up to 2 min,
             // ~15–20 MB of FLAC) so short congestion never reaches the ears.
             // Time wins over ExoPlayer's default byte cap, which would
             // otherwise stop a FLAC buffer at ~13 MB.
             audioLoadConfiguration: const AudioLoadConfiguration(
               androidLoadControl: AndroidLoadControl(
                 minBufferDuration: Duration(seconds: 50),
                 maxBufferDuration: Duration(seconds: 120),
                 bufferForPlaybackDuration: Duration(milliseconds: 1500),
                 bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
                 prioritizeTimeOverSizeThresholds: true,
               ),
               darwinLoadControl: DarwinLoadControl(
                 preferredForwardBufferDuration: Duration(seconds: 120),
               ),
             ),
           ),
       _transcodingService = transcodingService ?? TranscodingService() {
    _listenToPlayerEvents();
    _subscriptions.add(mediaItem.listen(_onMediaItemChanged));

    _subscriptions.add(this.player.currentIndexStream.listen((index) {
      // On desktop we manage index ourselves — ignore just_audio's index stream
      if (!_isDesktopBridge && index != null) {
        final globalIndex = _playlistOffset + index;
        if (globalIndex < _currentQueue.length) {
          _trackRecentlyPlayed(_currentQueue[globalIndex].id);
        }
        // A gapless advance changes the position without changing
        // playerState, and the notification interpolates elapsed time from
        // the last broadcast: without this it kept counting from the previous
        // song (a 4-minute song then a 3-minute one showed "3:00 of 3:00").
        // Deferred a microtask so it runs after just_audio has reset position.
        scheduleMicrotask(() {
          try {
            _broadcastState();
          } on UnimplementedError {
            // Test doubles of AudioPlayer that only stub queue behaviour.
          }
        });
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
          _publishMediaItem(source.tag as MediaItem);
        }
        _publishCarQueue();
      }));
    }
  }

  void _broadcastState() {
    final playing = player.playing;
    final state = carState?.call() ??
        (liked: false, shuffle: player.shuffleModeEnabled, repeat: _repeatMode);
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
          _likeControl(state.liked),
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          _shuffleControl(state.shuffle),
          _repeatControl(state.repeat),
        ],
        queueIndex: _isAndroid && _currentQueue.isNotEmpty
            ? (currentIndex - _carQueueOffset).clamp(0, _currentQueue.length - 1)
            : null,
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
        }[_repeatMode]!,
        shuffleMode: state.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  // Custom actions reach the car as well as the notification. The icons are
  // the app's own glyphs (res/drawable/navi_*); "on" states carry a dot.
  static MediaControl _likeControl(bool liked) => MediaControl.custom(
    androidIcon: liked ? 'drawable/navi_heart_filled' : 'drawable/navi_heart',
    label: liked ? 'Unlike' : 'Like',
    name: 'like',
  );

  static MediaControl _shuffleControl(bool on) => MediaControl.custom(
    androidIcon: on ? 'drawable/navi_shuffle_on' : 'drawable/navi_shuffle',
    label: on ? 'Shuffle on' : 'Shuffle',
    name: 'shuffle',
  );

  static MediaControl _repeatControl(LoopMode mode) => MediaControl.custom(
    androidIcon: switch (mode) {
      LoopMode.off => 'drawable/navi_repeat',
      LoopMode.all => 'drawable/navi_repeat_on',
      LoopMode.one => 'drawable/navi_repeat_one',
    },
    label: switch (mode) {
      LoopMode.off => 'Repeat',
      LoopMode.all => 'Repeat all',
      LoopMode.one => 'Repeat one',
    },
    name: 'repeat',
  );

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  // ── Android Auto / media-browser tree ──────────────────────────────────────

  /// Starts a queue through the player layer (wired in main()), so car playback
  /// goes through the same path as the UI. Null until wired.
  Future<void> Function(CarPlayRequest request)? onPlayRequest;

  /// Runs a custom action from the car or notification (`like`, `shuffle`,
  /// `repeat`) through the player layer. Null until wired.
  Future<void> Function(String action)? onCarAction;

  /// Current like / shuffle / repeat state, for the custom-action icons.
  ({bool liked, bool shuffle, LoopMode repeat}) Function()? carState;

  late final CarBrowser _car = CarBrowser(
    SubsonicCarLibrary(() => subsonicService),
    currentSong: _currentSongOrNull,
    lastSongId: _lastSongIdOrNull,
  );

  Song? _currentSongOrNull() {
    final i = currentIndex;
    return i >= 0 && i < _currentQueue.length ? _currentQueue[i] : null;
  }

  String? _lastSongIdOrNull() {
    try {
      return HiveBoxes.session.get(HiveBoxes.kCurrentTrackId) as String?;
    } catch (_) {
      return null; // boxes not open (tests, very early start)
    }
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async => _forCar(await _car.children(parentMediaId));

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final item = await _car.item(mediaId);
    return item == null ? null : _forCar([item]).single;
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async => _forCar(await _car.search(query));

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) => _playRequest(_car.resolve(mediaId), 'playFromMediaId($mediaId)');

  /// Plays what Android opened the app for: a voice request, or an audio
  /// file chosen with "Open with". Files play through the local-file path.
  Future<void> playOpenIntent(OpenIntent intent) async {
    switch (intent) {
      case SearchIntent():
        await playFromSearch(intent.query, intent.extras);
      case ViewIntent():
        final song = intent.toSong();
        LocalLibraryIndex.instance.register(song.id, intent.path);
        await _playRequest(Future.value(CarPlayRequest([song])), 'view(${intent.uri})');
    }
  }

  /// Voice: "Hey Google, play Radiohead on NaviVibe".
  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) => _playRequest(
    _car.resolveVoice(
      query,
      focus: VoiceSearch.focusOf(extras?['android.intent.extra.focus'] as String?),
      artistHint: extras?['android.intent.extra.artist'] as String?,
      albumHint: extras?['android.intent.extra.album'] as String?,
    ),
    'playFromSearch($query)',
  );

  Future<void> _playRequest(Future<CarPlayRequest?> pending, String what) async {
    try {
      final request = await pending;
      final play = onPlayRequest;
      if (request == null || play == null) return;
      await play(request);
    } catch (e) {
      // A bad request from the car must never take the service down.
      debugPrint('⚠️ [NaviAudioHandler] $what failed: $e');
    }
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    try {
      await onCarAction?.call(name);
    } catch (e) {
      debugPrint('⚠️ [NaviAudioHandler] customAction($name) failed: $e');
    }
  }

  /// Re-broadcasts state so the like / shuffle / repeat icons catch up after
  /// the player layer changed them.
  void refreshControls() => _broadcastState();

  /// Car-safe copies of [items]: artwork goes through the app's content
  /// provider on Android (the car can't fetch server URLs or private files).
  List<MediaItem> _forCar(List<MediaItem> items) => [
    for (final i in items) _carItem(i),
  ];

  MediaItem _carItem(MediaItem i) {
    final art = i.artUri;
    if (art == null || !_isAndroid) return i;
    return i.copyWith(
      artUri: CarArt.proxy(art),
      extras: {...?i.extras, 'artSrc': art.toString()},
    );
  }

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  // Auto's queue view: the whole queue up to this many items, windowed around
  // the current one beyond that (a MediaSession queue is a binder payload).
  static const int _carQueueMax = 100;
  int _carQueueOffset = 0;
  String? _carQueueKey;

  void _publishCarQueue() {
    if (!_isAndroid || _currentQueue.isEmpty) return;
    final cur = currentIndex.clamp(0, _currentQueue.length - 1);
    final start = _currentQueue.length <= _carQueueMax
        ? 0
        : (cur - 20).clamp(0, _currentQueue.length - _carQueueMax);
    final end = (start + _carQueueMax).clamp(0, _currentQueue.length);
    final key = '$start|$end|${_currentQueue[start].id}|${_currentQueue[end - 1].id}|${_currentQueue.length}';
    if (key == _carQueueKey) return;
    _carQueueKey = key;
    _carQueueOffset = start;
    queue.add([
      for (var i = start; i < end; i++)
        _carItem(BrowseTree.songItem(
          BrowseIds.ctxSingle,
          _currentQueue[i],
          (_) => _queueArt(_currentQueue[i]),
        )),
    ]);
  }

  Uri? _queueArt(Song song) {
    final local = OfflineService().getLocalCoverArtPath(song.id);
    return local != null
        ? Uri.file(local)
        : BrowseTree.uriOrNull(
            subsonicService.getCoverArtUrl(song.coverArt, size: 300),
          );
  }

  /// The playing item with car-readable artwork.
  void _publishMediaItem(MediaItem item) => mediaItem.add(_carItem(item));

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
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      applyRepeatMode(switch (repeatMode) {
        AudioServiceRepeatMode.none => LoopMode.off,
        AudioServiceRepeatMode.one => LoopMode.one,
        AudioServiceRepeatMode.all || AudioServiceRepeatMode.group =>
          LoopMode.all,
      });

  /// The user's repeat choice. This — not `player.loopMode` — is the source
  /// of truth: on desktop only one track is loaded at a time, so setting
  /// LoopMode.all on the player would loop that single track forever and the
  /// queue would never advance or wrap.
  LoopMode _repeatMode = LoopMode.off;
  LoopMode get repeatMode => _repeatMode;

  /// Applies [mode] and re-broadcasts state immediately. Loop changes don't
  /// alter playerState, so without the explicit broadcast the UI (which reads
  /// repeatMode from playbackState) never saw the change.
  Future<void> applyRepeatMode(LoopMode mode) async {
    _repeatMode = mode;
    await player.setLoopMode(
      _isDesktopBridge && mode == LoopMode.all ? LoopMode.off : mode,
    );
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
    final musicCacheEnabled = CacheSettingsService().getMusicCacheEnabled();
    // A copy on this device (Settings > Local music) always wins: no data
    // used, and it plays offline. Then the offline download, then the stream.
    final deviceFile = LocalLibraryIndex.instance.pathFor(song.id);
    final localPath = deviceFile ?? (musicCacheEnabled ? OfflineService().getLocalPath(song.id) : null);
    final streamUri = localPath != null
        ? LocalLibraryIndex.uriFor(localPath)
        : Uri.parse(subsonicService.getStreamUrl(
            song.id,
            maxBitRate: _transcodingService.getCurrentBitrate(),
            format: _transcodingService.getCurrentFormat(),
          ));

    final localCoverPath = OfflineService().getLocalCoverArtPath(song.id);
    final artUri = localCoverPath != null
        ? Uri.file(localCoverPath)
        : Uri.parse(subsonicService.getCoverArtUrl(song.coverArt, size: 600));

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
    final deviceFile = LocalLibraryIndex.instance.pathFor(song.id);
    final localPath = deviceFile ?? (musicCacheEnabled ? offlinePaths[song.id] : null);
    final streamUri = localPath != null
        ? LocalLibraryIndex.uriFor(localPath)
        : Uri.parse(subsonicService.getStreamUrl(
            song.id,
            maxBitRate: _transcodingService.getCurrentBitrate(),
            format: _transcodingService.getCurrentFormat(),
          ));

    final localCoverPath = OfflineService().getLocalCoverArtPath(song.id);
    final artUri = localCoverPath != null
        ? Uri.file(localCoverPath)
        : Uri.parse(subsonicService.getCoverArtUrl(song.coverArt, size: 600));

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
    _applyVolume();
  }

  // ---------------------------------------------------------------------------
  // ReplayGain, crossfade, speed
  // ---------------------------------------------------------------------------

  /// Applies the user's playback-tuning settings. Safe to call repeatedly.
  void configureTuning({
    required ReplayGainMode replayGainMode,
    required int crossfadeSeconds,
    required double speed,
  }) {
    _replayGainMode = replayGainMode;
    _fadeSeconds = clampCrossfadeSeconds(crossfadeSeconds);
    _refreshReplayVolume();
    if (_fadeSeconds > 0) {
      _fadeSub ??= player
          .createPositionStream(
            minPeriod: const Duration(milliseconds: 60),
            maxPeriod: const Duration(milliseconds: 120),
          )
          .listen(_onFadeTick);
    } else {
      unawaited(_fadeSub?.cancel());
      _fadeSub = null;
      _fadeFactor = 1.0;
      _fadeInActive = false;
    }
    _applyVolume();
    _speed = clampPlaybackSpeed(speed);
    _pushSpeed();
  }

  void _pushSpeed({bool force = false}) {
    if (!force && _speed == _appliedSpeed) return;
    _appliedSpeed = _speed;
    try {
      unawaited(
        Future<void>.value(player.setSpeed(_speed)).catchError((Object e) {
          debugPrint('⚠️ [NaviAudioHandler] setSpeed failed: $e');
        }),
      );
    } catch (e) {
      debugPrint('⚠️ [NaviAudioHandler] setSpeed failed: $e');
    }
  }

  bool _equalizerRestored = false;

  /// Re-applies the saved equalizer on/off state and band gains. The native
  /// effect only exists once audio has loaded, so this runs on the first track.
  Future<void> _restoreEqualizer() async {
    final eq = equalizer;
    if (eq == null || _equalizerRestored) return;
    _equalizerRestored = true;
    try {
      final prefs = HiveBoxes.prefs;
      await eq.setEnabled(prefs.get(HiveBoxes.kEqualizerEnabled) == true);
      final saved = prefs.get(HiveBoxes.kEqualizerGains);
      if (saved is List) {
        final bands = (await eq.parameters).bands;
        for (var i = 0; i < bands.length && i < saved.length; i++) {
          final g = saved[i];
          if (g is num) await bands[i].setGain(g.toDouble());
        }
      }
    } catch (e) {
      debugPrint('⚠️ [NaviAudioHandler] Equalizer restore failed: $e');
    }
  }

  void _onMediaItemChanged(MediaItem? item) {
    if (item == null) return;
    unawaited(_restoreEqualizer());
    final index = _currentGlobalIndex();
    Song? song;
    if (index != null && index < _currentQueue.length) {
      final candidate = _currentQueue[index];
      if (candidate.id == item.id) song = candidate;
    }
    song ??= _currentQueue.where((s) => s.id == item.id).firstOrNull;
    if (identical(song, _tunedSong)) return;
    // Arriving mid fade-out means this is a natural transition: ease in.
    _fadeInActive = _fadeSeconds > 0 && _fadeFactor < 0.999;
    _tunedSong = song;
    _refreshReplayVolume();
    _applyVolume();
    // Some backends reset the rate when a new source loads.
    if (_speed != 1.0) _pushSpeed(force: true);
  }

  void _refreshReplayVolume() {
    final song = _tunedSong;
    _replayVolume = song == null
        ? 1.0
        : replayGainVolume(song, _replayGainMode);
  }

  int? _currentGlobalIndex() {
    if (_isDesktopBridge) return _desktopIndex;
    final i = player.currentIndex;
    return i == null ? null : _playlistOffset + i;
  }

  Song? _nextSong() {
    final index = _currentGlobalIndex();
    if (index == null || _currentQueue.isEmpty) return null;
    if (player.loopMode == LoopMode.one) return null;
    final next = index + 1;
    if (next < _currentQueue.length) return _currentQueue[next];
    return player.loopMode == LoopMode.all ? _currentQueue.first : null;
  }

  void _onFadeTick(Duration position) {
    final song = _tunedSong;
    if (song == null || _fadeSeconds <= 0) return;
    final durationMs =
        player.duration?.inMilliseconds ?? song.duration * 1000;
    final fadeOut = shouldCrossfade(
      fadeSeconds: _fadeSeconds,
      current: song,
      next: _nextSong(),
    );
    final factor = crossfadeGain(
      positionMs: position.inMilliseconds,
      durationMs: durationMs,
      fadeSeconds: _fadeSeconds,
      fadeOut: fadeOut,
      fadeIn: _fadeInActive,
    );
    if ((factor - _fadeFactor).abs() < 0.005) return;
    _fadeFactor = factor;
    _applyVolume();
  }

  void _applyVolume() {
    final v = (_replayVolume * _fadeFactor).clamp(0.0, 1.0).toDouble();
    if ((_appliedVolume - v).abs() < 0.001) return;
    _appliedVolume = v;
    try {
      unawaited(Future<void>.value(player.setVolume(v)).catchError((_) {}));
    } catch (e) {
      debugPrint('⚠️ [NaviAudioHandler] setVolume failed: $e');
    }
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
    if (_repeatMode != LoopMode.off) {
      await player.setLoopMode(_repeatMode);
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
        : Uri.parse(subsonicService.getCoverArtUrl(song.coverArt, size: 600));
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
      if (_repeatMode == LoopMode.one) {
        await player.seek(Duration.zero);
        await player.play();
        return;
      }

      int next = _desktopTargetIndex + 1;
      if (next >= _currentQueue.length) {
        if (_repeatMode == LoopMode.all) {
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
      if (_repeatMode == LoopMode.all) {
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
      if (_repeatMode == LoopMode.all) {
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
      final localIndex = index - _playlistOffset;
      if (localIndex >= 0 && _playlist != null && localIndex < _playlist!.children.length) {
        await player.seek(Duration.zero, index: localIndex);
      } else {
        final wasPlaying = player.playing;
        await _rebuildSource(index);
        if (wasPlaying) await player.play();
      }
    }
  }

  /// Override BaseAudioHandler.skipToQueueItem so callers (and platform media
  /// controls) land on the correct track on Desktop single-source mode.
  @override
  Future<void> skipToQueueItem(int index) async {
    index += _carQueueOffset; // the car's queue may be a window of ours
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
      final localIndex = index - _playlistOffset;
      if (localIndex >= 0 && _playlist != null && localIndex < _playlist!.children.length) {
        await player.seek(Duration.zero, index: localIndex);
      } else {
        await _rebuildSource(index);
        if (wasPlaying) await player.play();
      }
    }
  }

  Future<void> _updateQueueAfterAnchor(
    int anchorIndex, {
    bool preferMoveBasedReorder = false,
    String? preserveActiveSongId,
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

    await _moveBasedReorder(
      anchorIndex,
      preserveActiveSongId: preserveActiveSongId,
    );
  }

  Future<void> _moveBasedReorder(
    int anchorIndex, {
    String? preserveActiveSongId,
  }) async {
    debugPrint('🎵 [NaviAudioHandler] _moveBasedReorder at anchor: $anchorIndex');
    final int n = _currentQueue.length;
    final int playlistLen = _playlist!.children.length;
    // Queues over the source cap load a window starting at _playlistOffset;
    // reorder within that window rather than treating the size difference
    // as divergence (which rebuilt the source: an audible gap on every
    // Smart Shuffle reorder of a long playlist).
    final int windowEnd = (_playlistOffset + playlistLen).clamp(0, n);
    final List<Song> window = _playlistOffset < windowEnd
        ? _currentQueue.sublist(_playlistOffset, windowEnd)
        : const <Song>[];
    final liveSet = {
      for (final src in _playlist!.children)
        if (src.sequence.isNotEmpty && src.sequence.first.tag is MediaItem) (src.sequence.first.tag as MediaItem).id,
    };
    final sameSongs = window.length == playlistLen && window.every((s) => liveSet.contains(s.id));

    // Guard: if the loaded sources hold different songs from the queue
    // window, move-based reorder is unsafe — fall back to a full source
    // rebuild to prevent the "Not in inclusive range 0..N: N+1" RangeError.
    if (!sameSongs) {
      final activeId = preserveActiveSongId ?? _currentQueue[anchorIndex.clamp(0, n - 1)].id;
      final activeIdx = _currentQueue.indexWhere((song) => song.id == activeId);
      final liveIndex = player.currentIndex;
      final liveTag = liveIndex != null && liveIndex < playlistLen
          ? _playlist!.children[liveIndex].sequence.firstOrNull?.tag
          : null;
      if (activeIdx >= 0 && liveTag is MediaItem && liveTag.id == activeId) {
        // The playing song is loaded: replace everything around it without
        // touching it, so the audio never stops.
        debugPrint('ℹ️ [Reorder] sources differ from queue — replacing around the playing song');
        await updateQueuePreservingCurrent(List<Song>.from(_currentQueue), activeIdx);
        return;
      }
      debugPrint('⚠️ [Reorder] playing song not loaded — rebuilding source at anchor $anchorIndex');
      final savedPosition = player.position;
      await _rebuildSource(
        (activeIdx >= 0 ? activeIdx : currentIndex).clamp(0, n - 1),
        initialPosition: savedPosition,
      );
      if (player.playing) player.play();
      return;
    }

    final List<String> liveIds = List.generate(playlistLen, (i) {
      final src = _playlist!.children[i];
      if (src.sequence.isNotEmpty && src.sequence.first.tag is MediaItem) {
        return (src.sequence.first.tag as MediaItem).id;
      }
      return '';
    });

    for (int targetIdx = 0; targetIdx < playlistLen; targetIdx++) {
      final wantedId = window[targetIdx].id;
      if (liveIds[targetIdx] == wantedId) continue;
      final fromIdx = liveIds.indexOf(wantedId, targetIdx + 1);
      if (fromIdx == -1) continue;
      await _playlist!.move(fromIdx, targetIdx);
      final moved = liveIds.removeAt(fromIdx);
      liveIds.insert(targetIdx, moved);
    }

    // Smart-local refills are allowed to overlap the end of a track. In that
    // case the audio engine may advance while the source moves are happening.
    // Seeking to the original anchor here would rewind playback to the song
    // that was active when the refill started, creating a UI/audio mismatch.
    // ConcatenatingAudioSource.move keeps the active media item in place, so
    // preserve that item and let just_audio maintain its live index.
    if (preserveActiveSongId == null) {
      final currentLiveIndex = currentIndex;
      final localAnchor = anchorIndex - _playlistOffset;
      if (currentLiveIndex != anchorIndex && localAnchor >= 0 && localAnchor < playlistLen) {
        await player.seek(player.position, index: localAnchor);
      }
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
        // A windowed queue: songs before the loaded window just shift the
        // offset; only the part inside the window touches the sources. (This
        // used to rebuild the whole source, restarting the playing song.)
        final oldOffset = _playlistOffset;
        final len = _playlist!.children.length;
        final beforeWindow = (end < oldOffset ? end : oldOffset) - start;
        final localStart = (start > oldOffset ? start : oldOffset) - oldOffset;
        final localEnd = ((end < oldOffset + len ? end : oldOffset + len) - oldOffset);
        if (beforeWindow > 0) _playlistOffset -= beforeWindow;
        if (localEnd > localStart) await _playlist!.removeRange(localStart, localEnd);
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
    // Capture the audio engine's active song before replacing the in-memory
    // queue. A Smart Shuffle refill can finish at the same moment playback
    // advances, so the caller's numeric anchor may already be stale.
    String? activeSongId;
    if (preferMoveBasedReorder && _currentQueue.isNotEmpty) {
      final liveIndex = currentIndex;
      if (liveIndex >= 0 && liveIndex < _currentQueue.length) {
        activeSongId = _currentQueue[liveIndex].id;
      }
    }

    _currentQueue = [...pastAndPresent, ...orderedFuture];
    await _updateQueueAfterAnchor(
      anchorIndex,
      preferMoveBasedReorder: preferMoveBasedReorder,
      preserveActiveSongId: activeSongId,
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
    await _fadeSub?.cancel();
    _fadeSub = null;
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
