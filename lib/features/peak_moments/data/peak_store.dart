import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/hive_boxes.dart';
import 'peak_mark.dart';
import 'seek_log.dart';

/// Where peak data is kept: json strings in the prefs box (device only).
abstract class PeakBackend {
  String? read(String key);
  Future<void> write(String key, String value);
}

class HivePeakBackend implements PeakBackend {
  static const marksKey = 'peakMarks_v1';
  static const seekKey = 'seekLog_v1';

  @override
  String? read(String key) {
    final v = HiveBoxes.prefs.get(key);
    return v is String ? v : null;
  }

  @override
  Future<void> write(String key, String value) => HiveBoxes.prefs.put(key, value);
}

final peakBackendProvider = Provider<PeakBackend>((ref) => HivePeakBackend());

/// What tapping the mark button did.
enum MarkOutcome { added, removed, noRoom }

class PeakMarksNotifier extends Notifier<PeakMarks> {
  @override
  PeakMarks build() {
    try {
      return PeakMarks.decode(ref.read(peakBackendProvider).read(HivePeakBackend.marksKey));
    } catch (_) {
      return const PeakMarks(); // no storage (a test, a first frame): no marks
    }
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Tap: marks the best part from [positionMs]; inside an existing mark it
  /// unmarks that one instead (the "second tap").
  Future<MarkOutcome> toggleAt(String songId, int positionMs, {required int durationMs}) async {
    final live = state.of(songId);
    final inside = live.where((m) => m.contains(positionMs)).firstOrNull;
    if (inside != null) {
      await _remove(songId, inside);
      return MarkOutcome.removed;
    }
    final mark = placeMark(
      id: const Uuid().v4(),
      positionMs: positionMs,
      durationMs: durationMs,
      existing: live,
      nowMs: _now(),
    );
    if (mark == null) return MarkOutcome.noRoom;
    await _save(songId, [...(state.map[songId] ?? const []), mark]);
    return MarkOutcome.added;
  }

  /// Long-press: unmarks the mark under [positionMs], else the nearest one.
  Future<bool> removeNear(String songId, int positionMs) async {
    final live = state.of(songId);
    if (live.isEmpty) return false;
    int dist(PeakMark m) => m.contains(positionMs) ? 0 : (positionMs < m.startMs ? m.startMs - positionMs : positionMs - m.endMs);
    final nearest = ([...live]..sort((a, b) => dist(a).compareTo(dist(b)))).first;
    await _remove(songId, nearest);
    return true;
  }

  /// Dragging a mark's end handle: its new length, kept clear of the next
  /// mark and inside the song.
  Future<void> resize(String songId, String markId, int lengthMs, {required int durationMs}) async {
    final m = state.of(songId).where((x) => x.id == markId).firstOrNull;
    if (m == null) return;
    await setBounds(songId, markId, endMs: m.startMs + lengthMs, durationMs: durationMs);
  }

  /// Dragging a mark's start handle: the start moves, the end stays. Kept
  /// clear of the previous mark, at 0 or later, and 5..90 s long.
  Future<void> moveStart(String songId, String markId, int startMs, {required int durationMs}) =>
      setBounds(songId, markId, startMs: startMs, durationMs: durationMs);

  /// Nudge buttons and arrow keys: move the start and/or the end by a delta
  /// (e.g. -1000 / +1000). The same limits as dragging.
  Future<void> nudge(String songId, String markId, {int startDeltaMs = 0, int endDeltaMs = 0, required int durationMs}) async {
    final m = state.of(songId).where((x) => x.id == markId).firstOrNull;
    if (m == null) return;
    await setBounds(
      songId,
      markId,
      startMs: startDeltaMs == 0 ? null : m.startMs + startDeltaMs,
      endMs: endDeltaMs == 0 ? null : m.endMs + endDeltaMs,
      durationMs: durationMs,
    );
  }

  /// The one place a mark's edges change (see [PeakMark.adjusted]). Bumps
  /// `updatedAt` like every edit, so a later sync takes the newest version.
  Future<void> setBounds(String songId, String markId, {int? startMs, int? endMs, required int durationMs}) async {
    final live = state.of(songId);
    final m = live.where((x) => x.id == markId).firstOrNull;
    if (m == null) return;
    final next = m.adjusted(live, startMs: startMs, endMs: endMs, durationMs: durationMs);
    if (next == null) return;
    final stamped = next.copyWith(updatedAt: _now());
    await _save(songId, [for (final x in state.map[songId] ?? const <PeakMark>[]) x.id == markId ? stamped : x]);
  }

  Future<void> _remove(String songId, PeakMark mark) {
    final now = _now();
    return _save(songId, [
      for (final x in state.map[songId] ?? const <PeakMark>[]) x.id == mark.id ? x.copyWith(updatedAt: now, deletedAt: now) : x,
    ]);
  }

  Future<void> _save(String songId, List<PeakMark> marks) async {
    state = state.withSong(songId, marks);
    // Bookkeeping: a failed write must not break the tap that caused it.
    try {
      await ref.read(peakBackendProvider).write(HivePeakBackend.marksKey, state.encode());
    } catch (_) {}
  }
}

final peakMarksProvider = NotifierProvider<PeakMarksNotifier, PeakMarks>(PeakMarksNotifier.new);

/// Live marks of one song; rebuilds only when that song's marks change.
final songMarksProvider = Provider.family<List<PeakMark>, String>((ref, songId) {
  return ref.watch(peakMarksProvider.select((m) => m.of(songId)));
});

class SeekLogNotifier extends Notifier<List<SeekEntry>> {
  @override
  List<SeekEntry> build() {
    try {
      return decodeSeekLog(ref.read(peakBackendProvider).read(HivePeakBackend.seekKey));
    } catch (_) {
      return const [];
    }
  }

  /// A backward scrub on the Now Playing scrubber. Ignored unless it jumps
  /// back far enough to mean "play that part again".
  Future<void> recordSeek(String songId, {required int fromMs, required int toMs}) async {
    if (!isReplaySeek(fromMs, toMs)) return;
    final next = [...state, SeekEntry(songId: songId, fromMs: fromMs, toMs: toMs, atMs: DateTime.now().millisecondsSinceEpoch)];
    state = next.length > SeekEntry.cap ? next.sublist(next.length - SeekEntry.cap) : next;
    try {
      await ref.read(peakBackendProvider).write(HivePeakBackend.seekKey, encodeSeekLog(state));
    } catch (_) {}
  }
}

final seekLogProvider = NotifierProvider<SeekLogNotifier, List<SeekEntry>>(SeekLogNotifier.new);
