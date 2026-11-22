import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/listen/data/listen_api.dart' show ListenException;
import 'package:navivibe/features/listen/data/listen_models.dart';
import 'package:navivibe/features/rotation/data/rotation_api.dart';
import 'package:navivibe/features/rotation/data/rotation_models.dart';
import 'package:navivibe/features/rotation/logic/rotation_providers.dart';
import 'package:navivibe/features/rotation/ui/back_in_rotation_section.dart';
import 'package:navivibe/features/rotation/ui/rest_actions.dart';
import 'package:navivibe/features/rotation/ui/rotation_taste_section.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/shuffle_bag.dart';
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

(RotationApi, _FakeAdapter) _api(ResponseBody Function(RequestOptions o) handler) {
  final adapter = _FakeAdapter(handler);
  return (RotationApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = adapter), adapter);
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _MemoryStore implements ShuffleBagStore {
  String? json;
  @override
  String? read() => json;
  @override
  void write(String value) => json = value;
}

final _snapshot = <String, dynamic>{
  'resting': [
    {'song_id': 'a', 'title': 'Alpha', 'artist': 'X', 'until': 1798761600, 'since': 1797552000, 'auto': true},
    {'song_id': '', 'title': 'No id', 'until': 5},
    'junk',
  ],
  'seasonal': [
    {'song_id': 'c', 'title': 'Christmas Eve', 'artist': 'Z', 'season': 'christmas', 'label': 'Christmas', 'in_season': false, 'manual': true},
    {'song_id': 'd', 'title': 'Diwali Dhamaka', 'artist': 'Z', 'season': 'deepavali', 'label': 'Deepavali', 'in_season': true, 'manual': false},
  ],
  'seasons': [
    {'key': 'christmas', 'label': 'Christmas', 'in_season': false, 'from': '1 Dec', 'to': '2 Jan'},
    {'label': 'no key'},
  ],
  'prefs': {'auto_rest': true, 'seasons': false},
};

class _FixedRotation extends RotationNotifier {
  final Rotation value;
  final List<String> calls = [];
  _FixedRotation(this.value);

  @override
  Future<Rotation> build() async => value;

  @override
  Future<void> unrest(String songId) async => calls.add('unrest $songId');

  @override
  Future<void> setSeason(String songId, String? season) async => calls.add('season $songId $season');

  @override
  Future<void> savePrefs({bool? autoRest, bool? seasons, bool? back}) async => calls.add('prefs $autoRest $seasons $back');
}

