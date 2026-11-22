import '../../../models/song.dart';
import '../data/peak_mark.dart';
import '../data/seek_log.dart';
import 'hotspots.dart';

/// One stretch of a song in a highlight reel.
class ReelSegment {
  const ReelSegment({required this.songId, required this.startMs, required this.endMs, this.markId, this.suggested = false});

  final String songId;
  final int startMs;
  final int endMs;

  /// The saved mark this plays; null for a suggested (most-replayed) stretch.
  final String? markId;
  final bool suggested;

  int get lengthMs => endMs - startMs;
}

/// A reel ready to play: the queue (one entry per segment, so a song with two
/// marks appears twice) and the segment for each entry, same order.
class ReelPlan {
  const ReelPlan(this.songs, this.segments);

  final List<Song> songs;
  final List<ReelSegment> segments;

  bool get isEmpty => songs.isEmpty;
  int get totalMs => segments.fold(0, (n, s) => n + s.lengthMs);

  /// The segment queue entry [index] plays, or null when that entry is no
  /// longer the reel's (the queue was edited): reel mode then ends.
  ReelSegment? segmentAt(int index, String songId) {
    if (index < 0 || index >= segments.length) return null;
    final s = segments[index];
    return s.songId == songId ? s : null;
  }
}

/// The reel for [songs] (in the order given): every live mark, in start order.
/// With [includeSuggested], a song without marks whose [seekLog] shows a
/// most-replayed stretch (see [findHotspots]) contributes that stretch.
/// Segments are fitted to each song's length; songs without any are skipped.
ReelPlan buildReel(
  List<Song> songs,
  PeakMarks marks, {
  List<SeekEntry> seekLog = const [],
  bool includeSuggested = false,
}) {
  final hot = includeSuggested ? {for (final h in findHotspots(seekLog)) h.songId: h} : const <String, Hotspot>{};
  final outSongs = <Song>[];
  final outSegs = <ReelSegment>[];
  for (final song in songs) {
    final durMs = song.duration * 1000;
    var added = false;
    for (final m in marks.of(song.id)) {
      final f = m.fitted(durMs);
      if (f == null) continue;
      outSongs.add(song);
      outSegs.add(ReelSegment(songId: song.id, startMs: f.startMs, endMs: f.endMs, markId: f.id));
      added = true;
    }
    final h = hot[song.id];
    if (!added && h != null) {
      final f = PeakMark(id: '', startMs: h.startMs, createdAt: 0, updatedAt: 0).fitted(durMs);
      if (f != null) {
        outSongs.add(song);
        outSegs.add(ReelSegment(songId: song.id, startMs: f.startMs, endMs: f.endMs, suggested: true));
      }
    }
  }
  return ReelPlan(outSongs, outSegs);
}

/// The songs of [library] that have a live mark, the most recently marked
/// first (so a moment you just saved leads the Highlights page).
List<Song> songsWithMarks(List<Song> library, PeakMarks marks) {
  final latest = <String, int>{};
  for (final id in marks.markedSongIds) {
    latest[id] = marks.of(id).fold(0, (m, x) => x.updatedAt > m ? x.updatedAt : m);
  }
  final out = [for (final s in library) if (latest.containsKey(s.id)) s];
  out.sort((a, b) => latest[b.id]!.compareTo(latest[a.id]!));
  return out;
}

/// "0:42" for a moment's start, and "20 s" style lengths: "1:05–1:25".
String momentSpan(int startMs, int endMs) {
  String clock(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  return '${clock(startMs)}–${clock(endMs)}';
}

// ── Seek-and-stop ────────────────────────────────────────────────────────────

sealed class SegmentAction {
  const SegmentAction();
}

class SegmentNothing extends SegmentAction {
  const SegmentNothing();
}

/// Jump to [ms] (a segment's start, or back to it for repeat-one).
class SegmentSeek extends SegmentAction {
  const SegmentSeek(this.ms);
  final int ms;
}

/// The end is reached: go on to the next segment.
class SegmentAdvance extends SegmentAction {
  const SegmentAdvance();
}

/// The end is [ms] away, closer than one position tick: act after exactly
/// that long (unless told [SegmentCancel] first).
class SegmentAdvanceIn extends SegmentAction {
  const SegmentAdvanceIn(this.ms);
  final int ms;
}

/// The position moved away from the end: drop the pending [SegmentAdvanceIn].
class SegmentCancel extends SegmentAction {
  const SegmentCancel();
}

/// That was the last segment: stop.
class SegmentFinish extends SegmentAction {
  const SegmentFinish();
}

/// Watches the position of the queue entry playing during a reel and says
/// when to seek and when to cut. Pure; the player owns the timer.
class SegmentGuard {
  /// Positions arrive about this often; inside it, the end is timed exactly.
  static const lookaheadMs = 260;

  /// A start seek is only needed when the song begins further than this
  /// before the segment's start.
  static const startSlackMs = 400;

  int _index = -1;
  ReelSegment? _seg;
  bool _isLast = false;
  bool _startDone = true;
  bool _endDone = true;
  bool _timerPending = false;

  ReelSegment? get segment => _seg;

  /// Queue entry [index] started playing [segment] (null: not part of a
  /// reel); [isLast] if it is the reel's last entry. Repeating the same call
  /// changes nothing.
  void trackChanged(int index, ReelSegment? segment, {required bool isLast}) {
    if (index == _index && identical(segment, _seg)) return;
    _index = index;
    _seg = segment;
    _isLast = isLast;
    _startDone = segment == null;
    _endDone = segment == null;
    _timerPending = false;
  }

  void reset() => trackChanged(-1, null, isLast: false);

  SegmentAction onPosition(int positionMs, {required bool repeatOne}) {
    final s = _seg;
    if (s == null) return const SegmentNothing();
    if (!_startDone) {
      _startDone = true;
      if (positionMs < s.startMs - startSlackMs) return SegmentSeek(s.startMs);
    }
    if (_endDone) return const SegmentNothing();
    if (positionMs >= s.endMs) return _end(s, repeatOne);
    final left = s.endMs - positionMs;
    if (left <= lookaheadMs) {
      if (_timerPending) return const SegmentNothing();
      _timerPending = true;
      return SegmentAdvanceIn(left);
    }
    if (_timerPending) {
      _timerPending = false;
      return const SegmentCancel();
    }
    return const SegmentNothing();
  }

  /// The exact-end timer fired. Same outcome as reaching the end.
  SegmentAction onTimer({required bool repeatOne}) {
    final s = _seg;
    if (s == null || _endDone) return const SegmentNothing();
    _timerPending = false;
    return _end(s, repeatOne);
  }

  SegmentAction _end(ReelSegment s, bool repeatOne) {
    _timerPending = false;
    if (repeatOne) return SegmentSeek(s.startMs); // loop this part; the end counts again
    _endDone = true;
    return _isLast ? const SegmentFinish() : const SegmentAdvance();
  }
}
