import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/data/fetch_queue_models.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart';
import 'package:navivibe/features/online_fetch/logic/fetch_queue_providers.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/online_fetch/ui/fetch_queue_sheet.dart';
import 'package:navivibe/features/trending/data/trending_models.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/art/generated_cover.dart';

class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions o) handler;
  _Adapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async => handler(o);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {'content-type': ['application/json']});

OnlineFetchApi _api(ResponseBody Function(RequestOptions o) handler) =>
    OnlineFetchApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = _Adapter(handler));

Finder _glyph(NaviGlyph g) => find.byWidgetPredicate((w) => w is NaviIcon && w.glyph == g);

Map<String, dynamic> _item(int id, String status, {String title = 'Tamil Hits', Map<String, dynamic>? more}) => {
      'id': id, 'user': 'admin', 'kind': 'playlist', 'title': title, 'artist': '', 'cover_url': null,
      'status': status, 'error': null, 'is_link': true, 'position': null, 'current': null,
      'total': 0, 'added': 0, 'owned': 0, 'lossy': 0, 'failed': 0, 'progress': 0.0, ...?more,
    };

Map<String, dynamic> _queue({bool admin = true, int? maxLinks, List<Map<String, dynamic>> items = const []}) =>
    {'admin': admin, 'max_links': maxLinks, 'items': items};

