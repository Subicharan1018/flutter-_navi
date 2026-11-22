import '../../models/song.dart';

/// R5: play count and last played, for every song row and the song sheet.
///
/// Two sources: Navidrome (`playCount`, `played`) and this device's own play
/// log. Neither is complete alone (the server misses plays made offline, the
/// log misses other devices), so the larger count and the later date win.
class PlayStats {
  const PlayStats({this.count = 0, this.lastPlayed});

  final int count;
  final DateTime? lastPlayed;

  static const none = PlayStats();

  bool get isEmpty => count == 0 && lastPlayed == null;

  /// The server's figures for [song], merged with the local log's.
  factory PlayStats.merge(Song song, {int localCount = 0, DateTime? localLast}) {
    final a = song.lastPlayed;
    final b = localLast;
    final last = a == null ? b : (b == null ? a : (b.isAfter(a) ? b : a));
    final count = song.playCount > localCount ? song.playCount : localCount;
    // A date with no count (server said "played" but count is 0) is still one play.
    return PlayStats(count: count == 0 && last != null ? 1 : count, lastPlayed: last);
  }

  /// "12 plays", "1 play", "Not played yet".
  String get countLabel => switch (count) {
    0 => 'Not played yet',
    1 => '1 play',
    _ => '$count plays',
  };

  /// "Today", "Yesterday", "3 days ago", "2 weeks ago", "5 months ago",
  /// "Mar 2025"; null when never played.
  String? lastPlayedLabel(DateTime now) {
    final d = lastPlayed;
    if (d == null) return null;
    return relativeDay(d, now);
  }

  /// The quiet second line: "12 plays · last played yesterday". Empty for a
  /// song that was never played, so a row shows nothing rather than "0".
  String line(DateTime now) {
    if (isEmpty) return '';
    final when = lastPlayedLabel(now);
    if (when == null) return countLabel;
    return '$countLabel · ${when == 'Today' || when == 'Yesterday' ? 'last played ${when.toLowerCase()}' : 'last played $when'}';
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Calendar-day distance, not 24-hour distance: 23:50 last night is
/// "Yesterday" at 00:10, even though only 20 minutes have passed.
String relativeDay(DateTime then, DateTime now) {
  final a = DateTime(then.year, then.month, then.day);
  final b = DateTime(now.year, now.month, now.day);
  final days = b.difference(a).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 30) {
    final w = days ~/ 7;
    return w == 1 ? '1 week ago' : '$w weeks ago';
  }
  if (days < 365) {
    final m = days ~/ 30;
    return m == 1 ? '1 month ago' : '$m months ago';
  }
  return '${_months[then.month - 1]} ${then.year}';
}

/// Sort orders the library can add for R5.
enum PlayStatSort { mostPlayed, leastPlayed, recentlyPlayed, longestUnplayed }

/// [songs] ordered by [sort], using [stats] (song id → merged stats; a missing
/// id counts as never played). Stable: ties keep their incoming order.
List<Song> sortByPlayStats(List<Song> songs, Map<String, PlayStats> stats, PlayStatSort sort) {
  PlayStats of(Song s) => stats[s.id] ?? PlayStats.merge(s);
  final indexed = [for (var i = 0; i < songs.length; i++) (i, songs[i])];
  int byLast(DateTime? a, DateTime? b, {required bool newestFirst, required bool neverFirst}) {
    if (a == null && b == null) return 0;
    if (a == null) return neverFirst ? -1 : 1;
    if (b == null) return neverFirst ? 1 : -1;
    return newestFirst ? b.compareTo(a) : a.compareTo(b);
  }

  int cmp((int, Song) x, (int, Song) y) {
    final a = of(x.$2), b = of(y.$2);
    final c = switch (sort) {
      PlayStatSort.mostPlayed => b.count.compareTo(a.count),
      PlayStatSort.leastPlayed => a.count.compareTo(b.count),
      PlayStatSort.recentlyPlayed =>
        byLast(a.lastPlayed, b.lastPlayed, newestFirst: true, neverFirst: false),
      // Songs never played come first (the longest-unplayed of all), then the oldest dates.
      PlayStatSort.longestUnplayed =>
        byLast(a.lastPlayed, b.lastPlayed, newestFirst: false, neverFirst: true),
    };
    return c != 0 ? c : x.$1.compareTo(y.$1);
  }

  return ([...indexed]..sort(cmp)).map((e) => e.$2).toList();
}
