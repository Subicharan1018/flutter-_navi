import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/exportify_import/data/exportify_api.dart';
import 'package:navivibe/features/exportify_import/data/exportify_models.dart';
import 'package:navivibe/features/exportify_import/logic/exportify_providers.dart';
import 'package:navivibe/features/exportify_import/ui/exportify_fetch_screen.dart';
import 'package:navivibe/features/exportify_import/ui/exportify_import_screen.dart';
import 'package:navivibe/features/exportify_import/ui/exportify_result_screen.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/ui/states.dart';

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

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {'content-type': ['application/json']});

(ExportifyApi, _Adapter) _api(ResponseBody Function(RequestOptions o) handler) {
  final adapter = _Adapter(handler);
  return (ExportifyApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = adapter), adapter);
}

Map<String, dynamic> _summary({
  int id = 7,
  String name = 'Tamil Mix',
  int unique = 6922,
  Map<String, int>? states,
  String status = 'idle',
  String? note,
  double wishlistGb = 210,
  double? free = 134,
  Map<String, dynamic>? more,
}) =>
    {
      'id': id, 'name': name, 'rows': unique + 100, 'unique': unique, 'duplicates': 90, 'skipped_rows': 10,
      'no_isrc': 84, 'maybe_owned': 5, 'playlist_id': null,
      'states': states ?? {'owned': 1118, 'wishlist': 5804},
      'owned': 1118, 'wishlist': 5804, 'wishlist_gb': wishlistGb, 'free_gb': free,
      'plan': {
        'status': status, 'priority': 'popularity', 'min_popularity': 0, 'per_night': 100,
        'disk_floor_gb': 40.0, 'night_only': true, 'note': note,
      },
      ...?more,
    };

Map<String, dynamic> _estimate({int songs = 5804, double gb = 210, double free = 134, int fits = 5804}) => {
      'songs': songs, 'gb': gb, 'hours': 412.0, 'free_gb': free, 'floor_gb': 40.0, 'fits': fits,
      'nights': 59, 'gb_per_hour': 0.51, 'bot_hours': 32.0,
    };

/// A tall screen, so the lazily built slivers of a long page are all on it.
void _tall(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 3200);
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: home)),
      ),
    );

Finder _glyph(NaviGlyph g) => find.byWidgetPredicate((w) => w is NaviIcon && w.glyph == g);

