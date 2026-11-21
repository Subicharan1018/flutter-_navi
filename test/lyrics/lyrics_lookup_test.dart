// Lyrics lookup v3: only a clean "not found" is remembered, the lookup revision
// retires old misses, the miss TTL, plain text re-checked, and "Search again".
// Lyrics here are made-up words, never a real song's text.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/lyrics/controllers/lyrics_controller.dart';
import 'package:navivibe/lyrics/controllers/lyrics_sources_provider.dart';
import 'package:navivibe/lyrics/models/lyrics_result.dart';
import 'package:navivibe/lyrics/services/lrc_parser.dart';
import 'package:navivibe/lyrics/services/lrclib_service.dart';
import 'package:navivibe/lyrics/services/lyrics_repository.dart';
import 'package:navivibe/lyrics/services/lyrics_server_api.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/lyrics_pane.dart';
import 'package:navivibe/player/now_playing_style.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/flow/flow_section_test.dart' show IdlePlayer;
import '../helpers/fake_http.dart';
import '../helpers/test_utils.dart' show makeSong;

class _Svc extends Fake implements SubsonicService {
  @override
  Future<Map<String, dynamic>?> getLyricsBySongId(String songId) async => null;
}

const _synced = '[00:01.00]one two\n[00:05.00]three four';

LrcLibService _lrclib(int status, {Object? body}) => LrcLibService(
  client: MockClient((_) async => http.Response(body == null ? '' : jsonEncode(body), status)),
);

LrcLibService get _lrclibHasNothing => _lrclib(404);

LrcLibService get _lrclibBroken => LrcLibService(
  client: MockClient((_) async => throw http.ClientException('no network')),
);

class _Clock {
  DateTime now = DateTime(2026, 11, 21, 12);
  DateTime call() => now;
}

FakeAdapter _proxy(int status, Map<String, dynamic> body) => FakeAdapter((_) => jsonBody(status, body));

LyricsRepository _repo(
  FakeAdapter adapter, {
  LrcLibService? lrclib,
  _Clock? clock,
  List<LyricsSource> sources = const [LyricsSource.lrcRed],
}) => LyricsRepository(
  subsonic: _Svc(),
  lrcLib: lrclib ?? _lrclibHasNothing,
  server: LyricsServerApi(fakeDio(adapter)),
  sources: () => sources,
  now: clock?.call,
);

Future<void> _seed(String id, Map<String, dynamic> entry) async {
  SharedPreferences.setMockInitialValues({'lyrics_v2_$id': jsonEncode(entry)});
}

