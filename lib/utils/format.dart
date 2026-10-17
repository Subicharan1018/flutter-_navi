/// "1 hr 32 min" / "48 min" — the long form Spotify and Apple Music use
/// under a playlist or album.
String formatLongDuration(int totalSeconds) {
  final d = Duration(seconds: totalSeconds);
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return m > 0 ? '$h hr $m min' : '$h hr';
  return '$m min';
}

/// "3:07" for one track.
String formatTrackDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// "12 songs", "1 song".
String songCount(int n) => n == 1 ? '1 song' : '$n songs';

/// "980", "4.3k", "12k", "6.7M", "1.2B" — counts in a big figure.
String compactCount(int v) {
  if (v < 1000) return '$v';
  final (n, unit) = v >= 1e9 ? (v / 1e9, 'B') : v >= 1e6 ? (v / 1e6, 'M') : (v / 1000, 'k');
  return '${n.toStringAsFixed(n >= 10 || n.truncateToDouble() == n ? 0 : 1)}$unit';
}

/// Listening time as a reader wants it: "45m", "3h 20m", "120h".
String listeningTime(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h >= 100 || m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// "12 am", "3 pm" — an hour of the day.
String hourLabel(int hour, {bool compact = false}) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  final suffix = hour < 12 ? (compact ? 'a' : ' am') : (compact ? 'p' : ' pm');
  return '$h$suffix';
}

/// yyyy-MM-dd, the key the stats server uses for days.
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
