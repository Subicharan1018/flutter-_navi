import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/history_import/data/history_import_api.dart';
import 'package:navivibe/features/history_import/data/history_import_models.dart';
import 'package:navivibe/features/history_import/logic/history_import_providers.dart';
import 'package:navivibe/features/history_import/ui/history_import_screen.dart';

const _key = '0123456789abcdef0123456789abcdef';

class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions o) handler;
  final List<RequestOptions> seen = [];
  _Adapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async {
    seen.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);

Map<String, dynamic> _job({
  int id = 4,
  String source = 'lastfm',
  String status = 'ready',
  int fetched = 0,
  int? total = 600,
  int imported = 0,
  int wished = 0,
  String? error,
  bool done = false,
  int waitS = 0,
  bool fatal = false,
}) => {
  'id': id,
  'source': source,
  'account': 'sample_user',
  'status': status,
  'total': total,
  'fetched': fetched,
  'imported': imported,
  'wished': wished,
  'already': 0,
  'near_dups': 0,
  'skipped': 0,
  'songs_matched': 2,
  'songs_unmatched': 1,
  'wishlist_id': 9,
  'error': error,
  'done': done,
  'wait_s': waitS,
  'fatal': fatal,
};

class _Store extends HistoryCredentialStore {
  final Map<String, String> data = {};
  @override
  String read(String key) => data[key] ?? '';
  @override
  Future<void> write(String key, String value) async => data[key] = value.trim();
}

class _Rig {
  final _Adapter adapter;
  final _Store store = _Store();
  final List<Duration> waited = [];
  late final ProviderContainer container;

  _Rig(ResponseBody Function(RequestOptions o) handler) : adapter = _Adapter(handler) {
    final dio = Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = adapter;
    container = ProviderContainer(
      overrides: [
        historyImportApiProvider.overrideWithValue(HistoryImportApi(dio)),
        historyCredentialStoreProvider.overrideWithValue(store),
        historyDelayProvider.overrideWithValue((d) async => waited.add(d)),
      ],
    );
  }

  HistoryImportController ctl(HistorySource s) => container.read(historyImportProvider(s).notifier);
  HistoryRun run(HistorySource s) => container.read(historyImportProvider(s));
  List<RequestOptions> get steps => adapter.seen.where((o) => o.path.endsWith('/step')).toList();
}

