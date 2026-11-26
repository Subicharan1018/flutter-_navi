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
  IntColumn get createdAt => integer().nullable()();

  // Audio format (schema 7). Null / 0 = unknown, as for rows mirrored by an
  // older build; the next library sync fills them in.
  TextColumn get suffix => text().nullable()();
  IntColumn get bitRate => integer().withDefault(const Constant(0))();
  IntColumn get bitDepth => integer().withDefault(const Constant(0))();
  IntColumn get samplingRate => integer().withDefault(const Constant(0))();
  IntColumn get channelCount => integer().withDefault(const Constant(0))();

  // ReplayGain (schema 8), for volume normalisation. Null = untagged, or a
  // row not yet re-synced.
  RealColumn get trackGain => real().nullable()();
  RealColumn get albumGain => real().nullable()();
  RealColumn get trackPeak => real().nullable()();
  RealColumn get albumPeak => real().nullable()();

  @override
  Set<Column> get primaryKey => {songId};
}