void main() {
  group('models', () {
    final r = Rotation.fromJson(_snapshot);

    test('a snapshot keeps usable rows, the seasons the server names and the settings', () {
      expect(r.resting.map((s) => s.songId), ['a']);
      expect(r.resting.single.auto, isTrue);
      expect(r.seasonal.map((s) => (s.songId, s.manual, s.inSeason)), [('c', true, false), ('d', false, true)]);
      expect(r.seasons.map((s) => s.key), ['christmas']);
      expect(r.prefs, const RotationPrefs(autoRest: true, seasons: false, back: true));
    });

    test('lookups by song', () {
      expect(r.isResting('a'), isTrue);
      expect(r.isResting('b'), isFalse);
      expect(r.seasonOf('d')?.label, 'Deepavali');
      expect(r.seasonOf('a'), isNull);
    });

    test('an empty or odd answer is an empty rotation with everything on', () {
      final e = Rotation.fromJson(const {});
      expect(e.resting, isEmpty);
      expect(e.prefs, const RotationPrefs());
      expect(RotationPrefs.fromJson('nope'), const RotationPrefs());
    });

    test('rest lengths and the date a song is back', () {
      expect(RestLength.values.map((l) => (l.label, l.days)), [('2 weeks', 14), ('1 month', 30), ('3 months', 90)]);
      expect(backOnLabel(DateTime(2026, 12, 12)), 'back on 12 Dec');
    });
  });

  group('api', () {
    test('rest sends the song, the days and the title', () async {
      final (api, net) = _api((_) => _json(200, {'ok': true}));
      await api.rest('s1', 30, label: 'Aathi');
      final o = net.seen.single;
      expect((o.method, o.path), ('POST', '/rotation/rest'));
      expect(o.data, {'song_id': 's1', 'days': 30, 'label': 'Aathi'});
    });

    test('bring back, tags and settings', () async {
      final (api, net) = _api((o) => _json(200, o.path == '/rotation/prefs' ? {'prefs': {'seasons': false}} : {}));
      await api.unrest('s1');
      await api.setSeason('s1', null);
      await api.setSeason('s2', 'none');
      final prefs = await api.savePrefs(seasons: false);
      expect(net.seen.map((o) => (o.method, o.path)), [
        ('DELETE', '/rotation/rest'), ('PUT', '/rotation/season'), ('PUT', '/rotation/season'), ('PUT', '/rotation/prefs'),
      ]);
      expect(net.seen[0].data, {'song_id': 's1'});
      expect(net.seen[1].data, {'song_id': 's1', 'season': null});
      expect(net.seen[2].data, {'song_id': 's2', 'season': 'none'});
      expect(net.seen[3].data, {'seasons': false});
      expect(prefs.seasons, isFalse);
    });

    test('back in rotation reads the picks', () async {
      final (api, net) = _api((_) => _json(200, {
            'items': [{'navidrome_id': 'b1', 'title': 'Old', 'artist': 'Y', 'why': 'You played it 5 times, last in Dec 2025'}, {'title': 'no id'}],
          }));
      final picks = await api.back(limit: 8);
      expect(net.seen.single.queryParameters, {'limit': 8});
      expect(picks.map((p) => p.songId), ['b1']);
      expect(picks.single.why, contains('5 times'));
    });

    test('failures say what happened', () async {
      for (final (code, text) in [(401, 'Sign in again'), (503, 'still starting'), (500, 'couldn’t answer')]) {
        final (api, _) = _api((_) => _json(code, {}));
        await expectLater(api.rotation(), throwsA(isA<ListenException>().having((e) => e.message, 'message', contains(text))));
      }
    });
  });

  group('back in rotation in a queue', () {
    final picks = [for (var i = 0; i < 18; i++) makeSong(id: 'p$i', title: 'P$i')];
    final back = [for (var i = 0; i < 6; i++) makeSong(id: 'b$i', title: 'B$i')];

    test('a few old favourites are spread through the picks, never the first places', () {
      for (var seed = 0; seed < 20; seed++) {
        final out = blendBackInRotation(picks, back, random: Random(seed));
        final at = [for (var i = 0; i < out.length; i++) if (out[i].id.startsWith('b')) i];
        expect(at.length, 3);
        expect(at.first, greaterThanOrEqualTo(2));
        expect(at.last, lessThan(2 + 2 * 6 + 5));
        expect(out.map((s) => s.id).toSet().length, out.length);
        expect(out.where((s) => s.id.startsWith('p')).map((s) => s.id), picks.map((s) => s.id), reason: 'the recommender’s order is kept');
      }
    });

    test('a short list gets none and nothing to add changes nothing', () {
      expect(blendBackInRotation(picks.take(5).toList(), back).length, 5);
      expect(blendBackInRotation(picks, const []), picks);
      expect(blendBackInRotation(const [], back), isEmpty);
    });

    test('a song already picked is not added twice', () {
      final out = blendBackInRotation(picks, [picks[3], picks[4], back.first], random: Random(1));
      expect(out.where((s) => s.id == 'p3').length, 1);
      expect(out.length, 19);
    });
  });

  group('true shuffle bag', () {
    final songs = [for (var i = 0; i < 5; i++) makeSong(id: 's$i', title: 'S$i')];

    test('a list has the same key in any order and a different one when it changes', () {
      final ids = [for (final s in songs) s.id];
      expect(ShuffleBag.keyFor(ids), ShuffleBag.keyFor(ids.reversed));
      expect(ShuffleBag.keyFor(ids), isNot(ShuffleBag.keyFor(ids.take(4))));
    });

    test('heard songs are remembered across bags and sessions', () {
      final store = _MemoryStore();
      final bag = ShuffleBag(store);
      bag.markHeard(songs, 's1');
      bag.markHeard(songs, 's3');
      expect(ShuffleBag(store).heard(songs), {'s1', 's3'});
      expect(ShuffleBag(store).heard(songs.take(3).toList()), isEmpty, reason: 'another list has its own bag');
    });

    test('when every song has played the bag starts again', () {
      final bag = ShuffleBag(_MemoryStore());
      for (final s in songs) {
        bag.markHeard(songs, s.id);
      }
      expect(bag.heard(songs), isEmpty);
      bag.markHeard(songs, 's2');
      expect(bag.heard(songs), {'s2'});
    });

    test('the first song is one that has not played yet', () {
      final bag = ShuffleBag(_MemoryStore());
      for (final id in ['s0', 's1', 's2', 's3']) {
        bag.markHeard(songs, id);
      }
      for (var seed = 0; seed < 20; seed++) {
        expect(bag.pickStart(songs, Random(seed)).id, 's4');
      }
    });

    test('across sessions the songs not heard yet come first, so nothing repeats until all have played', () {
      final bag = ShuffleBag(_MemoryStore());
      final played = <String>[];
      for (var session = 0; session < 3; session++) {
        final queue = bagShuffleIsolate({'songs': songs, 'heard': bag.heard(songs).toList()});
        for (final s in queue.take(2)) {
          bag.markHeard(songs, s.id);
          played.add(s.id);
        }
      }
      // Sessions of two over five songs: the first five plays are five different songs.
      expect(played.take(5).toSet().length, 5, reason: '$played');
    });

    test('unheard songs come first in a shuffle, heard ones after', () {
      for (var i = 0; i < 20; i++) {
        final out = bagShuffleIsolate({'songs': songs, 'heard': ['s0', 's1']});
        expect(out.take(3).map((s) => s.id).toSet(), {'s2', 's3', 's4'});
        expect(out.skip(3).map((s) => s.id).toSet(), {'s0', 's1'});
      }
    });

    test('a damaged store is an empty bag, and the least used lists are forgotten', () {
      final store = _MemoryStore()..json = '{not json';
      final bag = ShuffleBag(store);
      expect(bag.heard(songs), isEmpty);
      for (var n = 0; n < ShuffleBag.maxLists + 4; n++) {
        final list = [makeSong(id: 'x$n-a'), makeSong(id: 'x$n-b')];
        bag.markHeard(list, 'x$n-a');
      }
      expect((jsonDecode(store.json!) as Map).length, ShuffleBag.maxLists);
    });

    test('a song that is not in the list changes nothing', () {
      final store = _MemoryStore();
      ShuffleBag(store).markHeard(songs, 'elsewhere');
      expect(store.json, isNull);
    });

    test('True Shuffle is named and described for what it does', () {
      expect(ShuffleAlgorithm.trueRandom.label, 'True Shuffle');
      expect(ShuffleAlgorithm.trueRandom.summary, contains('no recommender'));
      expect(ShuffleAlgorithm.trueRandom.usesGrouping, isFalse);
    });
  });

  group('screens', () {
    Widget host(Widget child, List<Override> overrides) => ProviderScope(
          overrides: [subsonicServiceProvider.overrideWithValue(_FakeSubsonic()), ...overrides],
          child: MaterialApp(home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: SingleChildScrollView(child: child)))),
        );

    testWidgets('Taste lists resting and seasonal songs with their actions', (tester) async {
      final fixed = _FixedRotation(Rotation.fromJson(_snapshot));
      await tester.pumpWidget(host(const RotationTasteSection(), [rotationProvider.overrideWith(() => fixed)]));
      await tester.pumpAndSettle();
      expect(find.text('Resting'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.textContaining('rested for you'), findsOneWidget);
      expect(find.textContaining('back on'), findsOneWidget);
      expect(find.text('Seasonal'), findsOneWidget);
      expect(find.textContaining('Deepavali: in season'), findsOneWidget);
      await tester.tap(find.text('Bring back'));
      await tester.pump();
      await tester.tap(find.text('Not seasonal').first);
      await tester.pump();
      expect(fixed.calls, ['unrest a', 'season c none']);
    });

    testWidgets('the switches save what was changed and nothing else', (tester) async {
      final fixed = _FixedRotation(Rotation.fromJson(_snapshot));
      await tester.pumpWidget(host(const RotationTasteSection(), [rotationProvider.overrideWith(() => fixed)]));
      await tester.pumpAndSettle();
      expect(find.text('Rest songs I wear out'), findsOneWidget);
      expect(find.text('Back in rotation'), findsOneWidget);
      await tester.tap(find.byType(CupertinoSwitch).at(1));
      await tester.pump();
      expect(fixed.calls, ['prefs null true null']);
    });

    testWidgets('nothing is drawn before the server answers', (tester) async {
      await tester.pumpWidget(host(const RotationTasteSection(), [
        rotationProvider.overrideWith(() => _Failing()),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Rotation'), findsNothing);
    });

    Future<void> menu(WidgetTester tester, Rotation r) async {
      await tester.pumpWidget(host(
        Builder(builder: (context) => RotationActions(song: makeSong(id: 'a', title: 'Alpha'), page: context)),
        [rotationProvider.overrideWith(() => _FixedRotation(r))],
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the song menu offers to rest a song and to tag its season', (tester) async {
      await menu(tester, const Rotation());
      expect(find.text('Rest This Song…'), findsOneWidget);
      expect(find.text('Seasonal…'), findsOneWidget);
    });

    testWidgets('a resting song offers Bring Back instead', (tester) async {
      await menu(tester, Rotation.fromJson(_snapshot));
      expect(find.text('Bring Back'), findsOneWidget);
      expect(find.text('Rest This Song…'), findsNothing);
    });

    testWidgets('a song with a season shows it in the menu', (tester) async {
      await menu(tester, Rotation.fromJson({
        'seasonal': [{'song_id': 'a', 'season': 'pongal', 'label': 'Pongal', 'manual': true}],
      }));
      expect(find.text('Seasonal: Pongal'), findsOneWidget);
    });

    testWidgets('Home’s shelf shows the reason under each song', (tester) async {
      await tester.pumpWidget(host(const BackInRotationSection(), [
        backInRotationProvider.overrideWith((ref) async => [
              const ListenPick(songId: 'b1', title: 'Old One', artist: 'Y', why: 'You played it 5 times, last in Dec 2025'),
            ]),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Back in Rotation'), findsOneWidget);
      expect(find.text('Old One'), findsOneWidget);
      expect(find.textContaining('5 times'), findsOneWidget);
    });

    testWidgets('Home’s shelf is hidden when there is nothing to bring back', (tester) async {
      await tester.pumpWidget(host(const BackInRotationSection(), [
        backInRotationProvider.overrideWith((ref) async => const <ListenPick>[]),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Back in Rotation'), findsNothing);
    });
  });
}

class _Failing extends RotationNotifier {
  @override
  Future<Rotation> build() async => throw const ListenException('down');
}
