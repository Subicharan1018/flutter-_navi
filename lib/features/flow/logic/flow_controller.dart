import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../listen/data/listen_api.dart' show ListenException;
import '../../listen/data/listen_models.dart';
import '../../listen/logic/listen_providers.dart';
import 'flow_session.dart';

/// The queue name Flow plays under; another queue taking over ends the Flow.
const String flowPlaylistName = 'Flow';

class FlowState {
  /// Flow is feeding the queue.
  final bool active;

  /// The first batch is on its way.
  final bool starting;

  /// The mood chip picked (null: any).
  final String? mood;

  /// What went wrong last, in a sentence to show; cleared by the next success.
  final String? error;

  /// What the last batch was made of: familiar, fresh and new-language songs.
  final FlowBlend blend;

  const FlowState({this.active = false, this.starting = false, this.mood, this.error, this.blend = const FlowBlend()});

  FlowState copyWith({bool? active, bool? starting, Object? mood = _keep, Object? error = _keep, FlowBlend? blend}) =>
      FlowState(
        active: active ?? this.active,
        starting: starting ?? this.starting,
        mood: identical(mood, _keep) ? this.mood : mood as String?,
        error: identical(error, _keep) ? this.error : error as String?,
        blend: blend ?? this.blend,
      );
}

const Object _keep = Object();

/// Flow: an endless personal stream. Start it and it plays a first batch, then
/// asks the server for another whenever the queue runs low, telling it what you
/// skipped, finished and starred so the next batch follows your taste. Kept
/// alive: it has to outlive the Home screen that started it.
final flowProvider = NotifierProvider<FlowController, FlowState>(FlowController.new);

/// Mood chips Flow can use (those with songs in the library).
final flowMoodsProvider = FutureProvider.autoDispose<List<FlowMood>>(
  (ref) async {
    if (!watchSignedIn(ref)) return const [];
    return ref.read(listenApiProvider).flowMoods();
  },
  retry: (_, _) => null,
);

class FlowController extends Notifier<FlowState> {
  FlowSession _session = FlowSession();
  StreamSubscription<Duration>? _position;
  Timer? _retry;
  Song? _current;
  Duration _peak = Duration.zero;

  @override
  FlowState build() {
    ref.listen(playerProvider.select((s) => (s.currentSong?.id, s.queue.length, s.currentIndex)), (_, _) => _onPlayer());
    ref.listen(playerProvider.select((s) => s.starredIds), (prev, next) {
      if (state.active) _session.starredChanged({...?prev}, {...next});
    });
    ref.onDispose(_release);
    return const FlowState();
  }

  void _release() {
    _position?.cancel();
    _position = null;
    _retry?.cancel();
    _retry = null;
  }

  /// Starts Flow with the picked mood: fetches a first batch and plays it.
  /// Returns false (with [FlowState.error] set) when it couldn't.
  Future<bool> start() async {
    if (state.starting) return false;
    _release();
    _session = FlowSession();
    state = FlowState(starting: true, mood: state.mood);
    try {
      final songs = await _fetch(FlowSession.firstBatchSize);
      if (!ref.mounted) return false;
      if (songs.isEmpty) {
        state = state.copyWith(starting: false, error: _emptyMessage());
        return false;
      }
      final player = ref.read(playerProvider.notifier);
      await player.playPlaylist(songs, playlistName: flowPlaylistName);
      if (!ref.mounted) return false;
      _current = songs.first;
      _peak = Duration.zero;
      _position = player.player.positionStream.listen((p) {
        if (p > _peak) _peak = p;
      });
      state = state.copyWith(active: true, starting: false, error: null);
      return true;
    } catch (e) {
      if (ref.mounted) state = state.copyWith(starting: false, error: _say(e));
      return false;
    }
  }

  /// Ends Flow. What's queued keeps playing as an ordinary queue.
  void stop() {
    _release();
    _current = null;
    if (state.active || state.starting) state = state.copyWith(active: false, starting: false);
  }

  /// Picks a mood chip (null: any). While Flow plays, the songs still to come
  /// are swapped for ones that fit the mood; the song playing stays.
  Future<void> selectMood(String? mood) async {
    if (mood == state.mood) return;
    state = state.copyWith(mood: mood, error: null);
    if (!state.active) return;
    final player = ref.read(playerProvider.notifier);
    // The queue shrinks below the refill line while it is emptied; hold the refill until it is done.
    _session.fetching = true;
    try {
      for (var i = ref.read(playerProvider).queue.length - 1; i > ref.read(playerProvider).currentIndex; i--) {
        await player.removeFromQueue(i);
      }
    } finally {
      _session.fetching = false;
    }
    await _refill();
  }

  void _onPlayer() {
    if (!state.active) return;
    final player = ref.read(playerProvider.notifier);
    if (player.currentPlaylistName != flowPlaylistName) {
      stop();
      return;
    }
    final s = ref.read(playerProvider);
    final now = s.currentSong;
    final before = _current;
    if (now != null && before != null && now.id != before.id) {
      _session.left(before.id, heard: _peak, durationSec: before.duration);
      _peak = Duration.zero;
    }
    _current = now ?? before;
    final upNext = s.queue.length - s.currentIndex - 1;
    if (_session.wantsMore(upNext)) _refill();
  }

  Future<void> _refill() async {
    if (_session.fetching) return;
    _session.fetching = true;
    try {
      final songs = await _fetch(FlowSession.batchSize);
      if (!ref.mounted || !state.active) return;
      if (songs.isEmpty) throw ListenException(_emptyMessage());
      await ref.read(playerProvider.notifier).addAllToQueue(songs);
      _session.succeeded();
      if (ref.mounted) state = state.copyWith(error: null);
    } catch (e) {
      if (!ref.mounted) return;
      _session.failed();
      if (_session.exhausted) {
        stop();
        state = state.copyWith(error: 'Flow stopped. Check your connection, then start it again.');
      } else {
        state = state.copyWith(error: _say(e));
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 21), _onPlayer);
      }
    } finally {
      _session.fetching = false;
    }
  }

  /// One batch from the server as library songs; records them as served.
  Future<List<Song>> _fetch(int count) async {
    final batch = await ref.read(listenApiProvider).flowNext(
          count: count,
          mood: state.mood,
          seen: _session.seen,
          feedback: _session.feedback,
          session: _session.id,
        );
    if (ref.mounted) state = state.copyWith(blend: batch.blend);
    final songs = await songsForPicks(ref, [for (final p in batch.items) p.songId]);
    _session.served([for (final s in songs) s.id]);
    return songs;
  }

  static String _say(Object e) => e is ListenException ? e.message : 'Flow couldn’t load songs. Try again.';

  String _emptyMessage() => state.mood == null
      ? 'Flow has nothing new to play right now. Try again later.'
      : 'No more ${state.mood} songs for Flow right now. Try another mood.';
}
