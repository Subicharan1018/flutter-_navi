import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/exportify_import/data/exportify_api.dart';
import 'package:navivibe/features/exportify_import/logic/exportify_providers.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/weekly_exploration/data/weekly_api.dart';
import 'package:navivibe/features/weekly_exploration/data/weekly_models.dart';
import 'package:navivibe/features/weekly_exploration/logic/preview_player.dart';
import 'package:navivibe/features/weekly_exploration/logic/weekly_providers.dart';
import 'package:navivibe/features/weekly_exploration/ui/weekly_exploration_screen.dart';
import 'package:navivibe/features/weekly_exploration/ui/weekly_exploration_section.dart';
import 'package:navivibe/features/weekly_exploration/ui/weekly_exploration_settings.dart';
import 'package:navivibe/player/artwork.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/ui/states.dart';

import '../../helpers/fake_http.dart';

// ─────────────────────────────────────────────────────────────────────────────
// A fake server
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _pick(int id, {String state = 'pending', String dl = 'none', String? songId, String? preview, String kind = 'near', String week = '2026-11-16'}) => {
      'id': id,
      'title': 'Song $id',
      'artist': 'Artist ${id % 4}',
      'album': 'Album',
      'year': 2025,
      'duration_s': 200.0,
      'cover_url': 'https://is1-ssl.mzstatic.com/$id/600x600bb.jpg',
      'preview_url': preview ?? 'https://audio-ssl.itunes.apple.com/$id.m4a',
      'reason': id.isEven ? 'Like Artist X' : 'More from Artist Y, one of your most played',
      'kind': kind,
      'state': state,
      'week': week,
      'expires_at': 1795000000.0 + id,
      'download': {'state': dl, 'song_id': songId},
    };

Map<String, dynamic> _page({List<Map<String, dynamic>>? picks, bool enabled = true, bool building = false, int cap = 10, int kept = 0, String? note}) => {
      'enabled': enabled,
      'cap': cap,
      'max_cap': 25,
      'week': '2026-11-16',
      'kept_this_week': kept,
      'building': building,
      'needs_build': false,
      'build_note': note,
      'download_note': null,
      'night': {'from': 1, 'to': 7},
      'picks': picks ?? [for (var i = 1; i <= 6; i++) _pick(i)],
    };

class _Server {
  Map<String, dynamic> page;
  final List<Map<String, dynamic>> calls = [];
  bool failActions = false;
  Map<String, dynamic> keepAnswer = {'state': 'kept', 'download': {'state': 'waiting', 'song_id': null}};
  _Server(this.page);

  ResponseBody handle(RequestOptions o) {
    calls.add({'method': o.method, 'path': o.path, 'data': o.data});
    if (failActions && (o.path.endsWith('/skip') || o.path.endsWith('/keep'))) {
      return jsonBody(409, {'error': 'this pick has expired'});
    }
    if (o.method == 'GET') return jsonBody(200, page);
    final id = int.tryParse(RegExp(r'/(\d+)/').firstMatch(o.path)?.group(1) ?? '');
    List<Map<String, dynamic>> picks() => [for (final p in page['picks'] as List) Map<String, dynamic>.from(p as Map)];
    if (o.path.endsWith('/keep')) {
      page = {...page, 'picks': [for (final p in picks()) p['id'] == id ? {...p, 'state': 'kept', 'download': keepAnswer['download']} : p]};
      return jsonBody(200, keepAnswer);
    }
    if (o.path.endsWith('/skip')) {
      page = {...page, 'picks': [for (final p in picks()) if (p['id'] != id) p]}; // a passed song is not listed again
      return jsonBody(200, {'state': 'skipped'});
    }
    if (o.path.endsWith('/restore')) return jsonBody(200, {'state': 'pending'});
    if (o.path.endsWith('/prefs')) {
      final d = o.data as Map;
      page = {...page, if (d.containsKey('enabled')) 'enabled': d['enabled'], if (d.containsKey('cap')) 'cap': d['cap']};
      return jsonBody(200, page);
    }
    return jsonBody(404, {'error': 'no'});
  }
}

