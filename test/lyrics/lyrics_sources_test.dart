// The lyrics waterfall with the proxy's sources, word timing, and the chip.
// Lyrics here are made-up words, never a real song's text.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/lyrics/controllers/lyrics_sources_provider.dart';
import 'package:navivibe/lyrics/models/lyric_line.dart';
import 'package:navivibe/lyrics/models/lyrics_result.dart';
import 'package:navivibe/lyrics/services/lrclib_service.dart';
import 'package:navivibe/lyrics/services/lyrics_repository.dart';
import 'package:navivibe/lyrics/services/lyrics_server_api.dart';
import 'package:navivibe/player/lyric_word_sweep.dart';
import 'package:navivibe/player/lyrics_source_chip.dart';
import 'package:navivibe/player/now_playing_style.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_http.dart';
import '../helpers/test_utils.dart' show makeSong;

class _Svc extends Fake implements SubsonicService {
  final Map<String, dynamic>? entry;
  _Svc([this.entry]);
  @override
  Future<Map<String, dynamic>?> getLyricsBySongId(String songId) async => entry;
}

const _enhanced = '[00:12.50]<00:12.50>alpha <00:13.00>beta <00:14.00>gamma\n[00:16.00]<00:16.00>delta <00:17.00>epsilon';

/// An LRCLIB that has nothing.
LrcLibService get _noLrclib => LrcLibService(client: MockClient((_) async => http.Response('', 404)));

LyricsServerApi _server(FakeAdapter a) => LyricsServerApi(fakeDio(a));