void main() {
  group('models', () {
    test('a summary: counts, library and wishlist totals, plan', () {
      final s = ExportifySummary.fromJson(_summary(
        states: {'owned': 100, 'downloaded': 20, 'wishlist': 70, 'skipped_disk': 4, 'queued': 5, 'failed': 1},
        status: 'paused_disk',
        note: 'Paused: disk is low (31 GB free, floor 40 GB).',
      ));
      expect(s.inLibrary, 120);
      expect(s.waiting, 74);
      expect(s.count(WishlistState.queued), 5);
      expect(s.plan.status, PlanStatus.pausedDisk);
      expect(s.plan.status.running, isTrue);
      expect(s.plan.note, startsWith('Paused: disk is low'));
      expect(s.plan.draft, (order: ExportifyOrder.popularity, minPopularity: 0, perNight: 100, floorGb: 40, nightOnly: true));
      expect(s.hasFetch, isTrue);
    });

    test('a fresh import has no fetch; the name falls back; junk is tolerated', () {
      final s = ExportifySummary.fromJson(_summary(name: '  '));
      expect(s.name, 'Spotify playlist');
      expect(s.hasFetch, isFalse);
      final odd = ExportifySummary.fromJson({'id': 1, 'states': 'nope', 'plan': 5});
      expect(odd.inLibrary, 0);
      expect(odd.plan.status, PlanStatus.idle);
      expect(odd.plan.draft.perNight, 100);
    });

    test('plan wire form and state names', () {
      expect(planBody(defaultPlanDraft), {
        'priority': 'popularity', 'min_popularity': 0, 'per_night': 100, 'disk_floor_gb': 40, 'night_only': true,
      });
      expect(WishlistState.skippedDisk.wire, 'skipped_disk');
      expect(WishlistState.parse('skipped_disk'), WishlistState.skippedDisk);
      expect(ExportifyOrder.parse('list'), ExportifyOrder.list);
    });

    test('the cost: a wishlist bigger than the room says so', () {
      final e = ExportifyEstimate.fromJson(_estimate(fits: 1200));
      expect(e.tooBig, isTrue);
      expect(e.gbPerHour, 0.51);
      expect(ExportifyEstimate.fromJson(_estimate()).tooBig, isFalse);
    });

    test('numbers read naturally', () {
      expect(groupThousands(6922), '6,922');
      expect(groupThousands(12), '12');
      expect(groupThousands(1000000), '1,000,000');
      expect(formatGb(210.4), '210 GB');
      expect(formatGb(0.512), '0.5 GB');
      expect(formatGb(17), '17 GB');
    });

    test('songs: artists are joined for reading', () {
      final s = ExportifySong.fromJson({'title': 'A', 'artist': 'X;Y; Z', 'state': 'failed', 'popularity': 40, 'error': 'not found'});
      expect(s.artist, 'X, Y, Z');
      expect(s.state, WishlistState.failed);
    });

    test('footnotes: what was folded, guessed or too big', () {
      final s = ExportifySummary.fromJson(_summary());
      expect(notes(s), [
        '90 repeats and 10 rows without a title were left out.',
        '5 wishlist songs have a version in your library at a different length. They stay on the wishlist.',
        '84 had no ISRC and were matched by title and artist.',
        'The wishlist is bigger than the free space. Fetching starts with the most popular songs and pauses before the disk gets low.',
      ]);
      expect(notes(ExportifySummary.fromJson(_summary(wishlistGb: 20, more: {'duplicates': 0, 'skipped_rows': 0, 'no_isrc': 0, 'maybe_owned': 0}))), isEmpty);
    });
  });

  group('api', () {
    test('every call goes to its own route with the plan as its body', () async {
      final (api, seen) = _api((o) => _json(200, o.path.endsWith('/songs/failed/0')
          ? {'songs': []}
          : o.path.endsWith('/estimate')
              ? _estimate()
              : o.path.endsWith('/owned')
                  ? {'ids': ['a', 'b']}
                  : _summary()));
      await api.createImport('mix.csv', 'Track Name,Artist Name(s)\n');
      await api.start(7, defaultPlanDraft);
      await api.savePlan(7, (order: ExportifyOrder.list, minPopularity: 40, perNight: 50, floorGb: 60, nightOnly: false));
      await api.estimate(7, defaultPlanDraft);
      await api.pause(7);
      await api.cancel(7);
      await api.retryFailed(7);
      await api.songs(7, WishlistState.failed);
      expect(await api.ownedIds(7), ['a', 'b']);
      await api.setPlaylist(7, 'pl1');
      await api.delete(7);
      expect([for (final o in seen.seen) '${o.method} ${o.path}'], [
        'POST /exportify/imports',
        'POST /exportify/imports/7/start',
        'PUT /exportify/imports/7/plan',
        'POST /exportify/imports/7/estimate',
        'POST /exportify/imports/7/pause',
        'POST /exportify/imports/7/cancel',
        'POST /exportify/imports/7/retry-failed',
        'GET /exportify/imports/7/songs/failed/0',
        'GET /exportify/imports/7/owned',
        'POST /exportify/imports/7/playlist',
        'DELETE /exportify/imports/7',
      ]);
      expect(seen.seen[0].data, {'name': 'mix.csv', 'csv': 'Track Name,Artist Name(s)\n'});
      expect(seen.seen[2].data, {'priority': 'list', 'min_popularity': 40, 'per_night': 50, 'disk_floor_gb': 60, 'night_only': false});
      expect(seen.seen[9].data, {'playlist_id': 'pl1'});
    });

    test('the server’s sentence is shown as is; a lost connection is said plainly', () async {
      final (api, _) = _api((o) => _json(422, {'error': 'This isn’t an Exportify playlist.'}));
      await expectLater(
        api.createImport('x', 'a,b'),
        throwsA(isA<OnlineFetchException>().having((e) => e.message, 'message', 'This isn’t an Exportify playlist.')),
      );
      final (gone, _) = _api((o) => throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
      await expectLater(
        gone.imports(),
        throwsA(isA<OnlineFetchException>().having((e) => e.message, 'message', contains('Can’t reach the server'))),
      );
    });
  });

  group('upload', () {
    ProviderContainer container(ExportifyApi api, CsvPicker picker) => ProviderContainer(overrides: [
          exportifyApiProvider.overrideWithValue(api),
          exportifyCsvPickerProvider.overrideWithValue(picker),
        ]);

    test('the file’s text goes to the server and the import comes back', () async {
      final (api, seen) = _api((o) => _json(201, _summary()));
      final c = container(api, () async => PickedCsv('Tamil_Mix.csv', utf8.encode('﻿Track Name,Artist Name(s)\nCafé,Zoë\n')));
      addTearDown(c.dispose);
      final sub = c.listen(exportifyUploadProvider, (_, _) {});
      final imp = await c.read(exportifyUploadProvider.notifier).pickAndUpload();
      expect(imp?.unique, 6922);
      expect((seen.seen.single.data as Map)['csv'], contains('Café,Zoë'));
      expect(c.read(exportifyUploadProvider).busy, isFalse);
      sub.close();
    });

    test('backing out of the picker is not an error', () async {
      final (api, seen) = _api((o) => _json(201, _summary()));
      final c = container(api, () async => null);
      addTearDown(c.dispose);
      final sub = c.listen(exportifyUploadProvider, (_, _) {});
      expect(await c.read(exportifyUploadProvider.notifier).pickAndUpload(), isNull);
      expect(c.read(exportifyUploadProvider).error, isNull);
      expect(seen.seen, isEmpty);
      sub.close();
    });

    test('a file over 8 MB is refused without being sent', () async {
      final (api, seen) = _api((o) => _json(201, _summary()));
      final c = container(api, () async => PickedCsv('big.csv', List.filled(exportifyMaxBytes + 1, 65)));
      addTearDown(c.dispose);
      final sub = c.listen(exportifyUploadProvider, (_, _) {});
      expect(await c.read(exportifyUploadProvider.notifier).pickAndUpload(), isNull);
      expect(c.read(exportifyUploadProvider).error, contains('8 MB'));
      expect(seen.seen, isEmpty);
      sub.close();
    });

    test('the server’s refusal is kept for the screen', () async {
      final (api, _) = _api((o) => _json(422, {'error': 'No songs found in this file.'}));
      final c = container(api, () async => PickedCsv('x.csv', utf8.encode('a')));
      addTearDown(c.dispose);
      final sub = c.listen(exportifyUploadProvider, (_, _) {});
      expect(await c.read(exportifyUploadProvider.notifier).pickAndUpload(), isNull);
      expect(c.read(exportifyUploadProvider).error, 'No songs found in this file.');
      sub.close();
    });
  });

  group('import screen: four states', () {
    testWidgets('loading shows a skeleton, not a spinner page', (tester) async {
      final (api, _) = _api((o) => _json(200, []));
      var release = false;
      await tester.pumpWidget(_app(const ExportifyImportScreen(), [
        exportifyImportsProvider.overrideWith((ref) async {
          while (!release) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          return <ExportifySummary>[];
        }),
        exportifyApiProvider.overrideWithValue(api),
      ]));
      await tester.pump();
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.text('Choose CSV File'), findsOneWidget);
      release = true;
      await tester.pumpAndSettle();
    });

    testWidgets('empty invites to choose a file', (tester) async {
      final (api, _) = _api((o) => _json(200, []));
      await tester.pumpWidget(_app(const ExportifyImportScreen(), [exportifyApiProvider.overrideWithValue(api)]));
      await tester.pumpAndSettle();
      expect(find.text('No imports yet'), findsOneWidget);
      expect(find.text('Choose CSV File'), findsOneWidget);
    });

    testWidgets('error says what failed and retries', (tester) async {
      var fail = true;
      final (api, _) = _api((o) => fail ? _json(503, {'error': 'The song fetcher is offline.'}) : _json(200, [_summary()]));
      await tester.pumpWidget(_app(const ExportifyImportScreen(), [exportifyApiProvider.overrideWithValue(api)]));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load your imports'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Tamil Mix'), findsOneWidget);
    });

    testWidgets('data lists each import with its two numbers', (tester) async {
      final (api, _) = _api((o) => _json(200, [_summary()]));
      await tester.pumpWidget(_app(const ExportifyImportScreen(), [exportifyApiProvider.overrideWithValue(api)]));
      await tester.pumpAndSettle();
      expect(find.text('Tamil Mix'), findsOneWidget);
      expect(find.text('1,118 in your library · 5,804 on your wishlist'), findsOneWidget);
    });

    testWidgets('while the file is read, one line says so and the button gives way', (tester) async {
      final (api, _) = _api((o) => _json(200, []));
      await tester.pumpWidget(_app(const ExportifyImportScreen(), [
        exportifyApiProvider.overrideWithValue(api),
        exportifyUploadProvider.overrideWith(_Busy.new),
      ]));
      await tester.pump(const Duration(milliseconds: 50));         // the activity indicator never settles
      expect(find.text('Matching “mix.csv”…'), findsOneWidget);
      expect(find.text('Choose CSV File'), findsNothing);
    });
  });

  group('result screen', () {
    testWidgets('the four numbers, the notes and one primary action', (tester) async {
      final (api, _) = _api((o) => _json(200, _summary()));
      await tester.pumpWidget(_app(
        ExportifyResultScreen(initial: ExportifySummary.fromJson(_summary())),
        [exportifyApiProvider.overrideWithValue(api)],
      ));
      await tester.pumpAndSettle();
      expect(find.text('6,922 songs'), findsOneWidget);
      expect(find.text('1,118'), findsOneWidget);
      expect(find.text('already in your library'), findsOneWidget);
      expect(find.text('5,804'), findsOneWidget);
      expect(find.text('about 210 GB'), findsOneWidget);
      expect(find.text('134 GB'), findsOneWidget);
      expect(find.text('Fetch My Wishlist'), findsOneWidget);
      expect(find.text('Make a Playlist'), findsOneWidget);
      expect(find.textContaining('bigger than the free space'), findsOneWidget);
    });

    testWidgets('nothing on the wishlist: no fetch button', (tester) async {
      final json = _summary(unique: 50, states: {'owned': 50});
      final (api, _) = _api((o) => _json(200, json));
      await tester.pumpWidget(_app(
        ExportifyResultScreen(initial: ExportifySummary.fromJson(json)),
        [exportifyApiProvider.overrideWithValue(api)],
      ));
      await tester.pumpAndSettle();
      expect(find.text('Everything on this list is already in your library.'), findsOneWidget);
      expect(find.text('Fetch My Wishlist'), findsNothing);
    });

    testWidgets('a lost connection keeps what is on screen', (tester) async {
      final (api, _) = _api((o) => _json(503, {'error': 'offline'}));
      await tester.pumpWidget(_app(
        ExportifyResultScreen(initial: ExportifySummary.fromJson(_summary())),
        [exportifyApiProvider.overrideWithValue(api)],
      ));
      await tester.pumpAndSettle();
      expect(find.text('6,922 songs'), findsOneWidget);
    });
  });

  group('fetch screen', () {
    Future<_Adapter> pump(WidgetTester tester, Map<String, dynamic> summary, {Map<String, dynamic>? failed}) async {
      ExportifyDetail.pollEvery = const Duration(hours: 1);
      _tall(tester);
      final (api, seen) = _api((o) {
        if (o.path.endsWith('/estimate')) return _json(200, _estimate());
        if (o.path.contains('/songs/failed')) return _json(200, failed ?? {'songs': []});
        return _json(200, summary);
      });
      await tester.pumpWidget(_app(const ExportifyFetchScreen(id: 7), [exportifyApiProvider.overrideWithValue(api)]));
      await tester.pumpAndSettle();
      return seen;
    }

    testWidgets('before it starts: the cost, the settings, and Start Fetching', (tester) async {
      await pump(tester, _summary());
      expect(find.text('Ready to fetch'), findsOneWidget);
      expect(
        find.text('These 5,804 songs need about 210 GB (0.51 GB per hour of music); you have 134 GB free.'),
        findsOneWidget,
      );
      expect(find.text('Most popular first'), findsOneWidget);
      expect(find.text('My list order'), findsOneWidget);
      expect(find.text('Only at night'), findsOneWidget);
      expect(find.text('Start Fetching'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
    });

    testWidgets('Start sends the settings; changing one asks for a new cost', (tester) async {
      final seen = await pump(tester, _summary());
      await tester.tap(find.text('40+'));
      await tester.pumpAndSettle();
      final est = seen.seen.where((o) => o.path.endsWith('/estimate')).toList();
      expect(est.last.data['min_popularity'], 40);
      await tester.tap(find.text('Start Fetching'));
      await tester.pumpAndSettle();
      final start = seen.seen.lastWhere((o) => o.path.endsWith('/start'));
      expect(start.data, containsPair('min_popularity', 40));
      expect(start.data, containsPair('per_night', 100));
      expect(start.data, containsPair('disk_floor_gb', 40));
    });

    testWidgets('running: progress, Pause as the one primary, Cancel behind a confirmation', (tester) async {
      final seen = await pump(
        tester,
        _summary(states: {'owned': 1118, 'downloaded': 200, 'queued': 25, 'wishlist': 5575, 'failed': 4}, status: 'active', note: 'Queued 25 songs.'),
        failed: {'songs': [{'title': 'Lost Song', 'artist': 'A;B', 'state': 'failed', 'popularity': 10, 'error': 'not found on the music bot'}]},
      );
      expect(find.text('Fetching'), findsOneWidget);
      expect(find.text('Queued 25 songs.'), findsOneWidget);
      expect(find.textContaining('200 of 5,804 fetched'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Start Fetching'), findsNothing);
      expect(find.text('Didn’t come in · 4'), findsOneWidget);
      expect(find.text('Lost Song'), findsOneWidget);
      expect(find.text('A, B · not found on the music bot'), findsOneWidget);
      await tester.tap(find.text('Try Them Again'));
      await tester.pumpAndSettle();
      expect(seen.seen.any((o) => o.path.endsWith('/retry-failed')), isTrue);
      await tester.tap(find.text('Cancel Fetch'));
      await tester.pumpAndSettle();
      expect(seen.seen.any((o) => o.path.endsWith('/cancel')), isFalse);        // asked first
      await tester.tap(find.text('Cancel Fetch').last);
      await tester.pumpAndSettle();
      expect(seen.seen.any((o) => o.path.endsWith('/cancel')), isTrue);
    });

    testWidgets('paused for the disk says so, in words, with the server’s numbers', (tester) async {
      await pump(tester, _summary(status: 'paused_disk', note: 'Paused: disk is low (31 GB free, floor 40 GB).'));
      expect(find.text('Paused: disk is low'), findsOneWidget);
      expect(find.text('Paused: disk is low (31 GB free, floor 40 GB).'), findsOneWidget);
      expect(_glyph(NaviGlyph.alert), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);          // still running on the server: it resumes by itself
    });

    testWidgets('paused by the user offers Resume', (tester) async {
      final seen = await pump(tester, _summary(status: 'paused'));
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(seen.seen.any((o) => o.path.endsWith('/start')), isTrue);
    });

    testWidgets('error and empty states', (tester) async {
      _tall(tester);
      final (api, _) = _api((o) => _json(503, {'error': 'offline'}));
      await tester.pumpWidget(_app(const ExportifyFetchScreen(id: 7), [exportifyApiProvider.overrideWithValue(api)]));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load your wishlist'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await pump(tester, _summary(unique: 10, states: {'owned': 10}));
      expect(find.text('Nothing to fetch'), findsOneWidget);
    });
  });
}

class _Busy extends ExportifyUploadController {
  @override
  ExportifyUploadState build() => const ExportifyUploadState(busyName: 'mix.csv');
}
