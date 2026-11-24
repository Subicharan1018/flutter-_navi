import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart'
    show OnlineFetchException;
import 'package:navivibe/features/preview_feed/data/preview_models.dart';
import 'package:navivibe/features/preview_feed/logic/preview_feed_providers.dart';

import 'preview_feed_fakes.dart';

ProviderContainer _container(FeedHarness h) {
  final c = ProviderContainer(overrides: h.overrides.cast());
  addTearDown(c.dispose);
  c.listen(previewFeedProvider, (_, _) {});
  return c;
}

void main() {
  test(
    'open: main player steps aside, first clip plays on its own audio, the list shows',
    () async {
      final h = FeedHarness([
        [for (var i = 1; i <= 5; i++) previewItem(i)],
      ]);
      final c = _container(h);
      await c.read(previewFeedProvider.notifier).open();
      final s = c.read(previewFeedProvider);
      expect(s.load, FeedLoad.ready);
      expect(s.items.length, 5);
      expect(s.remaining, 5);
      expect(h.mainCalls, ['pause']);
      expect(h.audio.calls, ['play https://cdn.example/p1.mp3']);
      expect(s.playing, isTrue);
    },
  );

  test(
    'swiping past a song is a no (server signal + play event); the next clip plays',
    () async {
      final h = FeedHarness([
        [for (var i = 1; i <= 5; i++) previewItem(i)],
      ]);
      final c = _container(h);
      final n = c.read(previewFeedProvider.notifier);
      await n.open();
      await n.onPage(1);
      expect(h.api.signals, ['no pv_1']);
      expect(h.events, ['skip pv_1']);
      expect(h.audio.calls.last, 'play https://cdn.example/p2.mp3');
      expect(c.read(previewFeedProvider).index, 1);
      await n.onPage(1); // the same page again changes nothing
      expect(h.api.signals.length, 1);
    },
  );

  test(
    'heart: yes signal, play event, a fetch through the fetcher, then the swipe does not turn it into a no',
    () async {
      final h = FeedHarness([
        [for (var i = 1; i <= 5; i++) previewItem(i)],
      ]);
      final c = _container(h);
      final n = c.read(previewFeedProvider.notifier);
      await n.open();
      await n.heart();
      var s = c.read(previewFeedProvider);
      expect(h.api.signals, ['yes pv_1']);
      expect(h.events, ['complete pv_1']);
      expect(h.fetched, ['pv_1']);
      expect(s.hearted['pv_1'], FeedFetchPhase.queued);
      expect(s.remaining, 4);
      expect(s.note, 'Fetching Song 1');
      await n.heart(); // a second tap on the same song does nothing
      expect(h.fetched.length, 1);
      await n.onPage(1);
      expect(h.api.signals, ['yes pv_1']);
    },
  );

  test('a song already in the library is said so, not fetched twice', () async {
    final h = FeedHarness([
      [previewItem(1), previewItem(2)],
    ])..fetchResult = FeedFetchPhase.owned;
    final c = _container(h);
    final n = c.read(previewFeedProvider.notifier);
    await n.open();
    await n.heart();
    expect(
      c.read(previewFeedProvider).note,
      'Song 1 is already in your library',
    );
  });

  test(
    'daily cap: the server says 429, nothing is fetched, the heart is not kept, a sentence is shown',
    () async {
      final h = FeedHarness([
        [previewItem(1), previewItem(2)],
      ]);
      h.api.capped = true;
      final c = _container(h);
      final n = c.read(previewFeedProvider.notifier);
      await n.open();
      await n.heart();
      final s = c.read(previewFeedProvider);
      expect(h.fetched, isEmpty);
      expect(s.hearted, isEmpty);
      expect(s.remaining, 0);
      expect(s.note, contains('limit'));
      await n.heart(); // already known to be used up: no request at all
      expect(h.api.signals, isEmpty);
    },
  );

  test('a failed fetch start leaves the heart and says so', () async {
    final h = FeedHarness([
      [previewItem(1)],
    ])..fetchResult = FeedFetchPhase.failed;
    final c = _container(h);
    final n = c.read(previewFeedProvider.notifier);
    await n.open();
    await n.heart();
    expect(
      c.read(previewFeedProvider).note,
      contains('Couldn’t start fetching'),
    );
    expect(c.read(previewFeedProvider).hearted['pv_1'], FeedFetchPhase.failed);
  });

  test(
    'near the end the next page is asked for and appended without repeats',
    () async {
      final h = FeedHarness([
        [for (var i = 1; i <= 4; i++) previewItem(i)],
        [previewItem(4), previewItem(5), previewItem(6)],
      ]);
      final c = _container(h);
      final n = c.read(previewFeedProvider.notifier);
      await n.open();
      await n.onPage(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(previewFeedProvider).items.map((i) => i.key), [
        'pv_1',
        'pv_2',
        'pv_3',
        'pv_4',
        'pv_5',
        'pv_6',
      ]);
      expect(h.api.feeds, 2);
    },
  );

  test(
    'empty feed: exhausted; server error: error state with its sentence, retry works',
    () async {
      final h = FeedHarness([[]]);
      final c = _container(h);
      await c.read(previewFeedProvider.notifier).open();
      expect(c.read(previewFeedProvider).exhausted, isTrue);
      expect(c.read(previewFeedProvider).items, isEmpty);

      final h2 = FeedHarness([
        [previewItem(1)],
      ]);
      h2.api.failFeed = const OnlineFetchException(
        'The server is busy — still working on it.',
        statusCode: 504,
        busy: true,
      );
      final c2 = _container(h2);
      await c2.read(previewFeedProvider.notifier).open();
      expect(c2.read(previewFeedProvider).load, FeedLoad.error);
      expect(c2.read(previewFeedProvider).error, contains('busy'));
      h2.api.failFeed = null;
      await c2.read(previewFeedProvider.notifier).load();
      expect(c2.read(previewFeedProvider).load, FeedLoad.ready);
    },
  );

  test('a clip that cannot play says so and the pager keeps working', () async {
    final h = FeedHarness([
      [previewItem(1), previewItem(2)],
    ]);
    h.audio.failPlay = true;
    final c = _container(h);
    final n = c.read(previewFeedProvider.notifier);
    await n.open();
    expect(c.read(previewFeedProvider).note, contains('couldn’t play'));
    h.audio.failPlay = false;
    await n.onPage(1);
    expect(c.read(previewFeedProvider).playing, isTrue);
  });

  test(
    'progress follows the clip; the end stops it; tapping play starts the clip again',
    () async {
      final h = FeedHarness([
        [previewItem(1)],
      ]);
      final c = _container(h);
      final n = c.read(previewFeedProvider.notifier);
      await n.open();
      h.audio.pos.add(const Duration(seconds: 15));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(previewFeedProgressProvider), closeTo(0.5, 0.001));
      h.audio.done.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(previewFeedProgressProvider), 1);
      expect(c.read(previewFeedProvider).playing, isFalse);
      await n.togglePause();
      expect(h.audio.calls.where((x) => x.startsWith('play ')).length, 2);
    },
  );

  test(
    'pause and resume go to the feed audio, never to the main player',
    () async {
      final h = FeedHarness([
        [previewItem(1)],
      ]);
      final c = _container(h);
      final n = c.read(previewFeedProvider.notifier);
      await n.open();
      h.audio.pos.add(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);
      await n.togglePause();
      expect(h.audio.calls.last, 'pause');
      await n.togglePause();
      expect(h.audio.calls.last, 'resume');
      expect(h.mainCalls, ['pause']);
    },
  );

  test(
    'close: the clip stops and the main player is given back only if it was playing',
    () async {
      final h = FeedHarness([
        [previewItem(1)],
      ]);
      final c = _container(h);
      final n = c.read(previewFeedProvider.notifier);
      await n.open();
      await n.close();
      expect(h.audio.calls.last, 'stop');
      expect(h.mainCalls, ['pause', 'resume']);

      final h2 = FeedHarness([
        [previewItem(1)],
      ], mainWasPlaying: false);
      final c2 = _container(h2);
      final n2 = c2.read(previewFeedProvider.notifier);
      await n2.open();
      await n2.close();
      expect(h2.mainCalls, ['pause']);
    },
  );

  test(
    'the server answer is parsed leniently: unplayable rows are dropped',
    () {
      final p = PreviewFeedPage.fromJson({
        'items': [
          {
            'key': 'k',
            'title': 'T',
            'artist': 'A',
            'preview_url': 'https://x/p.mp3',
            'art_url': '',
            'source': 'release',
          },
          {'key': 'k2', 'title': 'No url', 'artist': 'A', 'preview_url': ''},
          'junk',
        ],
        'remaining': 3,
        'cap': 25,
      });
      expect(p.items.length, 1);
      expect(p.items.single.source, PreviewSource.release);
      expect(p.items.single.artUrl, isNull);
      expect(p.remaining, 3);
    },
  );
}
