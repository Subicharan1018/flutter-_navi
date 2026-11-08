import '../data/social_models.dart';

/// Who may do what with a collaborative playlist. Plain functions so the rules
/// are tested without a screen; the server enforces the same ones.

/// Every active collaborator (owner included) adds, removes and reorders songs.
bool canEditCollab(CollabPlaylist p, String me) => p.status == 'active';

/// Only the owner renames, deletes, invites or removes other people.
bool canManageCollab(CollabPlaylist p, String me) => p.isOwner;

/// A playlist someone else owns and you collaborate on (as opposed to one of
/// your own, or a read-only one shared with you).
bool isCollabOfOthers(CollabPlaylist p) => p.status == 'active' && !p.isOwner;

/// Active collaborators in the order they joined, the owner first.
List<CollabMember> collaborators(CollabPlaylist p) {
  final active = [for (final m in p.members) if (m.active) m];
  active.sort((a, b) => (a.username.toLowerCase() == p.owner.toLowerCase() ? 0 : 1)
      .compareTo(b.username.toLowerCase() == p.owner.toLowerCase() ? 0 : 1));
  return active;
}

/// Who added how many songs, most first (ties by name).
List<(String, int)> contributions(CollabPlaylist p) {
  final counts = <String, int>{};
  for (final s in p.songs) {
    counts[s.addedBy] = (counts[s.addedBy] ?? 0) + 1;
  }
  final out = [for (final e in counts.entries) (e.key, e.value)];
  out.sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
  return out;
}

/// [items] with the element at [from] moved so it ends up at [to] (the index
/// after it is taken out, which is what the server's `move` and the reorderable
/// list both use).
List<T> movedTo<T>(List<T> items, int from, int to) {
  if (from < 0 || from >= items.length || to < 0 || to >= items.length || from == to) return [...items];
  final next = [...items];
  next.insert(to, next.removeAt(from));
  return next;
}

// ── Room extras ──────────────────────────────────────────────────────────────

/// "just now", "3 min ago", "2 hr ago".
String agoText(int seconds) {
  if (seconds < 60) return 'just now';
  final m = seconds ~/ 60;
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  return h < 24 ? '$h hr ago' : '${h ~/ 24} d ago';
}

/// One line for the admin: who is asking to skip.
String skipRequestSummary(List<SkipRequest> requests) {
  final names = [for (final r in requests) r.username];
  return switch (names.length) {
    0 => '',
    1 => '${names[0]} asks to skip',
    2 => '${names[0]} and ${names[1]} ask to skip',
    final n => '${names[0]} and ${n - 1} others ask to skip',
  };
}

/// Whether this person is offered "Ask to skip": a Jam member who can't skip
/// themselves, with a song playing. (A Collab room needs no requests.)
bool canRequestSkip(JamState jam) => !jam.youCanEdit && !jam.isCollab && jam.current != null;

/// "Recently left" line: "left 3 min ago" or "removed 2 min ago".
String leftLine(LeftMember m) => '${m.removed ? 'Removed' : 'Left'} ${agoText(m.agoS)}';

/// What to do with a removal's toast: the text, and whether Undo applies (only
/// whoever may edit can put it back).
({String text, bool canUndo}) removalToast(JamState jam, String title) =>
    (text: 'Removed $title', canUndo: jam.youCanEdit);

// ── People ───────────────────────────────────────────────────────────────────

/// Sorted for display: listening now first, then idle, offline, not sharing.
List<Person> sortPeople(Iterable<Person> people) {
  final list = [...people];
  list.sort((a, b) {
    final c = a.state.index.compareTo(b.state.index);
    return c != 0 ? c : a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });
  return list;
}

