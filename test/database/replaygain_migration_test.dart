import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/providers/library_provider.dart' show songFromMetadata;

/// Schema 8 added ReplayGain to the song mirror. An existing install must keep
/// its rows and gain the four columns.
void main() {
  test('upgrades a schema 7 mirror, keeping its songs', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE song_metadata (song_id TEXT NOT NULL PRIMARY KEY, track_name TEXT NOT NULL, '
            'artist_name TEXT NOT NULL, album_name TEXT NOT NULL, genre TEXT, composer TEXT, '
            'duration_sec INTEGER NOT NULL, year INTEGER, play_count INTEGER NOT NULL DEFAULT 0, '
            'rating INTEGER NOT NULL DEFAULT 0, starred INTEGER NOT NULL DEFAULT 0, '
            'updated_at INTEGER NOT NULL, created_at INTEGER, suffix TEXT, bit_rate INTEGER NOT NULL DEFAULT 0, '
            'bit_depth INTEGER NOT NULL DEFAULT 0, sampling_rate INTEGER NOT NULL DEFAULT 0, '
            'channel_count INTEGER NOT NULL DEFAULT 0)',
          );
          // The other tables the index step touches.
          raw.execute('CREATE TABLE play_events (ts_start INTEGER, song_id TEXT)');
          raw.execute('CREATE TABLE local_songs (folder_id TEXT, server_id TEXT)');
          raw.execute(
            'INSERT INTO song_metadata (song_id, track_name, artist_name, album_name, duration_sec, updated_at) '
            "VALUES ('a', 'Title', 'Artist', 'Album', 200, 1)",
          );
          raw.execute('PRAGMA user_version = 7');
        },
      ),
    );
    addTearDown(db.close);

    final row = await db.select(db.songMetadata).getSingle();
    expect(row.trackName, 'Title');
    expect(songFromMetadata(row).trackGain, isNull);

    await db.customStatement('UPDATE song_metadata SET track_gain = -8.5, track_peak = 0.99');
    final song = songFromMetadata(await db.select(db.songMetadata).getSingle());
    expect(song.trackGain, -8.5);
    expect(song.trackPeak, 0.99);
  });
}
