import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/lyrics/controllers/lyrics_controller.dart';
import 'package:navivibe/lyrics/controllers/lyrics_search_provider.dart';
import 'package:navivibe/lyrics/controllers/lyrics_translation_controller.dart';
import 'package:navivibe/lyrics/models/lyric_line.dart';
import 'package:navivibe/lyrics/models/lyric_translation.dart';
import 'package:navivibe/lyrics/services/lyrics_server_api.dart';
import 'package:navivibe/player/lyrics_pane.dart';
import 'package:navivibe/player/now_playing_style.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/screens/search_screen.dart';

import '../helpers/fake_http.dart';
import '../helpers/test_utils.dart' show makeSong;

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

PlayerState _playing(String songId) => PlayerState(
      queue: [makeSong(id: songId)],
      currentIndex: 0,
      isPlaying: true,
      shuffleMode: false,
      autoplayMode: false,
      repeatMode: LoopMode.off,
      starredIds: const [],
      syncMode: SyncMode.activeHere,
    );

const _texts = ['Kannana kanne', '', 'Malare mounama'];

class _FakeLyrics extends LyricsController {
  @override
  LyricsState build() => LyricsState(
        status: LyricsStatus.synced,
        lyrics: SyncedLyrics(lines: [
          for (final (i, t) in _texts.indexed) LyricLine(timestamp: Duration(seconds: i * 5), text: t),
        ]),
      );
}

Map<String, dynamic> _translated() => {
      'language': 'Tamil',
      'lines': [
        {'translation': 'My darling', 'pronunciation': 'Kannana kanne'},
        {'translation': '', 'pronunciation': ''},
        {'translation': 'Flower, silence?', 'pronunciation': 'Malare mounamaa'},
      ],
    };

