import 'dart:convert';

/// One saved "best part" of a song: a start and a length.
///
/// Device-local, keyed by song id. `id` + `updatedAt` + `deletedAt` make each
/// mark mergeable later (last writer wins per mark) without a schema change.
class PeakMark {
  const PeakMark({
    required this.id,
    required this.startMs,
    this.lengthMs = defaultLengthMs,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final int startMs;
  final int lengthMs;
  final int createdAt; // ms since epoch
  final int updatedAt;

  /// Set when the mark was removed; kept so a later sync can propagate it.
  final int? deletedAt;

  static const defaultLengthMs = 20000;
  static const minLengthMs = 5000;
  static const maxLengthMs = 90000;

  /// Tombstones older than this are dropped when loading.
  static const tombstoneKeep = Duration(days: 90);

  int get endMs => startMs + lengthMs;
  bool get isDeleted => deletedAt != null;

  bool contains(int positionMs) => positionMs >= startMs && positionMs < endMs;

  PeakMark copyWith({int? startMs, int? lengthMs, int? updatedAt, int? deletedAt}) => PeakMark(
    id: id,
    startMs: startMs ?? this.startMs,
    lengthMs: lengthMs ?? this.lengthMs,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  /// Fitted to a song [durationMs] long (0 = unknown): the start inside the
  /// song, the length between [minLengthMs] and [maxLengthMs] and not past the
  /// end. Null when no 5 s stretch fits at that start.
  PeakMark? fitted(int durationMs) {
    var s = startMs < 0 ? 0 : startMs;
    var l = lengthMs.clamp(minLengthMs, maxLengthMs);
    if (durationMs > 0) {
      if (durationMs < minLengthMs) return null;
      if (s + minLengthMs > durationMs) s = durationMs - minLengthMs;
      if (s + l > durationMs) l = durationMs - s;
    }
    if (l < minLengthMs) return null;
    if (s == startMs && l == lengthMs) return this;
    return copyWith(startMs: s, lengthMs: l);
  }

  Map<String, dynamic> toJson() => {
    'i': id,
    's': startMs,
    'l': lengthMs,
    'c': createdAt,
    'u': updatedAt,
    if (deletedAt != null) 'd': deletedAt,
  };

  static PeakMark? fromJson(Object? j) {
    if (j is! Map) return null;
    int? n(Object? v) => v is num && v >= 0 ? v.toInt() : null;
    final id = j['i'];
    final s = n(j['s']);
    final l = n(j['l']);
    if (id is! String || id.isEmpty || s == null || l == null) return null;
    final created = n(j['c']) ?? 0;
    return PeakMark(
      id: id,
      startMs: s,
      lengthMs: l.clamp(minLengthMs, maxLengthMs),
      createdAt: created,
      updatedAt: n(j['u']) ?? created,
      deletedAt: n(j['d']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PeakMark &&
      other.id == id &&
      other.startMs == startMs &&
      other.lengthMs == lengthMs &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, startMs, lengthMs, updatedAt, deletedAt);
}

/// All marks, song id → marks sorted by start. Immutable.
class PeakMarks {
  const PeakMarks([this.map = const {}]);
  final Map<String, List<PeakMark>> map;

  /// Live (not deleted) marks of [songId], by start.
  List<PeakMark> of(String songId) => [
    for (final m in map[songId] ?? const <PeakMark>[])
      if (!m.isDeleted) m,
  ];

  /// Song ids that have at least one live mark.
  Iterable<String> get markedSongIds => [
    for (final e in map.entries)
      if (e.value.any((m) => !m.isDeleted)) e.key,
  ];

  int get liveCount => map.values.fold(0, (n, l) => n + l.where((m) => !m.isDeleted).length);

  /// [songId]'s marks replaced by [marks] (tombstones included), sorted.
  PeakMarks withSong(String songId, List<PeakMark> marks) {
    final next = {...map};
    if (marks.isEmpty) {
      next.remove(songId);
    } else {
      next[songId] = [...marks]..sort((a, b) => a.startMs.compareTo(b.startMs));
    }
    return PeakMarks(next);
  }

  String encode() => jsonEncode({
    for (final e in map.entries) e.key: [for (final m in e.value) m.toJson()],
  });

  static PeakMarks decode(String? raw, {int? nowMs}) {
    if (raw == null || raw.isEmpty) return const PeakMarks();
    try {
      final cutoff = (nowMs ?? DateTime.now().millisecondsSinceEpoch) - PeakMark.tombstoneKeep.inMilliseconds;
      final out = <String, List<PeakMark>>{};
      for (final e in (jsonDecode(raw) as Map).entries) {
        if (e.value is! List) continue;
        final marks = [
          for (final j in e.value as List)
            if (PeakMark.fromJson(j) case final m? when m.deletedAt == null || m.deletedAt! > cutoff) m,
        ]..sort((a, b) => a.startMs.compareTo(b.startMs));
        if (marks.isNotEmpty) out[e.key as String] = marks;
      }
      return PeakMarks(out);
    } catch (_) {
      return const PeakMarks();
    }
  }
}

/// A mark at [positionMs] for a song [durationMs] long, not overlapping the
/// live [existing] marks: shortened to end where the next one starts, moved
/// to start where the previous one ends. Null when it cannot fit (5 s gap).
PeakMark? placeMark({
  required String id,
  required int positionMs,
  required int durationMs,
  required List<PeakMark> existing,
  required int nowMs,
  int lengthMs = PeakMark.defaultLengthMs,
}) {
  var start = positionMs < 0 ? 0 : positionMs;
  final live = [...existing]..sort((a, b) => a.startMs.compareTo(b.startMs));
  for (final m in live) {
    if (start >= m.startMs && start < m.endMs) start = m.endMs;
  }
  var end = start + lengthMs;
  for (final m in live) {
    if (m.startMs >= start && m.startMs < end) end = m.startMs;
  }
  if (durationMs > 0 && end > durationMs) end = durationMs;
  if (end - start < PeakMark.minLengthMs) {
    // Too tight after the playhead: a short song's tail may still hold one.
    if (durationMs > 0 && start + PeakMark.minLengthMs > durationMs) {
      start = durationMs - PeakMark.minLengthMs;
      end = durationMs;
      if (start < 0 || live.any((m) => m.startMs < end && m.endMs > start)) return null;
    } else {
      return null;
    }
  }
  return PeakMark(id: id, startMs: start, lengthMs: end - start, createdAt: nowMs, updatedAt: nowMs);
}
