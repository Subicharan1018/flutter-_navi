import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/album_overnight/data/album_overnight_api.dart';
import 'package:navivibe/features/album_overnight/data/album_overnight_models.dart';
import 'package:navivibe/features/album_overnight/logic/album_overnight_providers.dart';
import 'package:navivibe/features/album_overnight/ui/album_overnight_screen.dart';
import 'package:navivibe/features/album_overnight/ui/album_overnight_settings.dart';
import 'package:navivibe/features/exportify_import/data/exportify_api.dart';
import 'package:navivibe/features/exportify_import/logic/exportify_providers.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/player/artwork.dart';

import '../../helpers/fake_http.dart';

Map<String, dynamic> _track(int id, {String state = 'waiting', String? songId}) =>
    {'id': id, 'title': 'Track $id', 'artist': 'Diya Ram', 'number': id, 'duration_s': 240.0, 'state': state, 'song_id': songId};

Map<String, dynamic> _album(int id, {String state = 'waiting', List<Map<String, dynamic>>? tracks, String from = 'Kaadhal Mazhai'}) {
  final ts = tracks ?? [_track(1), _track(2), _track(3, state: 'ready', songId: 'nd3')];
  int n(String s) => ts.where((t) => t['state'] == s).length;
  return {
    'id': id,
    'album': 'Film $id (Original Motion Picture Soundtrack)',
    'artist': 'Ravi Kumar',
    'cover_url': 'https://is1-ssl.mzstatic.com/$id/600x600bb.jpg',
    'state': state,
    'total': ts.length + 2,
    'owned': 2,
    'added_at': 1795000000.0,
    'from_song': from,
    'counts': {'waiting': n('waiting'), 'queued': n('queued'), 'ready': n('ready'), 'failed': n('failed')},
    'tracks': ts,
  };
}

Map<String, dynamic> _page({bool enabled = true, List<Map<String, dynamic>>? albums, int waiting = 2, String? note, int perNight = 30}) => {
      'enabled': enabled,
      'film_only': true,
      'per_night': perNight,
      'per_night_choices': [10, 20, 30, 50, 100],
      'max_per_album': 25,
      'max_per_album_choices': [5, 10, 15, 25, 40],
      'waiting': waiting,
      'max_waiting': 150,
      'download_note': note,
      'night': {'from': 1, 'to': 7},
      'albums': albums ?? [_album(1), _album(2, state: 'queued', tracks: [_track(1, state: 'queued'), _track(2, state: 'queued')])],
    };

class _Server {
  Map<String, dynamic> page;
  final List<Map<String, dynamic>> calls = [];
  bool failCancel = false;
  int onItsWay = 0;
  _Server(this.page);

  ResponseBody handle(RequestOptions o) {
    calls.add({'method': o.method, 'path': o.path, 'data': o.data});
    if (o.method == 'GET') return jsonBody(200, page);
    if (o.path.endsWith('/prefs')) {
      final d = o.data as Map;
      page = {
        ...page,
        if (d.containsKey('enabled')) 'enabled': d['enabled'],
        if (d.containsKey('film_only')) 'film_only': d['film_only'],
        if (d.containsKey('per_night')) 'per_night': d['per_night'],
        if (d.containsKey('max_per_album')) 'max_per_album': d['max_per_album'],
      };
      return jsonBody(200, page);
    }
    if (failCancel) return jsonBody(404, {'error': 'no such album'});
    if (o.path.endsWith('/cancel-all')) {
      page = {...page, 'albums': [], 'waiting': 0};
      return jsonBody(200, {'stopped': 5, 'already_on_its_way': onItsWay, 'albums': 2});
    }
    final id = int.tryParse(RegExp(r'/albums/(\d+)/cancel').firstMatch(o.path)?.group(1) ?? '');
    if (id != null) {
      page = {...page, 'albums': [for (final a in page['albums'] as List) if ((a as Map)['id'] != id) a]};
      return jsonBody(200, {'stopped': 2, 'already_on_its_way': onItsWay});
    }
    return jsonBody(404, {'error': 'no'});
  }
}

class _Rig {
  final _Server server;
  var canDownload = true;
  _Rig(this.server);

  List<Override> get overrides => [
        albumOvernightApiProvider.overrideWithValue(AlbumOvernightApi(fakeDio(FakeAdapter(server.handle)))),
        onlineFetchEnabledProvider.overrideWith((ref) => canDownload),
      ];
}

