import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/spotify_import/data/spotify_import_api.dart';
import 'package:navivibe/features/spotify_import/data/spotify_import_models.dart';
import 'package:navivibe/features/spotify_import/logic/spotify_import_providers.dart';
import 'package:navivibe/features/spotify_import/logic/spotify_parser.dart';
import 'package:navivibe/features/spotify_import/ui/spotify_import_screen.dart';

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
  int id = 7,
  String status = 'ready',
  int fetched = 0,
  int? total = 2500,
  int imported = 0,
  int skips = 0,
  int listens = 0,
  int songsMatched = 0,
  int songsUnmatched = 0,
  int wished = 0,
  int already = 0,
  int rejectedTotal = 0,
  int unclear = 0,
}) => {
  'id': id,
  'source': 'spotify',
  'account': 'spotify export',
  'status': status,
  'total': total,
  'fetched': fetched,
  'imported': imported,
  'wished': wished,
  'already': already,
  'near_dups': 0,
  'skipped': rejectedTotal,
  'rejected_total': rejectedTotal,
  'rejected': rejectedTotal == 0 ? <String, int>{} : {'bad_time': rejectedTotal},
  'skips': skips,
  'listens': listens,
  'unclear': unclear,
  'songs_matched': songsMatched,
  'songs_unmatched': songsUnmatched,
  'wishlist_id': songsUnmatched > 0 ? 3 : null,
  'oldest_ts': 1698924536,
  'newest_ts': 1794153638,
  'error': null,
};

List<SpotifyPlay> _plays(int n) => [
  for (var i = 0; i < n; i++)
    SpotifyPlay(t: 1700000000 + i * 200, ms: 200000, title: 'Song $i', artist: 'Artist', album: 'A', end: 'trackdone', skipped: false),
];

SpotifyParseResult _parsed(int n) => SpotifyParseResult(
  _plays(n),
  SpotifyParseSummary(
    format: SpotifyFormat.extended,
    filesRead: 2,
    filesIgnored: 3,
    rows: n + 21,
    kept: n,
    droppedEpisodes: 19,
    droppedPrivate: 2,
    firstTs: 1698924536,
    lastTs: 1794153638,
  ),
);

class _Rig {
  final _Adapter adapter;
  final List<Duration> waited = [];
  late final ProviderContainer container;

  _Rig(ResponseBody Function(RequestOptions o) handler, {int plays = 2500, List<String> paths = const ['x.zip']})
    : adapter = _Adapter(handler) {
    final dio = Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = adapter;
    container = ProviderContainer(
      overrides: [
        spotifyImportApiProvider.overrideWithValue(SpotifyImportApi(dio)),
        spotifyFilePickerProvider.overrideWithValue(() async => paths),
        spotifyParserProvider.overrideWithValue((_) async => _parsed(plays)),
        spotifyDelayProvider.overrideWithValue((d) async => waited.add(d)),
      ],
    );
    container.listen(spotifyImportProvider, (_, _) {});
  }

