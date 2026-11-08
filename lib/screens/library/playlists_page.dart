import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../features/smart_playlists/data/playlist_entries.dart';
import '../../features/smart_playlists/data/playlist_folders.dart';
import '../../features/smart_playlists/data/smart_rules.dart';
import '../../features/smart_playlists/logic/smart_playlist_providers.dart';
import '../../features/smart_playlists/ui/rule_editor_screen.dart';
import '../../features/smart_playlists/ui/smart_actions.dart';
import '../../features/smart_playlists/ui/smart_playlist_screen.dart';
import '../../features/smart_playlists/ui/smart_widgets.dart';
import '../../features/social/data/social_models.dart' show CollabPlaylist;
import '../../features/social/logic/social_providers.dart' show collabListProvider, socialEnabledProvider;
import '../../features/social/ui/collab_screens.dart' show CollabRow, createCollab;
import '../../models/playlist.dart';
import '../../models/playlist_access.dart';
import '../../providers/library_provider.dart';
import '../../providers/pins_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/format.dart';
import '../../utils/playlist_actions.dart';
import '../../widgets/app_scaffold.dart' show navigateInApp;
import '../../widgets/art/navi_icons.dart';
import '../../widgets/collection_actions.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/desktop_dialogs.dart';
import '../../widgets/ui/action_sheet.dart';
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/media.dart';
import 'library_entries.dart' show LibSection;
import '../../widgets/ui/states.dart';
import '../playlist_editor.dart';
import '../favorites_screen.dart';
import '../playlist_details_screen.dart';

