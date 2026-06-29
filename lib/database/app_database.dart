import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'tables/analytics_tables.dart';
import 'tables/playlist_cache_table.dart';
import 'tables/search_history_table.dart';
import 'tables/recommendation_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    PlayEvents,
    SongMetadata,
    SongPairs,
    UserFeedback,
    SongWeights,
    PlaylistCache,
    SearchHistory,
    RecommendationProfiles,
    ArtistAffinity,
    GenreAffinity,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'navivibe_drift'));

  /// Named constructor for tests — accepts any [QueryExecutor],
  /// typically [NativeDatabase.memory()] for a fully in-memory DB.
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

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
      },
    );
  }
}
