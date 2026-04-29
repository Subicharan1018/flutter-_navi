import 'package:drift/drift.dart';

@DataClassName('PlaylistCacheEntity')
class PlaylistCache extends Table {
  TextColumn get playlistId => text()();
  IntColumn get position => integer()();
  TextColumn get songJson => text()();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {playlistId, position};
}
