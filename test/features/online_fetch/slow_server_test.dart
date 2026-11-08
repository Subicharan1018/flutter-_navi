import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/online_fetch/data/fetch_models.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';

/// A slow bot or a slow server is "still looking", never a failed search.

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

Map<String, dynamic> _search(String status, {String? note, String? error, bool withHit = false}) => {
      'id': 10,
      'query': 'kanave kanave',
      'status': status,
      'note': note,
      'error': error,
      'llm_state': 'off',
      'library': {'verdict': 'not_found', 'matches': []},
      'candidates': [
        if (withHit)
          {
            'id': 71, 'title': 'Kanave Kanave', 'artist': 'Anirudh Ravichander', 'album': 'Remo', 'score': 100.0,
            'kind': 'original', 'reasons': ['exact title'], 'library': 'not_found', 'llm': null,
          },
      ],
    };

void main() {
  setUp(() => OnlineSearchController.pollEvery = Duration.zero);

  ProviderContainer container(OnlineFetchApi api) {
    final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
    addTearDown(c.dispose);
    c.listen(onlineSearchProvider, (_, _) {});
    return c;
  }

  test('the server’s note ("Still looking…") is parsed and shown while searching', () {
    final s = FetchSearch.fromJson(_search('queued', note: 'Still looking — the music bot is slow (try 2 of 5)'));
    expect(s.isSearching, isTrue);
    expect(s.note, contains('Still looking'));
    expect(FetchSearch.fromJson(_search('done')).note, isNull);
  });

  test('a requeued search keeps polling through bot retries and ends with the result', () async {
    final answers = [
      _search('searching', note: 'Looking…'),
      _search('queued', note: 'Still looking — the music bot is slow (try 1 of 5)'),
      _search('queued', note: 'Still looking — the music bot is slow (try 2 of 5)'),
      _search('done', withHit: true),
    ];
    var i = 0;
    final notes = <String?>[];
    final api = _api((o) => o.method == 'POST' ? _json(202, {'search_id': 10}) : _json(200, answers[i++]));
    final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
    addTearDown(c.dispose);
    c.listen(onlineSearchProvider, (_, s) => notes.add(s.stillLooking));

    await c.read(onlineSearchProvider.notifier).start('kanave kanave');
    final s = c.read(onlineSearchProvider);
    expect(s.error, isNull);
    expect(s.search!.candidates.single.title, 'Kanave Kanave');
    expect(notes.whereType<String>().any((n) => n.contains('try 2 of 5')), isTrue);
  });

  test('timeouts and busy answers while polling are "still looking", not an error', () async {
    var polls = 0;
    final api = _api((o) {
      if (o.method == 'POST') return _json(202, {'search_id': 10});
      polls++;
      return switch (polls) {
        1 => _json(504, {'error': 'The song fetcher is busy — still working on it.', 'busy': true}),
        2 => _json(503, {'error': 'The song fetcher is offline. Try again later.'}),
        3 => _json(504, {'busy': true, 'error': 'busy'}),
        4 => _json(504, {'busy': true, 'error': 'busy'}),
        5 => _json(504, {'busy': true, 'error': 'busy'}),
        _ => _json(200, _search('done', withHit: true)),
      };
    });
    final c = container(api);
    final waits = <String?>[];
    c.listen(onlineSearchProvider, (_, s) => waits.add(s.waitNote));

    await c.read(onlineSearchProvider.notifier).start('kanave kanave');
    final s = c.read(onlineSearchProvider);
    expect(s.error, isNull);
    expect(s.search!.status, FetchSearchStatus.done);
    expect(waits.whereType<String>(), isNotEmpty);
    expect(waits.whereType<String>().first, contains('Still looking'));
    expect(s.waitNote, isNull, reason: 'cleared once the server answers again');
  });

  test('a real server error still ends the search, after a few tries', () async {
    var polls = 0;
    final api = _api((o) {
      if (o.method == 'POST') return _json(202, {'search_id': 10});
      polls++;
      return _json(500, {'error': 'boom'});
    });
    final c = container(api);
    await c.read(onlineSearchProvider.notifier).start('kanave kanave');
    expect(c.read(onlineSearchProvider).error, 'boom');
    expect(polls, OnlineSearchController.maxHardErrors);
  });

  test('401 on a poll ends it at once', () async {
    var polls = 0;
    final api = _api((o) {
      if (o.method == 'POST') return _json(202, {'search_id': 10});
      polls++;
      return _json(401, {});
    });
    final c = container(api);
    await c.read(onlineSearchProvider.notifier).start('kanave kanave');
    expect(c.read(onlineSearchProvider).error, contains('Sign in again'));
    expect(polls, 1);
  });

  test('exception flags: busy covers 502/504 and the proxy’s busy flag', () async {
    Future<OnlineFetchException> failWith(int code, Object body) async {
      try {
        await _api((_) => _json(code, body)).search(1);
      } on OnlineFetchException catch (e) {
        return e;
      }
      throw StateError('no exception');
    }

    expect((await failWith(504, {'busy': true})).isTransient, isTrue);
    expect((await failWith(502, {})).busy, isTrue);
    expect((await failWith(500, {'error': 'x'})).isTransient, isFalse);
    expect((await failWith(404, {})).isTransient, isFalse);
  });

  test('fetch requests get patient timeouts', () {
    final dio = configureFetchTimeouts(Dio(BaseOptions(receiveTimeout: const Duration(seconds: 20))));
    expect(dio.options.receiveTimeout!.inSeconds, greaterThanOrEqualTo(30));
    expect(dio.options.connectTimeout!.inSeconds, greaterThanOrEqualTo(10));
  });
}