/// What a person's row says under their name.
String presenceLine(Person p) {
  switch (p.state) {
    case PresenceState.active:
      final s = p.nowPlaying;
      final song = s == null ? null : (s.artist.isEmpty ? s.title : '${s.title} · ${s.artist}');
      final room = p.room == null ? null : 'in a ${p.room!.mode.label} room';
      return [?song, ?room].isEmpty ? 'Listening now' : [?song, ?room].join(' · ');
    case PresenceState.idle:
      return 'Idle';
    case PresenceState.offline:
      return 'Offline';
    case PresenceState.hidden:
      return 'Not sharing what they listen to';
  }
}

/// Whether the Join action is offered: they are in a room that is open to
/// friends and you are not already in it.
bool canJoin(Person p) => p.state == PresenceState.active && (p.room?.joinable ?? false);

// ── Friend alerts ────────────────────────────────────────────────────────────

class FriendAlertSettings {
  /// Off until the person turns it on.
  final bool enabled;

  /// Friends whose alerts are silenced (lower-case names).
  final Set<String> muted;

  /// Quiet hours as minutes after midnight, local time; null for none.
  final int? quietFromMin;
  final int? quietToMin;
  const FriendAlertSettings({this.enabled = false, this.muted = const {}, this.quietFromMin, this.quietToMin});

  FriendAlertSettings copyWith({bool? enabled, Set<String>? muted, Object? quietFromMin = _keep, Object? quietToMin = _keep}) =>
      FriendAlertSettings(
        enabled: enabled ?? this.enabled,
        muted: muted ?? this.muted,
        quietFromMin: identical(quietFromMin, _keep) ? this.quietFromMin : quietFromMin as int?,
        quietToMin: identical(quietToMin, _keep) ? this.quietToMin : quietToMin as int?,
      );

  static const Object _keep = Object();

  bool isMuted(String name) => muted.contains(name.toLowerCase());

  /// Is [now] inside quiet hours (which may wrap past midnight)?
  bool inQuietHours(DateTime now) {
    final from = quietFromMin, to = quietToMin;
    if (from == null || to == null || from == to) return false;
    final m = now.hour * 60 + now.minute;
    return from < to ? (m >= from && m < to) : (m >= from || m < to);
  }
}

class FriendAlert {
  final String username;
  final FriendSong? song;

  /// Set when they are in a room you can join: the alert gets a Join action.
  final String? joinCode;
  final JamMode? roomMode;
  const FriendAlert(this.username, {this.song, this.joinCode, this.roomMode});
}

/// Decides which "friend started listening" alerts to raise from two polls of
/// People. Holds the rate-limit memory; everything else is a pure function of
/// its inputs.
///
/// An alert needs all of: alerts on, not quiet hours, the friend not muted,
/// the friend sharing (not hidden), a change *to* listening (not a song change,
/// not the first poll), and 30 minutes since this friend's last alert.
class FriendAlertPolicy {
  final Duration minGap;
  final Map<String, DateTime> _last = {};
  FriendAlertPolicy({this.minGap = const Duration(minutes: 30)});

  List<FriendAlert> evaluate({
    required PeopleList? previous,
    required PeopleList current,
    required FriendAlertSettings settings,
    required DateTime now,
  }) {
    // The first poll only sets the baseline: nobody "just started".
    if (previous == null || !settings.enabled || !current.enabled || settings.inQuietHours(now)) return const [];
    final before = {for (final p in previous.people) p.username.toLowerCase(): p.state};
    final out = <FriendAlert>[];
    for (final p in current.people) {
      final key = p.username.toLowerCase();
      if (p.state != PresenceState.active) continue; // idle, offline and hidden never alert
      if (before[key] == PresenceState.active) continue; // already listening: a song change is not news
      if (!before.containsKey(key)) continue; // newly listed (just turned social on): no alert
      if (settings.isMuted(p.username)) continue;
      final last = _last[key];
      if (last != null && now.difference(last) < minGap) continue;
      _last[key] = now;
      out.add(FriendAlert(
        p.username,
        song: p.nowPlaying,
        joinCode: canJoin(p) ? p.room!.code : null,
        roomMode: p.room?.mode,
      ));
    }
    return out;
  }
}
