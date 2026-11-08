import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/social/data/social_models.dart' show CollabPlaylist;
import '../../features/social/logic/social_providers.dart' show collabListProvider;
import '../../features/social/ui/collab_screens.dart' show CollabScreen, collabSubtitle, showCollabMenu;
import '../../models/album.dart';
import '../../models/playlist_access.dart';
import '../../models/artist.dart';
import '../../models/song.dart';
import '../../models/playlist.dart';
import '../../providers/library_provider.dart';
import '../../providers/pins_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/format.dart';
import '../../utils/queue_actions.dart';
import '../../widgets/art/navi_icons.dart';
import '../../widgets/collection_actions.dart';
import '../../widgets/shell/nav_stack.dart';
import '../album_details_screen.dart';
import '../artist_screen.dart';
import '../playlist_details_screen.dart';
import 'artists_page.dart';
import 'playlists_page.dart';

/// What a library list can show.
enum LibKind { playlists, albums, artists }

/// One thing in the library, whatever it is, with everything a row or a tile
/// needs: how it looks, what a click, a right-click and a hover-play do. The
/// desktop rail and the desktop Library page both draw from these, so a
/// playlist behaves the same wherever it is listed.
class LibEntry {
  final LibKind kind;
  final String id;
  final String title;

  /// "Playlist · 14 songs", "Album · Artist", "Artist".
  final String subtitle;

  /// The other column in a list view: owner / artist / album count.
  final String secondary;

  /// A number to sort by: songs in a playlist or album, albums by an artist.
  final int count;

  /// Seconds, and a release year (0: none), for the list view's columns.
  final int duration;
  final int year;
  final String? artUrl;
  final NaviGlyph placeholder;
  final bool circular;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onPlay;

  /// Set for playlists: a drop target for songs.
  final Playlist? playlist;

  const LibEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.secondary,
    required this.count,
    this.duration = 0,
    this.year = 0,
    required this.artUrl,
    required this.placeholder,
    required this.onTap,
    required this.onMenu,
    required this.onPlay,
    this.circular = false,
    this.playlist,
    this.section,
  });

  /// Which playlist section this belongs to (null for albums and artists).
  final LibSection? section;
}

/// The three kinds of playlist the Library separates, in the order shown.
enum LibSection {
  yours('Your playlists'),
  collab('Collab playlists'),
  shared('Shared with you');

  final String title;
  const LibSection(this.title);
}

/// A row of a sectioned library list: a quiet header, or an entry.
sealed class LibRow {
  const LibRow();
}

class LibHeaderRow extends LibRow {
  final LibSection section;
  final int count;

  /// Only "Shared with you" folds away.
  final bool collapsible;
  final bool collapsed;
  const LibHeaderRow(this.section, this.count, {this.collapsible = false, this.collapsed = false});
}

class LibEntryRow extends LibRow {
  final LibEntry entry;
  const LibEntryRow(this.entry);
}

/// [entries] laid out under section headers. Headers appear only when there is
/// something to separate (a section other than "Your playlists" has entries);
/// a section with nothing in it has no header; entries without a section (albums,
/// artists) pass through. [sharedCollapsed] hides the "Shared with you" entries
/// but keeps its header, with the count, so it can be opened again.
List<LibRow> sectionRows(List<LibEntry> entries, {bool sharedCollapsed = false}) {
  final sections = {for (final e in entries) if (e.section != null) e.section!};
  final separate = sections.any((s) => s != LibSection.yours);
  if (!separate) return [for (final e in entries) LibEntryRow(e)];
  final rows = <LibRow>[];
  for (final s in LibSection.values) {
    final of = [for (final e in entries) if (e.section == s) e];
    if (of.isEmpty) continue;
    final collapsed = s == LibSection.shared && sharedCollapsed;
    rows.add(LibHeaderRow(s, of.length, collapsible: s == LibSection.shared, collapsed: collapsed));
    if (!collapsed) rows.addAll([for (final e in of) LibEntryRow(e)]);
  }
  // Anything with no section (not expected in a playlists list) stays at the end.
  rows.addAll([for (final e in entries) if (e.section == null) LibEntryRow(e)]);
  return rows;
}

/// Sorts inside each section, so a sort never mixes your playlists with
/// other people's.
List<LibEntry> sortWithinSections(List<LibEntry> entries, int Function(LibEntry, LibEntry) cmp) {
  return [
    for (final s in [...LibSection.values, null])
      ...([for (final e in entries) if (e.section == s) e]..sort(cmp)),
  ];
}

