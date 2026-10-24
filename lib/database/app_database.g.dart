// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PlayEventsTable extends PlayEvents
    with TableInfo<$PlayEventsTable, PlayEventEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playIdMeta = const VerificationMeta('playId');
  @override
  late final GeneratedColumn<String> playId = GeneratedColumn<String>(
    'play_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tsStartMeta = const VerificationMeta(
    'tsStart',
  );
  @override
  late final GeneratedColumn<int> tsStart = GeneratedColumn<int>(
    'ts_start',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tsEndMeta = const VerificationMeta('tsEnd');
  @override
  late final GeneratedColumn<int> tsEnd = GeneratedColumn<int>(
    'ts_end',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playDurSecMeta = const VerificationMeta(
    'playDurSec',
  );
  @override
  late final GeneratedColumn<int> playDurSec = GeneratedColumn<int>(
    'play_dur_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _skipBefore50Meta = const VerificationMeta(
    'skipBefore50',
  );
  @override
  late final GeneratedColumn<bool> skipBefore50 = GeneratedColumn<bool>(
    'skip_before50',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("skip_before50" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _skipPositionPctMeta = const VerificationMeta(
    'skipPositionPct',
  );
  @override
  late final GeneratedColumn<double> skipPositionPct = GeneratedColumn<double>(
    'skip_position_pct',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repeatCountMeta = const VerificationMeta(
    'repeatCount',
  );
  @override
  late final GeneratedColumn<int> repeatCount = GeneratedColumn<int>(
    'repeat_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _queuePositionMeta = const VerificationMeta(
    'queuePosition',
  );
  @override
  late final GeneratedColumn<int> queuePosition = GeneratedColumn<int>(
    'queue_position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _shuffleActiveMeta = const VerificationMeta(
    'shuffleActive',
  );
  @override
  late final GeneratedColumn<bool> shuffleActive = GeneratedColumn<bool>(
    'shuffle_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("shuffle_active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceContextMeta = const VerificationMeta(
    'sourceContext',
  );
  @override
  late final GeneratedColumn<String> sourceContext = GeneratedColumn<String>(
    'source_context',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hourOfDayMeta = const VerificationMeta(
    'hourOfDay',
  );
  @override
  late final GeneratedColumn<int> hourOfDay = GeneratedColumn<int>(
    'hour_of_day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayOfWeekMeta = const VerificationMeta(
    'dayOfWeek',
  );
  @override
  late final GeneratedColumn<int> dayOfWeek = GeneratedColumn<int>(
    'day_of_week',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    playId,
    songId,
    sessionId,
    tsStart,
    tsEnd,
    playDurSec,
    skipBefore50,
    skipPositionPct,
    repeatCount,
    queuePosition,
    shuffleActive,
    sourceContext,
    hourOfDay,
    dayOfWeek,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayEventEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('play_id')) {
      context.handle(
        _playIdMeta,
        playId.isAcceptableOrUnknown(data['play_id']!, _playIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playIdMeta);
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('ts_start')) {
      context.handle(
        _tsStartMeta,
        tsStart.isAcceptableOrUnknown(data['ts_start']!, _tsStartMeta),
      );
    } else if (isInserting) {
      context.missing(_tsStartMeta);
    }
    if (data.containsKey('ts_end')) {
      context.handle(
        _tsEndMeta,
        tsEnd.isAcceptableOrUnknown(data['ts_end']!, _tsEndMeta),
      );
    }
    if (data.containsKey('play_dur_sec')) {
      context.handle(
        _playDurSecMeta,
        playDurSec.isAcceptableOrUnknown(
          data['play_dur_sec']!,
          _playDurSecMeta,
        ),
      );
    }
    if (data.containsKey('skip_before50')) {
      context.handle(
        _skipBefore50Meta,
        skipBefore50.isAcceptableOrUnknown(
          data['skip_before50']!,
          _skipBefore50Meta,
        ),
      );
    }
    if (data.containsKey('skip_position_pct')) {
      context.handle(
        _skipPositionPctMeta,
        skipPositionPct.isAcceptableOrUnknown(
          data['skip_position_pct']!,
          _skipPositionPctMeta,
        ),
      );
    }
    if (data.containsKey('repeat_count')) {
      context.handle(
        _repeatCountMeta,
        repeatCount.isAcceptableOrUnknown(
          data['repeat_count']!,
          _repeatCountMeta,
        ),
      );
    }
    if (data.containsKey('queue_position')) {
      context.handle(
        _queuePositionMeta,
        queuePosition.isAcceptableOrUnknown(
          data['queue_position']!,
          _queuePositionMeta,
        ),
      );
    }
    if (data.containsKey('shuffle_active')) {
      context.handle(
        _shuffleActiveMeta,
        shuffleActive.isAcceptableOrUnknown(
          data['shuffle_active']!,
          _shuffleActiveMeta,
        ),
      );
    }
    if (data.containsKey('source_context')) {
      context.handle(
        _sourceContextMeta,
        sourceContext.isAcceptableOrUnknown(
          data['source_context']!,
          _sourceContextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceContextMeta);
    }
    if (data.containsKey('hour_of_day')) {
      context.handle(
        _hourOfDayMeta,
        hourOfDay.isAcceptableOrUnknown(data['hour_of_day']!, _hourOfDayMeta),
      );
    } else if (isInserting) {
      context.missing(_hourOfDayMeta);
    }
    if (data.containsKey('day_of_week')) {
      context.handle(
        _dayOfWeekMeta,
        dayOfWeek.isAcceptableOrUnknown(data['day_of_week']!, _dayOfWeekMeta),
      );
    } else if (isInserting) {
      context.missing(_dayOfWeekMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playId};
  @override
  PlayEventEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayEventEntity(
      playId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}play_id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      tsStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts_start'],
      )!,
      tsEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts_end'],
      ),
      playDurSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_dur_sec'],
      )!,
      skipBefore50: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}skip_before50'],
      )!,
      skipPositionPct: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}skip_position_pct'],
      ),
      repeatCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repeat_count'],
      )!,
      queuePosition: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}queue_position'],
      )!,
      shuffleActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}shuffle_active'],
      )!,
      sourceContext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_context'],
      )!,
      hourOfDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hour_of_day'],
      )!,
      dayOfWeek: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_of_week'],
      )!,
    );
  }

  @override
  $PlayEventsTable createAlias(String alias) {
    return $PlayEventsTable(attachedDatabase, alias);
  }
}

