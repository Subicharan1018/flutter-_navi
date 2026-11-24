import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../ai_shuffle/data/models/feedback_request.dart';
import '../../online_fetch/data/fetch_models.dart';
import '../../online_fetch/data/online_fetch_api.dart'
    show OnlineFetchException;
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../../play_outbox/logic/play_event.dart';
import '../../play_outbox/logic/play_outbox_providers.dart'
    show playRecorderProvider;
import '../data/preview_feed_api.dart';
import '../data/preview_models.dart';
import 'preview_feed_audio.dart';

/// Songs asked for per page; the next page is asked for when three are left.
const int kPreviewPage = 12;
const int _kPrefetchAt = 3;

/// The seconds a preview runs.
const double kPreviewClipSeconds = 30;

final previewFeedApiProvider = Provider<PreviewFeedApi>(
  (ref) => PreviewFeedApi(ref.watch(fetchDioProvider)),
);

/// Where a heart's download is.
enum FeedFetchPhase { starting, queued, owned, failed }

enum FeedLoad { loading, ready, error }

@immutable
class PreviewFeedState {
  final FeedLoad load;
  final String? error;
  final List<PreviewItem> items;
  final int index;

  /// Keys hearted in this session, with where each download is.
  final Map<String, FeedFetchPhase> hearted;

  /// Hearts left today (the server's daily cap); null until known.
  final int? remaining;

  /// A sentence for a toast (cap reached, a fetch that could not start), cleared by [PreviewFeedController.ackNote].
  final String? note;
  final bool playing;
  final bool loadingMore;

  /// The server has nothing more to show right now.
  final bool exhausted;

  const PreviewFeedState({
    this.load = FeedLoad.loading,
    this.error,
    this.items = const [],
    this.index = 0,
    this.hearted = const {},
    this.remaining,
    this.note,
    this.playing = false,
    this.loadingMore = false,
    this.exhausted = false,
  });

  PreviewItem? get current =>
      index >= 0 && index < items.length ? items[index] : null;
  bool isHearted(String key) => hearted.containsKey(key);

  PreviewFeedState copyWith({
    FeedLoad? load,
    String? error,
    List<PreviewItem>? items,
    int? index,
    Map<String, FeedFetchPhase>? hearted,
    int? remaining,
    String? note,
    bool clearNote = false,
    bool? playing,
    bool? loadingMore,
    bool? exhausted,
  }) => PreviewFeedState(
    load: load ?? this.load,
    error: load == FeedLoad.error ? error : null,
    items: items ?? this.items,
    index: index ?? this.index,
    hearted: hearted ?? this.hearted,
    remaining: remaining ?? this.remaining,
    note: clearNote ? null : (note ?? this.note),
    playing: playing ?? this.playing,
    loadingMore: loadingMore ?? this.loadingMore,
    exhausted: exhausted ?? this.exhausted,
  );
}

/// How far into the current clip, 0 to 1. Its own provider so only the ring and the waveform rebuild.
class PreviewFeedProgress extends Notifier<double> {
  @override
  double build() => 0;
  void set(double v) => state = v;
}

final previewFeedProgressProvider =
    NotifierProvider<PreviewFeedProgress, double>(PreviewFeedProgress.new);

/// Starts the real download of a hearted song through the ordinary fetch path (search, then a job on the first candidate that
/// is not in the library). The grant and the signed bridge are the server's business, as for Search online. Overridden in tests.
final previewFetcherProvider =
    Provider<Future<FeedFetchPhase> Function(PreviewItem)>(
      (ref) => (item) async {
        final api = ref.read(onlineFetchApiProvider);
        final id = await api.startSearch(item.query);
        for (var i = 0; i < 30; i++) {
          final s = await api.search(id);
          switch (s.status) {
            case FetchSearchStatus.queued:
            case FetchSearchStatus.searching:
              await Future<void>.delayed(const Duration(seconds: 2));
              continue;
            case FetchSearchStatus.inLibrary:
              return FeedFetchPhase.owned;
            case FetchSearchStatus.done:
              final c = s.candidates
                  .where((c) => c.isSong && !c.blocked && !c.unreadable)
                  .firstOrNull;
              if (c == null) return FeedFetchPhase.failed;
              if (c.inLibrary) return FeedFetchPhase.owned;
              unawaited(
                ref
                    .read(fetchJobsProvider.notifier)
                    .download(c.id, coverUrl: c.coverUrl ?? item.artUrl),
              );
              return FeedFetchPhase.queued;
            case FetchSearchStatus.noResults:
            case FetchSearchStatus.superseded:
            case FetchSearchStatus.failed:
              return FeedFetchPhase.failed;
          }
        }
        return FeedFetchPhase.failed;
      },
    );

