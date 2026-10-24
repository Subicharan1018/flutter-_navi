/// A song as the matcher sees it: just what identifies a recording.
class MatchKey {
  final String id;
  final String title;
  final String artist;
  final int durationSec;
  const MatchKey(this.id, this.title, this.artist, this.durationSec);
}

/// How far apart two copies of a song may be in length (rips and encoders
/// trim or pad a second or two).
const matchDurationToleranceSec = 3;

const _accents = {
  'àáâãäå': 'a', 'ç': 'c', 'èéêë': 'e', 'ìíîï': 'i', 'ñ': 'n', 'òóôõö': 'o', 'ùúûü': 'u', 'ýÿ': 'y', //
};

/// Lower case, accents folded, "(feat. …)" / "[remix]"-style brackets and
/// everything but letters and digits removed.
String normalizeForMatch(String s) {
  var out = s.toLowerCase();
  out = out.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
  out = out.replaceAll(RegExp(r'\s(feat|ft|featuring)\.?\s.*$'), '');
  _accents.forEach((chars, plain) {
    for (final c in chars.split('')) {
      out = out.replaceAll(c, plain);
    }
  });
  return out.replaceAll(RegExp(r'[^a-z0-9\u0080-￿]'), '');
}

bool _artistsMatch(String a, String b) {
  if (a.isEmpty || b.isEmpty) return a == b;
  if (a == b) return true;
  // "A & B" on one side and "A" on the other is the same recording.
  return a.contains(b) || b.contains(a);
}

/// Pairs each local song with the server song it is a copy of: same title and
/// artist (after normalising) and a duration within
/// [matchDurationToleranceSec]. Returns local id → server id. When several
/// server songs qualify the closest duration wins; each server song is used
/// once, so two local files never share a server copy.
Map<String, String> matchLocalToServer(List<MatchKey> local, List<MatchKey> server) {
  final byTitle = <String, List<(MatchKey, String)>>{};
  for (final s in server) {
    final t = normalizeForMatch(s.title);
    if (t.isEmpty) continue;
    byTitle.putIfAbsent(t, () => []).add((s, normalizeForMatch(s.artist)));
  }

  final result = <String, String>{};
  final taken = <String>{};
  for (final l in local) {
    final candidates = byTitle[normalizeForMatch(l.title)];
    if (candidates == null) continue;
    final artist = normalizeForMatch(l.artist);
    MatchKey? best;
    var bestGap = 1 << 30;
    for (final (s, sArtist) in candidates) {
      if (taken.contains(s.id) || !_artistsMatch(artist, sArtist)) continue;
      final bothKnown = l.durationSec > 0 && s.durationSec > 0;
      final gap = bothKnown ? (l.durationSec - s.durationSec).abs() : 0;
      if (gap > matchDurationToleranceSec) continue;
      if (gap < bestGap) {
        best = s;
        bestGap = gap;
      }
    }
    if (best != null) {
      result[l.id] = best.id;
      taken.add(best.id);
    }
  }
  return result;
}