  SpotifyImportController get ctl => container.read(spotifyImportProvider.notifier);
  SpotifyRun get run => container.read(spotifyImportProvider);
  Future<void> loaded() async {
    for (var i = 0; i < 100 && !run.loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  List<RequestOptions> get pages => adapter.seen.where((o) => o.path.endsWith('/page')).toList();
}

void main() {
  test('the job model reads the server summary', () {
    final j = SpotifyJob.fromJson(_job(fetched: 1000, total: 4000, imported: 600, skips: 100, listens: 500));
    expect(j.progress, 0.25);
    expect((j.skips, j.listens), (100, 500));
    expect(SpotifyJob.fromJson(_job(status: 'done')).progress, 1);
    expect(SpotifyJob.fromJson(_job(total: null)).progress, isNull);
    expect(SpotifyJob.fromJson(_job(rejectedTotal: 3)).rejected, {'bad_time': 3});
    expect(monthYear(1698924536), 'Nov 2023');
  });

  test('choosing a file reads it and keeps the plays off the screen state', () async {
    final rig = _Rig((o) => _json(200, <dynamic>[]));
    addTearDown(rig.container.dispose);
    await rig.loaded();
    await rig.ctl.choose();
    expect(rig.run.parsed!.kept, 2500);
    expect(rig.run.pagesTotal, 3);
    expect(rig.adapter.seen.where((o) => o.method == 'POST'), isEmpty, reason: 'nothing is sent until Import');
  });

  test('sends the pages in order, only the needed fields, then finishes', () async {
    var n = 0;
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, <dynamic>[]);
      if (o.path == '/spotify-import/jobs') return _json(201, _job());
      if (o.path.endsWith('/finish')) return _json(200, _job(status: 'done', fetched: 2500, imported: 2000, skips: 300, listens: 1700));
      n++;
      return _json(200, _job(fetched: n * 1000));
    });
    addTearDown(rig.container.dispose);
    await rig.loaded();
    await rig.ctl.choose();
    await rig.ctl.start();
    expect(rig.run.error, isNull);
    expect(rig.run.job!.isDone, isTrue);
    expect(rig.run.parsed, isNull, reason: 'the file is forgotten once sent');
    final create = rig.adapter.seen.firstWhere((o) => o.path == '/spotify-import/jobs' && o.method == 'POST');
    expect(create.data, {'format': 'extended', 'total': 2500});
    expect(rig.pages.map((o) => (o.data['plays'] as List).length), [1000, 1000, 500]);
    final first = (rig.pages.first.data['plays'] as List).first as Map;
    expect(first.keys.toSet(), {'t', 'ms', 'title', 'artist', 'album', 'end', 'sk'});
    expect(rig.adapter.seen.last.path, endsWith('/finish'));
  });

  test('a busy server is waited out, a failed page stops the run, and Resume carries on from that page', () async {
    var calls = 0;
    var failPage2 = true;
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, <dynamic>[]);
      if (o.path == '/spotify-import/jobs') return _json(200, _job());
      if (o.path.endsWith('/finish')) return _json(200, _job(status: 'done', fetched: 2500));
      calls++;
      if (calls == 1) return _json(409, {'error': 'this import is already running'});
      if (calls == 3 && failPage2) {
        failPage2 = false;
        return _json(500, {'error': 'Online search isn’t available right now.'});
      }
      return _json(200, _job(fetched: 1000 * calls));
    });
    addTearDown(rig.container.dispose);
    await rig.loaded();
    await rig.ctl.choose();
    await rig.ctl.start();
    expect(rig.waited, [const Duration(seconds: 3)], reason: 'the 409 was waited out once');
    expect(rig.run.error, isNotNull);
    expect(rig.run.pagesSent, 1);
    expect(rig.run.running, isFalse);
    expect(rig.run.parsed, isNotNull, reason: 'the file is kept so Resume does not ask again');
    await rig.ctl.start();
    expect(rig.run.error, isNull);
    expect(rig.run.job!.isDone, isTrue);
    expect(rig.pages.length, 5, reason: '409, ok, 500, then pages 2 and 3');
  });

  test('pause stops after the page being sent', () async {
    late _Rig rig;
    rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, <dynamic>[]);
      if (o.path == '/spotify-import/jobs') return _json(201, _job());
      rig.ctl.pause();
      return _json(200, _job(fetched: 1000));
    });
    addTearDown(rig.container.dispose);
    await rig.loaded();
    await rig.ctl.choose();
    await rig.ctl.start();
    expect(rig.pages, hasLength(1));
    expect(rig.run.pagesSent, 1);
    expect(rig.run.running, isFalse);
    expect(rig.run.job!.isDone, isFalse);
  });

  test('a file with no plays is said plainly and nothing can be sent', () async {
    final rig = _Rig((o) => _json(200, <dynamic>[]), plays: 0);
    addTearDown(rig.container.dispose);
    await rig.loaded();
    await rig.ctl.choose();
    expect(rig.run.error, contains('No music plays'));
    await rig.ctl.start();
    expect(rig.adapter.seen.where((o) => o.method == 'POST'), isEmpty);
  });

  test('backing out of the picker changes nothing', () async {
    final rig = _Rig((o) => _json(200, <dynamic>[]), paths: const []);
    addTearDown(rig.container.dispose);
    await rig.loaded();
    await rig.ctl.choose();
    expect(rig.run.parsed, isNull);
    expect(rig.run.error, isNull);
  });

  test('opening the screen finds the last import; removing it clears it', () async {
    final rig = _Rig((o) {
      if (o.method == 'GET') return _json(200, [_job(status: 'done', fetched: 2500, imported: 2000)]);
      return _json(200, {'removed_plays': 2000});
    });
    addTearDown(rig.container.dispose);
    await rig.loaded();
    expect(rig.run.job!.imported, 2000);
    expect(await rig.ctl.undo(), 2000);
    expect(rig.run.job, isNull);
    expect(rig.adapter.seen.last.path, '/history-import/jobs/7/undo');
  });

  test('a server that cannot be reached is a failed load that can be retried', () async {
    var up = false;
    final rig = _Rig((o) => up ? _json(200, [_job(status: 'done')]) : _json(502, {'error': 'x'}));
    addTearDown(rig.container.dispose);
    await rig.loaded();
    expect(rig.run.loadFailed, isTrue);
    up = true;
    await rig.ctl.load();
    expect(rig.run.loadFailed, isFalse);
    expect(rig.run.job, isNotNull);
  });

  group('the screen', () {
    Future<void> show(WidgetTester tester, _Rig rig) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rig.container,
          child: MaterialApp(
            home: Scaffold(
              body: ThemeTokens(tokens: AppThemeTokens.fallback, child: const SpotifyImportScreen()),
            ),
          ),
        ),
      );
    }

    testWidgets('empty: says what is read and dropped and offers the file', (tester) async {
      final rig = _Rig((o) => _json(200, <dynamic>[]));
      addTearDown(rig.container.dispose);
      await show(tester, rig);
      await tester.pumpAndSettle();
      expect(find.text('Read from each song you played'), findsOneWidget);
      expect(find.text('Dropped on this device, never sent'), findsOneWidget);
      expect(find.textContaining('IP address'), findsOneWidget);
      expect(find.textContaining('Private Session'), findsOneWidget);
      expect(find.text('Choose Export File'), findsOneWidget);
    });

    testWidgets('loading shows a skeleton, not a button', (tester) async {
      final rig = _Rig((o) => _json(200, <dynamic>[]));
      addTearDown(rig.container.dispose);
      await show(tester, rig);
      expect(find.text('Choose Export File'), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('error: says what failed and offers Try again', (tester) async {
      final rig = _Rig((o) => _json(502, {'error': 'x'}));
      addTearDown(rig.container.dispose);
      await show(tester, rig);
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Choose Export File'), findsNothing);
    });

    testWidgets('a chosen file shows what it holds and what was left out, then Import', (tester) async {
      final rig = _Rig((o) => _json(200, <dynamic>[]));
      addTearDown(rig.container.dispose);
      await show(tester, rig);
      await tester.pumpAndSettle();
      await tester.runAsync(rig.ctl.choose);
      await tester.pumpAndSettle();
      expect(find.textContaining('2,500 plays of songs'), findsOneWidget);
      expect(find.textContaining('19 podcast episodes'), findsOneWidget);
      expect(find.textContaining('2 private plays'), findsOneWidget);
      expect(find.text('Import 2,500 Plays'), findsOneWidget);
    });

    testWidgets('the finished import shows skips and listens, the Wishlist and Remove', (tester) async {
      final rig = _Rig((o) {
        if (o.method == 'GET') {
          return _json(200, [
            _job(status: 'done', fetched: 15930, total: 15930, imported: 7385, skips: 2081, listens: 10392, songsMatched: 802, songsUnmatched: 1028, wished: 5088, already: 150, unclear: 539),
          ]);
        }
        return _json(200, <String, dynamic>{});
      });
      addTearDown(rig.container.dispose);
      await show(tester, rig);
      await tester.pumpAndSettle();
      expect(find.textContaining('Done: 15,930 plays read'), findsOneWidget);
      expect(find.textContaining('2,081 skips and 10,392 listens'), findsOneWidget);
      expect(find.textContaining('802 songs found in your library'), findsOneWidget);
      expect(find.text('Wishlist'), findsOneWidget);
      expect(find.text('Remove Imported History'), findsOneWidget);
      expect(find.text('Import Another File'), findsOneWidget);
    });
  });
}