void main() {
  group('models', () {
    test('queue: running first, finished split from active, listing counts as running', () {
      final q = FetchQueue.fromJson(_queue(items: [
        _item(1, 'listing'),
        _item(2, 'queued', more: {'position': 1}),
        _item(3, 'done', more: {'summary': '12 songs added'}),
        _item(4, 'cancelled'),
        _item(5, 'failed', more: {'error': 'the bot didn’t answer'}),
      ]));
      expect(q.admin, isTrue);
      expect([for (final i in q.active) i.id], [1, 2]);
      expect([for (final i in q.finished) i.id], [3, 4, 5]);
      expect(q.items.first.status, QueueStatus.running);
      expect(q.items[3].canRetry && !q.items[3].canCancel, isTrue);
      expect(q.items[1].position, 1);
    });

    test('row text: where it stands, the song on now, whose it is', () {
      String text(Map<String, dynamic> m, {bool user = false}) =>
          describeQueueItem(FetchQueueItem.fromJson(_item(1, m.remove('s') as String, more: m)), showUser: user);
      expect(text({'s': 'queued', 'position': 1}), 'Playlist link · Next up');
      expect(text({'s': 'queued', 'position': 3}), 'Playlist link · Waiting · #3 in the queue');
      expect(text({'s': 'listing'}), 'Playlist link · Getting the songs…');
      expect(
        text({'s': 'running', 'total': 40, 'added': 10, 'owned': 2, 'current': 'Kanne Kanne — Sam Cs'}, user: true),
        'Playlist link · admin · 12 of 40 songs · Kanne Kanne — Sam Cs',
      );
      expect(text({'s': 'failed', 'error': 'Telegram rate limit'}), 'Playlist link · Telegram rate limit');
      expect(text({'s': 'cancelled'}), 'Playlist link · Cancelled');
      expect(text({'s': 'done', 'summary': '38 of 40 songs.'}), 'Playlist link · 38 of 40 songs.');
    });

    test('a chart that is a Deezer playlist carries its link', () {
      final c = TrendingChart.fromJson({
        'key': 'worldwide', 'title': 'Worldwide', 'source': 'Deezer', 'playlist_link': 'https://www.deezer.com/playlist/1',
        'entries': <Object>[],
      });
      expect(c.playlistLink, 'https://www.deezer.com/playlist/1');
      expect(TrendingChart.fromJson({'key': 'tamil', 'title': 'Tamil', 'source': 'JioSaavn'}).playlistLink, isNull);
    });
  });

  group('api', () {
    test('queue and actions hit the proxy routes', () async {
      final seen = <String>[];
      final api = _api((o) {
        seen.add('${o.method} ${o.path}');
        return _json(200, o.method == 'GET' ? _queue(maxLinks: 2) : {'ok': true});
      });
      expect((await api.queue()).maxLinks, 2);
      await api.cancelBatch(7);
      await api.retryBatch(7);
      await api.moveBatchToTop(7);
      expect(seen, ['GET /fetch/queue', 'POST /fetch/batches/7/cancel', 'POST /fetch/batches/7/retry', 'POST /fetch/batches/7/top']);
    });

    test('a refusal comes back in the server’s words', () async {
      final api = _api((_) => _json(409, {'error': 'only a queued download can be moved'}));
      await expectLater(
        api.moveBatchToTop(7),
        throwsA(isA<OnlineFetchException>().having((e) => e.message, 'message', 'only a queued download can be moved')),
      );
    });
  });

  group('queue a playlist link', () {
    test('lists the songs, then queues the whole playlist', () async {
      final seen = <String>[];
      final api = _api((o) {
        seen.add('${o.method} ${o.path}');
        if (o.method == 'POST' && o.path.endsWith('/searches')) return _json(202, {'search_id': 9});
        if (o.method == 'POST') return _json(202, {'batch_id': 3});
        return _json(200, {
          'id': 9, 'query': 'x', 'status': 'done', 'title': 'Top', 'candidates': [
            {'id': 1, 'title': 'A', 'artist': 'B', 'album': '', 'score': 0.0, 'kind': 'original', 'type': 'song'},
          ],
        });
      });
      expect(await queuePlaylistLink(api, 'https://www.deezer.com/playlist/1', pollEvery: Duration.zero), isNull);
      expect(seen, ['POST /fetch/searches', 'GET /fetch/searches/9', 'POST /fetch/batches']);
    });

    test('a refused queue (limit) is said in the server’s words', () async {
      final api = _api((o) {
        if (o.method == 'POST' && o.path.endsWith('/searches')) return _json(202, {'search_id': 9});
        if (o.method == 'POST') return _json(409, {'error': 'You already have 2 playlist links in the queue.'});
        return _json(200, {
          'id': 9, 'query': 'x', 'status': 'done', 'candidates': [
            {'id': 1, 'title': 'A', 'artist': 'B', 'album': '', 'score': 0.0, 'kind': 'original', 'type': 'song'},
          ],
        });
      });
      expect(await queuePlaylistLink(api, 'https://www.deezer.com/playlist/1', pollEvery: Duration.zero),
          'You already have 2 playlist links in the queue.');
    });
  });

  group('sheet', () {
    Future<List<String>> pumpSheet(WidgetTester tester, Map<String, dynamic> queue) async {
      FetchQueueController.pollEvery = const Duration(hours: 1);
      final posts = <String>[];
      final api = _api((o) {
        if (o.method == 'POST') {
          posts.add(o.path);
          return _json(200, {'ok': true});
        }
        return _json(200, queue);
      });
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [onlineFetchApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: ThemeTokens(tokens: AppThemeTokens.fallback, child: const SingleChildScrollView(child: FetchQueueSheet())),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return posts;
    }

    testWidgets('empty queue invites to add a link', (tester) async {
      await pumpSheet(tester, _queue());
      expect(find.text('Nothing in the queue'), findsOneWidget);
      expect(find.text('Add a Link'), findsOneWidget);
    });

    testWidgets('admin sees everyone’s, can move a waiting one up, cancel and retry', (tester) async {
      final posts = await pumpSheet(
        tester,
        _queue(items: [
          _item(1, 'running', title: 'Running', more: {'total': 40, 'added': 5, 'current': 'A — B', 'progress': 0.2}),
          _item(2, 'queued', title: 'Next', more: {'position': 1}),
          _item(3, 'queued', title: 'Later', more: {'position': 2, 'user': 'subi'}),
          _item(4, 'failed', title: 'Broke', more: {'error': 'no songs found'}),
        ]),
      );
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.textContaining('subi'), findsOneWidget);                         // an admin sees whose it is
      expect(find.text('Playlist link · admin · 5 of 40 songs · A — B'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);                // only the running one
      expect(_glyph(NaviGlyph.caretUp), findsOneWidget);                           // not on the one that is next
      await tester.tap(_glyph(NaviGlyph.caretUp));
      await tester.pumpAndSettle();
      await tester.tap(_glyph(NaviGlyph.repeat));
      await tester.pumpAndSettle();
      await tester.tap(_glyph(NaviGlyph.close).first);
      await tester.pumpAndSettle();
      expect(posts, ['/fetch/batches/3/top', '/fetch/batches/4/retry', '/fetch/batches/1/cancel']);
      expect(find.byType(GeneratedCover), findsWidgets);                           // no cover from the server
    });

    testWidgets('a plain user has no reorder, and is told the link limit', (tester) async {
      await pumpSheet(
        tester,
        _queue(admin: false, maxLinks: 2, items: [
          _item(2, 'queued', title: 'Mine', more: {'position': 2}),
        ]),
      );
      expect(find.text('You can have 2 playlist links in the queue at once.'), findsOneWidget);
      expect(_glyph(NaviGlyph.caretUp), findsNothing);
      expect(find.textContaining('admin'), findsNothing);
      expect(_glyph(NaviGlyph.close), findsOneWidget);
    });
  });
}
