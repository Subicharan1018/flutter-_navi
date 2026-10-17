import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_exception.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_repository.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/offline_service.dart';
import 'package:navivibe/providers/id_migration_provider.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Navidrome upgrade renamed song ids; the device follows the server's map.
/// The swap case matters: C1 → C2 while D1 → C1 (one song's old id is
/// another's new id) must neither clash nor mix the two songs up.
const _map = {'A1': 'A2', 'C1': 'C2', 'D1': 'C1'};

Future<void> _song(AppDatabase db, String id, String title) => db.customStatement(
      'INSERT INTO song_metadata (song_id, track_name, artist_name, album_name, duration_sec, updated_at) '
      'VALUES (?, ?, ?, ?, 200, 0)',
      [id, title, 'Artist', 'Album'],
    );

/// Serves /id-map from fields the test can change between runs.
class _MapRepo extends Fake implements ShuffleRepository {
  String? epoch;
  Map<String, String> map;
  final bool fail;
  _MapRepo(this.epoch, this.map, {this.fail = false});

  @override
  Future<(String?, Map<String, String>)> getIdMap() async {
    if (fail) throw const ShuffleNetworkError();
    return (epoch, map);
  }
}

Future<Map<String, String>> _titles(AppDatabase db) async => {
      for (final r in await db.customSelect('SELECT song_id, track_name FROM song_metadata').get())
        r.read<String>('song_id'): r.read<String>('track_name'),
    };

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('database', () {
    test('every table follows the map, swaps included', () async {
      for (final (id, title) in [('A1', 'a'), ('B1', 'b'), ('C1', 'c'), ('D1', 'd')]) {
        await _song(db, id, title);
      }
      for (final (play, id) in [('p1', 'C1'), ('p2', 'D1')]) {
        await db.customStatement(
            'INSERT INTO play_events (play_id, song_id, session_id, ts_start, source_context, hour_of_day, day_of_week) '
            "VALUES (?, ?, 's', 0, 'library', 0, 0)",
            [play, id]);
      }
      await db.customStatement(
          "INSERT INTO playlist_cache (playlist_id, position, song_json, cached_at) VALUES ('p', 0, '{}', 0)");

      await db.remapSongIds(_map);

      expect(await _titles(db), {'A2': 'a', 'B1': 'b', 'C2': 'c', 'C1': 'd'});
      final plays = {
        for (final r in await db.customSelect('SELECT play_id, song_id FROM play_events').get())
          r.read<String>('play_id'): r.read<String>('song_id'),
      };
      expect(plays, {'p1': 'C2', 'p2': 'C1'});                       // D's play, under D's new id
      expect((await db.customSelect('SELECT COUNT(*) AS n FROM playlist_cache').getSingle()).read<int>('n'), 0);
    });

    test('a row the new server already synced gives way to the one with history', () async {
      await _song(db, 'A1', 'with history');
      await _song(db, 'A2', 'fresh from sync');
      await db.remapSongIds({'A1': 'A2'});
      expect(await _titles(db), {'A2': 'with history'});
    });

    test('upgrading from schema 3 drops the retired tables and keeps play history', () async {
      final dir = await Directory.systemTemp.createTemp('navivibe_db_');
      final file = File('${dir.path}/v3.sqlite');
      try {
        final v3 = AppDatabase.forTesting(NativeDatabase(file));
        await _song(v3, 'A1', 'kept');
        await v3.customStatement('CREATE TABLE song_pairs (prev_song_id TEXT, current_song_id TEXT)');
        await v3.customStatement('CREATE TABLE song_weights (song_id TEXT PRIMARY KEY, weight REAL)');
        await v3.customStatement('CREATE TABLE IF NOT EXISTS search_history (query TEXT PRIMARY KEY, last_searched_at INTEGER)');
        await v3.customStatement('PRAGMA user_version = 3');
        await v3.close();

        final latest = AppDatabase.forTesting(NativeDatabase(file));
        final tables = [
          for (final r in await latest.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get())
            r.read<String>('name'),
        ];
        expect(tables, isNot(contains('song_pairs')));
        expect(tables, isNot(contains('song_weights')));
        expect(tables, isNot(contains('search_history')));
        expect(await _titles(latest), {'A1': 'kept'});
        await latest.close();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('library prune', () {
    test('drops songs a complete sync no longer saw', () async {
      for (final id in ['a', 'b', 'c', 'gone']) {
        await _song(db, id, id);
      }
      expect(await pruneMissingForTest(db, {'a', 'b', 'c'}), 1);
      expect((await _titles(db)).keys, unorderedEquals(['a', 'b', 'c']));
    });

    test('an answer with under half the library prunes nothing', () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        await _song(db, id, id);
      }
      expect(await pruneMissingForTest(db, {'a'}), 0);
      expect((await _titles(db)).length, 4);
    });
  });

  group('once per epoch', () {
    late Directory tmp;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tmp = await Directory.systemTemp.createTemp('navivibe_idmig_hive');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => tmp.path);
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
      SharedPreferences.setMockInitialValues({});
      await Hive.initFlutter('idmig_hive');
      await HiveBoxes.init();
    });
    tearDownAll(() async {
      await Hive.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('a map is applied once; a later epoch applies again', () async {
      await HiveBoxes.prefs.delete(IdMigration.kEpoch);
      await _song(db, 'C1', 'c');
      await _song(db, 'D1', 'd');
      final repo = _MapRepo('e1', _map);
      final c = ProviderContainer(overrides: [
        shuffleRepositoryProvider.overrideWithValue(repo),
        appDatabaseProvider.overrideWithValue(db),
      ]);
      addTearDown(c.dispose);
      final mig = c.read(idMigrationProvider);

      expect(await mig.runIfNeeded(), 3);
      expect(await _titles(db), {'C2': 'c', 'C1': 'd'});
      expect(await mig.runIfNeeded(), 0);                    // same epoch: the swap is NOT redone
      expect(await _titles(db), {'C2': 'c', 'C1': 'd'});

      repo.epoch = 'e2';
      repo.map = {'C2': 'C3'};
      expect(await mig.runIfNeeded(), 1);
      expect(await _titles(db), {'C3': 'c', 'C1': 'd'});
    });

    test('no map from the server leaves everything alone and retries later', () async {
      await HiveBoxes.prefs.delete(IdMigration.kEpoch);
      final c = ProviderContainer(overrides: [
        shuffleRepositoryProvider.overrideWithValue(_MapRepo(null, const {}, fail: true)),
        appDatabaseProvider.overrideWithValue(db),
      ]);
      addTearDown(c.dispose);
      expect(await c.read(idMigrationProvider).runIfNeeded(), 0);
      expect(HiveBoxes.prefs.get(IdMigration.kEpoch), isNull);
    });
  });

  group('downloads', () {
    late Directory docs;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = await Directory.systemTemp.createTemp('navivibe_idmig');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docs.path,
      );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
      await docs.delete(recursive: true);
    });

    test('files, saved songs and lists move to the new ids', () async {
      SharedPreferences.setMockInitialValues({
        'offline_downloaded_songs': ['C1', 'D1', 'B1'],
        'pending_scrobbles': jsonEncode([{'id': 'D1', 'submission': 'true', 'time': '1'}]),
      });
      final dir = Directory('${docs.path}/offline_music')..createSync(recursive: true);
      for (final id in ['C1', 'D1']) {
        File('${dir.path}/$id.flac').writeAsStringSync('audio-$id');
        File('${dir.path}/$id.song.json').writeAsStringSync(jsonEncode({'id': id, 'title': 'song $id'}));
        File('${dir.path}/$id.jpg').writeAsStringSync('art-$id');
      }

      final offline = OfflineService()..resetForTest(); // shared instance: start clean
      await offline.initialize();
      expect(await offline.remapSongIds(_map), 2);

      expect(File('${dir.path}/C2.flac').readAsStringSync(), 'audio-C1');
      expect(File('${dir.path}/C1.flac').readAsStringSync(), 'audio-D1');   // swap: no overwrite
      final saved = jsonDecode(File('${dir.path}/C1.song.json').readAsStringSync()) as Map;
      expect(saved, {'id': 'C1', 'title': 'song D1'});
      expect(offline.getDownloadedSongIds(), ['C2', 'C1', 'B1']);
      expect(offline.isSongDownloaded('C2'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect((jsonDecode(prefs.getString('pending_scrobbles')!) as List).single['id'], 'C1');
      expect(dir.listSync().map((f) => f.uri.pathSegments.last).where((n) => n.startsWith('__idmig__')), isEmpty);
    });
  });
}
