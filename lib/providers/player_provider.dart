import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/subsonic_service.dart';
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
  final LoopMode repeatMode;
  final List<String> starredIds;

  const PlayerState({
    required this.queue,
    required this.currentIndex,
    required this.isPlaying,
    required this.shuffleMode,
    required this.repeatMode,
    required this.starredIds,
  });

  PlayerState copyWith({
    List<Song>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? shuffleMode,
    LoopMode? repeatMode,
    List<String>? starredIds,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      repeatMode: repeatMode ?? this.repeatMode,
      starredIds: starredIds ?? this.starredIds,
    );
  }
}

// ---------------------------------------------------------------------------
// Player notifier
// ---------------------------------------------------------------------------
class PlayerNotifier extends StateNotifier<PlayerState> {
  final Ref _ref;
  final AudioHandler _audioHandler;
  final SubsonicService _subsonicService;
  final Set<String> _scrobbledIds = {};
  final List<StreamSubscription> _subscriptions = [];

  PlayerNotifier(this._ref, this._audioHandler, this._subsonicService)
      : super(const PlayerState(
          queue: [],
          currentIndex: 0,
          isPlaying: false,
          shuffleMode: false,
          repeatMode: LoopMode.off,
          starredIds: [],
        )) {
    _init();
  }

  AudioPlayer get player => _audioHandler.player;

  void _init() {
    _subscriptions.add(player.currentIndexStream.listen((index) {
      if (index != null) state = state.copyWith(currentIndex: index);
    }));

    _subscriptions.add(player.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    }));

    _subscriptions.add(player.shuffleModeEnabledStream.listen((shuffle) {
      state = state.copyWith(shuffleMode: shuffle);
    }));

    _subscriptions.add(player.loopModeStream.listen((loopMode) {
      state = state.copyWith(repeatMode: loopMode);
    }));

    _subscriptions.add(player.positionStream.listen((position) {
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

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  Future<void> setQueue(List<Song> songs, int startIndex) async {
    state = state.copyWith(queue: songs, currentIndex: startIndex);
    await _audioHandler.setQueue(songs, startIndex);
    player.play();
  }

  Future<void> playNext() async {
    try {
      if (player.hasNext) {
        await player.seekToNext();
      } else {
        await jumpTo(state.currentIndex < state.queue.length - 1
            ? state.currentIndex + 1
            : 0);
      }
    } catch (_) {
      await jumpTo(state.currentIndex < state.queue.length - 1
          ? state.currentIndex + 1
          : 0);
    }
  }

  Future<void> playPrev() async {
    try {
      if (player.position.inSeconds > 3) {
        await player.seek(Duration.zero);
      } else if (player.hasPrevious) {
        await player.seekToPrevious();
      } else {
        await jumpTo(state.currentIndex > 0 ? state.currentIndex - 1 : 0);
      }
    } catch (_) {
      await jumpTo(state.currentIndex > 0 ? state.currentIndex - 1 : 0);
    }
  }

  Future<void> jumpTo(int index) async {
    await player.seek(Duration.zero, index: index);
  }

  Future<void> addToQueue(Song song) async {
    final currentQueue = List<Song>.from(state.queue)..add(song);
    state = state.copyWith(queue: currentQueue);
    await _audioHandler.setQueue(currentQueue, state.currentIndex);
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
    await _audioHandler.setQueue(currentQueue, newIndex);
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
    await _audioHandler.setQueue(currentQueue, currentIndex);
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
    await player.setShuffleModeEnabled(enabled);

    if (enabled) {
      applyShuffleAlgorithm();
    }
  }

  void applyShuffleAlgorithm() {
    final settings = _ref.read(settingsProvider);
    final algorithm = settings.shuffleAlgorithm;
    switch (algorithm) {
      case ShuffleAlgorithm.spotify:
        _audioHandler.spotifyDitherShuffle(settings.shufflePreference);
        break;
      case ShuffleAlgorithm.youtube:
        _audioHandler.youtubeWeightedShuffle();
        break;
      case ShuffleAlgorithm.standard:
        _audioHandler.standardShuffle();
        break;
    }
    // Sync state with the newly reordered queue from the handler
    state = state.copyWith(queue: _audioHandler.currentQueue);
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
  return PlayerNotifier(ref, handler, service);
});