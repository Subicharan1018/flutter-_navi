import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

import 'tables/analytics_tables.dart';
import 'tables/playlist_cache_table.dart';
import 'tables/search_history_table.dart';
import 'tables/recommendation_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'navivibe_drift'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Handle migrations here when schemaVersion increments
      },
    );
  }
}
