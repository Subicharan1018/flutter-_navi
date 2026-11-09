import '../../../models/playlist.dart';
import '../../../models/playlist_access.dart';

// =============================================================================
// shared_inbox.dart — the "Shared with you" inbox: other people's playlists the
// server lists for you, minus the ones you dismissed, each flagged new until
// you've looked. Pure; the providers keep the id sets in local prefs per user.
// =============================================================================

class InboxEntry {
  final Playlist playlist;
  final bool isNew;
  const InboxEntry(this.playlist, this.isNew);
}

class SharedInbox {
  final List<InboxEntry> entries;
  const SharedInbox(this.entries);

  /// Playlists that appeared since the inbox was last opened: the badge.
  int get newCount => entries.where((e) => e.isNew).length;
  bool get isEmpty => entries.isEmpty;
}

/// Others' playlists for [user], without [dismissed]; new when not in [seen].
/// Newest-looking first: new entries on top, the rest by name.
SharedInbox buildSharedInbox(
  Iterable<Playlist> all,
  String user, {
  required Set<String> seen,
  required Set<String> dismissed,
}) {
  final entries = [
    for (final p in all)
      if (p.isSharedFor(user) && !dismissed.contains(p.id)) InboxEntry(p, !seen.contains(p.id)),
  ];
  entries.sort((a, b) {
    if (a.isNew != b.isNew) return a.isNew ? -1 : 1;
    return a.playlist.name.toLowerCase().compareTo(b.playlist.name.toLowerCase());
  });
  return SharedInbox(entries);
}

/// Prefs key for one user's set, so two accounts on a device keep apart.
String inboxPrefsKey(String what, String user) => 'shared_inbox_${what}_${user.trim().toLowerCase()}';
