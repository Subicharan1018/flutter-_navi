import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/providers/library_provider.dart';

/// Schema 7 added the audio format of mirrored songs (suffix, bit rate, depth,
/// sampling rate, channels). A phone upgrading from 6 must keep its rows.
void main() {
  test('upgrading from schema 6 keeps song rows and adds the audio columns', () async {
    final executor = NativeDatabase.memory(setup: (raw) {
      raw.execute('''
        CREATE TABLE song_metadata (
          song_id TEXT NOT NULL PRIMARY KEY,
          track_name TEXT NOT NULL,
          artist_name TEXT NOT NULL,
          album_name TEXT NOT NULL,
          genre TEXT NULL,
          composer TEXT NULL,
          duration_sec INTEGER NOT NULL,
          year INTEGER NULL,
          play_count INTEGER NOT NULL DEFAULT 0,
          rating INTEGER NOT NULL DEFAULT 0,
          starred INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          created_at INTEGER NULL
        )''');
      raw.execute("INSERT INTO song_metadata (song_id, track_name, artist_name, album_name, duration_sec, updated_at) "
          "VALUES ('s1', 'Old row', 'Artist', 'Album', 200, 0)");
      // The other schema-6 tables, reduced to the columns the indexes touch.
      raw.execute('CREATE TABLE play_events (ts_start INTEGER, song_id TEXT)');
      raw.execute('CREATE TABLE local_songs (song_id TEXT PRIMARY KEY, folder_id TEXT, server_id TEXT)');
      raw.execute('PRAGMA user_version = 6');
    });
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    final rows = await db.select(db.songMetadata).get();
    expect(rows.single.trackName, 'Old row');
    final old = songFromMetadata(rows.single);
    expect((old.suffix, old.bitRate, old.bitDepth, old.samplingRate, old.channelCount), ('', 0, 0, 0, 0));

    await db.into(db.songMetadata).insert(SongMetadataCompanion.insert(
          songId: 's2',
          trackName: 'New',
          artistName: 'A',
          albumName: 'B',
          durationSec: 100,
          updatedAt: 0,
          suffix: const Value('flac'),
          bitRate: const Value(1411),
          bitDepth: const Value(24),
          samplingRate: const Value(96000),
          channelCount: const Value(2),
        ));
    final fresh = songFromMetadata(await (db.select(db.songMetadata)..where((t) => t.songId.equals('s2'))).getSingle());
    expect((fresh.suffix, fresh.bitDepth, fresh.samplingRate, fresh.channelCount), ('flac', 24, 96000, 2));
  });
}
