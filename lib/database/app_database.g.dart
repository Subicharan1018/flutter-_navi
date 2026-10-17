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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PlayEventsTable playEvents = $PlayEventsTable(this);
  late final $SongMetadataTable songMetadata = $SongMetadataTable(this);
  late final $PlaylistCacheTable playlistCache = $PlaylistCacheTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    playEvents,
    songMetadata,
    playlistCache,
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PlayEventsTableTableManager get playEvents =>
      $$PlayEventsTableTableManager(_db, _db.playEvents);
  $$SongMetadataTableTableManager get songMetadata =>
      $$SongMetadataTableTableManager(_db, _db.songMetadata);
  $$PlaylistCacheTableTableManager get playlistCache =>
      $$PlaylistCacheTableTableManager(_db, _db.playlistCache);
}