ProviderContainer _container(FakeAdapter adapter) {
  final c = ProviderContainer(overrides: [
    playerProvider.overrideWith((ref) => _FakePlayer(_playing('s1'))),
    lyricsControllerProvider.overrideWith(_FakeLyrics.new),
    lyricsServerApiProvider.overrideWithValue(LyricsServerApi(fakeDio(adapter))),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// Lets Dio's fake round trip finish (it takes a few event-loop turns).
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

/// Same, for widget tests: the request starts in fake time, so alternate
/// real waiting with frames until it has come back.
Future<void> _settleWidgets(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(_settle);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('models', () {
    test('translation is padded or cut to the number of lines sent', () {
      final short = LyricsTranslation.fromJson({
        'lines': [
          {'translation': 'a', 'pronunciation': 'x'},
        ],
      }, expectedLines: 3);
      expect(short.lines.length, 3);
      expect(short[0].translation, 'a');
      expect(short[2], same(LineTranslation.empty));

      final long = LyricsTranslation.fromJson({
        'lines': [
          for (var i = 0; i < 5; i++) {'translation': '$i'},
        ],
      }, expectedLines: 2);
      expect(long.lines.length, 2);
      expect(long[5], same(LineTranslation.empty));
    });

    test('lyric match reads the optional start time', () {
      final m = LyricMatch.fromJson({'song_id': '1', 'title': 'T', 'artist': 'A', 'line': 'l', 'start_ms': 12500});
      expect(m.start, const Duration(milliseconds: 12500));
      expect(LyricMatch.fromJson({'song_id': '1', 'line': 'l'}).start, isNull);
    });
  });

  group('api', () {
    test('translate posts the lines in order and parses the aligned answer', () async {
      final adapter = FakeAdapter((_) => jsonBody(200, _translated()));
      final r = await LyricsServerApi(fakeDio(adapter))
          .translate(songId: 's1', title: 'T', artist: 'A', lines: _texts);
      final sent = adapter.requests.single;
      expect(sent.path, '/lyrics/translate');
      expect((sent.data as Map)['lines'], _texts);
      expect((sent.data as Map)['target'], 'en');
      expect(r.language, 'Tamil');
      expect(r[2].pronunciation, 'Malare mounamaa');
    });

    test('server wording is shown for limits, offline gets its own line', () async {
      final limited = LyricsServerApi(fakeDio(FakeAdapter((_) => jsonBody(429, {'error': 'slow down'}))));
      await expectLater(
        limited.searchLyrics('abc'),
        throwsA(isA<LyricsServerException>().having((e) => e.message, 'message', 'slow down')),
      );
      final offline = LyricsServerApi(Dio(BaseOptions(baseUrl: 'https://x.test'))
        ..httpClientAdapter = FakeAdapter((o) => throw DioException(requestOptions: o)));
      await expectLater(
        offline.searchLyrics('abc'),
        throwsA(isA<LyricsServerException>().having((e) => e.statusCode, 'code', isNull)),
      );
    });

    test('search parses results and skips junk', () async {
      final api = LyricsServerApi(fakeDio(FakeAdapter((_) => jsonBody(200, {
            'results': [
              {'song_id': '9', 'title': 'Song', 'artist': 'Art', 'line': 'hello there', 'start_ms': 1000},
              'junk',
            ],
          }))));
      final r = await api.searchLyrics('hello');
      expect(r.single.songId, '9');
      expect(r.single.line, 'hello there');
    });
  });

  group('translation controller', () {
    test('asks nothing until a toggle is on, then once per song', () async {
      final adapter = FakeAdapter((_) => jsonBody(200, _translated()));
      final c = _container(adapter);
      final sub = c.listen(lyricsTranslationProvider, (_, _) {});
      addTearDown(sub.close);
      await _settle();
      expect(adapter.requests, isEmpty);

      c.read(lyricsTranslationProvider.notifier).setTranslation(true);
      await _settle();
      expect(adapter.requests.length, 1);
      expect(c.read(lyricsTranslationProvider).data![0].translation, 'My darling');

      // The second toggle reuses the answer: no second request.
      c.read(lyricsTranslationProvider.notifier).setPronunciation(true);
      await _settle();
      expect(adapter.requests.length, 1);
      expect(c.read(lyricsTranslationProvider).data![2].pronunciation, 'Malare mounamaa');

      // Off and on again keeps it too.
      c.read(lyricsTranslationProvider.notifier)
        ..setTranslation(false)
        ..setPronunciation(false)
        ..setTranslation(true);
      await _settle();
      expect(adapter.requests.length, 1);
    });

    test('a failure is shown and retry asks again', () async {
      var fail = true;
      final adapter = FakeAdapter((_) => fail ? jsonBody(500, {'error': 'model busy'}) : jsonBody(200, _translated()));
      final c = _container(adapter);
      final sub = c.listen(lyricsTranslationProvider, (_, _) {});
      addTearDown(sub.close);
      await _settle();

      c.read(lyricsTranslationProvider.notifier).setTranslation(true);
      await _settle();
      expect(c.read(lyricsTranslationProvider).error, 'model busy');
      expect(c.read(lyricsTranslationProvider).loading, isFalse);

      fail = false;
      c.read(lyricsTranslationProvider.notifier).retry();
      await _settle();
      expect(c.read(lyricsTranslationProvider).error, isNull);
      expect(c.read(lyricsTranslationProvider).data, isNotNull);
    });
  });

  group('lyrics search provider', () {
    test('short queries and failures give an empty list', () async {
      final adapter = FakeAdapter((_) => jsonBody(500, {'error': 'x'}));
      final c = ProviderContainer(overrides: [
        lyricsServerApiProvider.overrideWithValue(LyricsServerApi(fakeDio(adapter))),
      ]);
      addTearDown(c.dispose);
      expect(await c.read(lyricsSearchProvider('ab').future), isEmpty);
      expect(adapter.requests, isEmpty, reason: 'too short to ask the server');
      expect(await c.read(lyricsSearchProvider('abcd').future), isEmpty);
      expect(adapter.requests.length, 1);
    });
  });

  group('lyric match row', () {
    test('bolds each searched word, ignoring case', () {
      const plain = TextStyle(fontWeight: FontWeight.w400);
      const bold = TextStyle(fontWeight: FontWeight.w700);
      final spans = LyricMatchRow.highlight('Hello there, World', 'world HELLO', plain, bold);
      expect([for (final s in spans) s.text], ['Hello', ' there, ', 'World']);
      expect([for (final s in spans) s.style == bold], [true, false, true]);
    });

    test('regex characters in the query are literal', () {
      const plain = TextStyle();
      const bold = TextStyle(fontWeight: FontWeight.bold);
      final spans = LyricMatchRow.highlight('what? (really)', '(really)', plain, bold);
      expect(spans.last.text, '(really)');
    });
  });

  group('lyrics pane', () {
    Widget app(ProviderContainer c) => UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            home: Scaffold(body: LyricsPane(style: NowPlayingStyle.onArtwork)),
          ),
        );

    testWidgets('shows translation and pronunciation under each line when switched on', (tester) async {
      final c = _container(FakeAdapter((_) => jsonBody(200, _translated())));
      await tester.pumpWidget(app(c));
      await tester.pump();
      expect(find.text('Kannana kanne'), findsOneWidget);
      expect(find.text('My darling'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('translate-pill')));
      await _settleWidgets(tester);
      expect(find.text('My darling'), findsOneWidget);
      expect(find.text('Flower, silence?'), findsOneWidget);
      expect(find.text('Malare mounamaa'), findsNothing, reason: 'pronunciation is its own switch');

      await tester.tap(find.byKey(const ValueKey('pronounce-pill')));
      await tester.pump();
      expect(find.text('Malare mounamaa'), findsOneWidget);
      // The original lines stay, in order.
      expect(find.text('Malare mounama'), findsOneWidget);
    });

    testWidgets('a failed translation says so and offers to retry', (tester) async {
      final c = _container(FakeAdapter((_) => jsonBody(500, {'error': 'model busy'})));
      await tester.pumpWidget(app(c));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('translate-pill')));
      await _settleWidgets(tester);
      expect(find.byKey(const ValueKey('translate-retry')), findsOneWidget);
      expect(find.textContaining('model busy'), findsOneWidget);
    });
  });
}