/// Reports a decided preview to the recommender through the normal play-event outbox (`play_source: other`,
/// `file_path: preview:<key>`): a swipe past is a `skip`, a heart a `complete` (an explicit heart counts as at least half heard).
final previewPlayEventProvider =
    Provider<
      Future<void> Function(
        PreviewItem, {
        required bool yes,
        required double ratio,
      })
    >((ref) {
      return (item, {required yes, required double ratio}) async {
        final rec = ref.read(playRecorderProvider);
        if (rec == null) return;
        final id = const Uuid().v4();
        final now = DateTime.now();
        final r = yes ? ratio.clamp(0.5, 1.0) : ratio.clamp(0.0, 0.29);
        await rec.feedbackReady(
          playId: id,
          songId: 'preview:${item.key}',
          startedAtMs: now.millisecondsSinceEpoch,
          request: FeedbackRequest(
            title: item.title,
            filePath: 'preview:${item.key}',
            listenRatio: r,
            endReason: yes ? 'natural' : 'fwdbtn',
            durationS: kPreviewClipSeconds.toInt(),
            playId: id,
            playedAtMs: now.millisecondsSinceEpoch,
            eventType: yes ? PlayEventType.complete : PlayEventType.skip,
            secondsPlayed: r * kPreviewClipSeconds,
            tzOffsetMin: now.timeZoneOffset.inMinutes,
            playSource: PlaySource.other,
          ),
        );
      };
    });

class PreviewFeedController extends Notifier<PreviewFeedState> {
  StreamSubscription<Duration>? _pos;
  StreamSubscription<void>? _done;
  bool _owesResume = false;
  bool _opened = false;
  int _gen =
      0; // bumps on every page change so a slow load of an old clip never plays
  double _heard = 0;
  final _decided = <String>{};

  @override
  PreviewFeedState build() {
    ref.onDispose(() {
      _pos?.cancel();
      _done?.cancel();
    });
    return const PreviewFeedState();
  }

  FeedAudio get _audio => ref.read(feedAudioProvider);
  PreviewFeedApi get _api => ref.read(previewFeedApiProvider);

  /// The feed screen opened: the listener's music steps aside (only if it is playing), the first page loads, the first clip plays.
  Future<void> open() async {
    if (_opened) return;
    _opened = true;
    _owesResume = await ref.read(mainPlayerYieldProvider).pauseIfPlaying();
    await load();
  }

