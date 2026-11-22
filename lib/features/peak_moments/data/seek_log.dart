import 'dart:convert';

/// A backward scrub: the listener jumped from [fromMs] back to [toMs] to hear
/// that part again. Device-local; capped so it can never grow without bound.
class SeekEntry {
  const SeekEntry({required this.songId, required this.fromMs, required this.toMs, required this.atMs});

  final String songId;
  final int fromMs;
  final int toMs;
  final int atMs;

  static const cap = 1000;
}

/// Jumping back by at least this far means "again", not a nudge.
const replaySeekMinBackMs = 3000;

bool isReplaySeek(int fromMs, int toMs) => fromMs - toMs >= replaySeekMinBackMs && toMs >= 0;

String encodeSeekLog(List<SeekEntry> log) => jsonEncode([
  for (final e in log) [e.songId, e.fromMs, e.toMs, e.atMs],
]);

List<SeekEntry> decodeSeekLog(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final out = <SeekEntry>[];
    for (final r in jsonDecode(raw) as List) {
      if (r is List && r.length == 4 && r[0] is String && r[1] is num && r[2] is num && r[3] is num) {
        out.add(SeekEntry(songId: r[0] as String, fromMs: (r[1] as num).toInt(), toMs: (r[2] as num).toInt(), atMs: (r[3] as num).toInt()));
      }
    }
    return out.length > SeekEntry.cap ? out.sublist(out.length - SeekEntry.cap) : out;
  } catch (_) {
    return const [];
  }
}