void main() {
  test('the job model reads the server summary', () {
    final j = HistoryJob.fromJson(_job(fetched: 150, total: 600, imported: 100, wished: 20))!;
    expect(j.source, HistorySource.lastfm);
    expect(j.progress, 0.25);
    expect(j.songsUnmatched, 1);
    expect(HistoryJob.fromJson({..._job(), 'source': 'spotify'}), isNull);
    expect(HistoryJob.fromJson(_job(status: 'done', total: null))!.progress, 1);
    expect(HistoryJob.fromJson(_job(total: null))!.progress, isNull);
  });

  test('reads page after page until the server says done, sending the key each time and saving the inputs', () async {
    var n = 0;
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, <dynamic>[]);
      if (o.path == '/history-import/jobs') return _json(201, _job());
      n++;
      return _json(200, _job(fetched: n * 200, imported: n * 100, done: n == 3, status: n == 3 ? 'done' : 'ready'));
    });
    addTearDown(rig.container.dispose);
    await rig.ctl(HistorySource.lastfm).start(account: ' sample_user ', apiKey: _key);
    final run = rig.run(HistorySource.lastfm);
    expect(run.running, isFalse);
    expect(run.error, isNull);
    expect(run.job!.isDone, isTrue);
    expect(run.job!.fetched, 600);
    expect(rig.steps, hasLength(3));
    expect(rig.steps.every((o) => (o.data as Map)['secret'] == _key), isTrue);
    expect(rig.store.data['history_lastfm_account'], 'sample_user');
    expect(rig.store.data['history_lastfm_api_key'], _key);
    expect(rig.waited, isEmpty);
  });

  test('ListenBrainz sends no key at all', () async {
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, <dynamic>[]);
      if (o.path == '/history-import/jobs') return _json(201, _job(source: 'listenbrainz'));
      return _json(200, _job(source: 'listenbrainz', done: true, status: 'done'));
    });
    addTearDown(rig.container.dispose);
    await rig.ctl(HistorySource.listenbrainz).start(account: 'sample_user');
    expect(rig.steps.single.data, isEmpty);
    expect(rig.store.data.containsKey('history_lastfm_api_key'), isFalse);
  });

  test('a "slow down" is waited out second by second and then it goes on', () async {
    var n = 0;
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, <dynamic>[]);
      if (o.path == '/history-import/jobs') return _json(201, _job());
      n++;
      if (n == 1) return _json(200, _job(waitS: 3));
      return _json(200, _job(fetched: 200, done: true, status: 'done'));
    });
    addTearDown(rig.container.dispose);
    await rig.ctl(HistorySource.lastfm).start(account: 'u', apiKey: _key);
    expect(rig.waited, hasLength(3));
    expect(rig.run(HistorySource.lastfm).job!.isDone, isTrue);
  });

  test('keeps being told to wait: it stops and says so, and can be resumed', () async {
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, <dynamic>[]);
      if (o.path == '/history-import/jobs') return _json(201, _job());
      return _json(200, _job(waitS: 1));
    });
    addTearDown(rig.container.dispose);
    await rig.ctl(HistorySource.lastfm).start(account: 'u', apiKey: _key);
    final run = rig.run(HistorySource.lastfm);
    expect(run.running, isFalse);
    expect(run.error, contains('Resume'));
    expect(rig.steps, hasLength(maxWaitsInARow + 1));
  });

  test('a wrong name stops with the server\'s sentence', () async {
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, <dynamic>[]);
      if (o.path == '/history-import/jobs') return _json(201, _job());
      return _json(200, _job(status: 'error', error: 'Last.fm doesn’t know that username.', fatal: true));
    });
    addTearDown(rig.container.dispose);
    await rig.ctl(HistorySource.lastfm).start(account: 'nobody', apiKey: _key);
    expect(rig.run(HistorySource.lastfm).error, 'Last.fm doesn’t know that username.');
    expect(rig.steps, hasLength(1));
  });

  test('a dropped connection stops the run and keeps the progress', () async {
    var n = 0;
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, <dynamic>[]);
      if (o.path == '/history-import/jobs') return _json(201, _job());
      n++;
      if (n == 1) return _json(200, _job(fetched: 200, imported: 100));
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    });
    addTearDown(rig.container.dispose);
    await rig.ctl(HistorySource.lastfm).start(account: 'u', apiKey: _key);
    final run = rig.run(HistorySource.lastfm);
    expect(run.error, contains('Can’t reach the server'));
    expect(run.job!.fetched, 200);
    expect(run.running, isFalse);
  });

  test('missing name or a bad key never reach the server', () async {
    final rig = _Rig((o) => _json(200, <dynamic>[]));
    addTearDown(rig.container.dispose);
    await rig.ctl(HistorySource.listenbrainz).start(account: '  ');
    expect(rig.run(HistorySource.listenbrainz).error, contains('username'));
    await rig.ctl(HistorySource.lastfm).start(account: 'u', apiKey: 'nope');
    expect(rig.run(HistorySource.lastfm).error, contains('API key'));
    expect(rig.adapter.seen.where((o) => o.method == 'POST'), isEmpty);
  });

  test('opening the screen finds the last job; removing the history clears it', () async {
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, [_job(status: 'done', fetched: 600, imported: 400, done: true)]);
      return _json(200, {'removed_plays': 400});
    });
    addTearDown(rig.container.dispose);
    rig.container.listen(historyImportProvider(HistorySource.lastfm), (_, _) {});
    for (var i = 0; i < 50 && !rig.run(HistorySource.lastfm).loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(rig.run(HistorySource.lastfm).job!.imported, 400);
    expect(await rig.ctl(HistorySource.lastfm).undo(), 400);
    expect(rig.run(HistorySource.lastfm).job, isNull);
  });

  testWidgets('the screen asks for the key, shows progress and the wishlist link', (tester) async {
    final rig = _Rig((o) {
      if (o.method == 'GET') {
        return _json(200, [_job(status: 'ready', fetched: 150, total: 600, imported: 100, wished: 20)]);
      }
      return _json(200, <String, dynamic>{});
    });
    addTearDown(rig.container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: rig.container,
        child: MaterialApp(
          home: Scaffold(
            body: ThemeTokens(tokens: AppThemeTokens.fallback, child: const HistoryImportScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ListenBrainz'), findsWidgets);
    expect(find.text('Last.fm API key'), findsOneWidget);
    expect(find.textContaining('Read 150 of 600 plays'), findsOneWidget);
    expect(find.text('Resume'), findsWidgets);
    expect(find.text('Wishlist'), findsWidgets);
    await tester.tap(find.text('Resume').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter your'), findsWidgets);
  });
}