Widget _app(Widget home, _Rig rig) => ProviderScope(
      key: UniqueKey(),
      overrides: rig.overrides,
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

void main() {
  setUp(() => debugCoverImageOverride = (url, key) => MemoryImage(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')));
  tearDown(() => debugCoverImageOverride = null);

  group('models', () {
    test('a page is read: prefs, night, albums with their counts and tracks', () {
      final a = AlbumOvernight.fromJson(_page(note: 'Downloads tonight, 1–7 am.'));
      expect(a.enabled, isTrue);
      expect(a.filmOnly, isTrue);
      expect((a.perNight, a.maxPerAlbum, a.waiting, a.maxWaiting), (30, 25, 2, 150));
      expect(a.perNightChoices, [10, 20, 30, 50, 100]);
      expect(a.downloadNote, 'Downloads tonight, 1–7 am.');
      expect((a.nightFrom, a.nightTo), (1, 7));
      final first = a.albums.first;
      expect(first.stage, AlbumStage.waiting);
      expect((first.waiting, first.ready, first.owned, first.toCome), (2, 1, 2, 2));
      expect(first.tracks.map((t) => t.stage), [TrackStage.waiting, TrackStage.waiting, TrackStage.ready]);
      expect(first.tracks.last.songId, 'nd3');
      expect(first.line, '2 waiting for tonight · 1 in your library');
      expect(a.albums.last.line, '2 on their way');
      expect(a.open.length, 2);
    });

    test('an empty or odd answer reads as off with nothing queued', () {
      final a = AlbumOvernight.fromJson(const {});
      expect(a.enabled, isFalse);
      expect(a.albums, isEmpty);
      expect(a.perNightChoices, isNotEmpty);
      expect(QueuedAlbum.fromJson(const {'id': 1, 'album': 'x', 'state': 'nothing'}).line, 'You already have all of it');
    });

    test('what cancelling did is said in words', () {
      expect(cancelMessage(const CancelResult(4, 0)), 'Cancelled. 4 tracks dropped.');
      expect(cancelMessage(const CancelResult(1, 0)), 'Cancelled. 1 track dropped.');
      expect(cancelMessage(const CancelResult(2, 3)), 'Cancelled. 2 tracks dropped; 3 are already on their way and will finish.');
      expect(cancelMessage(const CancelResult(0, 0)), 'Nothing was waiting.');
    });
  });

  group('controller', () {
    ProviderContainer container(_Rig rig) {
      final c = ProviderContainer(overrides: rig.overrides);
      c.listen(albumOvernightProvider, (_, _) {});
      addTearDown(c.dispose);
      return c;
    }

    test('turning it on sends only what changed and keeps the answer', () async {
      final rig = _Rig(_Server(_page(enabled: false, albums: [])));
      final c = container(rig);
      await c.read(albumOvernightProvider.future);
      await c.read(albumOvernightProvider.notifier).setEnabled(true);
      expect(rig.server.calls.where((e) => e['method'] == 'PUT').single['data'], {'enabled': true});
      expect(c.read(albumOvernightProvider).requireValue.enabled, isTrue);
    });

    test('cancelling an album takes it off the list; the server decides what is left', () async {
      final rig = _Rig(_Server(_page()));
      final c = container(rig);
      await c.read(albumOvernightProvider.future);
      final r = await c.read(albumOvernightProvider.notifier).cancelAlbum(1);
      expect(r.stopped, 2);
      expect(rig.server.calls.any((e) => e['method'] == 'POST' && e['path'] == '/exportify/album-overnight/albums/1/cancel'), isTrue);
      expect(c.read(albumOvernightProvider).requireValue.albums.map((a) => a.id), [2]);
    });

    test('a refused cancel puts the album back and says why', () async {
      final rig = _Rig(_Server(_page()))..server.failCancel = true;
      final c = container(rig);
      await c.read(albumOvernightProvider.future);
      await expectLater(c.read(albumOvernightProvider.notifier).cancelAlbum(1), throwsA(isA<Exception>()));
      expect(c.read(albumOvernightProvider).requireValue.albums.length, 2);
    });
  });

  group('queue page', () {
    testWidgets('lists the albums with where each is, and tracks on tap', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page(note: 'Downloads tonight, 1–7 am.')));
      await tester.pumpWidget(_app(const AlbumOvernightScreen(), rig));
      await _settle(tester);
      expect(find.text('2 tracks to fetch'), findsOneWidget);
      expect(find.text('Downloads tonight, 1–7 am.'), findsOneWidget);
      expect(find.text('Film 1 (Original Motion Picture Soundtrack)'), findsOneWidget);
      expect(find.text('2 waiting for tonight · 1 in your library'), findsOneWidget);
      expect(find.text('2 on their way'), findsOneWidget);
      expect(find.text('Track 1'), findsNothing);
      await tester.tap(find.text('Film 1 (Original Motion Picture Soundtrack)'));
      await _settle(tester);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('In your library'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Cancel drops the album and says what happened', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page())..onItsWay = 1);
      await tester.pumpWidget(_app(const AlbumOvernightScreen(), rig));
      await _settle(tester);
      await tester.tap(find.text('Cancel').first);
      await _settle(tester);
      expect(find.text('Film 1 (Original Motion Picture Soundtrack)'), findsNothing);
      expect(find.text('Cancelled. 2 tracks dropped; 1 is already on its way and will finish.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Cancel all asks first, then clears the queue', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()));
      await tester.pumpWidget(_app(const AlbumOvernightScreen(), rig));
      await _settle(tester);
      await tester.tap(find.text('Cancel all'));
      await _settle(tester);
      expect(find.text('Cancel all albums?'), findsOneWidget);
      expect(rig.server.calls.where((e) => e['method'] == 'POST'), isEmpty);
      await tester.tap(find.text('Cancel all').last);
      await _settle(tester);
      expect(rig.server.calls.where((e) => e['method'] == 'POST').single['path'], '/exportify/album-overnight/cancel-all');
      expect(find.text('No albums queued'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('off and empty offers to turn it on; on and empty explains', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page(enabled: false, albums: [], waiting: 0)));
      await tester.pumpWidget(_app(const AlbumOvernightScreen(), rig));
      await _settle(tester);
      expect(find.text('Album Overnight is off'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await _settle(tester);
      expect(rig.server.calls.where((e) => e['method'] == 'PUT').single['data'], {'enabled': true});
      expect(find.text('No albums queued'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed load says so and offers Try again', (tester) async {
      _phone(tester);
      final overrides = [
        albumOvernightApiProvider.overrideWithValue(AlbumOvernightApi(fakeDio(FakeAdapter((o) => jsonBody(500, {'error': 'down'}))))),
        onlineFetchEnabledProvider.overrideWith((ref) => true),
      ];
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: overrides,
        child: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(theme: AppTheme.build(AppThemeTokens.fallback), home: const Scaffold(body: AlbumOvernightScreen())),
        ),
      ));
      await _settle(tester);
      expect(find.text('Your queue didn’t load'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('settings', () {
    testWidgets('off shows only the switch; on shows the choices and the queue', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page(enabled: false, albums: [], waiting: 0)));
      await tester.pumpWidget(_app(const SingleChildScrollView(child: AlbumOvernightSettings()), rig));
      await _settle(tester);
      expect(find.text('Album Overnight'), findsWidgets);
      expect(find.text('Songs a Night'), findsNothing);
      await tester.tap(find.byType(CupertinoSwitch).first);
      await _settle(tester);
      expect(rig.server.calls.where((e) => e['method'] == 'PUT').single['data'], {'enabled': true});
      expect(find.text('Film Albums Only'), findsOneWidget);
      expect(find.text('30 songs'), findsOneWidget);
      expect(find.text('25 tracks'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('songs a night is chosen from the server’s own list', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page(albums: [], waiting: 0)));
      await tester.pumpWidget(_app(const SingleChildScrollView(child: AlbumOvernightSettings()), rig));
      await _settle(tester);
      await tester.tap(find.text('Songs a Night'));
      await _settle(tester);
      await tester.tap(find.text('10 songs'));
      await _settle(tester);
      expect(rig.server.calls.where((e) => e['method'] == 'PUT').single['data'], {'per_night': 10});
      expect(find.text('10 songs'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('hidden for an account that cannot download', (tester) async {
      _phone(tester);
      final rig = _Rig(_Server(_page()))..canDownload = false;
      await tester.pumpWidget(_app(const AlbumOvernightSettings(), rig));
      await _settle(tester);
      expect(find.text('Film Albums Only'), findsNothing);
      expect(find.text('Album Overnight'), findsNothing);
    });
  });

  test('the Exportify list does not show the Album Overnight import', () async {
    Map<String, dynamic> imp(int id, String name) => {
          'id': id, 'name': name, 'rows': 10, 'unique': 10, 'duplicates': 0, 'skipped_rows': 0, 'no_isrc': 0,
          'maybe_owned': 0, 'playlist_id': null, 'states': {'owned': 1, 'wishlist': 9}, 'owned': 1, 'wishlist': 9,
          'wishlist_gb': 1.0, 'free_gb': 100.0,
          'plan': {'status': 'idle', 'priority': 'popularity', 'min_popularity': 0, 'per_night': 100, 'disk_floor_gb': 40.0, 'night_only': true},
        };
    final adapter = FakeAdapter((o) => jsonBody(200, [imp(1, 'Tamil Mix'), imp(2, kAlbumOvernightImportName), imp(3, kWeeklyExplorationImportName)]));
    final c = ProviderContainer(overrides: [exportifyApiProvider.overrideWithValue(ExportifyApi(fakeDio(adapter)))]);
    addTearDown(c.dispose);
    final list = await c.read(exportifyImportsProvider.future);
    expect(list.map((s) => s.name), ['Tamil Mix']);
  });
}