/// Playlists: the "New…" rows and Favorites first, then folders (pinned
/// first, expandable) and the playlists — smart ones marked with a badge.
class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final playlists = ref.watch(sortedPlaylistsProvider);
    final smart = ref.watch(smartPlaylistsProvider);
    final folders = ref.watch(playlistFoldersProvider);

    Widget glyphTile(NaviGlyph icon) => Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: t.bgSurface, borderRadius: BorderRadius.circular(Radii.cover)),
          alignment: Alignment.center,
          child: NaviIcon(icon, color: t.accent, size: 26),
        );

    Widget row(PlaylistEntry e) => switch (e) {
          FolderEntry() => _folderRow(context, ref, e),
          ItemEntry(:final smart?) => _smartRow(context, ref, smart, e.inFolder),
          ItemEntry(:final server?) => _serverRow(context, ref, server, e.inFolder),
          ItemEntry() => const SizedBox.shrink(),
        };

    return LargeTitlePage(
      title: 'Playlists',
      onRefresh: () async => ref.invalidate(playlistsProvider),
      slivers: [
        SliverList.list(children: [
          CollectionRow(
            title: 'New Playlist…',
            titleColor: t.accent,
            leading: glyphTile(NaviGlyph.plus),
            showChevron: false,
            onTap: () => showPlaylistEditor(context),
          ),
          CollectionRow(
            title: 'New Smart Playlist…',
            titleColor: t.accent,
            leading: const GlyphTile(NaviGlyph.smart, accent: true),
            showChevron: false,
            onTap: () async {
              final created = await showSmartPlaylistEditor(context);
              if (created != null && context.mounted) navigateInApp(context, SmartPlaylistScreen(playlistId: created.id));
            },
          ),
          CollectionRow(
            title: 'New Folder…',
            titleColor: t.accent,
            leading: const GlyphTile(NaviGlyph.folder, accent: true),
            showChevron: false,
            onTap: () async {
              final name = await showNamePrompt(context, title: 'New Folder', confirmLabel: 'Create', placeholder: 'Folder name');
              if (name != null) ref.read(playlistFoldersProvider.notifier).create(name);
            },
          ),
          CollectionRow(
            title: 'Favorites',
            subtitle: 'Songs you starred',
            leading: glyphTile(NaviGlyph.star),
            onTap: () => navigateInApp(context, const FavoritesScreen()),
          ),
        ]),
        ...playlists.when(
          loading: () => const [SliverToBoxAdapter(child: LoadingState())],
          error: (_, _) {
            // Folders and smart playlists live on the device, so they stay
            // usable while the server list can't load.
            final local = buildPlaylistEntries(folders: folders, smart: smart, server: const []);
            return [
              SliverList.builder(itemCount: local.length, itemBuilder: (context, i) => row(local[i])),
              SliverToBoxAdapter(
                child: MessageState.error(title: 'Couldn’t load playlists', onRetry: () => ref.invalidate(playlistsProvider)),
              ),
            ];
          },
          data: (list) {
            // Yours first, editable; other people's in their own section, read-only.
            final split = splitByOwner(list, ref.watch(settingsProvider.select((s) => s.username)));
            final entries = buildPlaylistEntries(folders: folders, smart: smart, server: split.mine);
            final hasCollab = (ref.watch(collabListProvider).asData?.value ?? const <CollabPlaylist>[]).any((c) => !c.invited);
            final separated = split.shared.isNotEmpty || hasCollab || ref.watch(socialEnabledProvider);
            return [
              // Yours first, under its own header once there is something to tell it apart from.
              if (separated) SliverToBoxAdapter(child: SectionHeader(title: LibSection.yours.title)),
              SliverList.builder(itemCount: entries.length, itemBuilder: (context, i) => row(entries[i])),
              // Playlists several people edit: collaborators shown, each song's contributor inside.
              const SliverToBoxAdapter(child: _CollabPlaylists()),
              // Other people's playlists: read-only, below, folds away.
              if (split.shared.isNotEmpty)
                SliverToBoxAdapter(
                  child: SharedPlaylistsSection(
                    count: split.shared.length,
                    rows: [for (final p in split.shared) _serverRow(context, ref, p, false)],
                  ),
                ),
            ];
          },
        ),
      ],
    );
  }

  static const _indent = Space.xl;

  Widget _folderRow(BuildContext context, WidgetRef ref, FolderEntry e) {
    final t = ThemeTokens.of(context);
    final f = e.folder;
    return CollectionRow(
      key: ValueKey(f.id),
      title: f.name,
      subtitle: e.count == 0 ? 'Empty' : '${e.count} ${e.count == 1 ? 'playlist' : 'playlists'}',
      leading: const GlyphTile(NaviGlyph.folder),
      badge: f.pinned ? NaviIcon(NaviGlyph.pin, size: 13, color: t.textMuted) : null,
      trailing: AnimatedRotation(
        turns: f.expanded ? 0.25 : 0,
        duration: const Duration(milliseconds: 180),
        child: NaviIcon(NaviGlyph.chevron, size: 16, color: t.textMuted),
      ),
      onTap: () => ref.read(playlistFoldersProvider.notifier).setExpanded(f.id, !f.expanded),
      onLongPress: () => _folderActions(context, ref, f, e.count),
    );
  }

  Widget _smartRow(BuildContext context, WidgetRef ref, SmartPlaylist p, bool inFolder) {
    final rules = p.rules.ruleCount;
    return Padding(
      key: ValueKey(p.id),
      padding: EdgeInsets.only(left: inFolder ? _indent : 0),
      child: CollectionRow(
        title: p.name,
        subtitle: rules == 1 ? '1 rule' : '$rules rules',
        leading: SmartCover(id: p.id, size: 56),
        badge: const SmartBadge(),
        onTap: () => navigateInApp(context, SmartPlaylistScreen(playlistId: p.id)),
        onLongPress: () => showSmartPlaylistActions(context, p),
      ),
    );
  }

  Widget _serverRow(BuildContext context, WidgetRef ref, Playlist p, bool inFolder) {
    final svc = ref.read(subsonicServiceProvider);
    final art = (p.coverArt ?? '').isEmpty ? null : svc.getCoverArtUrl(p.coverArt);
    return Padding(
      key: ValueKey(p.id),
      padding: EdgeInsets.only(left: inFolder ? _indent : 0),
      child: CollectionRow(
        title: p.name,
        subtitle: p.isSharedFor(ref.read(settingsProvider).username) && (p.owner ?? '').isNotEmpty
            ? '${songCount(p.songCount)} · ${p.owner}'
            : songCount(p.songCount),
        leading: CoverArt(url: art, size: 56, radius: Radii.cover, placeholderIcon: NaviGlyph.playlist),
        onTap: () => navigateInApp(context, PlaylistDetailsScreen(playlist: p)),
        onLongPress: () => showPlaylistMenu(context, ref, p),
      ),
    );
  }

  void _folderActions(BuildContext context, WidgetRef ref, PlaylistFolder f, int count) {
    final t = ThemeTokens.of(context);
    final folders = ref.read(playlistFoldersProvider.notifier);
    showPlatformSheet<void>(
      context: context,
      title: f.name,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetGroup(children: [
            SheetAction(
              label: 'Rename Folder',
              trailing: NaviIcon(NaviGlyph.edit, size: 21, color: t.textPrimary),
              onTap: () async {
                final name = await showNamePrompt(
                  context,
                  title: 'Rename Folder',
                  confirmLabel: 'Rename',
                  initial: f.name,
                  placeholder: 'Folder name',
                );
                if (name != null) folders.rename(f.id, name);
              },
            ),
            SheetAction(
              label: f.pinned ? 'Unpin Folder' : 'Pin Folder',
              detail: f.pinned ? null : 'Keeps it at the top of Playlists',
              trailing: NaviIcon(NaviGlyph.pin, size: 21, color: t.textPrimary, filled: f.pinned),
              onTap: () => folders.setPinned(f.id, !f.pinned),
            ),
          ]),
          SheetGroup(children: [
            SheetAction(
              label: 'Delete Folder',
              detail: count == 0 ? null : 'Its playlists stay, back at the top level',
              destructive: true,
              trailing: NaviIcon(NaviGlyph.trash, size: 21, color: t.danger),
              onTap: () async {
                final ok = await confirmDestructive(
                  context,
                  title: 'Delete “${f.name}”?',
                  message: 'Only the folder is removed. Its playlists stay in your library.',
                  confirmLabel: 'Delete',
                );
                if (ok) folders.delete(f.id);
              },
            ),
          ]),
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }
}

