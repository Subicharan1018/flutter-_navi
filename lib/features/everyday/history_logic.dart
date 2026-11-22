import '../../models/song.dart';
import 'play_stats.dart' show relativeDay;

/// R4: the listening history as a list you can act on. Pure logic; the data
/// comes from the local play log (see history_providers.dart).

/// One play in the history.
class HistoryEntry {
  const HistoryEntry({required this.song, required this.at, this.playedSec = 0});

  final Song song;
  final DateTime at;
  final int playedSec;
}

/// A calendar day of plays, newest first inside.
class HistoryDay {
  const HistoryDay({required this.day, required this.label, required this.entries});

  final DateTime day;

  /// "Today", "Yesterday", "Tuesday", "Nov 3".
  final String label;
  final List<HistoryEntry> entries;
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today", "Yesterday", the weekday for the last week, then "Nov 3" (with
/// the year when it is not this one).
String dayLabel(DateTime day, DateTime now) {
  final r = relativeDay(day, now);
  if (r == 'Today' || r == 'Yesterday') return r;
  final a = DateTime(day.year, day.month, day.day);
  final b = DateTime(now.year, now.month, now.day);
  if (b.difference(a).inDays < 7) return _weekdays[a.weekday - 1];
  final base = '${_monthsShort[a.month - 1]} ${a.day}';
  return a.year == b.year ? base : '$base, ${a.year}';
}

/// Day-part of an hour: morning 5–11, afternoon 12–16, evening 17–20, night
/// 21–4. These are the words people use ("that song on Tuesday night").
String dayPart(int hour) {
  if (hour >= 5 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 21) return 'evening';
  return 'night';
}

/// Groups [entries] (any order) by calendar day, newest day first and newest
/// play first inside a day.
List<HistoryDay> groupByDay(List<HistoryEntry> entries, DateTime now) {
  final sorted = [...entries]..sort((a, b) => b.at.compareTo(a.at));
  final days = <HistoryDay>[];
  for (final e in sorted) {
    final d = DateTime(e.at.year, e.at.month, e.at.day);
    if (days.isNotEmpty && days.last.day == d) {
      days.last.entries.add(e);
    } else {
      days.add(HistoryDay(day: d, label: dayLabel(d, now), entries: [e]));
    }
  }
  return days;
}

/// Entries matching [query]. Every word must match: either text of the song
/// (title, artist, album) or a time word of the play (weekday, "tuesday",
/// "tue"; "morning", "afternoon", "evening", "night"; "today", "yesterday").
/// An empty query keeps everything.
List<HistoryEntry> searchHistory(List<HistoryEntry> entries, String query, DateTime now) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return entries;
  bool timeWord(String w, DateTime at) {
    final wd = _weekdays[at.weekday - 1].toLowerCase();
    if (w.length >= 3 && wd.startsWith(w)) return true;
    if (w == dayPart(at.hour)) return true;
    final r = relativeDay(at, now);
    if (w == 'today') return r == 'Today';
    if (w == 'yesterday') return r == 'Yesterday';
    return false;
  }

  return [
    for (final e in entries)
      if (words.every((w) {
        final s = e.song;
        return s.title.toLowerCase().contains(w) ||
            s.artist.toLowerCase().contains(w) ||
            s.album.toLowerCase().contains(w) ||
            timeWord(w, e.at);
      }))
        e,
  ];
}

/// The songs of [entries] in the order they were heard (oldest first), each
/// once: what "Make a playlist from this evening" saves.
List<Song> songsInHeardOrder(List<HistoryEntry> entries) {
  final sorted = [...entries]..sort((a, b) => a.at.compareTo(b.at));
  final seen = <String>{};
  return [
    for (final e in sorted)
      if (seen.add(e.song.id)) e.song,
  ];
}

/// A stretch of one day (all plays in a row sharing a day-part): the unit
/// "Make a playlist from this evening" works on.
class HistoryPart {
  const HistoryPart({required this.part, required this.entries});
  final String part;
  final List<HistoryEntry> entries;
}

/// [day]'s entries (newest first) cut where the day-part changes.
List<HistoryPart> splitByPart(HistoryDay day) {
  final parts = <HistoryPart>[];
  for (final e in day.entries) {
    final p = dayPart(e.at.hour);
    if (parts.isNotEmpty && parts.last.part == p) {
      parts.last.entries.add(e);
    } else {
      parts.add(HistoryPart(part: p, entries: [e]));
    }
  }
  return parts;
}

/// Name suggested for a playlist made from [entries]: "Tuesday evening",
/// "Nov 3 night".
String suggestedPlaylistName(List<HistoryEntry> entries, DateTime now) {
  if (entries.isEmpty) return 'From my history';
  final first = entries.reduce((a, b) => a.at.isBefore(b.at) ? a : b);
  return '${dayLabel(first.at, now)} ${dayPart(first.at.hour)}';
}

/// From here to the end of the day's list: "Play from here" in a history
/// shows the song and the plays that came after it, in the order they were
/// heard. [index] is the position in [entries] (newest first).
List<Song> playFromHere(List<HistoryEntry> entries, int index) {
  if (index < 0 || index >= entries.length) return const [];
  // Newest-first list: the plays after this one in time are before it in the list.
  return [for (var i = index; i >= 0; i--) entries[i].song];
}
