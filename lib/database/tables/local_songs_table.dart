import 'package:drift/drift.dart';

/// Songs found in the folders the user added under Settings > Local music.
/// Device-only: never uploaded, never mixed into `song_metadata` (the server
/// mirror). A row's id is derived from its location, so a rescan keeps it.
@DataClassName('LocalSongEntity')
class LocalSongs extends Table {
  TextColumn get songId => text()();

  /// Absolute path (desktop, Android file paths) or a `content://` document
  /// URI (Android folders picked through the Storage Access Framework).
  TextColumn get path => text()();

  /// The added folder this file was found under.
  TextColumn get folderId => text()();

  /// Size, modified time and sidecar times of the file when it was read.
  /// A rescan re-reads a file only when this changes.
  TextColumn get fingerprint => text()();

  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get albumArtist => text().withDefault(const Constant(''))();
  TextColumn get genre => text().withDefault(const Constant(''))();
  IntColumn get track => integer().withDefault(const Constant(0))();
  IntColumn get disc => integer().withDefault(const Constant(0))();
  IntColumn get year => integer().withDefault(const Constant(0))();
  IntColumn get durationSec => integer().withDefault(const Constant(0))();
  IntColumn get bitRate => integer().withDefault(const Constant(0))();
  TextColumn get suffix => text().withDefault(const Constant(''))();

  RealColumn get trackGain => real().nullable()();
  RealColumn get albumGain => real().nullable()();
  RealColumn get trackPeak => real().nullable()();
  RealColumn get albumPeak => real().nullable()();

  /// Cover extracted from the tags (or a folder.jpg beside the file), saved
  /// under the app's support folder. Null when the file has none.
  TextColumn get coverPath => text().nullable()();

  /// Text of the sidecar `.lrc` (or the tag's lyrics); read at scan time so
  /// playback never touches the folder again.
  TextColumn get lyrics => text().nullable()();

  /// Server song this file is a copy of (title + artist + duration match).
  TextColumn get serverId => text().nullable()();

  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {songId};

  @override
  List<Set<Column>> get uniqueKeys => [
        {path},
      ];
}
