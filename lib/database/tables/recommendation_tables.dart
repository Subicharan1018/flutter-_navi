import 'package:drift/drift.dart';

@DataClassName('RecommendationProfileEntity')
class RecommendationProfiles extends Table {
  TextColumn get songId => text()();
  RealColumn get skipRate => real()();
  RealColumn get completionRate => real()();
  RealColumn get affinityScore => real()();
  TextColumn get timePatternsJson => text()();
  IntColumn get lastUpdated => integer()();

  @override
  Set<Column> get primaryKey => {songId};
}

@DataClassName('ArtistAffinityEntity')
class ArtistAffinity extends Table {
  TextColumn get artistName => text()();
  RealColumn get score => real()();
  IntColumn get lastUpdated => integer()();

  @override
  Set<Column> get primaryKey => {artistName};
}

@DataClassName('GenreAffinityEntity')
class GenreAffinity extends Table {
  TextColumn get genre => text()();
  RealColumn get score => real()();
  IntColumn get lastUpdated => integer()();

  @override
  Set<Column> get primaryKey => {genre};
}