class PlayEventEntity extends DataClass implements Insertable<PlayEventEntity> {
  final String playId;
  final String songId;
  final String sessionId;
  final int tsStart;
  final int? tsEnd;
  final int playDurSec;
  final bool skipBefore50;
  final double? skipPositionPct;
  final int repeatCount;
  final int queuePosition;
  final bool shuffleActive;
  final String sourceContext;
  final int hourOfDay;
  final int dayOfWeek;
  const PlayEventEntity({
    required this.playId,
    required this.songId,
    required this.sessionId,
    required this.tsStart,
    this.tsEnd,
    required this.playDurSec,
    required this.skipBefore50,
    this.skipPositionPct,
    required this.repeatCount,
    required this.queuePosition,
    required this.shuffleActive,
    required this.sourceContext,
    required this.hourOfDay,
    required this.dayOfWeek,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['play_id'] = Variable<String>(playId);
    map['song_id'] = Variable<String>(songId);
    map['session_id'] = Variable<String>(sessionId);
    map['ts_start'] = Variable<int>(tsStart);
    if (!nullToAbsent || tsEnd != null) {
      map['ts_end'] = Variable<int>(tsEnd);
    }
    map['play_dur_sec'] = Variable<int>(playDurSec);
    map['skip_before50'] = Variable<bool>(skipBefore50);
    if (!nullToAbsent || skipPositionPct != null) {
      map['skip_position_pct'] = Variable<double>(skipPositionPct);
    }
    map['repeat_count'] = Variable<int>(repeatCount);
    map['queue_position'] = Variable<int>(queuePosition);
    map['shuffle_active'] = Variable<bool>(shuffleActive);
    map['source_context'] = Variable<String>(sourceContext);
    map['hour_of_day'] = Variable<int>(hourOfDay);
    map['day_of_week'] = Variable<int>(dayOfWeek);
    return map;
  }

  PlayEventsCompanion toCompanion(bool nullToAbsent) {
    return PlayEventsCompanion(
      playId: Value(playId),
      songId: Value(songId),
      sessionId: Value(sessionId),
      tsStart: Value(tsStart),
      tsEnd: tsEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(tsEnd),
      playDurSec: Value(playDurSec),
      skipBefore50: Value(skipBefore50),
      skipPositionPct: skipPositionPct == null && nullToAbsent
          ? const Value.absent()
          : Value(skipPositionPct),
      repeatCount: Value(repeatCount),
      queuePosition: Value(queuePosition),
      shuffleActive: Value(shuffleActive),
      sourceContext: Value(sourceContext),
      hourOfDay: Value(hourOfDay),
      dayOfWeek: Value(dayOfWeek),
    );
  }

  factory PlayEventEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayEventEntity(
      playId: serializer.fromJson<String>(json['playId']),
      songId: serializer.fromJson<String>(json['songId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      tsStart: serializer.fromJson<int>(json['tsStart']),
      tsEnd: serializer.fromJson<int?>(json['tsEnd']),
      playDurSec: serializer.fromJson<int>(json['playDurSec']),
      skipBefore50: serializer.fromJson<bool>(json['skipBefore50']),
      skipPositionPct: serializer.fromJson<double?>(json['skipPositionPct']),
      repeatCount: serializer.fromJson<int>(json['repeatCount']),
      queuePosition: serializer.fromJson<int>(json['queuePosition']),
      shuffleActive: serializer.fromJson<bool>(json['shuffleActive']),
      sourceContext: serializer.fromJson<String>(json['sourceContext']),
      hourOfDay: serializer.fromJson<int>(json['hourOfDay']),
      dayOfWeek: serializer.fromJson<int>(json['dayOfWeek']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playId': serializer.toJson<String>(playId),
      'songId': serializer.toJson<String>(songId),
      'sessionId': serializer.toJson<String>(sessionId),
      'tsStart': serializer.toJson<int>(tsStart),
      'tsEnd': serializer.toJson<int?>(tsEnd),
      'playDurSec': serializer.toJson<int>(playDurSec),
      'skipBefore50': serializer.toJson<bool>(skipBefore50),
      'skipPositionPct': serializer.toJson<double?>(skipPositionPct),
      'repeatCount': serializer.toJson<int>(repeatCount),
      'queuePosition': serializer.toJson<int>(queuePosition),
      'shuffleActive': serializer.toJson<bool>(shuffleActive),
      'sourceContext': serializer.toJson<String>(sourceContext),
      'hourOfDay': serializer.toJson<int>(hourOfDay),
      'dayOfWeek': serializer.toJson<int>(dayOfWeek),
    };
  }

  PlayEventEntity copyWith({
    String? playId,
    String? songId,
    String? sessionId,
    int? tsStart,
    Value<int?> tsEnd = const Value.absent(),
    int? playDurSec,
    bool? skipBefore50,
    Value<double?> skipPositionPct = const Value.absent(),
    int? repeatCount,
    int? queuePosition,
    bool? shuffleActive,
    String? sourceContext,
    int? hourOfDay,
    int? dayOfWeek,
  }) => PlayEventEntity(
    playId: playId ?? this.playId,
    songId: songId ?? this.songId,
    sessionId: sessionId ?? this.sessionId,
    tsStart: tsStart ?? this.tsStart,
    tsEnd: tsEnd.present ? tsEnd.value : this.tsEnd,
    playDurSec: playDurSec ?? this.playDurSec,
    skipBefore50: skipBefore50 ?? this.skipBefore50,
    skipPositionPct: skipPositionPct.present
        ? skipPositionPct.value
        : this.skipPositionPct,
    repeatCount: repeatCount ?? this.repeatCount,
    queuePosition: queuePosition ?? this.queuePosition,
    shuffleActive: shuffleActive ?? this.shuffleActive,
    sourceContext: sourceContext ?? this.sourceContext,
    hourOfDay: hourOfDay ?? this.hourOfDay,
    dayOfWeek: dayOfWeek ?? this.dayOfWeek,
  );
  PlayEventEntity copyWithCompanion(PlayEventsCompanion data) {
    return PlayEventEntity(
      playId: data.playId.present ? data.playId.value : this.playId,
      songId: data.songId.present ? data.songId.value : this.songId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      tsStart: data.tsStart.present ? data.tsStart.value : this.tsStart,
      tsEnd: data.tsEnd.present ? data.tsEnd.value : this.tsEnd,
      playDurSec: data.playDurSec.present
          ? data.playDurSec.value
          : this.playDurSec,
      skipBefore50: data.skipBefore50.present
          ? data.skipBefore50.value
          : this.skipBefore50,
      skipPositionPct: data.skipPositionPct.present
          ? data.skipPositionPct.value
          : this.skipPositionPct,
      repeatCount: data.repeatCount.present
          ? data.repeatCount.value
          : this.repeatCount,
      queuePosition: data.queuePosition.present
          ? data.queuePosition.value
          : this.queuePosition,
      shuffleActive: data.shuffleActive.present
          ? data.shuffleActive.value
          : this.shuffleActive,
      sourceContext: data.sourceContext.present
          ? data.sourceContext.value
          : this.sourceContext,
      hourOfDay: data.hourOfDay.present ? data.hourOfDay.value : this.hourOfDay,
      dayOfWeek: data.dayOfWeek.present ? data.dayOfWeek.value : this.dayOfWeek,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayEventEntity(')
          ..write('playId: $playId, ')
          ..write('songId: $songId, ')
          ..write('sessionId: $sessionId, ')
          ..write('tsStart: $tsStart, ')
          ..write('tsEnd: $tsEnd, ')
          ..write('playDurSec: $playDurSec, ')
          ..write('skipBefore50: $skipBefore50, ')
          ..write('skipPositionPct: $skipPositionPct, ')
          ..write('repeatCount: $repeatCount, ')
          ..write('queuePosition: $queuePosition, ')
          ..write('shuffleActive: $shuffleActive, ')
          ..write('sourceContext: $sourceContext, ')
          ..write('hourOfDay: $hourOfDay, ')
          ..write('dayOfWeek: $dayOfWeek')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    playId,
    songId,
    sessionId,
    tsStart,
    tsEnd,
    playDurSec,
    skipBefore50,
    skipPositionPct,
    repeatCount,
    queuePosition,
    shuffleActive,
    sourceContext,
    hourOfDay,
    dayOfWeek,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayEventEntity &&
          other.playId == this.playId &&
          other.songId == this.songId &&
          other.sessionId == this.sessionId &&
          other.tsStart == this.tsStart &&
          other.tsEnd == this.tsEnd &&
          other.playDurSec == this.playDurSec &&
          other.skipBefore50 == this.skipBefore50 &&
          other.skipPositionPct == this.skipPositionPct &&
          other.repeatCount == this.repeatCount &&
          other.queuePosition == this.queuePosition &&
          other.shuffleActive == this.shuffleActive &&
          other.sourceContext == this.sourceContext &&
          other.hourOfDay == this.hourOfDay &&
          other.dayOfWeek == this.dayOfWeek);
}

class PlayEventsCompanion extends UpdateCompanion<PlayEventEntity> {
  final Value<String> playId;
  final Value<String> songId;
  final Value<String> sessionId;
  final Value<int> tsStart;
  final Value<int?> tsEnd;
  final Value<int> playDurSec;
  final Value<bool> skipBefore50;
  final Value<double?> skipPositionPct;
  final Value<int> repeatCount;
  final Value<int> queuePosition;
  final Value<bool> shuffleActive;
  final Value<String> sourceContext;
  final Value<int> hourOfDay;
  final Value<int> dayOfWeek;
  final Value<int> rowid;
  const PlayEventsCompanion({
    this.playId = const Value.absent(),
    this.songId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.tsStart = const Value.absent(),
    this.tsEnd = const Value.absent(),
    this.playDurSec = const Value.absent(),
    this.skipBefore50 = const Value.absent(),
    this.skipPositionPct = const Value.absent(),
    this.repeatCount = const Value.absent(),
    this.queuePosition = const Value.absent(),
    this.shuffleActive = const Value.absent(),
    this.sourceContext = const Value.absent(),
    this.hourOfDay = const Value.absent(),
    this.dayOfWeek = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlayEventsCompanion.insert({
    required String playId,
    required String songId,
    required String sessionId,
    required int tsStart,
    this.tsEnd = const Value.absent(),
    this.playDurSec = const Value.absent(),
    this.skipBefore50 = const Value.absent(),
    this.skipPositionPct = const Value.absent(),
    this.repeatCount = const Value.absent(),
    this.queuePosition = const Value.absent(),
    this.shuffleActive = const Value.absent(),
    required String sourceContext,
    required int hourOfDay,
    required int dayOfWeek,
    this.rowid = const Value.absent(),
  }) : playId = Value(playId),
       songId = Value(songId),
       sessionId = Value(sessionId),
       tsStart = Value(tsStart),
       sourceContext = Value(sourceContext),
       hourOfDay = Value(hourOfDay),
       dayOfWeek = Value(dayOfWeek);
  static Insertable<PlayEventEntity> custom({
    Expression<String>? playId,
    Expression<String>? songId,
    Expression<String>? sessionId,
    Expression<int>? tsStart,
    Expression<int>? tsEnd,
    Expression<int>? playDurSec,
    Expression<bool>? skipBefore50,
    Expression<double>? skipPositionPct,
    Expression<int>? repeatCount,
    Expression<int>? queuePosition,
    Expression<bool>? shuffleActive,
    Expression<String>? sourceContext,
    Expression<int>? hourOfDay,
    Expression<int>? dayOfWeek,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playId != null) 'play_id': playId,
      if (songId != null) 'song_id': songId,
      if (sessionId != null) 'session_id': sessionId,
      if (tsStart != null) 'ts_start': tsStart,
      if (tsEnd != null) 'ts_end': tsEnd,
      if (playDurSec != null) 'play_dur_sec': playDurSec,
      if (skipBefore50 != null) 'skip_before50': skipBefore50,
      if (skipPositionPct != null) 'skip_position_pct': skipPositionPct,
      if (repeatCount != null) 'repeat_count': repeatCount,
      if (queuePosition != null) 'queue_position': queuePosition,
      if (shuffleActive != null) 'shuffle_active': shuffleActive,
      if (sourceContext != null) 'source_context': sourceContext,
      if (hourOfDay != null) 'hour_of_day': hourOfDay,
      if (dayOfWeek != null) 'day_of_week': dayOfWeek,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlayEventsCompanion copyWith({
    Value<String>? playId,
    Value<String>? songId,
    Value<String>? sessionId,
    Value<int>? tsStart,
    Value<int?>? tsEnd,
    Value<int>? playDurSec,
    Value<bool>? skipBefore50,
    Value<double?>? skipPositionPct,
    Value<int>? repeatCount,
    Value<int>? queuePosition,
    Value<bool>? shuffleActive,
    Value<String>? sourceContext,
    Value<int>? hourOfDay,
    Value<int>? dayOfWeek,
    Value<int>? rowid,
  }) {
    return PlayEventsCompanion(
      playId: playId ?? this.playId,
      songId: songId ?? this.songId,
      sessionId: sessionId ?? this.sessionId,
      tsStart: tsStart ?? this.tsStart,
      tsEnd: tsEnd ?? this.tsEnd,
      playDurSec: playDurSec ?? this.playDurSec,
      skipBefore50: skipBefore50 ?? this.skipBefore50,
      skipPositionPct: skipPositionPct ?? this.skipPositionPct,
      repeatCount: repeatCount ?? this.repeatCount,
      queuePosition: queuePosition ?? this.queuePosition,
      shuffleActive: shuffleActive ?? this.shuffleActive,
      sourceContext: sourceContext ?? this.sourceContext,
      hourOfDay: hourOfDay ?? this.hourOfDay,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playId.present) {
      map['play_id'] = Variable<String>(playId.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (tsStart.present) {
      map['ts_start'] = Variable<int>(tsStart.value);
    }
    if (tsEnd.present) {
      map['ts_end'] = Variable<int>(tsEnd.value);
    }
    if (playDurSec.present) {
      map['play_dur_sec'] = Variable<int>(playDurSec.value);
    }
    if (skipBefore50.present) {
      map['skip_before50'] = Variable<bool>(skipBefore50.value);
    }
    if (skipPositionPct.present) {
      map['skip_position_pct'] = Variable<double>(skipPositionPct.value);
    }
    if (repeatCount.present) {
      map['repeat_count'] = Variable<int>(repeatCount.value);
    }
    if (queuePosition.present) {
      map['queue_position'] = Variable<int>(queuePosition.value);
    }
    if (shuffleActive.present) {
      map['shuffle_active'] = Variable<bool>(shuffleActive.value);
    }
    if (sourceContext.present) {
      map['source_context'] = Variable<String>(sourceContext.value);
    }
    if (hourOfDay.present) {
      map['hour_of_day'] = Variable<int>(hourOfDay.value);
    }
    if (dayOfWeek.present) {
      map['day_of_week'] = Variable<int>(dayOfWeek.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayEventsCompanion(')
          ..write('playId: $playId, ')
          ..write('songId: $songId, ')
          ..write('sessionId: $sessionId, ')
          ..write('tsStart: $tsStart, ')
          ..write('tsEnd: $tsEnd, ')
          ..write('playDurSec: $playDurSec, ')
          ..write('skipBefore50: $skipBefore50, ')
          ..write('skipPositionPct: $skipPositionPct, ')
          ..write('repeatCount: $repeatCount, ')
          ..write('queuePosition: $queuePosition, ')
          ..write('shuffleActive: $shuffleActive, ')
          ..write('sourceContext: $sourceContext, ')
          ..write('hourOfDay: $hourOfDay, ')
          ..write('dayOfWeek: $dayOfWeek, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SongMetadataTable extends SongMetadata
    with TableInfo<$SongMetadataTable, SongMetadataEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackNameMeta = const VerificationMeta(
    'trackName',
  );
  @override
  late final GeneratedColumn<String> trackName = GeneratedColumn<String>(
    'track_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistNameMeta = const VerificationMeta(
    'artistName',
  );
  @override
  late final GeneratedColumn<String> artistName = GeneratedColumn<String>(
    'artist_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumNameMeta = const VerificationMeta(
    'albumName',
  );
  @override
  late final GeneratedColumn<String> albumName = GeneratedColumn<String>(
    'album_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _composerMeta = const VerificationMeta(
    'composer',
  );
  @override
  late final GeneratedColumn<String> composer = GeneratedColumn<String>(
    'composer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
    'duration_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _starredMeta = const VerificationMeta(
    'starred',
  );
  @override
  late final GeneratedColumn<bool> starred = GeneratedColumn<bool>(
    'starred',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("starred" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    songId,
    trackName,
    artistName,
    albumName,
    genre,
    composer,
    durationSec,
    year,
    playCount,
    rating,
    starred,
    updatedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'song_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<SongMetadataEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('track_name')) {
      context.handle(
        _trackNameMeta,
        trackName.isAcceptableOrUnknown(data['track_name']!, _trackNameMeta),
      );
    } else if (isInserting) {
      context.missing(_trackNameMeta);
    }
    if (data.containsKey('artist_name')) {
      context.handle(
        _artistNameMeta,
        artistName.isAcceptableOrUnknown(data['artist_name']!, _artistNameMeta),
      );
    } else if (isInserting) {
      context.missing(_artistNameMeta);
    }
    if (data.containsKey('album_name')) {
      context.handle(
        _albumNameMeta,
        albumName.isAcceptableOrUnknown(data['album_name']!, _albumNameMeta),
      );
    } else if (isInserting) {
      context.missing(_albumNameMeta);
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('composer')) {
      context.handle(
        _composerMeta,
        composer.isAcceptableOrUnknown(data['composer']!, _composerMeta),
      );
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('starred')) {
      context.handle(
        _starredMeta,
        starred.isAcceptableOrUnknown(data['starred']!, _starredMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {songId};
  @override
  SongMetadataEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongMetadataEntity(
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      trackName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_name'],
      )!,
      artistName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_name'],
      )!,
      albumName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_name'],
      )!,
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      composer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}composer'],
      ),
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_sec'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      )!,
      starred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}starred'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      ),
    );
  }

  @override
  $SongMetadataTable createAlias(String alias) {
    return $SongMetadataTable(attachedDatabase, alias);
  }
}

class SongMetadataEntity extends DataClass
    implements Insertable<SongMetadataEntity> {
  final String songId;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? genre;
  final String? composer;
  final int durationSec;
  final int? year;
  final int playCount;
  final int rating;
  final bool starred;
  final int updatedAt;
  final int? createdAt;
  const SongMetadataEntity({
    required this.songId,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.genre,
    this.composer,
    required this.durationSec,
    this.year,
    required this.playCount,
    required this.rating,
    required this.starred,
    required this.updatedAt,
    this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['song_id'] = Variable<String>(songId);
    map['track_name'] = Variable<String>(trackName);
    map['artist_name'] = Variable<String>(artistName);
    map['album_name'] = Variable<String>(albumName);
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || composer != null) {
      map['composer'] = Variable<String>(composer);
    }
    map['duration_sec'] = Variable<int>(durationSec);
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    map['play_count'] = Variable<int>(playCount);
    map['rating'] = Variable<int>(rating);
    map['starred'] = Variable<bool>(starred);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<int>(createdAt);
    }
    return map;
  }

  SongMetadataCompanion toCompanion(bool nullToAbsent) {
    return SongMetadataCompanion(
      songId: Value(songId),
      trackName: Value(trackName),
      artistName: Value(artistName),
      albumName: Value(albumName),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      composer: composer == null && nullToAbsent
          ? const Value.absent()
          : Value(composer),
      durationSec: Value(durationSec),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      playCount: Value(playCount),
      rating: Value(rating),
      starred: Value(starred),
      updatedAt: Value(updatedAt),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
    );
  }

  factory SongMetadataEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SongMetadataEntity(
      songId: serializer.fromJson<String>(json['songId']),
      trackName: serializer.fromJson<String>(json['trackName']),
      artistName: serializer.fromJson<String>(json['artistName']),
      albumName: serializer.fromJson<String>(json['albumName']),
      genre: serializer.fromJson<String?>(json['genre']),
      composer: serializer.fromJson<String?>(json['composer']),
      durationSec: serializer.fromJson<int>(json['durationSec']),
      year: serializer.fromJson<int?>(json['year']),
      playCount: serializer.fromJson<int>(json['playCount']),
      rating: serializer.fromJson<int>(json['rating']),
      starred: serializer.fromJson<bool>(json['starred']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      createdAt: serializer.fromJson<int?>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'songId': serializer.toJson<String>(songId),
      'trackName': serializer.toJson<String>(trackName),
      'artistName': serializer.toJson<String>(artistName),
      'albumName': serializer.toJson<String>(albumName),
      'genre': serializer.toJson<String?>(genre),
      'composer': serializer.toJson<String?>(composer),
      'durationSec': serializer.toJson<int>(durationSec),
      'year': serializer.toJson<int?>(year),
      'playCount': serializer.toJson<int>(playCount),
      'rating': serializer.toJson<int>(rating),
      'starred': serializer.toJson<bool>(starred),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'createdAt': serializer.toJson<int?>(createdAt),
    };
  }

  SongMetadataEntity copyWith({
    String? songId,
    String? trackName,
    String? artistName,
    String? albumName,
    Value<String?> genre = const Value.absent(),
    Value<String?> composer = const Value.absent(),
    int? durationSec,
    Value<int?> year = const Value.absent(),
    int? playCount,
    int? rating,
    bool? starred,
    int? updatedAt,
    Value<int?> createdAt = const Value.absent(),
  }) => SongMetadataEntity(
    songId: songId ?? this.songId,
    trackName: trackName ?? this.trackName,
    artistName: artistName ?? this.artistName,
    albumName: albumName ?? this.albumName,
    genre: genre.present ? genre.value : this.genre,
    composer: composer.present ? composer.value : this.composer,
    durationSec: durationSec ?? this.durationSec,
    year: year.present ? year.value : this.year,
    playCount: playCount ?? this.playCount,
    rating: rating ?? this.rating,
    starred: starred ?? this.starred,
    updatedAt: updatedAt ?? this.updatedAt,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
  );
  SongMetadataEntity copyWithCompanion(SongMetadataCompanion data) {
    return SongMetadataEntity(
      songId: data.songId.present ? data.songId.value : this.songId,
      trackName: data.trackName.present ? data.trackName.value : this.trackName,
      artistName: data.artistName.present
          ? data.artistName.value
          : this.artistName,
      albumName: data.albumName.present ? data.albumName.value : this.albumName,
      genre: data.genre.present ? data.genre.value : this.genre,
      composer: data.composer.present ? data.composer.value : this.composer,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      year: data.year.present ? data.year.value : this.year,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      rating: data.rating.present ? data.rating.value : this.rating,
      starred: data.starred.present ? data.starred.value : this.starred,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SongMetadataEntity(')
          ..write('songId: $songId, ')
          ..write('trackName: $trackName, ')
          ..write('artistName: $artistName, ')
          ..write('albumName: $albumName, ')
          ..write('genre: $genre, ')
          ..write('composer: $composer, ')
          ..write('durationSec: $durationSec, ')
          ..write('year: $year, ')
          ..write('playCount: $playCount, ')
          ..write('rating: $rating, ')
          ..write('starred: $starred, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    songId,
    trackName,
    artistName,
    albumName,
    genre,
    composer,
    durationSec,
    year,
    playCount,
    rating,
    starred,
    updatedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SongMetadataEntity &&
          other.songId == this.songId &&
          other.trackName == this.trackName &&
          other.artistName == this.artistName &&
          other.albumName == this.albumName &&
          other.genre == this.genre &&
          other.composer == this.composer &&
          other.durationSec == this.durationSec &&
          other.year == this.year &&
          other.playCount == this.playCount &&
          other.rating == this.rating &&
          other.starred == this.starred &&
          other.updatedAt == this.updatedAt &&
          other.createdAt == this.createdAt);
}

class SongMetadataCompanion extends UpdateCompanion<SongMetadataEntity> {
  final Value<String> songId;
  final Value<String> trackName;
  final Value<String> artistName;
  final Value<String> albumName;
  final Value<String?> genre;
  final Value<String?> composer;
  final Value<int> durationSec;
  final Value<int?> year;
  final Value<int> playCount;
  final Value<int> rating;
  final Value<bool> starred;
  final Value<int> updatedAt;
  final Value<int?> createdAt;
  final Value<int> rowid;
  const SongMetadataCompanion({
    this.songId = const Value.absent(),
    this.trackName = const Value.absent(),
    this.artistName = const Value.absent(),
    this.albumName = const Value.absent(),
    this.genre = const Value.absent(),
    this.composer = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.year = const Value.absent(),
    this.playCount = const Value.absent(),
    this.rating = const Value.absent(),
    this.starred = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SongMetadataCompanion.insert({
    required String songId,
    required String trackName,
    required String artistName,
    required String albumName,
    this.genre = const Value.absent(),
    this.composer = const Value.absent(),
    required int durationSec,
    this.year = const Value.absent(),
    this.playCount = const Value.absent(),
    this.rating = const Value.absent(),
    this.starred = const Value.absent(),
    required int updatedAt,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : songId = Value(songId),
       trackName = Value(trackName),
       artistName = Value(artistName),
       albumName = Value(albumName),
       durationSec = Value(durationSec),
       updatedAt = Value(updatedAt);
  static Insertable<SongMetadataEntity> custom({
    Expression<String>? songId,
    Expression<String>? trackName,
    Expression<String>? artistName,
    Expression<String>? albumName,
    Expression<String>? genre,
    Expression<String>? composer,
    Expression<int>? durationSec,
    Expression<int>? year,
    Expression<int>? playCount,
    Expression<int>? rating,
    Expression<bool>? starred,
    Expression<int>? updatedAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (songId != null) 'song_id': songId,
      if (trackName != null) 'track_name': trackName,
      if (artistName != null) 'artist_name': artistName,
      if (albumName != null) 'album_name': albumName,
      if (genre != null) 'genre': genre,
      if (composer != null) 'composer': composer,
      if (durationSec != null) 'duration_sec': durationSec,
      if (year != null) 'year': year,
      if (playCount != null) 'play_count': playCount,
      if (rating != null) 'rating': rating,
      if (starred != null) 'starred': starred,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SongMetadataCompanion copyWith({
    Value<String>? songId,
    Value<String>? trackName,
    Value<String>? artistName,
    Value<String>? albumName,
    Value<String?>? genre,
    Value<String?>? composer,
    Value<int>? durationSec,
    Value<int?>? year,
    Value<int>? playCount,
    Value<int>? rating,
    Value<bool>? starred,
    Value<int>? updatedAt,
    Value<int?>? createdAt,
    Value<int>? rowid,
  }) {
    return SongMetadataCompanion(
      songId: songId ?? this.songId,
      trackName: trackName ?? this.trackName,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      genre: genre ?? this.genre,
      composer: composer ?? this.composer,
      durationSec: durationSec ?? this.durationSec,
      year: year ?? this.year,
      playCount: playCount ?? this.playCount,
      rating: rating ?? this.rating,
      starred: starred ?? this.starred,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (trackName.present) {
      map['track_name'] = Variable<String>(trackName.value);
    }
    if (artistName.present) {
      map['artist_name'] = Variable<String>(artistName.value);
    }
    if (albumName.present) {
      map['album_name'] = Variable<String>(albumName.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (composer.present) {
      map['composer'] = Variable<String>(composer.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (starred.present) {
      map['starred'] = Variable<bool>(starred.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongMetadataCompanion(')
          ..write('songId: $songId, ')
          ..write('trackName: $trackName, ')
          ..write('artistName: $artistName, ')
          ..write('albumName: $albumName, ')
          ..write('genre: $genre, ')
          ..write('composer: $composer, ')
          ..write('durationSec: $durationSec, ')
          ..write('year: $year, ')
          ..write('playCount: $playCount, ')
          ..write('rating: $rating, ')
          ..write('starred: $starred, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistCacheTable extends PlaylistCache
    with TableInfo<$PlaylistCacheTable, PlaylistCacheEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _songJsonMeta = const VerificationMeta(
    'songJson',
  );
  @override
  late final GeneratedColumn<String> songJson = GeneratedColumn<String>(
    'song_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    playlistId,
    position,
    songJson,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistCacheEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('song_json')) {
      context.handle(
        _songJsonMeta,
        songJson.isAcceptableOrUnknown(data['song_json']!, _songJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_songJsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playlistId, position};
  @override
  PlaylistCacheEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistCacheEntity(
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      songJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_json'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $PlaylistCacheTable createAlias(String alias) {
    return $PlaylistCacheTable(attachedDatabase, alias);
  }
}

class PlaylistCacheEntity extends DataClass
    implements Insertable<PlaylistCacheEntity> {
  final String playlistId;
  final int position;
  final String songJson;
  final int cachedAt;
  const PlaylistCacheEntity({
    required this.playlistId,
    required this.position,
    required this.songJson,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<String>(playlistId);
    map['position'] = Variable<int>(position);
    map['song_json'] = Variable<String>(songJson);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  PlaylistCacheCompanion toCompanion(bool nullToAbsent) {
    return PlaylistCacheCompanion(
      playlistId: Value(playlistId),
      position: Value(position),
      songJson: Value(songJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory PlaylistCacheEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistCacheEntity(
      playlistId: serializer.fromJson<String>(json['playlistId']),
      position: serializer.fromJson<int>(json['position']),
      songJson: serializer.fromJson<String>(json['songJson']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<String>(playlistId),
      'position': serializer.toJson<int>(position),
      'songJson': serializer.toJson<String>(songJson),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  PlaylistCacheEntity copyWith({
    String? playlistId,
    int? position,
    String? songJson,
    int? cachedAt,
  }) => PlaylistCacheEntity(
    playlistId: playlistId ?? this.playlistId,
    position: position ?? this.position,
    songJson: songJson ?? this.songJson,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  PlaylistCacheEntity copyWithCompanion(PlaylistCacheCompanion data) {
    return PlaylistCacheEntity(
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      position: data.position.present ? data.position.value : this.position,
      songJson: data.songJson.present ? data.songJson.value : this.songJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistCacheEntity(')
          ..write('playlistId: $playlistId, ')
          ..write('position: $position, ')
          ..write('songJson: $songJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(playlistId, position, songJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistCacheEntity &&
          other.playlistId == this.playlistId &&
          other.position == this.position &&
          other.songJson == this.songJson &&
          other.cachedAt == this.cachedAt);
}

class PlaylistCacheCompanion extends UpdateCompanion<PlaylistCacheEntity> {
  final Value<String> playlistId;
  final Value<int> position;
  final Value<String> songJson;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const PlaylistCacheCompanion({
    this.playlistId = const Value.absent(),
    this.position = const Value.absent(),
    this.songJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistCacheCompanion.insert({
    required String playlistId,
    required int position,
    required String songJson,
    required int cachedAt,
    this.rowid = const Value.absent(),
  }) : playlistId = Value(playlistId),
       position = Value(position),
       songJson = Value(songJson),
       cachedAt = Value(cachedAt);
  static Insertable<PlaylistCacheEntity> custom({
    Expression<String>? playlistId,
    Expression<int>? position,
    Expression<String>? songJson,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (position != null) 'position': position,
      if (songJson != null) 'song_json': songJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistCacheCompanion copyWith({
    Value<String>? playlistId,
    Value<int>? position,
    Value<String>? songJson,
    Value<int>? cachedAt,
    Value<int>? rowid,
  }) {
    return PlaylistCacheCompanion(
      playlistId: playlistId ?? this.playlistId,
      position: position ?? this.position,
      songJson: songJson ?? this.songJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (songJson.present) {
      map['song_json'] = Variable<String>(songJson.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistCacheCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('position: $position, ')
          ..write('songJson: $songJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSongsTable extends LocalSongs
    with TableInfo<$LocalSongsTable, LocalSongEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumArtistMeta = const VerificationMeta(
    'albumArtist',
  );
  @override
  late final GeneratedColumn<String> albumArtist = GeneratedColumn<String>(
    'album_artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _trackMeta = const VerificationMeta('track');
  @override
  late final GeneratedColumn<int> track = GeneratedColumn<int>(
    'track',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _discMeta = const VerificationMeta('disc');
  @override
  late final GeneratedColumn<int> disc = GeneratedColumn<int>(
    'disc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
    'duration_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bitRateMeta = const VerificationMeta(
    'bitRate',
  );
  @override
  late final GeneratedColumn<int> bitRate = GeneratedColumn<int>(
    'bit_rate',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _suffixMeta = const VerificationMeta('suffix');
  @override
  late final GeneratedColumn<String> suffix = GeneratedColumn<String>(
    'suffix',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _trackGainMeta = const VerificationMeta(
    'trackGain',
  );
  @override
  late final GeneratedColumn<double> trackGain = GeneratedColumn<double>(
    'track_gain',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumGainMeta = const VerificationMeta(
    'albumGain',
  );
  @override
  late final GeneratedColumn<double> albumGain = GeneratedColumn<double>(
    'album_gain',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackPeakMeta = const VerificationMeta(
    'trackPeak',
  );
  @override
  late final GeneratedColumn<double> trackPeak = GeneratedColumn<double>(
    'track_peak',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumPeakMeta = const VerificationMeta(
    'albumPeak',
  );
  @override
  late final GeneratedColumn<double> albumPeak = GeneratedColumn<double>(
    'album_peak',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lyricsMeta = const VerificationMeta('lyrics');
  @override
  late final GeneratedColumn<String> lyrics = GeneratedColumn<String>(
    'lyrics',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    songId,
    path,
    folderId,
    fingerprint,
    title,
    artist,
    album,
    albumArtist,
    genre,
    track,
    disc,
    year,
    durationSec,
    bitRate,
    suffix,
    trackGain,
    albumGain,
    trackPeak,
    albumPeak,
    coverPath,
    lyrics,
    serverId,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSongEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_folderIdMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    } else if (isInserting) {
      context.missing(_albumMeta);
    }
    if (data.containsKey('album_artist')) {
      context.handle(
        _albumArtistMeta,
        albumArtist.isAcceptableOrUnknown(
          data['album_artist']!,
          _albumArtistMeta,
        ),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('track')) {
      context.handle(
        _trackMeta,
        track.isAcceptableOrUnknown(data['track']!, _trackMeta),
      );
    }
    if (data.containsKey('disc')) {
      context.handle(
        _discMeta,
        disc.isAcceptableOrUnknown(data['disc']!, _discMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
        ),
      );
    }
    if (data.containsKey('bit_rate')) {
      context.handle(
        _bitRateMeta,
        bitRate.isAcceptableOrUnknown(data['bit_rate']!, _bitRateMeta),
      );
    }
    if (data.containsKey('suffix')) {
      context.handle(
        _suffixMeta,
        suffix.isAcceptableOrUnknown(data['suffix']!, _suffixMeta),
      );
    }
    if (data.containsKey('track_gain')) {
      context.handle(
        _trackGainMeta,
        trackGain.isAcceptableOrUnknown(data['track_gain']!, _trackGainMeta),
      );
    }
    if (data.containsKey('album_gain')) {
      context.handle(
        _albumGainMeta,
        albumGain.isAcceptableOrUnknown(data['album_gain']!, _albumGainMeta),
      );
    }
    if (data.containsKey('track_peak')) {
      context.handle(
        _trackPeakMeta,
        trackPeak.isAcceptableOrUnknown(data['track_peak']!, _trackPeakMeta),
      );
    }
    if (data.containsKey('album_peak')) {
      context.handle(
        _albumPeakMeta,
        albumPeak.isAcceptableOrUnknown(data['album_peak']!, _albumPeakMeta),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('lyrics')) {
      context.handle(
        _lyricsMeta,
        lyrics.isAcceptableOrUnknown(data['lyrics']!, _lyricsMeta),
      );
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {songId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {path},
  ];
  @override
  LocalSongEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSongEntity(
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      )!,
      albumArtist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_artist'],
      )!,
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      )!,
      track: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track'],
      )!,
      disc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disc'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      )!,
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_sec'],
      )!,
      bitRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bit_rate'],
      )!,
      suffix: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suffix'],
      )!,
      trackGain: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}track_gain'],
      ),
      albumGain: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}album_gain'],
      ),
      trackPeak: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}track_peak'],
      ),
      albumPeak: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}album_peak'],
      ),
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      lyrics: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lyrics'],
      ),
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $LocalSongsTable createAlias(String alias) {
    return $LocalSongsTable(attachedDatabase, alias);
  }
}

class LocalSongEntity extends DataClass implements Insertable<LocalSongEntity> {
  final String songId;

  /// Absolute path (desktop, Android file paths) or a `content://` document
  /// URI (Android folders picked through the Storage Access Framework).
  final String path;

  /// The added folder this file was found under.
  final String folderId;

  /// Size, modified time and sidecar times of the file when it was read.
  /// A rescan re-reads a file only when this changes.
  final String fingerprint;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final int track;
  final int disc;
  final int year;
  final int durationSec;
  final int bitRate;
  final String suffix;
  final double? trackGain;
  final double? albumGain;
  final double? trackPeak;
  final double? albumPeak;

  /// Cover extracted from the tags (or a folder.jpg beside the file), saved
  /// under the app's support folder. Null when the file has none.
  final String? coverPath;

  /// Text of the sidecar `.lrc` (or the tag's lyrics); read at scan time so
  /// playback never touches the folder again.
  final String? lyrics;

  /// Server song this file is a copy of (title + artist + duration match).
  final String? serverId;
  final int addedAt;
  const LocalSongEntity({
    required this.songId,
    required this.path,
    required this.folderId,
    required this.fingerprint,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.genre,
    required this.track,
    required this.disc,
    required this.year,
    required this.durationSec,
    required this.bitRate,
    required this.suffix,
    this.trackGain,
    this.albumGain,
    this.trackPeak,
    this.albumPeak,
    this.coverPath,
    this.lyrics,
    this.serverId,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['song_id'] = Variable<String>(songId);
    map['path'] = Variable<String>(path);
    map['folder_id'] = Variable<String>(folderId);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    map['album'] = Variable<String>(album);
    map['album_artist'] = Variable<String>(albumArtist);
    map['genre'] = Variable<String>(genre);
    map['track'] = Variable<int>(track);
    map['disc'] = Variable<int>(disc);
    map['year'] = Variable<int>(year);
    map['duration_sec'] = Variable<int>(durationSec);
    map['bit_rate'] = Variable<int>(bitRate);
    map['suffix'] = Variable<String>(suffix);
    if (!nullToAbsent || trackGain != null) {
      map['track_gain'] = Variable<double>(trackGain);
    }
    if (!nullToAbsent || albumGain != null) {
      map['album_gain'] = Variable<double>(albumGain);
    }
    if (!nullToAbsent || trackPeak != null) {
      map['track_peak'] = Variable<double>(trackPeak);
    }
    if (!nullToAbsent || albumPeak != null) {
      map['album_peak'] = Variable<double>(albumPeak);
    }
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    if (!nullToAbsent || lyrics != null) {
      map['lyrics'] = Variable<String>(lyrics);
    }
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  LocalSongsCompanion toCompanion(bool nullToAbsent) {
    return LocalSongsCompanion(
      songId: Value(songId),
      path: Value(path),
      folderId: Value(folderId),
      fingerprint: Value(fingerprint),
      title: Value(title),
      artist: Value(artist),
      album: Value(album),
      albumArtist: Value(albumArtist),
      genre: Value(genre),
      track: Value(track),
      disc: Value(disc),
      year: Value(year),
      durationSec: Value(durationSec),
      bitRate: Value(bitRate),
      suffix: Value(suffix),
      trackGain: trackGain == null && nullToAbsent
          ? const Value.absent()
          : Value(trackGain),
      albumGain: albumGain == null && nullToAbsent
          ? const Value.absent()
          : Value(albumGain),
      trackPeak: trackPeak == null && nullToAbsent
          ? const Value.absent()
          : Value(trackPeak),
      albumPeak: albumPeak == null && nullToAbsent
          ? const Value.absent()
          : Value(albumPeak),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      lyrics: lyrics == null && nullToAbsent
          ? const Value.absent()
          : Value(lyrics),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      addedAt: Value(addedAt),
    );
  }

  factory LocalSongEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSongEntity(
      songId: serializer.fromJson<String>(json['songId']),
      path: serializer.fromJson<String>(json['path']),
      folderId: serializer.fromJson<String>(json['folderId']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String>(json['album']),
      albumArtist: serializer.fromJson<String>(json['albumArtist']),
      genre: serializer.fromJson<String>(json['genre']),
      track: serializer.fromJson<int>(json['track']),
      disc: serializer.fromJson<int>(json['disc']),
      year: serializer.fromJson<int>(json['year']),
      durationSec: serializer.fromJson<int>(json['durationSec']),
      bitRate: serializer.fromJson<int>(json['bitRate']),
      suffix: serializer.fromJson<String>(json['suffix']),
      trackGain: serializer.fromJson<double?>(json['trackGain']),
      albumGain: serializer.fromJson<double?>(json['albumGain']),
      trackPeak: serializer.fromJson<double?>(json['trackPeak']),
      albumPeak: serializer.fromJson<double?>(json['albumPeak']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      lyrics: serializer.fromJson<String?>(json['lyrics']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'songId': serializer.toJson<String>(songId),
      'path': serializer.toJson<String>(path),
      'folderId': serializer.toJson<String>(folderId),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String>(album),
      'albumArtist': serializer.toJson<String>(albumArtist),
      'genre': serializer.toJson<String>(genre),
      'track': serializer.toJson<int>(track),
      'disc': serializer.toJson<int>(disc),
      'year': serializer.toJson<int>(year),
      'durationSec': serializer.toJson<int>(durationSec),
      'bitRate': serializer.toJson<int>(bitRate),
      'suffix': serializer.toJson<String>(suffix),
      'trackGain': serializer.toJson<double?>(trackGain),
      'albumGain': serializer.toJson<double?>(albumGain),
      'trackPeak': serializer.toJson<double?>(trackPeak),
      'albumPeak': serializer.toJson<double?>(albumPeak),
      'coverPath': serializer.toJson<String?>(coverPath),
      'lyrics': serializer.toJson<String?>(lyrics),
      'serverId': serializer.toJson<String?>(serverId),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  LocalSongEntity copyWith({
    String? songId,
    String? path,
    String? folderId,
    String? fingerprint,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    int? track,
    int? disc,
    int? year,
    int? durationSec,
    int? bitRate,
    String? suffix,
    Value<double?> trackGain = const Value.absent(),
    Value<double?> albumGain = const Value.absent(),
    Value<double?> trackPeak = const Value.absent(),
    Value<double?> albumPeak = const Value.absent(),
    Value<String?> coverPath = const Value.absent(),
    Value<String?> lyrics = const Value.absent(),
    Value<String?> serverId = const Value.absent(),
    int? addedAt,
  }) => LocalSongEntity(
    songId: songId ?? this.songId,
    path: path ?? this.path,
    folderId: folderId ?? this.folderId,
    fingerprint: fingerprint ?? this.fingerprint,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    albumArtist: albumArtist ?? this.albumArtist,
    genre: genre ?? this.genre,
    track: track ?? this.track,
    disc: disc ?? this.disc,
    year: year ?? this.year,
    durationSec: durationSec ?? this.durationSec,
    bitRate: bitRate ?? this.bitRate,
    suffix: suffix ?? this.suffix,
    trackGain: trackGain.present ? trackGain.value : this.trackGain,
    albumGain: albumGain.present ? albumGain.value : this.albumGain,
    trackPeak: trackPeak.present ? trackPeak.value : this.trackPeak,
    albumPeak: albumPeak.present ? albumPeak.value : this.albumPeak,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    lyrics: lyrics.present ? lyrics.value : this.lyrics,
    serverId: serverId.present ? serverId.value : this.serverId,
    addedAt: addedAt ?? this.addedAt,
  );
  LocalSongEntity copyWithCompanion(LocalSongsCompanion data) {
    return LocalSongEntity(
      songId: data.songId.present ? data.songId.value : this.songId,
      path: data.path.present ? data.path.value : this.path,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      albumArtist: data.albumArtist.present
          ? data.albumArtist.value
          : this.albumArtist,
      genre: data.genre.present ? data.genre.value : this.genre,
      track: data.track.present ? data.track.value : this.track,
      disc: data.disc.present ? data.disc.value : this.disc,
      year: data.year.present ? data.year.value : this.year,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      bitRate: data.bitRate.present ? data.bitRate.value : this.bitRate,
      suffix: data.suffix.present ? data.suffix.value : this.suffix,
      trackGain: data.trackGain.present ? data.trackGain.value : this.trackGain,
      albumGain: data.albumGain.present ? data.albumGain.value : this.albumGain,
      trackPeak: data.trackPeak.present ? data.trackPeak.value : this.trackPeak,
      albumPeak: data.albumPeak.present ? data.albumPeak.value : this.albumPeak,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      lyrics: data.lyrics.present ? data.lyrics.value : this.lyrics,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSongEntity(')
          ..write('songId: $songId, ')
          ..write('path: $path, ')
          ..write('folderId: $folderId, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('genre: $genre, ')
          ..write('track: $track, ')
          ..write('disc: $disc, ')
          ..write('year: $year, ')
          ..write('durationSec: $durationSec, ')
          ..write('bitRate: $bitRate, ')
          ..write('suffix: $suffix, ')
          ..write('trackGain: $trackGain, ')
          ..write('albumGain: $albumGain, ')
          ..write('trackPeak: $trackPeak, ')
          ..write('albumPeak: $albumPeak, ')
          ..write('coverPath: $coverPath, ')
          ..write('lyrics: $lyrics, ')
          ..write('serverId: $serverId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    songId,
    path,
    folderId,
    fingerprint,
    title,
    artist,
    album,
    albumArtist,
    genre,
    track,
    disc,
    year,
    durationSec,
    bitRate,
    suffix,
    trackGain,
    albumGain,
    trackPeak,
    albumPeak,
    coverPath,
    lyrics,
    serverId,
    addedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSongEntity &&
          other.songId == this.songId &&
          other.path == this.path &&
          other.folderId == this.folderId &&
          other.fingerprint == this.fingerprint &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.albumArtist == this.albumArtist &&
          other.genre == this.genre &&
          other.track == this.track &&
          other.disc == this.disc &&
          other.year == this.year &&
          other.durationSec == this.durationSec &&
          other.bitRate == this.bitRate &&
          other.suffix == this.suffix &&
          other.trackGain == this.trackGain &&
          other.albumGain == this.albumGain &&
          other.trackPeak == this.trackPeak &&
          other.albumPeak == this.albumPeak &&
          other.coverPath == this.coverPath &&
          other.lyrics == this.lyrics &&
          other.serverId == this.serverId &&
          other.addedAt == this.addedAt);
}

class LocalSongsCompanion extends UpdateCompanion<LocalSongEntity> {
  final Value<String> songId;
  final Value<String> path;
  final Value<String> folderId;
  final Value<String> fingerprint;
  final Value<String> title;
  final Value<String> artist;
  final Value<String> album;
  final Value<String> albumArtist;
  final Value<String> genre;
  final Value<int> track;
  final Value<int> disc;
  final Value<int> year;
  final Value<int> durationSec;
  final Value<int> bitRate;
  final Value<String> suffix;
  final Value<double?> trackGain;
  final Value<double?> albumGain;
  final Value<double?> trackPeak;
  final Value<double?> albumPeak;
  final Value<String?> coverPath;
  final Value<String?> lyrics;
  final Value<String?> serverId;
  final Value<int> addedAt;
  final Value<int> rowid;
  const LocalSongsCompanion({
    this.songId = const Value.absent(),
    this.path = const Value.absent(),
    this.folderId = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.genre = const Value.absent(),
    this.track = const Value.absent(),
    this.disc = const Value.absent(),
    this.year = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.bitRate = const Value.absent(),
    this.suffix = const Value.absent(),
    this.trackGain = const Value.absent(),
    this.albumGain = const Value.absent(),
    this.trackPeak = const Value.absent(),
    this.albumPeak = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.lyrics = const Value.absent(),
    this.serverId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSongsCompanion.insert({
    required String songId,
    required String path,
    required String folderId,
    required String fingerprint,
    required String title,
    required String artist,
    required String album,
    this.albumArtist = const Value.absent(),
    this.genre = const Value.absent(),
    this.track = const Value.absent(),
    this.disc = const Value.absent(),
    this.year = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.bitRate = const Value.absent(),
    this.suffix = const Value.absent(),
    this.trackGain = const Value.absent(),
    this.albumGain = const Value.absent(),
    this.trackPeak = const Value.absent(),
    this.albumPeak = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.lyrics = const Value.absent(),
    this.serverId = const Value.absent(),
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : songId = Value(songId),
       path = Value(path),
       folderId = Value(folderId),
       fingerprint = Value(fingerprint),
       title = Value(title),
       artist = Value(artist),
       album = Value(album),
       addedAt = Value(addedAt);
  static Insertable<LocalSongEntity> custom({
    Expression<String>? songId,
    Expression<String>? path,
    Expression<String>? folderId,
    Expression<String>? fingerprint,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? albumArtist,
    Expression<String>? genre,
    Expression<int>? track,
    Expression<int>? disc,
    Expression<int>? year,
    Expression<int>? durationSec,
    Expression<int>? bitRate,
    Expression<String>? suffix,
    Expression<double>? trackGain,
    Expression<double>? albumGain,
    Expression<double>? trackPeak,
    Expression<double>? albumPeak,
    Expression<String>? coverPath,
    Expression<String>? lyrics,
    Expression<String>? serverId,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (songId != null) 'song_id': songId,
      if (path != null) 'path': path,
      if (folderId != null) 'folder_id': folderId,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (albumArtist != null) 'album_artist': albumArtist,
      if (genre != null) 'genre': genre,
      if (track != null) 'track': track,
      if (disc != null) 'disc': disc,
      if (year != null) 'year': year,
      if (durationSec != null) 'duration_sec': durationSec,
      if (bitRate != null) 'bit_rate': bitRate,
      if (suffix != null) 'suffix': suffix,
      if (trackGain != null) 'track_gain': trackGain,
      if (albumGain != null) 'album_gain': albumGain,
      if (trackPeak != null) 'track_peak': trackPeak,
      if (albumPeak != null) 'album_peak': albumPeak,
      if (coverPath != null) 'cover_path': coverPath,
      if (lyrics != null) 'lyrics': lyrics,
      if (serverId != null) 'server_id': serverId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSongsCompanion copyWith({
    Value<String>? songId,
    Value<String>? path,
    Value<String>? folderId,
    Value<String>? fingerprint,
    Value<String>? title,
    Value<String>? artist,
    Value<String>? album,
    Value<String>? albumArtist,
    Value<String>? genre,
    Value<int>? track,
    Value<int>? disc,
    Value<int>? year,
    Value<int>? durationSec,
    Value<int>? bitRate,
    Value<String>? suffix,
    Value<double?>? trackGain,
    Value<double?>? albumGain,
    Value<double?>? trackPeak,
    Value<double?>? albumPeak,
    Value<String?>? coverPath,
    Value<String?>? lyrics,
    Value<String?>? serverId,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return LocalSongsCompanion(
      songId: songId ?? this.songId,
      path: path ?? this.path,
      folderId: folderId ?? this.folderId,
      fingerprint: fingerprint ?? this.fingerprint,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      track: track ?? this.track,
      disc: disc ?? this.disc,
      year: year ?? this.year,
      durationSec: durationSec ?? this.durationSec,
      bitRate: bitRate ?? this.bitRate,
      suffix: suffix ?? this.suffix,
      trackGain: trackGain ?? this.trackGain,
      albumGain: albumGain ?? this.albumGain,
      trackPeak: trackPeak ?? this.trackPeak,
      albumPeak: albumPeak ?? this.albumPeak,
      coverPath: coverPath ?? this.coverPath,
      lyrics: lyrics ?? this.lyrics,
      serverId: serverId ?? this.serverId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (albumArtist.present) {
      map['album_artist'] = Variable<String>(albumArtist.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (track.present) {
      map['track'] = Variable<int>(track.value);
    }
    if (disc.present) {
      map['disc'] = Variable<int>(disc.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
    }
    if (bitRate.present) {
      map['bit_rate'] = Variable<int>(bitRate.value);
    }
    if (suffix.present) {
      map['suffix'] = Variable<String>(suffix.value);
    }
    if (trackGain.present) {
      map['track_gain'] = Variable<double>(trackGain.value);
    }
    if (albumGain.present) {
      map['album_gain'] = Variable<double>(albumGain.value);
    }
    if (trackPeak.present) {
      map['track_peak'] = Variable<double>(trackPeak.value);
    }
    if (albumPeak.present) {
      map['album_peak'] = Variable<double>(albumPeak.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (lyrics.present) {
      map['lyrics'] = Variable<String>(lyrics.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSongsCompanion(')
          ..write('songId: $songId, ')
          ..write('path: $path, ')
          ..write('folderId: $folderId, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('genre: $genre, ')
          ..write('track: $track, ')
          ..write('disc: $disc, ')
          ..write('year: $year, ')
          ..write('durationSec: $durationSec, ')
          ..write('bitRate: $bitRate, ')
          ..write('suffix: $suffix, ')
          ..write('trackGain: $trackGain, ')
          ..write('albumGain: $albumGain, ')
          ..write('trackPeak: $trackPeak, ')
          ..write('albumPeak: $albumPeak, ')
          ..write('coverPath: $coverPath, ')
          ..write('lyrics: $lyrics, ')
          ..write('serverId: $serverId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PlayEventsTable playEvents = $PlayEventsTable(this);
  late final $SongMetadataTable songMetadata = $SongMetadataTable(this);
  late final $PlaylistCacheTable playlistCache = $PlaylistCacheTable(this);
  late final $LocalSongsTable localSongs = $LocalSongsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    playEvents,
    songMetadata,
    playlistCache,
    localSongs,
  ];
}

typedef $$PlayEventsTableCreateCompanionBuilder =
    PlayEventsCompanion Function({
      required String playId,
      required String songId,
      required String sessionId,
      required int tsStart,
      Value<int?> tsEnd,
      Value<int> playDurSec,
      Value<bool> skipBefore50,
      Value<double?> skipPositionPct,
      Value<int> repeatCount,
      Value<int> queuePosition,
      Value<bool> shuffleActive,
      required String sourceContext,
      required int hourOfDay,
      required int dayOfWeek,
      Value<int> rowid,
    });
typedef $$PlayEventsTableUpdateCompanionBuilder =
    PlayEventsCompanion Function({
      Value<String> playId,
      Value<String> songId,
      Value<String> sessionId,
      Value<int> tsStart,
      Value<int?> tsEnd,
      Value<int> playDurSec,
      Value<bool> skipBefore50,
      Value<double?> skipPositionPct,
      Value<int> repeatCount,
      Value<int> queuePosition,
      Value<bool> shuffleActive,
      Value<String> sourceContext,
      Value<int> hourOfDay,
      Value<int> dayOfWeek,
      Value<int> rowid,
    });

class $$PlayEventsTableFilterComposer
    extends Composer<_$AppDatabase, $PlayEventsTable> {
  $$PlayEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playId => $composableBuilder(
    column: $table.playId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tsStart => $composableBuilder(
    column: $table.tsStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tsEnd => $composableBuilder(
    column: $table.tsEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playDurSec => $composableBuilder(
    column: $table.playDurSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get skipBefore50 => $composableBuilder(
    column: $table.skipBefore50,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get skipPositionPct => $composableBuilder(
    column: $table.skipPositionPct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repeatCount => $composableBuilder(
    column: $table.repeatCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get queuePosition => $composableBuilder(
    column: $table.queuePosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get shuffleActive => $composableBuilder(
    column: $table.shuffleActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceContext => $composableBuilder(
    column: $table.sourceContext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hourOfDay => $composableBuilder(
    column: $table.hourOfDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayOfWeek => $composableBuilder(
    column: $table.dayOfWeek,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlayEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayEventsTable> {
  $$PlayEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playId => $composableBuilder(
    column: $table.playId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tsStart => $composableBuilder(
    column: $table.tsStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tsEnd => $composableBuilder(
    column: $table.tsEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playDurSec => $composableBuilder(
    column: $table.playDurSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get skipBefore50 => $composableBuilder(
    column: $table.skipBefore50,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get skipPositionPct => $composableBuilder(
    column: $table.skipPositionPct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repeatCount => $composableBuilder(
    column: $table.repeatCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queuePosition => $composableBuilder(
    column: $table.queuePosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get shuffleActive => $composableBuilder(
    column: $table.shuffleActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceContext => $composableBuilder(
    column: $table.sourceContext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hourOfDay => $composableBuilder(
    column: $table.hourOfDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayOfWeek => $composableBuilder(
    column: $table.dayOfWeek,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayEventsTable> {
  $$PlayEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playId =>
      $composableBuilder(column: $table.playId, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get tsStart =>
      $composableBuilder(column: $table.tsStart, builder: (column) => column);

  GeneratedColumn<int> get tsEnd =>
      $composableBuilder(column: $table.tsEnd, builder: (column) => column);

  GeneratedColumn<int> get playDurSec => $composableBuilder(
    column: $table.playDurSec,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get skipBefore50 => $composableBuilder(
    column: $table.skipBefore50,
    builder: (column) => column,
  );

  GeneratedColumn<double> get skipPositionPct => $composableBuilder(
    column: $table.skipPositionPct,
    builder: (column) => column,
  );

  GeneratedColumn<int> get repeatCount => $composableBuilder(
    column: $table.repeatCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get queuePosition => $composableBuilder(
    column: $table.queuePosition,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get shuffleActive => $composableBuilder(
    column: $table.shuffleActive,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceContext => $composableBuilder(
    column: $table.sourceContext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hourOfDay =>
      $composableBuilder(column: $table.hourOfDay, builder: (column) => column);

  GeneratedColumn<int> get dayOfWeek =>
      $composableBuilder(column: $table.dayOfWeek, builder: (column) => column);
}

class $$PlayEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayEventsTable,
          PlayEventEntity,
          $$PlayEventsTableFilterComposer,
          $$PlayEventsTableOrderingComposer,
          $$PlayEventsTableAnnotationComposer,
          $$PlayEventsTableCreateCompanionBuilder,
          $$PlayEventsTableUpdateCompanionBuilder,
          (
            PlayEventEntity,
            BaseReferences<_$AppDatabase, $PlayEventsTable, PlayEventEntity>,
          ),
          PlayEventEntity,
          PrefetchHooks Function()
        > {
  $$PlayEventsTableTableManager(_$AppDatabase db, $PlayEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> playId = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> tsStart = const Value.absent(),
                Value<int?> tsEnd = const Value.absent(),
                Value<int> playDurSec = const Value.absent(),
                Value<bool> skipBefore50 = const Value.absent(),
                Value<double?> skipPositionPct = const Value.absent(),
                Value<int> repeatCount = const Value.absent(),
                Value<int> queuePosition = const Value.absent(),
                Value<bool> shuffleActive = const Value.absent(),
                Value<String> sourceContext = const Value.absent(),
                Value<int> hourOfDay = const Value.absent(),
                Value<int> dayOfWeek = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlayEventsCompanion(
                playId: playId,
                songId: songId,
                sessionId: sessionId,
                tsStart: tsStart,
                tsEnd: tsEnd,
                playDurSec: playDurSec,
                skipBefore50: skipBefore50,
                skipPositionPct: skipPositionPct,
                repeatCount: repeatCount,
                queuePosition: queuePosition,
                shuffleActive: shuffleActive,
                sourceContext: sourceContext,
                hourOfDay: hourOfDay,
                dayOfWeek: dayOfWeek,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playId,
                required String songId,
                required String sessionId,
                required int tsStart,
                Value<int?> tsEnd = const Value.absent(),
                Value<int> playDurSec = const Value.absent(),
                Value<bool> skipBefore50 = const Value.absent(),
                Value<double?> skipPositionPct = const Value.absent(),
                Value<int> repeatCount = const Value.absent(),
                Value<int> queuePosition = const Value.absent(),
                Value<bool> shuffleActive = const Value.absent(),
                required String sourceContext,
                required int hourOfDay,
                required int dayOfWeek,
                Value<int> rowid = const Value.absent(),
              }) => PlayEventsCompanion.insert(
                playId: playId,
                songId: songId,
                sessionId: sessionId,
                tsStart: tsStart,
                tsEnd: tsEnd,
                playDurSec: playDurSec,
                skipBefore50: skipBefore50,
                skipPositionPct: skipPositionPct,
                repeatCount: repeatCount,
                queuePosition: queuePosition,
                shuffleActive: shuffleActive,
                sourceContext: sourceContext,
                hourOfDay: hourOfDay,
                dayOfWeek: dayOfWeek,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlayEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayEventsTable,
      PlayEventEntity,
      $$PlayEventsTableFilterComposer,
      $$PlayEventsTableOrderingComposer,
      $$PlayEventsTableAnnotationComposer,
      $$PlayEventsTableCreateCompanionBuilder,
      $$PlayEventsTableUpdateCompanionBuilder,
      (
        PlayEventEntity,
        BaseReferences<_$AppDatabase, $PlayEventsTable, PlayEventEntity>,
      ),
      PlayEventEntity,
      PrefetchHooks Function()
    >;
typedef $$SongMetadataTableCreateCompanionBuilder =
    SongMetadataCompanion Function({
      required String songId,
      required String trackName,
      required String artistName,
      required String albumName,
      Value<String?> genre,
      Value<String?> composer,
      required int durationSec,
      Value<int?> year,
      Value<int> playCount,
      Value<int> rating,
      Value<bool> starred,
      required int updatedAt,
      Value<int?> createdAt,
      Value<int> rowid,
    });
typedef $$SongMetadataTableUpdateCompanionBuilder =
    SongMetadataCompanion Function({
      Value<String> songId,
      Value<String> trackName,
      Value<String> artistName,
      Value<String> albumName,
      Value<String?> genre,
      Value<String?> composer,
      Value<int> durationSec,
      Value<int?> year,
      Value<int> playCount,
      Value<int> rating,
      Value<bool> starred,
      Value<int> updatedAt,
      Value<int?> createdAt,
      Value<int> rowid,
    });

class $$SongMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $SongMetadataTable> {
  $$SongMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackName => $composableBuilder(
    column: $table.trackName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistName => $composableBuilder(
    column: $table.artistName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get composer => $composableBuilder(
    column: $table.composer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SongMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $SongMetadataTable> {
  $$SongMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackName => $composableBuilder(
    column: $table.trackName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistName => $composableBuilder(
    column: $table.artistName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get composer => $composableBuilder(
    column: $table.composer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SongMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $SongMetadataTable> {
  $$SongMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get trackName =>
      $composableBuilder(column: $table.trackName, builder: (column) => column);

  GeneratedColumn<String> get artistName => $composableBuilder(
    column: $table.artistName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get albumName =>
      $composableBuilder(column: $table.albumName, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<String> get composer =>
      $composableBuilder(column: $table.composer, builder: (column) => column);

  GeneratedColumn<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<bool> get starred =>
      $composableBuilder(column: $table.starred, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SongMetadataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SongMetadataTable,
          SongMetadataEntity,
          $$SongMetadataTableFilterComposer,
          $$SongMetadataTableOrderingComposer,
          $$SongMetadataTableAnnotationComposer,
          $$SongMetadataTableCreateCompanionBuilder,
          $$SongMetadataTableUpdateCompanionBuilder,
          (
            SongMetadataEntity,
            BaseReferences<
              _$AppDatabase,
              $SongMetadataTable,
              SongMetadataEntity
            >,
          ),
          SongMetadataEntity,
          PrefetchHooks Function()
        > {
  $$SongMetadataTableTableManager(_$AppDatabase db, $SongMetadataTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> songId = const Value.absent(),
                Value<String> trackName = const Value.absent(),
                Value<String> artistName = const Value.absent(),
                Value<String> albumName = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<String?> composer = const Value.absent(),
                Value<int> durationSec = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int> rating = const Value.absent(),
                Value<bool> starred = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongMetadataCompanion(
                songId: songId,
                trackName: trackName,
                artistName: artistName,
                albumName: albumName,
                genre: genre,
                composer: composer,
                durationSec: durationSec,
                year: year,
                playCount: playCount,
                rating: rating,
                starred: starred,
                updatedAt: updatedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String songId,
                required String trackName,
                required String artistName,
                required String albumName,
                Value<String?> genre = const Value.absent(),
                Value<String?> composer = const Value.absent(),
                required int durationSec,
                Value<int?> year = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int> rating = const Value.absent(),
                Value<bool> starred = const Value.absent(),
                required int updatedAt,
                Value<int?> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongMetadataCompanion.insert(
                songId: songId,
                trackName: trackName,
                artistName: artistName,
                albumName: albumName,
                genre: genre,
                composer: composer,
                durationSec: durationSec,
                year: year,
                playCount: playCount,
                rating: rating,
                starred: starred,
                updatedAt: updatedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SongMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SongMetadataTable,
      SongMetadataEntity,
      $$SongMetadataTableFilterComposer,
      $$SongMetadataTableOrderingComposer,
      $$SongMetadataTableAnnotationComposer,
      $$SongMetadataTableCreateCompanionBuilder,
      $$SongMetadataTableUpdateCompanionBuilder,
      (
        SongMetadataEntity,
        BaseReferences<_$AppDatabase, $SongMetadataTable, SongMetadataEntity>,
      ),
      SongMetadataEntity,
      PrefetchHooks Function()
    >;
typedef $$PlaylistCacheTableCreateCompanionBuilder =
    PlaylistCacheCompanion Function({
      required String playlistId,
      required int position,
      required String songJson,
      required int cachedAt,
      Value<int> rowid,
    });
typedef $$PlaylistCacheTableUpdateCompanionBuilder =
    PlaylistCacheCompanion Function({
      Value<String> playlistId,
      Value<int> position,
      Value<String> songJson,
      Value<int> cachedAt,
      Value<int> rowid,
    });

class $$PlaylistCacheTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistCacheTable> {
  $$PlaylistCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songJson => $composableBuilder(
    column: $table.songJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistCacheTable> {
  $$PlaylistCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songJson => $composableBuilder(
    column: $table.songJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistCacheTable> {
  $$PlaylistCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get songJson =>
      $composableBuilder(column: $table.songJson, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$PlaylistCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistCacheTable,
          PlaylistCacheEntity,
          $$PlaylistCacheTableFilterComposer,
          $$PlaylistCacheTableOrderingComposer,
          $$PlaylistCacheTableAnnotationComposer,
          $$PlaylistCacheTableCreateCompanionBuilder,
          $$PlaylistCacheTableUpdateCompanionBuilder,
          (
            PlaylistCacheEntity,
            BaseReferences<
              _$AppDatabase,
              $PlaylistCacheTable,
              PlaylistCacheEntity
            >,
          ),
          PlaylistCacheEntity,
          PrefetchHooks Function()
        > {
  $$PlaylistCacheTableTableManager(_$AppDatabase db, $PlaylistCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> playlistId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> songJson = const Value.absent(),
                Value<int> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistCacheCompanion(
                playlistId: playlistId,
                position: position,
                songJson: songJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playlistId,
                required int position,
                required String songJson,
                required int cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistCacheCompanion.insert(
                playlistId: playlistId,
                position: position,
                songJson: songJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistCacheTable,
      PlaylistCacheEntity,
      $$PlaylistCacheTableFilterComposer,
      $$PlaylistCacheTableOrderingComposer,
      $$PlaylistCacheTableAnnotationComposer,
      $$PlaylistCacheTableCreateCompanionBuilder,
      $$PlaylistCacheTableUpdateCompanionBuilder,
      (
        PlaylistCacheEntity,
        BaseReferences<_$AppDatabase, $PlaylistCacheTable, PlaylistCacheEntity>,
      ),
      PlaylistCacheEntity,
      PrefetchHooks Function()
    >;
typedef $$LocalSongsTableCreateCompanionBuilder =
    LocalSongsCompanion Function({
      required String songId,
      required String path,
      required String folderId,
      required String fingerprint,
      required String title,
      required String artist,
      required String album,
      Value<String> albumArtist,
      Value<String> genre,
      Value<int> track,
      Value<int> disc,
      Value<int> year,
      Value<int> durationSec,
      Value<int> bitRate,
      Value<String> suffix,
      Value<double?> trackGain,
      Value<double?> albumGain,
      Value<double?> trackPeak,
      Value<double?> albumPeak,
      Value<String?> coverPath,
      Value<String?> lyrics,
      Value<String?> serverId,
      required int addedAt,
      Value<int> rowid,
    });
typedef $$LocalSongsTableUpdateCompanionBuilder =
    LocalSongsCompanion Function({
      Value<String> songId,
      Value<String> path,
      Value<String> folderId,
      Value<String> fingerprint,
      Value<String> title,
      Value<String> artist,
      Value<String> album,
      Value<String> albumArtist,
      Value<String> genre,
      Value<int> track,
      Value<int> disc,
      Value<int> year,
      Value<int> durationSec,
      Value<int> bitRate,
      Value<String> suffix,
      Value<double?> trackGain,
      Value<double?> albumGain,
      Value<double?> trackPeak,
      Value<double?> albumPeak,
      Value<String?> coverPath,
      Value<String?> lyrics,
      Value<String?> serverId,
      Value<int> addedAt,
      Value<int> rowid,
    });

class $$LocalSongsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSongsTable> {
  $$LocalSongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get track => $composableBuilder(
    column: $table.track,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get disc => $composableBuilder(
    column: $table.disc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bitRate => $composableBuilder(
    column: $table.bitRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suffix => $composableBuilder(
    column: $table.suffix,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get trackGain => $composableBuilder(
    column: $table.trackGain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get albumGain => $composableBuilder(
    column: $table.albumGain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get trackPeak => $composableBuilder(
    column: $table.trackPeak,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get albumPeak => $composableBuilder(
    column: $table.albumPeak,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lyrics => $composableBuilder(
    column: $table.lyrics,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSongsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSongsTable> {
  $$LocalSongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get track => $composableBuilder(
    column: $table.track,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get disc => $composableBuilder(
    column: $table.disc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bitRate => $composableBuilder(
    column: $table.bitRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suffix => $composableBuilder(
    column: $table.suffix,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get trackGain => $composableBuilder(
    column: $table.trackGain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get albumGain => $composableBuilder(
    column: $table.albumGain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get trackPeak => $composableBuilder(
    column: $table.trackPeak,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get albumPeak => $composableBuilder(
    column: $table.albumPeak,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lyrics => $composableBuilder(
    column: $table.lyrics,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSongsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSongsTable> {
  $$LocalSongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => column,
  );

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<int> get track =>
      $composableBuilder(column: $table.track, builder: (column) => column);

  GeneratedColumn<int> get disc =>
      $composableBuilder(column: $table.disc, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bitRate =>
      $composableBuilder(column: $table.bitRate, builder: (column) => column);

  GeneratedColumn<String> get suffix =>
      $composableBuilder(column: $table.suffix, builder: (column) => column);

  GeneratedColumn<double> get trackGain =>
      $composableBuilder(column: $table.trackGain, builder: (column) => column);

  GeneratedColumn<double> get albumGain =>
      $composableBuilder(column: $table.albumGain, builder: (column) => column);

  GeneratedColumn<double> get trackPeak =>
      $composableBuilder(column: $table.trackPeak, builder: (column) => column);

  GeneratedColumn<double> get albumPeak =>
      $composableBuilder(column: $table.albumPeak, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<String> get lyrics =>
      $composableBuilder(column: $table.lyrics, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$LocalSongsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalSongsTable,
          LocalSongEntity,
          $$LocalSongsTableFilterComposer,
          $$LocalSongsTableOrderingComposer,
          $$LocalSongsTableAnnotationComposer,
          $$LocalSongsTableCreateCompanionBuilder,
          $$LocalSongsTableUpdateCompanionBuilder,
          (
            LocalSongEntity,
            BaseReferences<_$AppDatabase, $LocalSongsTable, LocalSongEntity>,
          ),
          LocalSongEntity,
          PrefetchHooks Function()
        > {
  $$LocalSongsTableTableManager(_$AppDatabase db, $LocalSongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> songId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> folderId = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> album = const Value.absent(),
                Value<String> albumArtist = const Value.absent(),
                Value<String> genre = const Value.absent(),
                Value<int> track = const Value.absent(),
                Value<int> disc = const Value.absent(),
                Value<int> year = const Value.absent(),
                Value<int> durationSec = const Value.absent(),
                Value<int> bitRate = const Value.absent(),
                Value<String> suffix = const Value.absent(),
                Value<double?> trackGain = const Value.absent(),
                Value<double?> albumGain = const Value.absent(),
                Value<double?> trackPeak = const Value.absent(),
                Value<double?> albumPeak = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String?> lyrics = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSongsCompanion(
                songId: songId,
                path: path,
                folderId: folderId,
                fingerprint: fingerprint,
                title: title,
                artist: artist,
                album: album,
                albumArtist: albumArtist,
                genre: genre,
                track: track,
                disc: disc,
                year: year,
                durationSec: durationSec,
                bitRate: bitRate,
                suffix: suffix,
                trackGain: trackGain,
                albumGain: albumGain,
                trackPeak: trackPeak,
                albumPeak: albumPeak,
                coverPath: coverPath,
                lyrics: lyrics,
                serverId: serverId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String songId,
                required String path,
                required String folderId,
                required String fingerprint,
                required String title,
                required String artist,
                required String album,
                Value<String> albumArtist = const Value.absent(),
                Value<String> genre = const Value.absent(),
                Value<int> track = const Value.absent(),
                Value<int> disc = const Value.absent(),
                Value<int> year = const Value.absent(),
                Value<int> durationSec = const Value.absent(),
                Value<int> bitRate = const Value.absent(),
                Value<String> suffix = const Value.absent(),
                Value<double?> trackGain = const Value.absent(),
                Value<double?> albumGain = const Value.absent(),
                Value<double?> trackPeak = const Value.absent(),
                Value<double?> albumPeak = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String?> lyrics = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                required int addedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalSongsCompanion.insert(
                songId: songId,
                path: path,
                folderId: folderId,
                fingerprint: fingerprint,
                title: title,
                artist: artist,
                album: album,
                albumArtist: albumArtist,
                genre: genre,
                track: track,
                disc: disc,
                year: year,
                durationSec: durationSec,
                bitRate: bitRate,
                suffix: suffix,
                trackGain: trackGain,
                albumGain: albumGain,
                trackPeak: trackPeak,
                albumPeak: albumPeak,
                coverPath: coverPath,
                lyrics: lyrics,
                serverId: serverId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSongsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalSongsTable,
      LocalSongEntity,
      $$LocalSongsTableFilterComposer,
      $$LocalSongsTableOrderingComposer,
      $$LocalSongsTableAnnotationComposer,
      $$LocalSongsTableCreateCompanionBuilder,
      $$LocalSongsTableUpdateCompanionBuilder,
      (
        LocalSongEntity,
        BaseReferences<_$AppDatabase, $LocalSongsTable, LocalSongEntity>,
      ),
      LocalSongEntity,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PlayEventsTableTableManager get playEvents =>
      $$PlayEventsTableTableManager(_db, _db.playEvents);
  $$SongMetadataTableTableManager get songMetadata =>
      $$SongMetadataTableTableManager(_db, _db.songMetadata);
  $$PlaylistCacheTableTableManager get playlistCache =>
      $$PlaylistCacheTableTableManager(_db, _db.playlistCache);
  $$LocalSongsTableTableManager get localSongs =>
      $$LocalSongsTableTableManager(_db, _db.localSongs);
}