class _FakeEngine implements PreviewEngine {
  final played = <String>[];
  var stops = 0;
  var failNext = false;
  final _pos = StreamController<Duration>.broadcast();
  final _done = StreamController<void>.broadcast();

  @override
  Stream<Duration> get position => _pos.stream;
  @override
  Stream<void> get completed => _done.stream;
  @override
  Future<void> play(String url) async {
    if (failNext) {
      failNext = false;
      throw StateError('no');
    }
    played.add(url);
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}

  void at(int seconds) => _pos.add(Duration(seconds: seconds));
  void end() => _done.add(null);
}

class _Rig {
  final _Server server;
  final _FakeEngine engine = _FakeEngine();
  var mainPaused = 0;
  var network = true;

  /// An account that may download (the default) or not.
  var canDownload = true;

  /// Replaces the fake server's api (a server that never answers, or answers an error).
  WeeklyApi? api;
  _Rig(this.server);

  List<Override> get overrides => [
        weeklyApiProvider.overrideWithValue(api ?? WeeklyApi(fakeDio(FakeAdapter(server.handle)))),
        previewEngineProvider.overrideWithValue(engine),
        previewPauseMainProvider.overrideWithValue(() async => mainPaused++),
        previewNetworkOkProvider.overrideWithValue(() async => network),
        onlineFetchEnabledProvider.overrideWith((ref) => canDownload),
      ];
}

ProviderContainer _container(_Rig rig) {
  final c = ProviderContainer(overrides: rig.overrides);
  c.listen(weeklyExplorationProvider, (_, _) {}); // an auto-dispose provider lives while the page watches it
  addTearDown(c.dispose);
  return c;
}

Widget _app(Widget home, _Rig rig, {List<Override> extra = const []}) => ProviderScope(
      key: UniqueKey(),
      overrides: [...rig.overrides, ...extra],
      child: ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(AppThemeTokens.fallback),
          home: Scaffold(body: home),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1800);
  addTearDown(tester.view.reset);
}

