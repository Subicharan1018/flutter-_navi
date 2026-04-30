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
      queue.isNotEmpty && currentIndex < queue.length ? queue[currentIndex] : null;
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
    _loadPersistedState();
  }

  void _loadPersistedState() {
    final s = HiveBoxes.session;
    final p = HiveBoxes.prefs;

    final lastPosMs = s.get(HiveBoxes.kLastPositionMs, defaultValue: 0) as int;
    final shuffle = p.get(HiveBoxes.kShufflePreference, defaultValue: false) as bool;
    final repeatIdx = p.get('repeatMode', defaultValue: 0) as int;

    state = state.copyWith(
      shuffleMode: shuffle,
      repeatMode: LoopMode.values[repeatIdx.clamp(0, LoopMode.values.length - 1)],
    );

    if (lastPosMs > 0) {
      player.seek(Duration(milliseconds: lastPosMs));
    }
  }

  void _persistState() {
    final s = HiveBoxes.session;
    final p = HiveBoxes.prefs;

    if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
      final currentSong = state.queue[state.currentIndex];
      s.put(HiveBoxes.kCurrentTrackId, currentSong.id);
    }
    s.put(HiveBoxes.kLastPositionMs, player.position.inMilliseconds);
    p.put(HiveBoxes.kShufflePreference, state.shuffleMode);
    p.put('repeatMode', state.repeatMode.index);
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
            completed: prevSong != null && _lastKnownPosition.inSeconds > (prevSong.duration * 0.8).toInt(),
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

      if (state.autoplayMode && !_isFetchingSimilar && index == state.queue.length - 1) {
        final lastSong = state.queue[index];
        if (!_autoplayTriggeredFor.contains(lastSong.id)) {
          _autoplayTriggeredFor.add(lastSong.id);
          _fetchAndAppendSimilar(lastSong);
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
      state = state.copyWith(isPlaying: playing);
    }));

    _subscriptions.add(player.loopModeStream.listen((loopMode) {
      state = state.copyWith(repeatMode: loopMode);
    }));

    _subscriptions.add(player.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed) {
        // Queue ended or single song finished
        if (state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
          final song = state.queue[state.currentIndex];
          _collector.onSongEnded(song, player.position);
        }
      }
    }));

    Duration prevPosition = Duration.zero;
    _subscriptions.add(player.positionStream.listen((position) {
      if (player.currentIndex == _lastKnownIndex) {
        _lastKnownPosition = position;
      }
      if (position.inSeconds % 5 == 0) {
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
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _audioHandler.dispose();
    super.dispose();
  }

  Future<void> setQueue(List<Song> songs, int startIndex) async {
    _clearHistory();
    _nextSourceContext = 'user_queue';
    _nextTransitionType = 'user_selected';
    state = state.copyWith(queue: songs, currentIndex: startIndex);
    await _audioHandler.setQueue(songs, startIndex);
    player.play();
  }

  Future<void> playPlaylist(List<Song> songs, {bool shuffle = false}) async {
    if (songs.isEmpty) return;
    _clearHistory();
    _nextSourceContext = 'playlist';
    _nextTransitionType = 'user_selected';

    if (!shuffle) {
      state = state.copyWith(shuffleMode: false, queue: songs, currentIndex: 0);
      await _audioHandler.setQueue(songs, 0, unshuffledSongs: songs);
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
      final shuffled = await _audioHandler.computeShuffle(pool, settings.shuffleAlgorithm, settings.shufflePreference);
      final finalQueue = [currentSong, ...shuffled];
      state = state.copyWith(queue: finalQueue, currentIndex: 0);
      await _audioHandler.setQueue(finalQueue, 0, unshuffledSongs: songs);
      player.play();
    } finally {
      _isShuffling = false;
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
        await _jumpToInternal(state.currentIndex < state.queue.length - 1 ? state.currentIndex + 1 : 0, pushHistory: false);
      }
    } catch (_) {
      await _jumpToInternal(state.currentIndex < state.queue.length - 1 ? state.currentIndex + 1 : 0, pushHistory: false);
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
        final historyIndex = state.queue.sublist(0, state.currentIndex).lastIndexWhere((s) => s.id == historySong.id);
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
        await _jumpToInternal(state.currentIndex > 0 ? state.currentIndex - 1 : 0, pushHistory: false);
      }
    } catch (_) {
      _suppressNextHistoryPush = true;
      await _jumpToInternal(state.currentIndex > 0 ? state.currentIndex - 1 : 0, pushHistory: false);
    }
  }

  Future<void> jumpTo(int index) async {
    _nextTransitionType = 'user_selected';
    _nextSourceContext = 'user_selected';
    await _jumpToInternal(index, pushHistory: true);
  }

  Future<void> _jumpToInternal(int index, {required bool pushHistory}) async {
    if (pushHistory && state.queue.isNotEmpty && state.currentIndex < state.queue.length) {
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

  Future<void> toggleStar(String songId) async {
    final currentlyStarred = state.starredIds.contains(songId);
    if (currentlyStarred) {
      await _subsonicService.unstar(songId);
      state = state.copyWith(
        starredIds: state.starredIds.where((id) => id != songId).toList(),
        queue: state.queue.map((s) => s.id == songId ? s.copyWith(starred: false) : s).toList(),
      );
    } else {
      await _subsonicService.star(songId);
      state = state.copyWith(
        starredIds: [...state.starredIds, songId],
        queue: state.queue.map((s) => s.id == songId ? s.copyWith(starred: true) : s).toList(),
      );
    }
  }

  Future<void> toggleShuffle() async {
    await setShuffleMode(!state.shuffleMode);
  }

  Future<void> setShuffleMode(bool enabled) async {
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
      state = state.copyWith(queue: _audioHandler.currentQueue, currentIndex: _audioHandler.player.currentIndex ?? 0);
    } finally {
      _isShuffling = false;
    }
  }

  Future<void> applyShuffleAlgorithm() async {
    _isShuffling = true;
    try {
      await Future.delayed(const Duration(milliseconds: 50));
      final savedIndex = _audioHandler.player.currentIndex ?? state.currentIndex;
      final settings = _ref.read(settingsProvider);
      switch (settings.shuffleAlgorithm) {
        case ShuffleAlgorithm.spotify: await _audioHandler.spotifyDitherShuffle(settings.shufflePreference); break;
        case ShuffleAlgorithm.youtube: await _audioHandler.youtubeWeightedShuffle(); break;
        case ShuffleAlgorithm.standard: await _audioHandler.standardShuffle(); break;
      }
      state = state.copyWith(queue: _audioHandler.currentQueue, currentIndex: savedIndex);
    } finally {
      _isShuffling = false;
    }
  }

  Future<void> cycleRepeat() async {
    final LoopMode nextMode;
    switch (state.repeatMode) {
      case LoopMode.off: nextMode = LoopMode.all; break;
      case LoopMode.all: nextMode = LoopMode.one; break;
      case LoopMode.one: nextMode = LoopMode.off; break;
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
    if (settings.dataCollectionEnabled) _collector.recordSuggestFeedback(song, isMore);
    _audioHandler.updateSongWeight(song, isMore);
    final updatedSong = _audioHandler.currentQueue.where((s) => s.id == song.id).firstOrNull;
    if (updatedSong != null) _collector.persistWeight(updatedSong.id, updatedSong.dynamicWeight);
    state = state.copyWith(queue: _audioHandler.currentQueue);
  }

  Future<void> scrobble(String songId) async {
    await _subsonicService.scrobble(songId);
  }

  Future<void> toggleAutoplay() async {
    state = state.copyWith(autoplayMode: !state.autoplayMode);
  }

  Future<void> _fetchAndAppendSimilar(Song lastSong) async {
    _isFetchingSimilar = true;
    try {
      final similar = await _subsonicService.getSimilarSongs(lastSong.id);
      if (similar.isNotEmpty) {
        final newQueue = [...state.queue, ...similar];
        state = state.copyWith(queue: newQueue);
        await _audioHandler.addAllToQueue(similar);
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