/// The library's [kind], from the providers the app already keeps (the user's
/// sort preference for playlists and albums is respected).
List<LibEntry> libraryEntries(BuildContext context, WidgetRef ref, LibKind kind) {
  final svc = ref.read(subsonicServiceProvider);
  switch (kind) {
    case LibKind.playlists:
      final me = ref.watch(settingsProvider.select((s) => s.username));
      final all = ref.watch(sortedPlaylistsProvider).asData?.value ?? const <Playlist>[];
      final split = splitByOwner(all, me);
      final collabs = [
        for (final c in ref.watch(collabListProvider).asData?.value ?? const <CollabPlaylist>[])
          if (!c.invited) c,
      ];
      LibEntry playlistEntry(Playlist p, {required bool shared}) => LibEntry(
            kind: kind,
            id: 'p${p.id}',
            title: p.name,
            // Your playlists, then Collab playlists, then Shared with you (read-only).
            subtitle: shared
                ? '${(p.owner ?? '').isEmpty ? '' : '${p.owner} · '}${songCount(p.songCount)}'
                : 'Playlist · ${songCount(p.songCount)}',
            section: shared ? LibSection.shared : LibSection.yours,
            secondary: p.owner ?? '',
            count: p.songCount,
            duration: p.duration,
            artUrl: (p.coverArt ?? '').isEmpty ? null : svc.getCoverArtUrl(p.coverArt),
            placeholder: NaviGlyph.playlist,
            // Only your own playlists take dropped songs.
            playlist: shared ? null : p,
            onTap: () => navigateInApp(context, PlaylistDetailsScreen(playlist: p), title: p.name),
            onMenu: () => showPlaylistMenu(context, ref, p),
            onPlay: () => playCollection(context, ref, () => svc.getPlaylistSongs(p.id), p.name),
          );
      return [
        for (final p in split.mine) playlistEntry(p, shared: false),
        for (final c in collabs)
          LibEntry(
            kind: kind,
            id: 'c${c.id}',
            title: c.name,
            subtitle: collabSubtitle(c),
            section: LibSection.collab,
            secondary: c.owner,
            count: c.songCount,
            artUrl: null,
            placeholder: NaviGlyph.group,
            onTap: () => navigateInApp(context, CollabScreen(id: c.id), title: c.name),
            onMenu: () => showCollabMenu(context, ref, c),
            onPlay: () => navigateInApp(context, CollabScreen(id: c.id), title: c.name),
          ),
        for (final p in split.shared) playlistEntry(p, shared: true),
      ];
    case LibKind.albums:
      final list = ref.watch(sortedAlbumsProvider).asData?.value ?? const <Album>[];
      return [
        for (final a in list)
          LibEntry(
            kind: kind,
            id: 'a${a.id}',
            title: a.name,
            subtitle: 'Album · ${a.artist}',
            secondary: a.artist,
            count: a.songCount,
            duration: a.duration,
            year: a.year,
            artUrl: svc.getCoverArtUrl(a.coverArt),
            placeholder: NaviGlyph.library,
            onTap: () => navigateInApp(context, AlbumDetailsScreen(album: a)),
            onMenu: () => showCollectionActions(
              context,
              title: a.name,
              subtitle: a.artist,
              artUrl: svc.getCoverArtUrl(a.coverArt),
              placeholderIcon: NaviGlyph.library,
              loadSongs: () => svc.getAlbum(a.id),
              pin: Pin.album(a),
            ),
            onPlay: () => playCollection(context, ref, () => svc.getAlbum(a.id), a.name),
          ),
      ];
    case LibKind.artists:
      final list = ref.watch(libraryArtistsProvider).asData?.value ?? const <Artist>[];
      Future<List<Song>> songsOf(Artist a) async {
        final albums = await svc.getArtistAlbums(a.id);
        final lists = await Future.wait(albums.map((al) => svc.getAlbum(al.id)));
        return [for (final l in lists) ...l];
      }
      return [
        for (final a in list)
          LibEntry(
            kind: kind,
            id: 'r${a.id}',
            title: a.name,
            subtitle: 'Artist',
            secondary: a.albumCount == 1 ? '1 album' : '${a.albumCount} albums',
            count: a.albumCount,
            artUrl: svc.getCoverArtUrl(a.coverArtId),
            placeholder: NaviGlyph.person,
            circular: true,
            onTap: () => navigateInApp(context, ArtistScreen(artistId: a.id, name: a.name)),
            onMenu: () => showCollectionActions(
              context,
              title: a.name,
              subtitle: 'Artist',
              artUrl: svc.getCoverArtUrl(a.coverArtId),
              placeholderIcon: NaviGlyph.person,
              loadSongs: () => songsOf(a),
              pin: Pin.artist(a.id, a.name),
            ),
            onPlay: () => playCollection(context, ref, () => songsOf(a), a.name),
          ),
      ];
  }
}
