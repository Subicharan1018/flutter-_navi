import 'package:drift/drift.dart';

@DataClassName('PlayEventEntity')
class PlayEvents extends Table {
  TextColumn get playId => text()();
  TextColumn get songId => text()();
  TextColumn get sessionId => text()();
  IntColumn get tsStart => integer()();
  IntColumn get tsEnd => integer().nullable()();
  IntColumn get playDurSec => integer().withDefault(const Constant(0))();
  BoolColumn get skipBefore50 => boolean().withDefault(const Constant(false))();
  RealColumn get skipPositionPct => real().nullable()();
  IntColumn get repeatCount => integer().withDefault(const Constant(0))();
  IntColumn get queuePosition => integer().withDefault(const Constant(0))();
  BoolColumn get shuffleActive =>
      boolean().withDefault(const Constant(false))();
  TextColumn get sourceContext => text()();
  IntColumn get hourOfDay => integer()();
  IntColumn get dayOfWeek => integer()();

  @override
  Set<Column> get primaryKey => {playId};
}

@DataClassName('SongMetadataEntity')
class SongMetadata extends Table {
  TextColumn get songId => text()();
  TextColumn get trackName => text()();
  TextColumn get artistName => text()();
  TextColumn get albumName => text()();
  TextColumn get genre => text().nullable()();
  TextColumn get composer => text().nullable()();
  IntColumn get durationSec => integer()();
  IntColumn get year => integer().nullable()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get rating => integer().withDefault(const Constant(0))();
  BoolColumn get starred => boolean().withDefault(const Constant(false))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {songId};
}

@DataClassName('SongPairEntity')
class SongPairs extends Table {
  TextColumn get prevSongId => text()();
  TextColumn get currentSongId => text()();
  TextColumn get transitionType => text()();
  IntColumn get playCount => integer().withDefault(const Constant(1))();
  IntColumn get lastSeen => integer()();

  @override
  Set<Column> get primaryKey => {prevSongId, currentSongId, transitionType};
}

@DataClassName('UserFeedbackEntity')
class UserFeedback extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  TextColumn get feedbackType => text()();
  IntColumn get ts => integer()();
  TextColumn get sessionId => text()();
}

@DataClassName('SongWeightEntity')
class SongWeights extends Table {
  TextColumn get songId => text()();
  RealColumn get weight => real().withDefault(const Constant(1.0))();

  @override
  Set<Column> get primaryKey => {songId};
}
