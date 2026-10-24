/// Client-side playlist folders. Navidrome has no folders, so they live on the
/// device: a list of folders and a playlist-id → folder-id map. Server and
/// smart playlists share one id space ('smart:…' never collides), so the same
/// map holds both. A playlist is in at most one folder.
class PlaylistFolder {
  final String id;
  final String name;
  final bool pinned;
  final bool expanded;

  const PlaylistFolder({required this.id, required this.name, this.pinned = false, this.expanded = true});

  PlaylistFolder copyWith({String? name, bool? pinned, bool? expanded}) => PlaylistFolder(
        id: id,
        name: name ?? this.name,
        pinned: pinned ?? this.pinned,
        expanded: expanded ?? this.expanded,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'pinned': pinned, 'expanded': expanded};

  static PlaylistFolder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return PlaylistFolder(
      id: id,
      name: raw['name']?.toString() ?? 'Folder',
      pinned: raw['pinned'] == true,
      expanded: raw['expanded'] != false,
    );
  }
}

/// Immutable folder state; every change returns a new one.
class PlaylistFolders {
  final List<PlaylistFolder> folders;

  /// playlist id → folder id.
  final Map<String, String> membership;

  const PlaylistFolders({this.folders = const [], this.membership = const {}});

  static const empty = PlaylistFolders();

  PlaylistFolder? folder(String id) => folders.where((f) => f.id == id).firstOrNull;

  /// The folder [playlistId] is in, if any.
  String? folderOf(String playlistId) => membership[playlistId];

  /// Folders as the Playlists page lists them: pinned first, each group in
  /// the order the folders were made.
  List<PlaylistFolder> get ordered => [
        ...folders.where((f) => f.pinned),
        ...folders.where((f) => !f.pinned),
      ];

  List<String> playlistIdsIn(String folderId) => [
        for (final e in membership.entries)
          if (e.value == folderId) e.key,
      ];

  int countIn(String folderId) => membership.values.where((v) => v == folderId).length;

  /// A new folder named [name] (trimmed; blank names are ignored). Names
  /// needn't be unique — the id is what identifies a folder.
  PlaylistFolders create(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty || folder(id) != null) return this;
    return PlaylistFolders(folders: [...folders, PlaylistFolder(id: id, name: clean)], membership: membership);
  }

  PlaylistFolders rename(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty) return this;
    return _mapFolder(id, (f) => f.copyWith(name: clean));
  }

  PlaylistFolders setPinned(String id, bool pinned) => _mapFolder(id, (f) => f.copyWith(pinned: pinned));

  PlaylistFolders setExpanded(String id, bool expanded) => _mapFolder(id, (f) => f.copyWith(expanded: expanded));

  /// Removes the folder; its playlists go back to the top level, untouched.
  PlaylistFolders delete(String id) => PlaylistFolders(
        folders: [for (final f in folders) if (f.id != id) f],
        membership: {
          for (final e in membership.entries)
            if (e.value != id) e.key: e.value,
        },
      );

  /// Puts [playlistId] in [folderId], or back at the top level when null.
  /// An unknown folder is ignored.
  PlaylistFolders move(String playlistId, String? folderId) {
    final next = {...membership};
    if (folderId == null) {
      next.remove(playlistId);
    } else if (folder(folderId) != null) {
      next[playlistId] = folderId;
    } else {
      return this;
    }
    return PlaylistFolders(folders: folders, membership: next);
  }

  PlaylistFolders _mapFolder(String id, PlaylistFolder Function(PlaylistFolder) fn) {
    if (folder(id) == null) return this;
    return PlaylistFolders(folders: [for (final f in folders) f.id == id ? fn(f) : f], membership: membership);
  }

  Map<String, dynamic> toJson() => {
        'folders': [for (final f in folders) f.toJson()],
        'membership': membership,
      };

  factory PlaylistFolders.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final folders = [for (final f in (raw['folders'] as List? ?? const [])) ?PlaylistFolder.fromJson(f)];
    final ids = {for (final f in folders) f.id};
    final members = raw['membership'];
    return PlaylistFolders(
      folders: folders,
      membership: {
        if (members is Map)
          for (final e in members.entries)
            if (ids.contains(e.value?.toString())) e.key.toString(): e.value.toString(),
      },
    );
  }
}
