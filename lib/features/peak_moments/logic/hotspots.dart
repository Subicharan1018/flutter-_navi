import '../data/peak_mark.dart' show PeakMark;
import '../data/seek_log.dart';

/// A stretch of a song the listener keeps coming back to.
class Hotspot {
  const Hotspot({required this.songId, required this.startMs, required this.count, required this.lastAtMs});

  final String songId;
  final int startMs;

  /// Scrub-backs that landed in the stretch.
  final int count;
  final int lastAtMs;
}

/// How wide "the same part" is.
const hotspotWindowMs = 20000;

/// A suggested peak needs the listener to have gone back to it this often.
const minHotspotCount = 2;

/// The most-scrubbed-back-to window of every song in [log]: the densest
/// [hotspotWindowMs] window of landing points, anchored at its earliest
/// landing. Songs whose best window holds fewer than [minCount] landings are
/// left out. Ordered by count, then most recent.
List<Hotspot> findHotspots(List<SeekEntry> log, {int minCount = minHotspotCount}) {
  final bySong = <String, List<SeekEntry>>{};
  for (final e in log) {
    (bySong[e.songId] ??= []).add(e);
  }
  final out = <Hotspot>[];
  for (final entry in bySong.entries) {
    final landings = [...entry.value]..sort((a, b) => a.toMs.compareTo(b.toMs));
    var bestCount = 0;
    var bestFrom = 0;
    var bestLast = 0;
    var hi = 0;
    for (var lo = 0; lo < landings.length; lo++) {
      if (hi < lo) hi = lo;
      while (hi < landings.length && landings[hi].toMs - landings[lo].toMs < hotspotWindowMs) {
        hi++;
      }
      final n = hi - lo;
      if (n > bestCount) {
        bestCount = n;
        bestFrom = lo;
        bestLast = landings.sublist(lo, hi).fold(0, (m, e) => e.atMs > m ? e.atMs : m);
      }
    }
    if (bestCount >= minCount) {
      // Like a saved moment, start a little before the earliest landing.
      final start = landings[bestFrom].toMs - PeakMark.leadInMs;
      out.add(Hotspot(songId: entry.key, startMs: start < 0 ? 0 : start, count: bestCount, lastAtMs: bestLast));
    }
  }
  out.sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : b.lastAtMs.compareTo(a.lastAtMs));
  return out;
}