/// "Shared with you": other people's playlists, read-only. The header folds the
/// list away and says how many there are.
class SharedPlaylistsSection extends StatefulWidget {
  final int count;
  final List<Widget> rows;
  const SharedPlaylistsSection({super.key, required this.count, required this.rows});

  @override
  State<SharedPlaylistsSection> createState() => _SharedPlaylistsSectionState();
}

class _SharedPlaylistsSectionState extends State<SharedPlaylistsSection> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        header: true,
        button: true,
        expanded: _open,
        label: '${LibSection.shared.title}, ${widget.count}',
        child: CupertinoClickable(
          onTap: () => setState(() => _open = !_open),
          scaleFactor: 0.99,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pageGutter(context), Space.xxl, pageGutter(context), Space.md),
            child: Row(children: [
              Expanded(child: Text(LibSection.shared.title, style: t.title2, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${widget.count}', style: t.subheadline),
              const SizedBox(width: Space.sm),
              AnimatedRotation(
                turns: _open ? 0.25 : 0,
                duration: const Duration(milliseconds: 180),
                child: NaviIcon(NaviGlyph.chevron, size: 18, color: t.textMuted),
              ),
            ]),
          ),
        ),
      ),
      if (_open) ...widget.rows,
    ]);
  }
}

/// "Collab playlists": the ones you share with people (you own it, or you were
/// invited and joined). Hidden while social features are off and you have none.
class _CollabPlaylists extends ConsumerWidget {
  const _CollabPlaylists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final enabled = ref.watch(socialEnabledProvider);
    final lists = ref.watch(collabListProvider).asData?.value ?? const <CollabPlaylist>[];
    final mine = [for (final p in lists) if (!p.invited) p];
    if (!enabled && mine.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title: LibSection.collab.title),
      for (final p in mine) CollabRow(playlist: p),
      if (enabled)
        CollectionRow(
          title: 'New Collab Playlist…',
          titleColor: t.accent,
          leading: SizedBox(width: 56, height: 56, child: Center(child: NaviIcon(NaviGlyph.group, size: 26, color: t.accent))),
          showChevron: false,
          showSeparator: false,
          onTap: () => createCollab(context, ProviderScope.containerOf(context)),
        ),
    ]);
  }
}

/// The playlist menu (Play, Shuffle, queue, Rename, Delete, Pin, Move to Folder):
/// a long-press sheet on a phone, a right-click menu on desktop. One definition,
/// used by Library and by the sidebar's playlist rows.
void showPlaylistMenu(BuildContext context, WidgetRef ref, Playlist p) {
  final svc = ref.read(subsonicServiceProvider);
  // Someone else's playlist: no Edit, Delete or folder; Make a Copy instead.
  final shared = p.isSharedFor(ref.read(settingsProvider).username);
  showCollectionActions(
    context,
    title: p.name,
    subtitle: songCount(p.songCount),
    artUrl: (p.coverArt ?? '').isEmpty ? null : svc.getCoverArtUrl(p.coverArt),
    loadSongs: () => svc.getPlaylistSongs(p.id),
    onEdit: shared ? null : () => showPlaylistEditor(context, playlist: p),
    onDelete: shared ? null : () => deletePlaylistWithConfirm(context, ref, p),
    pin: Pin.playlist(p),
    extraActions: [
      if (shared)
        SheetAction(
          label: 'Make a Copy',
          icon: NaviGlyph.copy,
          onTap: () async {
            try {
              final copy = await ref.read(playlistControllerProvider).makeCopy(p);
              if (context.mounted) showToast(context, 'Copied to “${copy.name}”');
            } catch (_) {
              if (context.mounted) showToast(context, 'Couldn’t make a copy. Try again.');
            }
          },
        )
      else
        FolderMoveAction(playlistId: p.id, page: context),
    ],
  );
}