  Future<void> load() async {
    state = state.copyWith(load: FeedLoad.loading, clearNote: true);
    try {
      final page = await _api.feed(limit: kPreviewPage);
      if (!ref.mounted) return;
      state = state.copyWith(
        load: FeedLoad.ready,
        items: page.items,
        index: 0,
        remaining: page.remaining,
        exhausted: page.items.isEmpty,
      );
      if (page.items.length <= _kPrefetchAt) unawaited(_more());
      if (page.items.isNotEmpty) await _playCurrent();
    } on OnlineFetchException catch (e) {
      if (ref.mounted) {
        state = state.copyWith(load: FeedLoad.error, error: e.message);
      }
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(
          load: FeedLoad.error,
          error: 'The preview feed didn’t load. Try again.',
        );
      }
    }
  }

  Future<void> _more() async {
    if (state.loadingMore || state.exhausted) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _api.feed(limit: kPreviewPage);
      if (!ref.mounted) return;
      final have = {for (final i in state.items) i.key};
      final fresh = [
        for (final i in page.items)
          if (!have.contains(i.key)) i,
      ];
      state = state.copyWith(
        items: [...state.items, ...fresh],
        remaining: page.remaining,
        loadingMore: false,
        exhausted: fresh.isEmpty,
      );
    } catch (_) {
      if (ref.mounted) state = state.copyWith(loadingMore: false);
    }
  }

  /// The pager settled on page [i]. The song left behind counts as a "no" unless it was hearted.
  Future<void> onPage(int i) async {
    if (i == state.index || i < 0 || i >= state.items.length) return;
    final left = state.current;
    final ratio = _heard;
    state = state.copyWith(index: i);
    if (left != null) unawaited(_decide(left, yes: false, ratio: ratio));
    if (i >= state.items.length - _kPrefetchAt) unawaited(_more());
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    final item = state.current;
    if (item == null) return;
    final gen = ++_gen;
    _heard = 0;
    ref.read(previewFeedProgressProvider.notifier).set(0);
    // Not awaited: a cancel has nothing to wait for, and the next clip must not queue behind it.
    unawaited(_pos?.cancel());
    unawaited(_done?.cancel());
    try {
      final a = _audio;
      if (state.playing) {
        await fadeVolume(a, 1, 0, const Duration(milliseconds: 140));
      }
      if (gen != _gen || !ref.mounted) return;
      await a.setVolume(0);
      await a.play(item.previewUrl);
      if (gen != _gen || !ref.mounted) return;
      state = state.copyWith(playing: true);
      _pos = a.position.listen((d) {
        if (gen != _gen) return;
        _heard = (d.inMilliseconds / (kPreviewClipSeconds * 1000)).clamp(
          0.0,
          1.0,
        );
        ref.read(previewFeedProgressProvider.notifier).set(_heard);
      });
      _done = a.completed.listen((_) {
        if (gen != _gen) return;
        _heard = 1;
        ref.read(previewFeedProgressProvider.notifier).set(1);
        state = state.copyWith(playing: false);
      });
      await fadeVolume(a, 0, 1, const Duration(milliseconds: 260));
    } catch (_) {
      if (gen == _gen && ref.mounted) {
        state = state.copyWith(
          playing: false,
          note: 'That preview couldn’t play. Swipe for the next one.',
        );
      }
    }
  }

  Future<void> togglePause() async {
    if (state.current == null) return;
    if (state.playing) {
      await _audio.pause();
      state = state.copyWith(playing: false);
    } else if (_heard >= 1) {
      await _playCurrent();
    } else {
      await _audio.resume();
      state = state.copyWith(playing: true);
    }
  }

  /// Heart: yes for the recommender, and the song is fetched. Used up for today: a sentence instead.
  Future<void> heart() async {
    final item = state.current;
    if (item == null || state.isHearted(item.key)) return;
    if (state.remaining != null && state.remaining! <= 0) {
      state = state.copyWith(
        note: 'That’s today’s limit of hearts. More tomorrow.',
      );
      return;
    }
    state = state.copyWith(
      hearted: {...state.hearted, item.key: FeedFetchPhase.starting},
    );
    final ok = await _decide(item, yes: true, ratio: _heard);
    if (!ref.mounted) return;
    if (!ok) {
      final h = {...state.hearted}..remove(item.key);
      state = state.copyWith(
        hearted: h,
        remaining: 0,
        note: 'That’s today’s limit of hearts. More tomorrow.',
      );
      return;
    }
    FeedFetchPhase phase;
    try {
      phase = await ref.read(previewFetcherProvider)(item);
    } catch (e) {
      phase = FeedFetchPhase.failed;
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      hearted: {...state.hearted, item.key: phase},
      note: switch (phase) {
        FeedFetchPhase.queued => 'Fetching ${item.title}',
        FeedFetchPhase.owned => '${item.title} is already in your library',
        FeedFetchPhase.failed =>
          'Couldn’t start fetching ${item.title}. It stays hearted.',
        FeedFetchPhase.starting => null,
      },
    );
  }

  /// Sends the yes/no once per song. Returns false when a heart was refused for the daily cap.
  Future<bool> _decide(
    PreviewItem item, {
    required bool yes,
    required double ratio,
  }) async {
    if (!yes && (_decided.contains(item.key) || state.isHearted(item.key))) {
      return true;
    }
    if (yes && _decided.contains('yes:${item.key}')) return true;
    _decided.add(yes ? 'yes:${item.key}' : item.key);
    try {
      final r = await _api.signal(item, yes: yes, ratio: ratio);
      if (ref.mounted) state = state.copyWith(remaining: r.remaining);
      if (r.capReached && yes) {
        _decided.remove('yes:${item.key}');
        return false;
      }
    } catch (_) {
      // The server may be unreachable: the swipe still works, the signal is just lost. A heart's fetch is the part that matters.
    }
    try {
      await ref.read(previewPlayEventProvider)(item, yes: yes, ratio: ratio);
    } catch (_) {}
    return true;
  }

  void ackNote() {
    if (state.note != null) state = state.copyWith(clearNote: true);
  }

  /// The screen closed: the clip stops, the listener's music comes back if it was playing before.
  Future<void> close() async {
    // Everything is read first: this runs while the screen is going away, and the provider may be disposed during the awaits.
    final audio = _audio;
    final yielder = ref.read(mainPlayerYieldProvider);
    final owes = _owesResume;
    _gen++;
    _owesResume = false;
    _opened = false;
    final pos = _pos, done = _done;
    _pos = _done = null;
    try {
      await audio.stop();
    } catch (_) {}
    unawaited(pos?.cancel());
    unawaited(done?.cancel());
    if (owes) await yielder.resume();
  }
}

final previewFeedProvider =
    NotifierProvider.autoDispose<PreviewFeedController, PreviewFeedState>(
      PreviewFeedController.new,
    );
