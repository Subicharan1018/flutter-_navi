import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'tables/analytics_tables.dart';
import 'tables/playlist_cache_table.dart';
import 'tables/search_history_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [PlayEvents, SongMetadata, PlaylistCache, SearchHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'navivibe_drift'));

  /// Named constructor for tests — accepts any [QueryExecutor],
  /// typically [NativeDatabase.memory()] for a fully in-memory DB.
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  /// Tables from schema 3 that were written but never read (co-play pairs,
  /// suggest feedback, song weights) or never used at all (recommendation
  /// profiles and affinities, which live in Hive).
  static const _droppedInV4 = [
    'song_pairs',
    'user_feedback',
    'song_weights',
    'recommendation_profiles',
    'artist_affinity',
    'genre_affinity',
  ];

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          try {
            await m.addColumn(playEvents, playEvents.skipBefore50);
          } catch (e) {
            // Ignore if column already exists
          }
        }
        if (from < 3) {
          try {
            await m.addColumn(songMetadata, songMetadata.createdAt);
          } catch (e) {
            // Ignore if column already exists
          }
        }
        if (from < 4) {
          for (final table in _droppedInV4) {
            await m.deleteTable(table);
          }
        }
      },
      // Idempotent: covers fresh installs and existing DBs without a bump.
      beforeOpen: (_) => _ensureIndexes(),
    );
  }

  /// Indexes for the hot reads: per-row artwork lookups by title/artist and
  /// "recently played" ordering were full scans of a library-sized table.
  Future<void> _ensureIndexes() async {
    const statements = [
      'CREATE INDEX IF NOT EXISTS idx_song_meta_title_artist ON song_metadata (track_name, artist_name)',
      'CREATE INDEX IF NOT EXISTS idx_song_meta_artist ON song_metadata (artist_name)',
      'CREATE INDEX IF NOT EXISTS idx_play_events_ts ON play_events (ts_start)',
      'CREATE INDEX IF NOT EXISTS idx_play_events_song ON play_events (song_id)',
    ];
    for (final sql in statements) {
      await customStatement(sql);
    }
  }

  /// Every local column that stores a server song id.
  static const _songIdColumns = [
    ('song_metadata', 'song_id'),
    ('play_events', 'song_id'),
  ];

  /// After a server upgrade changed song ids (old → new): rewrite every local
  /// table in one transaction, so play history and metadata follow the
  /// songs. Two-phase (one song's old id can be another's new id); on a clash
  /// with a row the new server already produced (a sync ran first), the row
  /// carrying the local history wins. Cached playlist pages hold whole songs
  /// with old ids and are simply dropped — they refetch.
  Future<void> remapSongIds(Map<String, String> idMap) async {
    if (idMap.isEmpty) return;
    const tmp = '__idmig__';
    await transaction(() async {
      await customStatement('CREATE TEMP TABLE IF NOT EXISTS id_map (old TEXT PRIMARY KEY, new TEXT NOT NULL)');
      await customStatement('DELETE FROM id_map');
      for (final e in idMap.entries) {
        await customStatement('INSERT INTO id_map VALUES (?, ?)', [e.key, e.value]);
      }
      for (final (table, col) in _songIdColumns) {
        await customStatement(
          'UPDATE $table SET $col = ? || (SELECT new FROM id_map WHERE old = $col) '
          'WHERE $col IN (SELECT old FROM id_map)',
          [tmp],
        );
        await customStatement(
          'UPDATE OR REPLACE $table SET $col = substr($col, ${tmp.length + 1}) '
          'WHERE substr($col, 1, ${tmp.length}) = ?',
          [tmp],
        );
      }
      await customStatement('DELETE FROM playlist_cache');
      await customStatement('DROP TABLE id_map');
    });
  }
}
