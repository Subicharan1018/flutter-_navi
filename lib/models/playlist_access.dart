import 'playlist.dart';

/// Who may change a playlist. Spotify-style: you edit your own; other people's
/// playlists (public ones the server lists, "Shared with you") are read-only
/// for everyone, a Jam admin included. To change one, make a copy.
extension PlaylistOwnership on Playlist {
  /// True when [user] owns this playlist. A playlist whose owner the server
  /// doesn't report is treated as the user's own (older servers list only
  /// your playlists).
  bool isOwnedBy(String user) {
    final o = owner;
    if (o == null || o.isEmpty) return true;
    return o.toLowerCase() == user.toLowerCase();
  }

  /// Someone else's playlist, read-only here.
  bool isSharedFor(String user) => !isOwnedBy(user);
}

/// Splits a list into what [user] owns and what others own.
({List<Playlist> mine, List<Playlist> shared}) splitByOwner(Iterable<Playlist> all, String user) {
  final mine = <Playlist>[];
  final shared = <Playlist>[];
  for (final p in all) {
    (p.isOwnedBy(user) ? mine : shared).add(p);
  }
  return (mine: mine, shared: shared);
}

/// Thrown when something tries to change a playlist the person doesn't own.
class PlaylistNotEditable implements Exception {
  final String playlistId;
  final String? owner;
  const PlaylistNotEditable(this.playlistId, this.owner);

  String get message => owner == null || owner!.isEmpty
      ? 'This playlist isn’t yours to change. Make a copy to edit it.'
      : 'This playlist belongs to $owner. Make a copy to edit it.';

  @override
  String toString() => message;
}

/// The one gate every playlist change passes through. It learns who owns what
/// from the lists the server returns and refuses to write to anything that
/// isn't the current user's, so no screen (a room, a picker, a menu) can
/// change someone else's playlist by accident.
class PlaylistAccess {
  final String username;
  final Map<String, String?> _owners = {};
  PlaylistAccess(this.username);

  /// Remember the owners in a freshly loaded list.
  void learn(Iterable<Playlist> playlists) {
    for (final p in playlists) {
      _owners[p.id] = p.owner;
    }
  }

  void learnOne(Playlist p) => _owners[p.id] = p.owner;

  bool canEdit(String playlistId) {
    if (!_owners.containsKey(playlistId)) return true; // unknown: the server still enforces its own rules
    final o = _owners[playlistId];
    return o == null || o.isEmpty || o.toLowerCase() == username.toLowerCase();
  }

  /// Throws [PlaylistNotEditable] unless [playlistId] is the user's.
  void requireEditable(String playlistId) {
    if (!canEdit(playlistId)) throw PlaylistNotEditable(playlistId, _owners[playlistId]);
  }
}