Future<void> _tick() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUp(() => debugCoverImageOverride = (url, key) => MemoryImage(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')));
  tearDown(() {
    debugCoverImageOverride = null;
    PlatformUtils.debugDesktopOverride = null;
  });

  // ── the data ───────────────────────────────────────────────────────────────

  group('models', () {
    test('a page is read, with far picks, downloads and expiry', () {
      final w = WeeklyExploration.fromJson(_page(picks: [
        _pick(1),
        _pick(2, state: 'kept', dl: 'ready', songId: 'nd9', kind: 'far'),
      ], cap: 5, kept: 2));
      expect(w.cap, 5);
      expect(w.keptThisWeek, 2);
      expect(w.nightFrom, 1);
      expect(w.pending.map((p) => p.id), [1]);
      expect(w.kept.single.far, isTrue);
      expect(w.kept.single.download, DownloadStage.ready);
      expect(w.kept.single.songId, 'nd9');
      expect(w.picks.first.expiresAt, isNotNull);
    });

    test('missing fields never throw', () {
      final w = WeeklyExploration.fromJson({'picks': [{'id': 3}]});
      expect(w.enabled, isTrue);
      expect(w.picks.single.title, '');
      expect(w.picks.single.download, DownloadStage.none);
    });
  });

  group('controller', () {
    test('loads the list', () async {
      final rig = _Rig(_Server(_page()));
      final c = _container(rig);
      final w = await c.read(weeklyExplorationProvider.future);
      expect(w.picks, hasLength(6));
      expect(rig.server.calls.single['path'], '/weekly/exploration');
    });

    test('Keep shows at once and takes the server’s answer', () async {
      final rig = _Rig(_Server(_page()));
      rig.server.keepAnswer = {'state': 'kept', 'download': {'state': 'queued', 'song_id': null}};
      final c = _container(rig);
      await c.read(weeklyExplorationProvider.future);
      final f = c.read(weeklyExplorationProvider.notifier).keep(2);
      expect(c.read(weeklyExplorationProvider).value!.picks[1].state, PickState.kept); // before the answer
      await f;
      final p = c.read(weeklyExplorationProvider).value!.picks[1];
      expect(p.state, PickState.kept);
      expect(p.download, DownloadStage.queued);
    });

    test('a refused Keep puts the song back and says why', () async {
      final rig = _Rig(_Server(_page()));
      final c = _container(rig);
      await c.read(weeklyExplorationProvider.future);
      rig.server.failActions = true;
      await expectLater(c.read(weeklyExplorationProvider.notifier).keep(2), throwsA(isA<OnlineFetchException>()));
      expect(c.read(weeklyExplorationProvider).value!.picks[1].state, PickState.pending);
    });

    test('Not for me and Undo', () async {
      final rig = _Rig(_Server(_page()));
      final c = _container(rig);
      await c.read(weeklyExplorationProvider.future);
      final n = c.read(weeklyExplorationProvider.notifier);
      await n.skip(3);
      expect(c.read(weeklyExplorationProvider).value!.picks[2].state, PickState.skipped);
      await n.restore(3);
      expect(c.read(weeklyExplorationProvider).value!.picks[2].state, PickState.pending);
      expect(rig.server.calls.map((e) => e['path']), containsAll(['/weekly/exploration/3/skip', '/weekly/exploration/3/restore']));
    });

    test('on/off and the weekly cap go to the server and come back', () async {
      final rig = _Rig(_Server(_page()));
      final c = _container(rig);
      await c.read(weeklyExplorationProvider.future);
      final n = c.read(weeklyExplorationProvider.notifier);
      await n.setCap(5);
      expect(c.read(weeklyExplorationProvider).value!.cap, 5);
      await n.setEnabled(false);
      expect(c.read(weeklyExplorationProvider).value!.enabled, isFalse);
      final puts = rig.server.calls.where((e) => e['method'] == 'PUT').map((e) => e['data']).toList();
      expect(puts.first, {'cap': 5});
      expect(puts[1], {'enabled': false});
    });
  });

  // ── previews ───────────────────────────────────────────────────────────────

  group('preview', () {
    test('plays the clip on its own player, stops the queue, and tracks the 30 s', () async {
      final rig = _Rig(_Server(_page()));
      final c = _container(rig);
      final w = await c.read(weeklyExplorationProvider.future);
      final pc = c.read(previewControllerProvider.notifier);
      await pc.toggle(w.picks[0]);
      expect(rig.engine.played, [w.picks[0].previewUrl]);
      expect(rig.mainPaused, 1);
      expect(c.read(previewControllerProvider).status, PreviewStatus.playing);
      rig.engine.at(15);
      await _tick();
      expect(c.read(previewProgressProvider), closeTo(0.5, 0.001));
      await pc.toggle(w.picks[0]); // the same song again: stop
      expect(c.read(previewControllerProvider).status, PreviewStatus.idle);
      expect(c.read(previewProgressProvider), 0);
    });

    test('Wi-Fi only: no clip on mobile data, and it says so', () async {
      final rig = _Rig(_Server(_page()))..network = false;
      final c = _container(rig);
      final w = await c.read(weeklyExplorationProvider.future);
      await c.read(previewControllerProvider.notifier).toggle(w.picks[0]);
      expect(rig.engine.played, isEmpty);
      expect(c.read(previewControllerProvider).error, contains('Wi-Fi'));
    });

    test('a song with no preview does nothing', () async {
      final page = _page(picks: [_pick(1)..['preview_url'] = null]);
      final rig = _Rig(_Server(page));
      final c = _container(rig);
      final w = await c.read(weeklyExplorationProvider.future);
      // the fake always fills a preview; clear it on the parsed pick
      await c.read(previewControllerProvider.notifier).toggle(WeeklyPick(id: w.picks[0].id, title: 't', artist: 'a'));
      expect(rig.engine.played, isEmpty);
    });

    test('a clip that will not start is an error message, not a crash', () async {
      final rig = _Rig(_Server(_page()));
      rig.engine.failNext = true;
      final c = _container(rig);
      final w = await c.read(weeklyExplorationProvider.future);
      await c.read(previewControllerProvider.notifier).toggle(w.picks[0]);
      expect(c.read(previewControllerProvider).error, isNotNull);
      expect(c.read(previewControllerProvider).status, PreviewStatus.idle);
    });

    test('Play previews walks the undecided list, and deciding a song moves on', () async {
      final rig = _Rig(_Server(_page()));
      final c = _container(rig);
      await c.read(weeklyExplorationProvider.future);
      final pc = c.read(previewControllerProvider.notifier);
      await pc.playAll();
      expect(c.read(previewControllerProvider).pickId, 1);
      rig.engine.end();
      await _tick();
      expect(c.read(previewControllerProvider).pickId, 2);
      await c.read(weeklyExplorationProvider.notifier).skip(2);
      await pc.decided(2); // Not for me on the one playing: the next starts
      expect(c.read(previewControllerProvider).pickId, 3);
      expect(c.read(previewControllerProvider).all, isTrue);
      for (final next in [4, 5, 6]) {
        rig.engine.end();
        await _tick();
        expect(c.read(previewControllerProvider).pickId, next);
      }
      rig.engine.end(); // the last one ends: nothing after it
      await _tick();
      expect(c.read(previewControllerProvider).status, PreviewStatus.idle);
    });
  });

  // ── the page: four states and the actions ──────────────────────────────────

  group('page', () {
    testWidgets('loading shows skeleton rows', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      final never = Completer<ResponseBody>();
      rig.api = WeeklyApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = _Slow(never.future));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TrackListSkeleton), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('error says what to do and retries', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      var fail = true;
      rig.api = WeeklyApi(fakeDio(FakeAdapter((o) => fail ? jsonBody(503, {'error': 'The song fetcher is offline.'}) : jsonBody(200, _page()))));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      expect(find.text('Your list didn’t load'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('Song 1'), findsOneWidget);
    });

    testWidgets('empty: building, nothing yet, and off', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page(picks: [], building: true)));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      expect(find.text('Finding songs for you'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      rig.server.page = _page(picks: [], note: 'Nothing new to suggest yet. Play a few more songs and check back.');
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      expect(find.text('Nothing new yet'), findsOneWidget);
      expect(find.textContaining('Play a few more songs'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      rig.server.page = _page(picks: [], enabled: false);
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      expect(find.text('Weekly Exploration is off'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await _settle(tester);
      expect(rig.server.calls.where((e) => e['method'] == 'PUT').last['data'], {'enabled': true});
    });

    testWidgets('while the list is being built the page asks again and fills in', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page(picks: [], building: true)));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      expect(find.text('Finding songs for you'), findsOneWidget);
      rig.server.page = _page();
      await tester.pump(kWeeklyBuildPoll + const Duration(seconds: 1));
      await _settle(tester);
      expect(find.text('Song 1'), findsOneWidget);
      expect(find.text('Finding songs for you'), findsNothing);
    });

    testWidgets('data: songs with why, a preview control, Keep and Not for me', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      expect(find.text('Week of 16 Nov'), findsOneWidget);
      expect(find.text('6 to hear'), findsOneWidget);
      expect(find.text('Song 1'), findsOneWidget);
      expect(find.text('Like Artist X'), findsWidgets);
      expect(find.bySemanticsLabel('Keep Song 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Not for me: Song 1'), findsOneWidget);
      expect(find.text('Play previews'), findsOneWidget);
    });

    testWidgets('Keep moves the song to Kept and says when it downloads', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      rig.server.keepAnswer = {'state': 'kept', 'download': {'state': 'queued', 'song_id': null}};
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Keep Song 2'));
      await _settle(tester);
      expect(find.text('Kept'), findsOneWidget);
      expect(find.text('Kept · downloads 1–7 am'), findsOneWidget);
      expect(find.textContaining('1 kept'), findsOneWidget);
      expect(find.bySemanticsLabel('Keep Song 2'), findsNothing);
    });

    testWidgets('Not for me offers Undo, and Undo brings the song back', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Not for me: Song 3'));
      await _settle(tester);
      expect(find.textContaining('1 passed'), findsOneWidget);
      expect(find.textContaining('won’t come back'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await _settle(tester);
      expect(find.textContaining('passed'), findsNothing);
      expect(find.bySemanticsLabel('Keep Song 3'), findsOneWidget);
    });

    testWidgets('a refused Keep says why and leaves the song alone', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      rig.server.failActions = true;
      await tester.tap(find.bySemanticsLabel('Keep Song 1'));
      await _settle(tester);
      expect(find.text('this pick has expired'), findsOneWidget);
      expect(find.bySemanticsLabel('Keep Song 1'), findsOneWidget);
    });

    testWidgets('a kept song that is in the library can be played; one without a preview says so', (tester) async {
      _phone(tester);
      final played = <String>[];
      final rig = _Rig(_Server(_page(picks: [
        _pick(1, state: 'kept', dl: 'ready', songId: 'nd7'),
        _pick(2, week: '2026-11-09')..['preview_url'] = null,
      ])));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig, extra: [
        weeklyLibraryPlayerProvider.overrideWithValue((id) async {
          played.add(id);
          return true;
        }),
      ]));
      await _settle(tester);
      expect(find.text('In your library'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Play Song 1'));
      await tester.pump();
      expect(played, ['nd7']);
      expect(find.text('Still here from last week'), findsOneWidget);
    });

    testWidgets('tapping a cover plays its preview and the ring appears', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Preview Song 1'));
      await _settle(tester);
      expect(rig.engine.played, ['https://audio-ssl.itunes.apple.com/1.m4a']);
      expect(find.bySemanticsLabel('Stop preview of Song 1'), findsOneWidget);
      expect(find.text('Stop previews'), findsOneWidget);
      expect(find.text('Play previews'), findsNothing);
      rig.engine.at(10);
      await tester.pump();
    });

    testWidgets('on Windows the buttons are words, and the page stays a readable width', (tester) async {
      PlatformUtils.debugDesktopOverride = true;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1366, 1800);
      addTearDown(tester.view.reset);
      final rig = _Rig(_Server(_page()));
      await tester.pumpWidget(_app(const WeeklyExplorationScreen(), rig));
      await _settle(tester);
      expect(find.text('Keep'), findsWidgets);
      expect(find.text('Not for me'), findsWidgets);
      final row = tester.getTopLeft(find.text('Song 1').first).dx;
      expect(row, greaterThan(300)); // centred in the window, not stuck to the left edge
      expect(tester.getTopRight(find.text('Keep').first).dx, lessThan(1366 / 2 + kWeeklyMaxWidth / 2 + 1));
    });
  });

  group('ledger', () {
    test('repaints only when the week changes', () {
      const a = LedgerPainter(marks: [LedgerMark.waiting, LedgerMark.kept], playing: -1, ink: Colors.white, dim: Colors.grey);
      const same = LedgerPainter(marks: [LedgerMark.waiting, LedgerMark.kept], playing: -1, ink: Colors.white, dim: Colors.grey);
      const kept = LedgerPainter(marks: [LedgerMark.kept, LedgerMark.kept], playing: -1, ink: Colors.white, dim: Colors.grey);
      const moved = LedgerPainter(marks: [LedgerMark.waiting, LedgerMark.kept], playing: 0, ink: Colors.white, dim: Colors.grey);
      expect(same.shouldRepaint(a), isFalse);
      expect(kept.shouldRepaint(a), isTrue);
      expect(moved.shouldRepaint(a), isTrue);
    });

    test('the ring only repaints when the clock moves', () {
      const r = RingPainter(0.2, Colors.white);
      expect(const RingPainter(0.2, Colors.white).shouldRepaint(r), isFalse);
      expect(const RingPainter(0.3, Colors.white).shouldRepaint(r), isTrue);
    });
  });

  // ── Home and Settings ──────────────────────────────────────────────────────

  group('home shelf', () {
    testWidgets('shows what is still to decide', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page(picks: [_pick(1), _pick(2, state: 'kept', dl: 'queued'), _pick(3)])));
      await tester.pumpWidget(_app(const SingleChildScrollView(child: WeeklyExplorationSection()), rig));
      await _settle(tester);
      expect(find.text('Weekly Exploration'), findsOneWidget);
      expect(find.text('Song 1'), findsOneWidget);
      expect(find.text('Song 3'), findsOneWidget);
      expect(find.text('Song 2'), findsNothing); // kept: decided
    });

    testWidgets('is hidden without download access, when off, and when there is nothing to hear', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      rig.canDownload = false;
      await tester.pumpWidget(_app(const WeeklyExplorationSection(), rig));
      await _settle(tester);
      expect(find.text('Weekly Exploration'), findsNothing);
      expect(rig.server.calls, isEmpty); // and it never even asked
      await tester.pumpWidget(const SizedBox());

      rig.canDownload = true;
      rig.server.page = _page(enabled: false);
      await tester.pumpWidget(_app(const WeeklyExplorationSection(), rig));
      await _settle(tester);
      expect(find.text('Weekly Exploration'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      rig.server.page = _page(picks: [], building: true);
      await tester.pumpWidget(_app(const WeeklyExplorationSection(), rig));
      await _settle(tester);
      expect(find.text('Weekly Exploration'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('settings', () {
    testWidgets('on/off, downloads a week, Wi-Fi only', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page(cap: 10)));
      await tester.pumpWidget(_app(const SingleChildScrollView(child: WeeklyExplorationSettings()), rig));
      await _settle(tester);
      expect(find.text('Weekly Exploration'), findsWidgets);
      expect(find.text('10 songs'), findsOneWidget);
      expect(find.text('Wi-Fi Only Previews'), findsOneWidget);
      await tester.tap(find.text('Downloads a Week'));
      await _settle(tester);
      await tester.tap(find.text('5 songs'));
      await _settle(tester);
      expect(rig.server.calls.where((e) => e['method'] == 'PUT').single['data'], {'cap': 5});
      expect(find.text('5 songs'), findsOneWidget);
    });

    testWidgets('hidden for an account that cannot download', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      rig.canDownload = false;
      await tester.pumpWidget(_app(const WeeklyExplorationSettings(), rig));
      await _settle(tester);
      expect(find.text('Wi-Fi Only Previews'), findsNothing);
    });
  });

  test('the Exportify list does not show the Weekly Exploration import', () async {
    Map<String, dynamic> imp(int id, String name) => {
          'id': id, 'name': name, 'rows': 10, 'unique': 10, 'duplicates': 0, 'skipped_rows': 0, 'no_isrc': 0,
          'maybe_owned': 0, 'playlist_id': null, 'states': {'owned': 1, 'wishlist': 9}, 'owned': 1, 'wishlist': 9,
          'wishlist_gb': 1.0, 'free_gb': 100.0,
          'plan': {'status': 'idle', 'priority': 'popularity', 'min_popularity': 0, 'per_night': 100, 'disk_floor_gb': 40.0, 'night_only': true},
        };
    final adapter = FakeAdapter((o) => jsonBody(200, [imp(1, 'Tamil Mix'), imp(2, kWeeklyExplorationImportName)]));
    final c = ProviderContainer(overrides: [exportifyApiProvider.overrideWithValue(ExportifyApi(fakeDio(adapter)))]);
    addTearDown(c.dispose);
    final list = await c.read(exportifyImportsProvider.future);
    expect(list.map((s) => s.name), ['Tamil Mix']);
  });
}

/// A server that never answers: the page stays loading.
class _Slow implements HttpClientAdapter {
  final Future<ResponseBody> answer;
  _Slow(this.answer);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) => answer;
  @override
  void close({bool force = false}) {}
}
