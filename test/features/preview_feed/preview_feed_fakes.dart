import 'dart:async';

import 'package:navivibe/features/preview_feed/data/preview_feed_api.dart';
import 'package:navivibe/features/preview_feed/data/preview_models.dart';
import 'package:navivibe/features/preview_feed/logic/preview_feed_audio.dart';
import 'package:navivibe/features/preview_feed/logic/preview_feed_providers.dart';

PreviewItem previewItem(int n, {String source = 'chart'}) => PreviewItem(
  key: 'pv_$n',
  title: 'Song $n',
  artist: 'Artist $n',
  previewUrl: 'https://cdn.example/p$n.mp3',
  source: PreviewSource.parse(source),
  reason: 'Trending · tamil #$n',
);

class FakeFeedAudio implements FeedAudio {
  final pos = StreamController<Duration>.broadcast();
  final done = StreamController<void>.broadcast();
  final calls = <String>[];
  bool failPlay = false;

  @override
  Stream<Duration> get position => pos.stream;
  @override
  Stream<void> get completed => done.stream;
  @override
  Future<void> play(String url) async {
    if (failPlay) throw StateError('no');
    calls.add('play $url');
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> dispose() async {}
}

class FakePreviewApi implements PreviewFeedApi {
  FakePreviewApi(this.pages);
  final List<List<PreviewItem>> pages;
  int remaining = 5;
  final signals = <String>[];
  bool capped = false;
  Object? failFeed;
  int feeds = 0;

  @override
  Future<PreviewFeedPage> feed({int limit = 12}) async {
    if (failFeed != null) throw failFeed!;
    final items = feeds < pages.length ? pages[feeds] : <PreviewItem>[];
    feeds++;
    return PreviewFeedPage(items: items, remaining: remaining, cap: 5);
  }

  @override
  Future<PreviewSignalResult> signal(
    PreviewItem item, {
    required bool yes,
    required double ratio,
  }) async {
    if (yes && capped) {
      return const PreviewSignalResult(remaining: 0, capReached: true);
    }
    signals.add('${yes ? 'yes' : 'no'} ${item.key}');
    if (yes) remaining--;
    return PreviewSignalResult(remaining: remaining);
  }
}

class FeedHarness {
  FeedHarness(List<List<PreviewItem>> pages, {this.mainWasPlaying = true})
    : api = FakePreviewApi(pages);
  final FakePreviewApi api;
  final audio = FakeFeedAudio();
  final bool mainWasPlaying;
  final mainCalls = <String>[];
  final fetched = <String>[];
  final events = <String>[];
  FeedFetchPhase fetchResult = FeedFetchPhase.queued;

  List<dynamic> get overrides => [
    previewFeedApiProvider.overrideWithValue(api),
    feedAudioProvider.overrideWithValue(audio),
    mainPlayerYieldProvider.overrideWithValue(
      MainPlayerYield(
        pauseIfPlaying: () async {
          mainCalls.add('pause');
          return mainWasPlaying;
        },
        resume: () async => mainCalls.add('resume'),
      ),
    ),
    previewFetcherProvider.overrideWithValue((item) async {
      fetched.add(item.key);
      return fetchResult;
    }),
    previewPlayEventProvider.overrideWithValue((
      item, {
      required bool yes,
      required double ratio,
    }) async {
      events.add('${yes ? 'complete' : 'skip'} ${item.key}');
    }),
  ];
}
