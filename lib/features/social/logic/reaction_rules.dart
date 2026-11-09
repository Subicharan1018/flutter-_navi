import 'package:flutter/widgets.dart' show StringCharacters;

import '../data/social_models.dart';
import 'social_rules.dart';

/// Pure rules for reactions on a friend's song and the weekly recap.

/// The reactions on offer. The server accepts exactly these.
const reactionEmoji = ['❤️', '🔥', '👏', '😍', '🎧', '😂'];

const reactionNoteMax = 80;

/// The note as it will be sent: whitespace collapsed, at most [reactionNoteMax]
/// characters (counting what people see, so an emoji is one).
String cleanReactionNote(String raw) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  final chars = t.characters;
  return chars.length <= reactionNoteMax ? t : chars.take(reactionNoteMax).toString();
}

/// Whether the React action is offered for [p]: they are sharing a song, the
/// server knows reactions, and social is on.
bool canReact(Person p, {required bool serverSupports}) =>
    serverSupports && p.state == PresenceState.active && p.nowPlaying != null;

/// A reaction as a notification: ("Bob reacted 🔥", "Song · Artist — “note”").
(String, String) reactionText(Reaction r) {
  final song = r.title.isEmpty ? null : (r.artist.isEmpty ? r.title : '${r.title} · ${r.artist}');
  final note = r.note.isEmpty ? null : '“${r.note}”';
  return ('${r.from} reacted ${r.emoji}', [?song, ?note].join(' — '));
}

/// Reactions to announce from a poll: newer than [lastSeen], not from a muted
/// friend, and only when it is not quiet hours. [lastSeen] null (first run)
/// treats anything older than [freshFor] as already seen, so installing the app
/// doesn't replay a day of history.
///
/// The caller always moves its mark to [highestId] even when nothing is
/// announced, so muted or quiet-hours reactions are not replayed later.
List<Reaction> reactionsToAnnounce(
  List<Reaction> inbox, {
  required int? lastSeen,
  required FriendAlertSettings settings,
  required DateTime now,
  Duration freshFor = const Duration(minutes: 30),
}) {
  if (settings.inQuietHours(now)) return const [];
  final nowS = now.millisecondsSinceEpoch ~/ 1000;
  return [
    for (final r in inbox)
      if ((lastSeen != null ? r.id > lastSeen : nowS - r.at <= freshFor.inSeconds) && !settings.isMuted(r.from)) r,
  ];
}

/// The highest id in [inbox], or [current] when it has none.
int? highestReactionId(List<Reaction> inbox, int? current) {
  var top = current;
  for (final r in inbox) {
    if (top == null || r.id > top) top = r.id;
  }
  return top;
}

// ── weekly recap ─────────────────────────────────────────────────────────────

/// "1 h 5 min", "42 min", "0 min".
String recapDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The Monday of [d]'s week as `yyyy-mm-dd`: a stable key for "this week".
String weekKey(DateTime d) {
  final monday = DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - DateTime.monday));
  return '${monday.year.toString().padLeft(4, '0')}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
}

/// The friend whose taste is closest to yours this week, for the Home card.
RecapFriend? closestFriend(WeeklyRecap r) {
  RecapFriend? best;
  for (final f in r.friends) {
    if (f.matchPct == null) continue;
    if (best == null || f.matchPct! > best.matchPct!) best = f;
  }
  return best ?? (r.friends.isEmpty ? null : r.friends.first);
}

/// One line about a friend: "74% match · 3 shared artists" (parts that exist).
String recapFriendLine(RecapFriend f) {
  if (f.hidden) return f.matchPct == null ? 'Not sharing what they listen to' : '${f.matchPct}% match';
  final parts = <String>[
    if (f.matchPct != null) '${f.matchPct}% match',
    if (f.sharedArtists.isNotEmpty) '${f.sharedArtists.length} shared ${f.sharedArtists.length == 1 ? 'artist' : 'artists'}',
    if (f.sharedSongs.isNotEmpty) '${f.sharedSongs.length} shared ${f.sharedSongs.length == 1 ? 'song' : 'songs'}',
  ];
  return parts.isEmpty ? 'Nothing shared yet this week' : parts.join(' · ');
}
