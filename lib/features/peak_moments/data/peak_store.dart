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
    final all = state.map[songId] ?? const <PeakMark>[];
    final live = state.of(songId);
    final m = live.where((x) => x.id == markId).firstOrNull;
    if (m == null) return;
    var l = lengthMs.clamp(PeakMark.minLengthMs, PeakMark.maxLengthMs);
    final next = live.where((x) => x.startMs >= m.endMs).firstOrNull;
    if (next != null && m.startMs + l > next.startMs) l = next.startMs - m.startMs;
    if (durationMs > 0 && m.startMs + l > durationMs) l = durationMs - m.startMs;
    if (l < PeakMark.minLengthMs || l == m.lengthMs) return;
    await _save(songId, [for (final x in all) x.id == markId ? x.copyWith(lengthMs: l, updatedAt: _now()) : x]);
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