FakeAdapter _answering(Map<String, dynamic> body, {int status = 200}) =>
    FakeAdapter((_) => jsonBody(status, body));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('enhanced LRC from the proxy parses to word-timed lines and is credited', () async {
    final adapter = _answering({'source': 'lrcred', 'sync': 'word', 'lrc': _enhanced});
    final repo = LyricsRepository(
      subsonic: _Svc(),
      lrcLib: _noLrclib,
      server: _server(adapter),
      sources: () => [LyricsSource.lrcRed, LyricsSource.betterLyrics],
    );
    final r = await repo.getLyrics(makeSong(id: 'a1'));
    expect(r.type, LyricsType.synced);
    expect(r.source, 'lrcred');
    expect(r.wordSynced, isTrue);
    final first = r.lyrics!.lines.first;
    expect(first.text, 'alpha beta gamma');
    expect(first.words!.map((w) => w.text), ['alpha', 'beta', 'gamma']);
    expect(first.words![1].timestamp, const Duration(seconds: 13));
    final q = adapter.requests.single.queryParameters;
    expect(q['sources'], 'lrcred,betterlyrics');
    expect(q['title'], 'Test Song');
  });

  test('a second ask comes from the cache with its source, with no request', () async {
    final adapter = _answering({'source': 'betterlyrics', 'sync': 'word', 'lrc': _enhanced});
    final repo = LyricsRepository(
      subsonic: _Svc(),
      lrcLib: _noLrclib,
      server: _server(adapter),
      sources: () => [LyricsSource.betterLyrics],
    );
    await repo.getLyrics(makeSong(id: 'a2'));
    final again = await repo.getLyrics(makeSong(id: 'a2'));
    expect(again.source, 'betterlyrics');
    expect(again.wordSynced, isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test('with no source switched on the proxy is never asked; LRCLIB still answers', () async {
    final adapter = _answering({'source': 'lrcred', 'sync': 'word', 'lrc': _enhanced});
    final lrclib = LrcLibService(
      client: MockClient((_) async => http.Response(jsonEncode({'syncedLyrics': '[00:01.00]one two'}), 200)),
    );
    final repo = LyricsRepository(subsonic: _Svc(), lrcLib: lrclib, server: _server(adapter), sources: () => []);
    final r = await repo.getLyrics(makeSong(id: 'a3'));
    expect(adapter.requests, isEmpty);
    expect((r.type, r.source, r.wordSynced), (LyricsType.synced, 'lrclib', false));
  });

  test('a proxy that is down falls through to LRCLIB instead of failing', () async {
    final lrclib = LrcLibService(
      client: MockClient((_) async => http.Response(jsonEncode({'syncedLyrics': '[00:01.00]one two'}), 200)),
    );
    final repo = LyricsRepository(
      subsonic: _Svc(),
      lrcLib: lrclib,
      server: _server(_answering({'error': 'boom'}, status: 500)),
      sources: () => [LyricsSource.lrcRed],
    );
    expect((await repo.getLyrics(makeSong(id: 'a4'))).source, 'lrclib');
  });

  test('the file’s own synced tags win over every online source', () async {
    final adapter = _answering({'source': 'lrcred', 'sync': 'word', 'lrc': _enhanced});
    final repo = LyricsRepository(
      subsonic: _Svc({
        'synced': true,
        'line': [
          {'start': 1000, 'value': 'tagged line'},
        ],
      }),
      lrcLib: _noLrclib,
      server: _server(adapter),
      sources: () => [LyricsSource.lrcRed],
    );
    final r = await repo.getLyrics(makeSong(id: 'a5'));
    expect(r.source, 'server');
    expect(adapter.requests, isEmpty);
  });

  test('plain tags on the server don’t block a synced online version', () async {
    final repo = LyricsRepository(
      subsonic: _Svc({
        'synced': false,
        'line': [
          {'value': 'plain line one'},
          {'value': 'plain line two'},
        ],
      }),
      lrcLib: _noLrclib,
      server: _server(_answering({'source': 'lrcred', 'sync': 'line', 'lrc': '[00:01.00]synced line'})),
      sources: () => [LyricsSource.lrcRed],
    );
    final r = await repo.getLyrics(makeSong(id: 'a6'));
    expect((r.type, r.source), (LyricsType.synced, 'lrcred'));
  });

  test('plain tags are still used when nothing synced exists anywhere', () async {
    final repo = LyricsRepository(
      subsonic: _Svc({
        'synced': false,
        'line': [
          {'value': 'plain line one'},
        ],
      }),
      lrcLib: _noLrclib,
      server: _server(_answering({'error': 'none'}, status: 404)),
      sources: () => [LyricsSource.lrcRed],
    );
    final r = await repo.getLyrics(makeSong(id: 'a7'));
    expect((r.type, r.source), (LyricsType.plain, 'server'));
  });

  group('wordProgress', () {
    const words = [
      WordSegment(timestamp: Duration(milliseconds: 1000), text: 'a'),
      WordSegment(timestamp: Duration(milliseconds: 1500), text: 'b'),
      WordSegment(timestamp: Duration(milliseconds: 9000), text: 'c'),
    ];
    const end = Duration(milliseconds: 20000);

    test('fills across the word and clamps', () {
      expect(wordProgress(words, 0, end, 900), 0);
      expect(wordProgress(words, 0, end, 1250), closeTo(0.5, 1e-9));
      expect(wordProgress(words, 0, end, 5000), 1);
    });

    test('a word before a long gap, and the last word, never glow longer than 1.4 s', () {
      expect(wordProgress(words, 1, end, 1500 + 700), closeTo(0.5, 1e-9));
      expect(wordProgress(words, 2, end, 9000 + 1400), 1);
    });
  });

  group('word sweep widget', () {
    testWidgets('colours words as the position passes them and repaints only itself', (tester) async {
      var pos = 12400;
      const line = LyricLine(
        timestamp: Duration(milliseconds: 12500),
        text: 'alpha beta gamma',
        words: [
          WordSegment(timestamp: Duration(milliseconds: 12500), text: 'alpha'),
          WordSegment(timestamp: Duration(milliseconds: 13000), text: 'beta'),
          WordSegment(timestamp: Duration(milliseconds: 14000), text: 'gamma'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LyricWordSweep(
            line: line,
            endsAt: const Duration(seconds: 16),
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 20),
            positionMs: () => pos,
          ),
        ),
      );
      List<double> alphas() {
        // Text wraps the span it is given in its own, so go one level down.
        final outer = tester.widget<RichText>(find.byType(RichText).first).text as TextSpan;
        final mine = outer.children!.single as TextSpan;
        return [for (final c in mine.children!) (c as TextSpan).style!.color!.a];
      }

      final before = alphas();
      expect(before, hasLength(3));
      expect(before.every((a) => (a - 0.42).abs() < 0.01), isTrue, reason: '$before'); // nothing sung yet

      pos = 14500;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final after = alphas();
      expect(after[0], closeTo(1, 0.01));
      expect(after[1], closeTo(1, 0.01));
      expect(after[2], greaterThan(0.42));
    });
  });

  test('source labels', () {
    expect(lyricsSourceLabel('lrcred'), 'lrc.red');
    expect(lyricsSourceLabel('betterlyrics'), 'BetterLyrics');
    expect(lyricsSourceLabel('lrclib'), 'LRCLIB');
    expect(lyricsSourceLabel('server'), 'Your server');
    expect(lyricsSourceLabel(null), isNull);
  });

  test('only lrc.red and BetterLyrics are on by default; the Spotify wrapper is off', () {
    expect([for (final s in LyricsSource.values) if (s.defaultOn) s.wire], ['lrcred', 'betterlyrics']);
  });

  testWidgets('the chip names the source and the timing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LyricsSourceChip(style: NowPlayingStyle.onArtwork, label: 'lrc.red', kind: 'WORD'),
      ),
    );
    expect(find.text('lrc.red'), findsOneWidget);
    expect(find.text('WORD'), findsOneWidget);
  });
}
