import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/discover/logic/discover_providers.dart' show mergeDiscover;
import 'package:navivibe/features/flow/logic/flow_session.dart';
import 'package:navivibe/features/flow/ui/flow_section.dart' show FlowBlendStrip;
import 'package:navivibe/features/listen/data/listen_api.dart';
import 'package:navivibe/features/listen/data/listen_models.dart';
import 'package:navivibe/features/month/logic/month_providers.dart';
import 'package:navivibe/features/month/ui/month_screen.dart';
import 'package:navivibe/features/taste/logic/taste_providers.dart';
import 'package:navivibe/features/taste/ui/taste_screen.dart';
import 'package:navivibe/features/weekly_mix/logic/weekly_mix_providers.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

import '../../helpers/test_utils.dart';

class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> seen = [];
  final ResponseBody Function(RequestOptions o) handler;
  _FakeAdapter(this.handler);

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

(ListenApi, _FakeAdapter) _api(ResponseBody Function(RequestOptions o) handler) {
  final adapter = _FakeAdapter(handler);
  return (ListenApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = adapter), adapter);
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

const _pick = {'navidrome_id': 's1', 'title': 'Aathi', 'artist': 'Anirudh', 'why': 'You play a lot of Anirudh'};

void main() {
  group('models', () {
    test('a weekly mix keeps playable picks and its week', () {
      final mix = WeeklyMix.fromJson({
        'week_of': '2026-10-19',
        'next_refresh': '2026-10-26T06:00:00+05:30',
        'items': [_pick, {'title': 'No id'}, 'junk'],
      });
      expect(mix.items.map((p) => p.songId), ['s1']);
      expect(mix.items.single.why, 'You play a lot of Anirudh');
      expect(mix.weekOf, DateTime(2026, 10, 19));
      expect(weekLabel(mix.weekOf), '19 Oct');
      expect(weeklyMixPlaylistName(mix), 'Weekly Mix · 19 Oct');
      expect(weeklyMixPlaylistName(const WeeklyMix(items: [])), 'Weekly Mix');
    });

    test('a flow batch knows which picks are fresh', () {
      final b = FlowBatch.fromJson({
        'items': [{..._pick, 'kind': 'fresh'}, {..._pick, 'navidrome_id': 's2', 'kind': 'familiar'}],
        'fresh_share': 0.4,
        'mood': 'calm',
      });
      expect(b.items.map((p) => p.fresh), [true, false]);
      expect(b.freshShare, 0.4);
      expect(b.mood, 'calm');
    });

    test('mood chips read capitalised', () {
      final moods = parseFlowMoods({'moods': [{'mood': 'calm', 'songs': 9}, {'mood': '', 'songs': 1}]});
      expect(moods.single.label, 'Calm');
    });

    test('exclusions skip kinds this version does not know', () {
      final list = TasteExclusion.parseAll({
        'exclusions': [
          {'kind': 'song', 'value': 's1', 'label': 'Aathi', 'added_at': 1760000000},
          {'kind': 'album', 'value': 'x', 'label': 'x'},
          {'kind': 'artist', 'value': 'Anirudh'},
        ],
      });
      expect(list.map((e) => e.kind), [TasteKind.song, TasteKind.artist]);
      expect(list.last.label, 'Anirudh');
      expect(list.first.addedAt, isNotNull);
    });

    test('a month parses its lists and months', () {
      final m = MonthStats.fromJson({
        'year': 2026, 'month': 10, 'month_name': 'October', 'total_plays': 5, 'total_minutes': 130,
        'previous_minutes': 100, 'active_days': 3, 'days_in_month': 31, 'streak_days': 2, 'unique_songs': 4,
        'daily_minutes': [1, 2, 0], 'new_songs_count': 1,
        'top_songs': [{'id': 'a', 'title': 'A', 'artist': 'X', 'plays': 3, 'minutes': 12}, {'title': 'no id'}],
        'top_artists': [{'name': 'X', 'plays': 3, 'minutes': 12, 'art_id': 'a'}],
        'top_composers': [{'name': 'Y', 'plays': 2, 'minutes': 8, 'art_id': ''}],
        'new_songs': [{'id': 'b', 'title': 'B', 'artist': 'Z', 'plays': 1}],
        'months': [{'year': 2026, 'month': 10}, {'year': 2026, 'month': 9}],
      });
      expect(m.topSongs.single.songId, 'a');
      expect(m.topArtists.single.artId, 'a');
      expect(m.topComposers.single.artId, isNull);
      expect(m.months, [const MonthKey(2026, 10), const MonthKey(2026, 9)]);
      expect(m.isEmpty, isFalse);
      expect(MonthStats.fromJson(const {}).isEmpty, isTrue);
    });

    test('minutes read as hours and compare with last month', () {
      expect(minutesLabel(45), '45m');
      expect(minutesLabel(120), '2h');
      expect(minutesLabel(130), '2h 10m');
      expect(minutesChange(130, 100), '+30m on last month');
      expect(minutesChange(100, 220), '−2h on last month');
      expect(minutesChange(100, 100), 'Same as last month');
      expect(minutesChange(100, 0), isNull);
    });
  });

  group('api', () {
    test('flow sends count, mood, seen and feedback as JSON', () async {
      final (api, adapter) = _api((o) => _json(200, {'items': [_pick], 'fresh_share': 0.5}));
      final batch = await api.flowNext(
        count: 6,
        mood: 'calm',
        seen: ['a', 'b'],
        feedback: const [FlowFeedback('a', FlowAction.skip)],
      );
      expect(batch.items.single.songId, 's1');
      final req = adapter.seen.single;
      expect(req.path, '/flow/next');
      expect(req.data, {
        'count': 6,
        'mood': 'calm',
        'seen': ['a', 'b'],
        'feedback': [{'id': 'a', 'action': 'skip'}],
      });
    });

    test('flow leaves the mood out when there is none', () async {
      final (api, adapter) = _api((o) => _json(200, {'items': []}));
      await api.flowNext();
      expect((adapter.seen.single.data as Map).containsKey('mood'), isFalse);
    });

    test('exclusions add and remove, returning the list', () async {
      final (api, adapter) = _api((o) => _json(200, {
            'exclusions': [{'kind': 'song', 'value': 's1', 'label': 'Aathi', 'added_at': 1}],
          }));
      final added = await api.addExclusion(TasteKind.song, 's1', label: 'Aathi');
      expect(added.single.label, 'Aathi');
      expect(adapter.seen.last.data, {'kind': 'song', 'value': 's1', 'label': 'Aathi'});
      await api.removeExclusion(TasteKind.artist, 'Anirudh');
      expect(adapter.seen.last.method, 'DELETE');
      expect(adapter.seen.last.queryParameters, {'kind': 'artist', 'value': 'Anirudh'});
    });

    test('a month asks for the picked month only', () async {
      final (api, adapter) = _api((o) => _json(200, {'year': 2026, 'month': 9}));
      await api.month(const MonthKey(2026, 9));
      expect(adapter.seen.last.queryParameters, {'year': 2026, 'month': 9});
      await api.month();
      expect(adapter.seen.last.queryParameters, isEmpty);
    });

    test('failures become sentences', () async {
      for (final (status, text) in [(401, 'Sign in again'), (503, 'starting up'), (500, 'couldn’t answer')]) {
        final (api, _) = _api((o) => _json(status, {'error': 'x'}));
        await expectLater(
          api.weeklyMix(),
          throwsA(isA<ListenException>().having((e) => e.message, 'message', contains(text))),
        );
      }
    });
  });

  group('flow session', () {
    test('a song left early is a skip, finished is a play, in between is nothing', () {
      final s = FlowSession()..served(['a', 'b', 'c']);
      s.left('a', heard: const Duration(seconds: 10), durationSec: 200);
      s.left('b', heard: const Duration(seconds: 190), durationSec: 200);
      s.left('c', heard: const Duration(seconds: 100), durationSec: 200);
      expect(s.feedback, [const FlowFeedback('a', FlowAction.skip), const FlowFeedback('b', FlowAction.play)]);
    });

    test('only songs Flow served count, and each reaction once', () {
      final s = FlowSession()..served(['a']);
      s.left('zzz', heard: Duration.zero, durationSec: 100);
      s.left('a', heard: Duration.zero, durationSec: 100);
      s.left('a', heard: Duration.zero, durationSec: 100);
      s.left('a', heard: Duration.zero, durationSec: 0);
      expect(s.feedback.length, 1);
    });

    test('newly starred served songs are likes', () {
      final s = FlowSession()..served(['a', 'b']);
      s.starredChanged({'x'}, {'x', 'a', 'other'});
      expect(s.feedback, [const FlowFeedback('a', FlowAction.like)]);
    });

    test('asks for more only when the queue is low, nothing is in flight and it has not given up', () {
      final s = FlowSession();
      final now = DateTime(2026, 10, 24, 12);
      expect(s.wantsMore(9, now: now), isFalse);
      expect(s.wantsMore(FlowSession.refillAt, now: now), isTrue);
      s.fetching = true;
      expect(s.wantsMore(0, now: now), isFalse);
      s.fetching = false;
      s.failed(now: now);
      expect(s.wantsMore(0, now: now.add(const Duration(seconds: 5))), isFalse);
      expect(s.wantsMore(0, now: now.add(const Duration(seconds: 21))), isTrue);
      s.succeeded();
      expect(s.failures, 0);
      for (var i = 0; i < FlowSession.maxFailures; i++) {
        s.failed(now: now);
      }
      expect(s.exhausted, isTrue);
      expect(s.wantsMore(0, now: now.add(const Duration(hours: 1))), isFalse);
    });

    test('seen and feedback are capped, oldest dropped', () {
      final s = FlowSession();
      s.served([for (var i = 0; i < FlowSession.maxSeen + 10; i++) 's$i']);
      expect(s.seen.length, FlowSession.maxSeen);
      expect(s.wasServed('s0'), isFalse);
      expect(s.wasServed('s${FlowSession.maxSeen + 9}'), isTrue);
      for (var i = 0; i < FlowSession.maxFeedback + 5; i++) {
        s.left('s${FlowSession.maxSeen + 9 - (i % 400)}', heard: Duration.zero, durationSec: 100);
      }
      expect(s.feedback.length <= FlowSession.maxFeedback, isTrue);
    });
  });

  group('language exploration', () {
    test('a pick knows it is a try in a new language', () {
      final p = ListenPick.parse({..._pick, 'kind': 'explore', 'explore': true, 'language': 'ml'})!;
      expect(p.explore, isTrue);
      expect(p.languageName, 'Malayalam');
      expect(ListenPick.parse(_pick)!.explore, isFalse);
      expect(ListenPick.parse({..._pick, 'language': 'xx'})!.languageName, 'XX');
    });

    test('a batch reports its blend', () {
      final b = FlowBatch.fromJson({
        'items': [_pick],
        'blend': {'familiar': 4, 'fresh': 3, 'explore': 1},
      });
      expect(b.blend, const FlowBlend(familiar: 4, fresh: 3, explore: 1));
      expect(b.blend.total, 8);
      expect(FlowBatch.fromJson(const {}).blend.total, 0);
    });

    test('every Flow run has its own session id, sent with each request', () async {
      expect(FlowSession().id, isNot(FlowSession().id));
      expect(FlowSession(id: 'abc').id, 'abc');
      final (api, adapter) = _api((o) => _json(200, {'items': []}));
      await api.flowNext(session: 'abc');
      expect((adapter.seen.single.data as Map)['session'], 'abc');
      await api.flowNext();
      expect((adapter.seen.last.data as Map).containsKey('session'), isFalse);
    });

    test('Discover marks the songs offered as a new language', () {
      final items = mergeDiscover(const [], [
        (id: 'a', title: 'A', artist: 'x'),
        (id: 'b', title: 'B', artist: 'y'),
      ], newLanguage: {'b'});
      expect(items.map((i) => i.reason), ['Never played', 'New language']);
    });

    testWidgets('the blend strip names the three parts and skips empty ones', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: const Scaffold(body: FlowBlendStrip(blend: FlowBlend(familiar: 4, fresh: 3, explore: 1))),
        ),
      ));
      expect(find.text('Familiar 4'), findsOneWidget);
      expect(find.text('Fresh 3'), findsOneWidget);
      expect(find.text('New language 1'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(
        home: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: const Scaffold(body: FlowBlendStrip(blend: FlowBlend(familiar: 4, fresh: 4))),
        ),
      ));
      expect(find.textContaining('New language'), findsNothing);
    });
  });

  group('never recommend', () {
    test('offers the song, the first artist and the first composer', () {
      final opts = neverOptionsFor(makeSong(id: 's1', title: 'Aathi', artist: 'Anirudh, Dhanush', composer: 'Anirudh Ravichander'));
      expect(opts.map((o) => (o.kind, o.value)), [
        (TasteKind.song, 's1'),
        (TasteKind.artist, 'Anirudh'),
        (TasteKind.composer, 'Anirudh Ravichander'),
      ]);
    });

    test('a composer equal to the artist is offered once; none when empty', () {
      final same = neverOptionsFor(makeSong(artist: 'Sid Sriram', composer: 'sid sriram'));
      expect(same.map((o) => o.kind), [TasteKind.song, TasteKind.artist]);
      final bare = neverOptionsFor(makeSong(artist: '', composer: ''));
      expect(bare.map((o) => o.kind), [TasteKind.song]);
    });
  });

  group('screens', () {
    Widget host(Widget child, List<Override> overrides) => ProviderScope(
          overrides: [subsonicServiceProvider.overrideWithValue(_FakeSubsonic()), ...overrides],
          child: MaterialApp(home: ThemeTokens(tokens: AppThemeTokens.fallback, child: child)),
        );

    testWidgets('the taste page lists exclusions by kind', (tester) async {
      await tester.pumpWidget(host(const TasteScreen(), [
        tasteExclusionsProvider.overrideWith(_FixedTaste.new),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Composers'), findsNothing);
      expect(find.text('Aathi'), findsOneWidget);
      expect(find.text('Undo'), findsNWidgets(2));
    });

    testWidgets('the taste page invites when nothing is blocked', (tester) async {
      await tester.pumpWidget(host(const TasteScreen(), [
        tasteExclusionsProvider.overrideWith(_EmptyTaste.new),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Nothing is blocked'), findsOneWidget);
    });

    testWidgets('the month page shows minutes, streak and top lists', (tester) async {
      final stats = MonthStats.fromJson({
        'year': 2026, 'month': 10, 'month_name': 'October', 'total_plays': 5, 'total_minutes': 130,
        'previous_minutes': 100, 'active_days': 3, 'days_in_month': 31, 'streak_days': 2, 'unique_songs': 4,
        'daily_minutes': [1, 2, 0], 'new_songs_count': 1,
        'top_songs': [{'id': 'a', 'title': 'Alpha', 'artist': 'X', 'plays': 3, 'minutes': 12}],
        'top_artists': [{'name': 'Xavier', 'plays': 3, 'minutes': 12, 'art_id': 'a'}],
        'top_composers': [],
        'new_songs': [{'id': 'b', 'title': 'Beta', 'artist': 'Z', 'plays': 1}],
        'months': [],
      });
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        SingleChildScrollView(child: MonthBody(stats: stats)),
        const [],
      ));
      expect(find.text('2h 10m'), findsOneWidget);
      expect(find.textContaining('+30m on last month'), findsOneWidget);
      expect(find.text('day streak'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Xavier'), findsOneWidget);
      expect(find.text('Top Composers'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    });
  });
}

class _FixedTaste extends TasteExclusions {
  @override
  Future<List<TasteExclusion>> build() async => const [
        TasteExclusion(kind: TasteKind.song, value: 's1', label: 'Aathi'),
        TasteExclusion(kind: TasteKind.artist, value: 'Anirudh', label: 'Anirudh'),
      ];
}

class _EmptyTaste extends TasteExclusions {
  @override
  Future<List<TasteExclusion>> build() async => const [];
}
