import '../../../models/playlist.dart';
import 'playlist_folders.dart';
import 'smart_rules.dart';

/// One row of the Playlists page.
sealed class PlaylistEntry {
  const PlaylistEntry();
}

class FolderEntry extends PlaylistEntry {
  final PlaylistFolder folder;

  /// Playlists in the folder that still exist.
  final int count;
  const FolderEntry(this.folder, this.count);
}

/// A server playlist ([server]) or a smart one ([smart]) — exactly one is set.
class ItemEntry extends PlaylistEntry {
  final Playlist? server;
  final SmartPlaylist? smart;

  /// Shown indented under its (expanded) folder.
  final bool inFolder;

  const ItemEntry({this.server, this.smart, this.inFolder = false}) : assert((server == null) != (smart == null));

  String get id => server?.id ?? smart!.id;
}

/// The Playlists page as a flat list: pinned folders, other folders (each
/// followed by its playlists when expanded), then the playlists that aren't
/// in a folder. Smart playlists come before server ones; [server] keeps the
/// order the person sorted it in.
List<PlaylistEntry> buildPlaylistEntries({
  required PlaylistFolders folders,
  required List<SmartPlaylist> smart,
  required List<Playlist> server,
}) {
  final items = <ItemEntry>[
    for (final s in smart) ItemEntry(smart: s),
    for (final p in server) ItemEntry(server: p),
  ];
  final byFolder = <String, List<ItemEntry>>{};
  final loose = <ItemEntry>[];
  for (final item in items) {
    final folderId = folders.folderOf(item.id);
    if (folderId != null && folders.folder(folderId) != null) {
      (byFolder[folderId] ??= []).add(item);
    } else {
      loose.add(item);
    }
  }
  return [
    for (final f in folders.ordered) ...[
      FolderEntry(f, byFolder[f.id]?.length ?? 0),
      if (f.expanded)
        for (final item in byFolder[f.id] ?? const <ItemEntry>[])
          ItemEntry(server: item.server, smart: item.smart, inFolder: true),
    ],
    ...loose,
  ];
}