Future<Map<String, dynamic>?> _stored(String id) async {
  final raw = (await SharedPreferences.getInstance()).getString('lyrics_v2_$id');
  return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('three outcomes: found / not found / could not find out', () {
    test('found: synced lyrics come back and are kept', () async {
      final adapter = _proxy(200, {'source': 'lrcred', 'sync': 'line', 'lrc': _synced});
      final repo = _repo(adapter);
      final r = await repo.getLyrics(makeSong(id: 'f1'));
      expect((r.type, r.source, r.unreachable), (LyricsType.synced, 'lrcred', false));
      expect((await _stored('f1'))!['type'], 'synced');
    });

    test('not found: every source says no -> "no lyrics", remembered, and not asked again', () async {
      final adapter = _proxy(404, {'error': 'No lyrics found for this song.'});
      final repo = _repo(adapter);
      final r = await repo.getLyrics(makeSong(id: 'n1'));
      expect((r.type, r.unreachable), (LyricsType.none, false));
      expect((await _stored('n1'))!['rev'], kLookupRev);
      await repo.getLyrics(makeSong(id: 'n1'));
      expect(adapter.requests, hasLength(1)); // the second open came from the cache
    });

    test('a 200 without text is also a clean "none"', () async {
      final repo = _repo(_proxy(200, {'source': 'lrcred', 'sync': 'line', 'lrc': ''}));
      final r = await repo.getLyrics(makeSong(id: 'n2'));
      expect((r.type, r.unreachable), (LyricsType.none, false));
    });

    for (final c in <(String, int)>[('a 500', 500), ('a 429', 429), ('a 401', 401), ('a 503', 503)]) {
      test('${c.$1} from the proxy is "could not find out": not cached, asked again next time', () async {
        final adapter = _proxy(c.$2, {'error': 'x'});
        final repo = _repo(adapter);
        final r = await repo.getLyrics(makeSong(id: 'x${c.$2}'));
        expect((r.type, r.unreachable), (LyricsType.none, true));
        expect(await _stored('x${c.$2}'), isNull);
        await repo.getLyrics(makeSong(id: 'x${c.$2}'));
        expect(adapter.requests, hasLength(2));
      });
    }

    test('a 404 that says retry (a source did not answer) is a failure, not "nobody has it"', () async {
      final adapter = _proxy(404, {'error': 'The lyrics sources did not answer.', 'retry': true});
      final r = await _repo(adapter).getLyrics(makeSong(id: 'r1'));
      expect(r.unreachable, isTrue);
      expect(await _stored('r1'), isNull);
    });

    test('LRCLIB timing out or returning 5xx also stops "none" from being remembered', () async {
      final proxyNo = _proxy(404, {'error': 'none'});
      final a = await _repo(proxyNo, lrclib: _lrclibBroken).getLyrics(makeSong(id: 'l1'));
      expect(a.unreachable, isTrue);
      final b = await _repo(proxyNo, lrclib: _lrclib(503)).getLyrics(makeSong(id: 'l2'));
      expect(b.unreachable, isTrue);
      expect(await _stored('l1'), isNull);
      expect(await _stored('l2'), isNull);
    });

    test('a proxy that failed but LRCLIB has plain text -> the plain text is shown (and re-checked later)', () async {
      final repo = _repo(_proxy(500, {'error': 'x'}), lrclib: _lrclib(200, body: {'plainLyrics': 'one two\nthree four'}));
      final r = await repo.getLyrics(makeSong(id: 'p0'));
      expect((r.type, r.source), (LyricsType.plain, 'lrclib'));
    });

    test('nothing to ask (no source on, no server) is a clean none', () async {
      final repo = LyricsRepository(subsonic: _Svc(), lrcLib: _lrclibHasNothing);
      final r = await repo.getLyrics(makeSong(id: 'e1'));
      expect((r.type, r.unreachable), (LyricsType.none, false));
    });
  });

  group('the lookup revision and the miss TTL', () {
    final at = DateTime(2026, 11, 21, 12).millisecondsSinceEpoch;

    test('a miss from before revisions existed (this song on v165) is asked about again, once', () async {
      // The exact shape the old build wrote: no "rev".
      await _seed('life', {'type': 'none', 'rawText': '', 'at': at});
      final adapter = _proxy(200, {'source': 'lrcred', 'sync': 'line', 'lrc': _synced});
      final clock = _Clock();
      final repo = _repo(adapter, clock: clock);
      final r = await repo.getLyrics(makeSong(id: 'life'));
      expect((r.type, r.source), (LyricsType.synced, 'lrcred'));
      expect(adapter.requests, hasLength(1));
      // Now it is a hit and is never asked about again.
      await repo.getLyrics(makeSong(id: 'life'));
      expect(adapter.requests, hasLength(1));
    });

    test('a miss from an older revision than this build is ignored', () async {
      await _seed('old', {'type': 'none', 'rawText': '', 'at': at, 'rev': kLookupRev - 1});
      final adapter = _proxy(404, {'error': 'none'});
      await _repo(adapter, clock: _Clock()).getLyrics(makeSong(id: 'old'));
      expect(adapter.requests, hasLength(1));
    });

    test('a miss of this revision is believed for under two hours, then asked about again', () async {
      await _seed('ttl', {'type': 'none', 'rawText': '', 'at': at, 'rev': kLookupRev});
      final adapter = _proxy(404, {'error': 'none'});
      final clock = _Clock();
      final repo = _repo(adapter, clock: clock);

      clock.now = DateTime(2026, 11, 21, 13, 59); // 1 h 59 min later
      await repo.getLyrics(makeSong(id: 'ttl'));
      expect(adapter.requests, isEmpty);

      clock.now = DateTime(2026, 11, 21, 14, 1); // 2 h 1 min later
      await repo.getLyrics(makeSong(id: 'ttl'));
      expect(adapter.requests, hasLength(1));
    });

    test('found lyrics are kept across revisions (hits are never retired)', () async {
      await _seed('hit', {'type': 'synced', 'rawText': _synced, 'source': 'lrcred', 'at': 1});
      final adapter = _proxy(500, {'error': 'x'});
      final r = await _repo(adapter, clock: _Clock()).getLyrics(makeSong(id: 'hit'));
      expect((r.type, r.source), (LyricsType.synced, 'lrcred'));
      expect(adapter.requests, isEmpty);
    });
  });

  group('plain text must not hide synced lyrics', () {
    final plainAt = DateTime(2026, 11, 21, 12);

    Future<void> seedPlain(String id, DateTime at) => _seed(id, {
      'type': 'plain',
      'rawText': 'one two\nthree four',
      'source': 'lrclib',
      'at': at.millisecondsSinceEpoch,
      'rev': kLookupRev,
    });

    test('plain text younger than 15 minutes is shown without asking', () async {
      await seedPlain('pl1', plainAt);
      final adapter = _proxy(200, {'source': 'lrcred', 'sync': 'line', 'lrc': _synced});
      final clock = _Clock()..now = plainAt.add(const Duration(minutes: 10));
      final r = await _repo(adapter, clock: clock).getLyrics(makeSong(id: 'pl1'));
      expect(r.type, LyricsType.plain);
      expect(adapter.requests, isEmpty);
    });

    test('older plain text asks the proxy once; synced lyrics replace it', () async {
      await seedPlain('pl2', plainAt);
      final adapter = _proxy(200, {'source': 'lrcred', 'sync': 'line', 'lrc': _synced});
      final clock = _Clock()..now = plainAt.add(const Duration(minutes: 20));
      final repo = _repo(adapter, clock: clock);
      final r = await repo.getLyrics(makeSong(id: 'pl2'));
      expect((r.type, r.source), (LyricsType.synced, 'lrcred'));
      expect(adapter.requests, hasLength(1));
      expect((await _stored('pl2'))!['type'], 'synced');
    });

    test('when the re-check finds nothing the plain text stays, and it is not asked again this session', () async {
      await seedPlain('pl3', plainAt);
      final adapter = _proxy(404, {'error': 'none'});
      final clock = _Clock()..now = plainAt.add(const Duration(hours: 3));
      final repo = _repo(adapter, clock: clock);
      expect((await repo.getLyrics(makeSong(id: 'pl3'))).type, LyricsType.plain);
      expect((await repo.getLyrics(makeSong(id: 'pl3'))).type, LyricsType.plain);
      expect(adapter.requests, hasLength(1));
      // A new session (a new repository) may look again.
      await _repo(adapter, clock: clock).getLyrics(makeSong(id: 'pl3'));
      expect(adapter.requests, hasLength(2));
    });

    test('a failed re-check keeps the plain text too', () async {
      await seedPlain('pl4', plainAt);
      final clock = _Clock()..now = plainAt.add(const Duration(hours: 1));
      final r = await _repo(_proxy(500, {'error': 'x'}), clock: clock).getLyrics(makeSong(id: 'pl4'));
      expect(r.type, LyricsType.plain);
    });
  });

  group('Search again (refresh)', () {
    final at = DateTime(2026, 11, 21, 12).millisecondsSinceEpoch;

    test('skips a fresh remembered miss and tells the server to ask its sources again', () async {
      await _seed('s1', {'type': 'none', 'rawText': '', 'at': at, 'rev': kLookupRev});
      final adapter = _proxy(200, {'source': 'lrcred', 'sync': 'line', 'lrc': _synced});
      final repo = _repo(adapter, clock: _Clock());
      expect((await repo.getLyrics(makeSong(id: 's1'))).type, LyricsType.none); // believed
      expect(adapter.requests, isEmpty);
      final r = await repo.getLyrics(makeSong(id: 's1'), refresh: true);
      expect(r.type, LyricsType.synced);
      expect(adapter.requests.single.queryParameters['refresh'], 1);
    });

    test('a normal lookup never sends refresh', () async {
      final adapter = _proxy(404, {'error': 'none'});
      await _repo(adapter).getLyrics(makeSong(id: 's2'));
      expect(adapter.requests.single.queryParameters.containsKey('refresh'), isFalse);
    });

    test('never throws away found lyrics', () async {
      await _seed('s3', {'type': 'synced', 'rawText': _synced, 'source': 'lrcred', 'at': at, 'rev': kLookupRev});
      final adapter = _proxy(404, {'error': 'none'});
      final r = await _repo(adapter, clock: _Clock()).getLyrics(makeSong(id: 's3'), refresh: true);
      expect(r.type, LyricsType.synced);
      expect(adapter.requests, isEmpty);
    });

    test('a refresh that finds the server down reports unreachable, not "no lyrics"', () async {
      await _seed('s4', {'type': 'none', 'rawText': '', 'at': at, 'rev': kLookupRev});
      final r = await _repo(_proxy(500, {'error': 'x'}), clock: _Clock()).getLyrics(makeSong(id: 's4'), refresh: true);
      expect(r.unreachable, isTrue);
    });
  });

  test('LyricsResult.none() and unreachable() differ only by the flag', () {
    expect(LyricsResult.none().unreachable, isFalse);
    expect(LyricsResult.unreachable().unreachable, isTrue);
    expect(LyricsResult.unreachable().type, LyricsType.none);
    expect(LrcParser.isLrcFormat(_synced), isTrue);
  });

  // ── the controller and the pane ──────────────────────────────────────────

  group('controller and pane', () {
    final song = makeSong(id: 'c1');

    Future<ProviderContainer> start(WidgetTester tester, _FakeRepo repo) async {
      final c = ProviderContainer(
        overrides: [
          playerProvider.overrideWith((ref) => _PlayingPlayer(song)),
          lyricsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      c.listen(lyricsControllerProvider, (_, _) {});
      await tester.pump();
      await tester.pump();
      return c;
    }

    testWidgets('an unreachable lookup is the error state, never the empty "no lyrics" state', (tester) async {
      final repo = _FakeRepo([LyricsResult.unreachable()]);
      final c = await start(tester, repo);
      final s = c.read(lyricsControllerProvider);
      expect(s.status, LyricsStatus.error);
      expect(s.errorMessage, kLyricsUnreachableMessage);
    });

    testWidgets('Search again asks with refresh, then cools down for 20 s', (tester) async {
      final repo = _FakeRepo([LyricsResult.none(), LyricsResult.none(), LyricsResult.none()]);
      final c = await start(tester, repo);
      expect(c.read(lyricsControllerProvider).status, LyricsStatus.empty);
      expect(c.read(lyricsControllerProvider).cooling, isFalse);

      await c.read(lyricsControllerProvider.notifier).searchAgain();
      expect(repo.refreshes, [false, true]);
      expect(c.read(lyricsControllerProvider).cooling, isTrue);

      await c.read(lyricsControllerProvider.notifier).searchAgain(); // hammering: ignored
      expect(repo.refreshes, [false, true]);

      await tester.pump(kSearchAgainCooldown + const Duration(seconds: 1));
      expect(c.read(lyricsControllerProvider).cooling, isFalse);
      await c.read(lyricsControllerProvider.notifier).searchAgain();
      expect(repo.refreshes, [false, true, true]);
      await tester.pump(kSearchAgainCooldown + const Duration(seconds: 1)); // let the last cooldown end
    });

    testWidgets('Search again that finds lyrics shows them', (tester) async {
      final found = LyricsResult(
        type: LyricsType.plain,
        lyrics: LrcParser.parsePlain('one two\nthree four'),
        rawText: 'one two\nthree four',
        source: 'ytmusic',
      );
      final repo = _FakeRepo([LyricsResult.none(), found]);
      final c = await start(tester, repo);
      await c.read(lyricsControllerProvider.notifier).searchAgain();
      expect(c.read(lyricsControllerProvider).status, LyricsStatus.plain);
    });

    testWidgets('the empty state offers Search again; it is disabled while cooling down', (tester) async {
      var searched = 0;
      Future<void> show(LyricsState s) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [lyricsControllerProvider.overrideWith(() => _FakeLyrics(s, () => searched++))],
            child: const MaterialApp(
              home: Scaffold(body: LyricsPane(style: NowPlayingStyle.onArtwork)),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
      }

      await show(const LyricsState(status: LyricsStatus.empty));
      expect(find.text('No lyrics for this song'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-again')));
      expect(searched, 1);

      await show(const LyricsState(status: LyricsStatus.empty, cooling: true));
      expect(find.text('Searched just now'), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('search-again'))).onPressed, isNull);
    });

    testWidgets('the error state says it could not reach the sources and offers Try again', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lyricsControllerProvider.overrideWith(
              () => _FakeLyrics(
                const LyricsState(status: LyricsStatus.error, errorMessage: kLyricsUnreachableMessage),
                () {},
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: LyricsPane(style: NowPlayingStyle.onArtwork)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('reach the lyrics sources'), findsOneWidget);
      expect(find.byKey(const ValueKey('lyrics-retry')), findsOneWidget);
      expect(find.text('No lyrics for this song'), findsNothing);
    });

    testWidgets('an answer for a song that is no longer playing is dropped', (tester) async {
      final pending = _PendingRepo();
      final c = ProviderContainer(
        overrides: [
          playerProvider.overrideWith((ref) => _PlayingPlayer(song)),
          lyricsRepositoryProvider.overrideWithValue(pending),
        ],
      );
      addTearDown(c.dispose);
      c.listen(lyricsControllerProvider, (_, _) {});
      await tester.pump();
      await tester.pump();
      expect(pending.calls, hasLength(1)); // the first song is still being asked about

      // Another song starts; then the FIRST song's answer arrives late.
      (c.read(playerProvider.notifier) as _PlayingPlayer).switchTo(makeSong(id: 'other'));
      await tester.pump();
      expect(pending.calls, hasLength(2));
      pending.calls[0].complete(
        LyricsResult(type: LyricsType.plain, lyrics: LrcParser.parsePlain('old song'), rawText: 'old song'),
      );
      await tester.pump();
      expect(c.read(lyricsControllerProvider).status, LyricsStatus.loading); // not the old song's lyrics

      pending.calls[1].complete(LyricsResult.none());
      await tester.pump();
      expect(c.read(lyricsControllerProvider).status, LyricsStatus.empty);
    });
  });
}

class _PendingRepo extends Fake implements LyricsRepository {
  final calls = <Completer<LyricsResult>>[];

  @override
  Future<LyricsResult> getLyrics(Song song, {bool refresh = false}) {
    final c = Completer<LyricsResult>();
    calls.add(c);
    return c.future;
  }
}

class _PlayingPlayer extends IdlePlayer {
  _PlayingPlayer(Song song) {
    state = state.copyWith(queue: [song], currentIndex: 0);
  }

  void switchTo(Song s) => state = state.copyWith(queue: [s], currentIndex: 0);
}

class _FakeRepo extends Fake implements LyricsRepository {
  final List<LyricsResult> script;
  final refreshes = <bool>[];
  int _i = 0;

  _FakeRepo(this.script);

  @override
  Future<LyricsResult> getLyrics(Song song, {bool refresh = false}) async {
    refreshes.add(refresh);
    final r = script[_i < script.length ? _i : script.length - 1];
    _i++;
    return r;
  }
}

class _FakeLyrics extends LyricsController {
  final LyricsState initial;
  final void Function() onSearchAgain;
  _FakeLyrics(this.initial, this.onSearchAgain);

  @override
  LyricsState build() => initial;

  @override
  Future<void> searchAgain() async => onSearchAgain();
}
