import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/focus/navi_focus.dart';
import '../../../core/theme.dart';
import '../../ui/navi_icon_button.dart';
import '../../../features/online_fetch/logic/online_fetch_providers.dart';
import '../../../features/social/logic/jam_controller.dart' show jamControllerProvider;
import '../../../features/social/logic/social_providers.dart' show invitationCountProvider;
import '../../../features/online_fetch/ui/fetch_activity.dart';
import '../../../models/playlist.dart';
import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../screens/favorites_screen.dart';
import '../../../screens/library/library_entries.dart';
import '../../../screens/library/songs_page.dart';
import '../../../screens/playlist_editor.dart';
import '../../../screens/settings_screen.dart';
import '../../art/navi_icons.dart';
import '../../cover_art.dart';
import '../../desktop_dialogs.dart';
import '../../table/song_table.dart' show SongDrag;
import '../../ui/action_sheet.dart';
import '../../ui/playlist_cover.dart';
import '../app_tab.dart';
import '../nav_stack.dart';
import 'desktop_layout.dart';

// =============================================================================
// library_rail.dart — the left rail of the desktop window.
//
// Home, Shuffle, Jam and Stats on top as compact items, then Your Library: what
// you own, filtered (Playlists, Albums, Artists), searched and sorted. It can
// be dragged wider or narrower, and collapsed to icons; the width is
// remembered ([DesktopLayout]). Playlists take right-click and songs dropped
// from a table.
// =============================================================================

enum RailFilter { playlists, albums, artists }

enum RailSort { library, alphabetical }

class LibraryRail extends ConsumerStatefulWidget {
  final AppTab tab;
  final ValueChanged<AppTab> onSelect;

  /// The window is narrow: always icons, whatever was chosen.
  final bool forceCollapsed;
  const LibraryRail({super.key, required this.tab, required this.onSelect, this.forceCollapsed = false});

  @override
  ConsumerState<LibraryRail> createState() => _LibraryRailState();
}

class _LibraryRailState extends ConsumerState<LibraryRail> {
  final _find = TextEditingController();
  RailFilter? _filter = RailFilter.playlists;
  RailSort _sort = RailSort.library;

  @override
  void dispose() {
    _find.dispose();
    super.dispose();
  }

  /// Songs dropped on a playlist row: add them, say so.
  Future<void> _addDropped(BuildContext context, Playlist p, List<Song> songs) async {
    final svc = ref.read(subsonicServiceProvider);
    try {
      for (final s in songs) {
        await svc.updatePlaylist(p.id, songIdToAdd: s.id);
      }
      ref.invalidate(playlistsProvider);
      if (context.mounted) {
        showToast(context, songs.length == 1 ? 'Added “${songs.first.title}” to ${p.name}' : 'Added ${songs.length} songs to ${p.name}');
      }
    } catch (_) {
      if (context.mounted) showToast(context, 'Couldn’t add to ${p.name}. Try again.');
    }
  }

  void _sortMenu() {
    showDesktopMenu<void>(
      context: context,
      width: 200,
      builder: (_) => SheetGroup(children: [
        for (final (s, label) in const [(RailSort.library, 'Library order'), (RailSort.alphabetical, 'Alphabetical')])
          SheetAction(
            label: label,
            icon: _sort == s ? NaviGlyph.check : null,
            onTap: () => setState(() => _sort = s),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jamLive = ref.watch(jamControllerProvider.select((s) => s.jam != null));
    final invites = ref.watch(invitationCountProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([DesktopLayout.railWidth, DesktopLayout.railCollapsed]),
      builder: (context, _) {
        final collapsed = widget.forceCollapsed || DesktopLayout.railCollapsed.value;
        final width = collapsed ? DesktopLayout.railIcons : DesktopLayout.railWidth.value;
        return ColoredBox(
          color: Colors.transparent, // the window's one ground shows through
          child: SizedBox(
            width: width,
            child: FocusTraversalGroup(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(collapsed ? Space.sm : Space.md, Space.md, collapsed ? Space.sm : Space.md, 0),
                    child: Column(
                      children: [
                        for (final dest in AppTab.browseTabs)
                          RailRow(
                            icon: dest.icon,
                            label: dest.label,
                            iconOnly: collapsed,
                            selected: widget.tab == dest,
                            // A live Jam or a waiting invitation: a dot on Jam.
                            dot: dest == AppTab.jam && (jamLive || invites > 0),
                            onTap: () => widget.onSelect(dest),
                          ),
                        const _DownloadsRow(),
                      ],
                    ),
                  ),
                  _LibraryHeader(
                    collapsed: collapsed,
                    forced: widget.forceCollapsed,
                    selected: widget.tab == AppTab.library,
                    onOpen: () => widget.onSelect(AppTab.library),
                  ),
                  if (!collapsed) ...[
                    _Filters(
                      filter: _filter,
                      onChange: (f) => setState(() => _filter = f),
                    ),
                    _FindRow(controller: _find, sort: _sort, onSort: _sortMenu),
                  ],
                  Expanded(
                    // Only the list listens to the find box: a keystroke rebuilds it,
                    // not the whole rail.
                    // The list fades out above the Settings entry instead of being cut
                    // through a row.
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (r) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                        stops: [0, 0.94, 1],
                      ).createShader(r),
                      child: ListenableBuilder(
                        listenable: _find,
                        builder: (context, _) => _LibraryList(
                          collapsed: collapsed,
                          filter: _filter,
                          sort: _sort,
                          query: _find.text.trim().toLowerCase(),
                          onDrop: _addDropped,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: collapsed ? Space.sm : Space.md),
                    child: Divider(height: 1, thickness: 0.5, color: ThemeTokens.of(context).outline),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(collapsed ? Space.sm : Space.md, Space.xs, collapsed ? Space.sm : Space.md, Space.md),
                    child: RailRow(
                      icon: NaviGlyph.gear,
                      label: 'Settings',
                      iconOnly: collapsed,
                      onTap: () => navigateInApp(context, const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Header, filters, find ────────────────────────────────────────────────────

class _LibraryHeader extends StatelessWidget {
  final bool collapsed;
  final bool forced;
  final bool selected;
  final VoidCallback onOpen;
  const _LibraryHeader({required this.collapsed, required this.forced, required this.selected, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, Space.xs),
        child: Column(
          children: [
            RailRow(icon: NaviGlyph.library, label: 'Your Library', iconOnly: true, selected: selected, onTap: onOpen),
            if (!forced)
              RailRow(
                icon: NaviGlyph.sidebarToggle,
                label: 'Expand the library',
                iconOnly: true,
                onTap: () => DesktopLayout.setCollapsed(false),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.sm, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: NaviFocusable(
              radius: 6,
              onTap: onOpen,
              semanticLabel: 'Open Your Library',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 6),
                child: Row(
                  children: [
                    NaviIcon(NaviGlyph.library, size: 20, color: selected ? t.accent : t.textSecondary, filled: selected),
                    const SizedBox(width: Space.sm),
                    Flexible(
                      child: Text(
                        'Your Library',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.subheadline.copyWith(fontWeight: FontWeight.w700, color: selected ? t.accent : t.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _IconAction(glyph: NaviGlyph.plus, tooltip: 'New playlist', onTap: () => showPlaylistEditor(context)),
          _IconAction(
            glyph: NaviGlyph.sidebarToggle,
            tooltip: 'Collapse the library',
            onTap: () => DesktopLayout.setCollapsed(true),
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final NaviGlyph glyph;
  final String tooltip;
  final VoidCallback onTap;
  const _IconAction({required this.glyph, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return NaviIconButton(glyph: glyph, tooltip: tooltip, onTap: onTap);
  }
}

class _Filters extends StatelessWidget {
  final RailFilter? filter;
  final ValueChanged<RailFilter?> onChange;
  const _Filters({required this.filter, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.xs),
      child: Wrap(
        spacing: Space.xs + 2,
        runSpacing: Space.xs,
        children: [
          for (final (f, label) in const [
            (RailFilter.playlists, 'Playlists'),
            (RailFilter.albums, 'Albums'),
            (RailFilter.artists, 'Artists'),
          ])
            Semantics(
              button: true,
              selected: filter == f,
              label: label,
              child: NaviFocusable(
                radius: Radii.capsule,
                hoverTint: false,
                onTap: () => onChange(filter == f ? null : f),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  decoration: BoxDecoration(
                    color: filter == f ? t.accentFill : t.fill,
                    borderRadius: BorderRadius.circular(Radii.capsule),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      style: t.caption1.copyWith(
                        color: filter == f ? t.bgBase : t.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FindRow extends StatelessWidget {
  final TextEditingController controller;
  final RailSort sort;
  final VoidCallback onSort;
  const _FindRow({required this.controller, required this.sort, required this.onSort});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.xs, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: controller,
                style: t.footnote.copyWith(color: t.textPrimary),
                cursorColor: t.textPrimary,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: t.fill,
                  hintText: 'Find in Your Library',
                  hintStyle: t.footnote,
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(7),
                    child: NaviIcon(NaviGlyph.search, size: 14, color: t.textSecondary),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          NaviIconButton(
            glyph: NaviGlyph.listView,
            tooltip: sort == RailSort.library ? 'Sort: library order' : 'Sort: A–Z',
            onTap: onSort,
          ),
        ],
      ),
    );
  }
}

// ── The list ─────────────────────────────────────────────────────────────────

/// One line of the library list, whatever it is.
class _Item {
  final String id;
  final String title;
  final String subtitle;
  final String? artUrl;
  final NaviGlyph placeholder;
  final bool circular;
  final VoidCallback onTap;
  final VoidCallback? onMenu;
  final void Function(List<Song>)? onDrop;

  /// A playlist without a cover of its own is drawn as a mosaic of its songs' covers.
  final Playlist? playlist;
  const _Item({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.artUrl,
    required this.placeholder,
    required this.onTap,
    this.circular = false,
    this.onMenu,
    this.onDrop,
    this.playlist,
  });
}

class _LibraryList extends ConsumerStatefulWidget {
  final bool collapsed;
  final RailFilter? filter;
  final RailSort sort;
  final String query;
  final Future<void> Function(BuildContext, Playlist, List<Song>) onDrop;
  const _LibraryList({
    required this.collapsed,
    required this.filter,
    required this.sort,
    required this.query,
    required this.onDrop,
  });

  @override
  ConsumerState<_LibraryList> createState() => _LibraryListState();
}

class _LibraryListState extends ConsumerState<_LibraryList> {
  /// "Shared with you" folds away; a search always shows what matches.
  bool _sharedCollapsed = false;

  bool get collapsed => widget.collapsed;
  RailFilter? get filter => widget.filter;
  RailSort get sort => widget.sort;
  String get query => widget.query;
  Future<void> Function(BuildContext, Playlist, List<Song>) get onDrop => widget.onDrop;

  @override
  Widget build(BuildContext context) {
    final showPlaylists = filter == null || filter == RailFilter.playlists;
    _Item fromEntry(LibEntry e) => _Item(
          id: e.id,
          title: e.title,
          subtitle: e.subtitle,
          artUrl: e.artUrl,
          placeholder: e.placeholder,
          circular: e.circular,
          onTap: e.onTap,
          onMenu: e.onMenu,
          onDrop: e.playlist == null ? null : (songs) => onDrop(context, e.playlist!, songs),
          playlist: e.playlist,
        );

    final items = <_Item>[
      // What is always yours, ahead of the rest, while playlists are in view.
      if (showPlaylists) ...[
        _Item(
          id: 'fav',
          title: 'Favorites',
          subtitle: 'Playlist',
          artUrl: null,
          placeholder: NaviGlyph.star, // the app's favourite mark is the star everywhere
          onTap: () => navigateInApp(context, const FavoritesScreen()),
        ),
        _Item(
          id: 'songs',
          title: 'Songs',
          subtitle: 'Every song',
          artUrl: null,
          placeholder: NaviGlyph.note,
          onTap: () => navigateInApp(context, const SongsPage()),
        ),
        _Item(
          id: 'dl',
          title: 'Downloaded',
          subtitle: 'On this device',
          artUrl: null,
          placeholder: NaviGlyph.downloadCircle,
          onTap: () => navigateInApp(context, const SongsPage(downloadedOnly: true), title: 'Downloaded'),
        ),
      ],
    ];

    bool matches(String title, String subtitle) =>
        query.isEmpty || title.toLowerCase().contains(query) || subtitle.toLowerCase().contains(query);
    int byTitle(LibEntry a, LibEntry b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());

    // Playlists: yours, collab and shared with you, each under a quiet header.
    var playlistEntries = [
      if (filter == null || filter == RailFilter.playlists)
        for (final e in libraryEntries(context, ref, LibKind.playlists)) if (matches(e.title, e.subtitle)) e,
    ];
    if (sort == RailSort.alphabetical) playlistEntries = sortWithinSections(playlistEntries, byTitle);
    final playlistRows = sectionRows(playlistEntries, sharedCollapsed: _sharedCollapsed && query.isEmpty);

    var others = [
      for (final i in items) if (matches(i.title, i.subtitle)) i,
      if (filter == null || filter == RailFilter.albums)
        for (final e in libraryEntries(context, ref, LibKind.albums)) if (matches(e.title, e.subtitle)) fromEntry(e),
      if (filter == null || filter == RailFilter.artists)
        for (final e in libraryEntries(context, ref, LibKind.artists)) if (matches(e.title, e.subtitle)) fromEntry(e),
    ];
    if (sort == RailSort.alphabetical) {
      others = [...others]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }

    // What is always yours (Favorites, Songs, Downloaded) stays on top, then the
    // playlist sections, then albums and artists.
    final pinnedIds = {'fav', 'songs', 'dl'};
    final rows = <_RailRow>[
      for (final i in others) if (pinnedIds.contains(i.id)) _RailRow.item(i),
      for (final r in playlistRows)
        switch (r) {
          LibHeaderRow() => _RailRow.header(r),
          LibEntryRow(:final entry) => _RailRow.item(fromEntry(entry)),
        },
      for (final i in others) if (!pinnedIds.contains(i.id)) _RailRow.item(i),
    ];
    final shown = rows;

    if (shown.isEmpty) {
      final t = ThemeTokens.of(context);
      return Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Text(collapsed ? '' : 'Nothing here matches.', style: t.footnote),
      );
    }

    final itemExtent = collapsed ? 52.0 : 56.0;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(collapsed ? Space.sm : Space.sm, Space.xs, collapsed ? Space.sm : Space.sm, Space.sm),
      itemExtentBuilder: (i, _) => shown[i].header == null ? itemExtent : (collapsed ? 14.0 : 36.0),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final r = shown[i];
        final h = r.header;
        if (h != null) {
          return _SectionHeader(
            header: h,
            collapsedRail: collapsed,
            onToggle: h.collapsible ? () => setState(() => _sharedCollapsed = !_sharedCollapsed) : null,
          );
        }
        return _ItemRow(item: r.item!, collapsed: collapsed);
      },
    );
  }
}

/// One line of the rail: an item, or a section header.
class _RailRow {
  final _Item? item;
  final LibHeaderRow? header;
  const _RailRow.item(_Item i)
      : item = i,
        header = null;
  const _RailRow.header(LibHeaderRow h)
      : header = h,
        item = null;
  String get title => item?.title ?? '';
}

/// "Your playlists", "Collab playlists", "Shared with you": small, quiet text
/// on the rail itself (no card). "Shared with you" folds away. In the icon-only
/// rail a header is just a hairline.
class _SectionHeader extends StatelessWidget {
  final LibHeaderRow header;
  final bool collapsedRail;
  final VoidCallback? onToggle;
  const _SectionHeader({required this.header, required this.collapsedRail, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    if (collapsedRail) {
      return Center(child: Container(height: 0.5, margin: const EdgeInsets.symmetric(horizontal: Space.sm), color: t.outline));
    }
    final label = Row(children: [
      Expanded(
        child: Text(
          header.section.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.caption1.copyWith(color: t.textMuted, fontWeight: FontWeight.w600),
        ),
      ),
      if (header.collapsible) ...[
        Text('${header.count}', style: t.caption1.copyWith(color: t.textMuted)),
        const SizedBox(width: Space.xs),
        AnimatedRotation(
          turns: header.collapsed ? 0 : 0.25,
          duration: const Duration(milliseconds: 150),
          child: NaviIcon(NaviGlyph.chevron, size: 12, color: t.textMuted),
        ),
      ],
    ]);
    return Semantics(
      header: true,
      container: true,
      label: header.collapsible
          ? '${header.section.title}, ${header.count}, ${header.collapsed ? 'collapsed' : 'expanded'}'
          : header.section.title,
      child: NaviFocusable(
        radius: 6,
        onTap: onToggle,
        semanticLabel: header.section.title,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs + 2, Space.sm, Space.xs + 2, Space.xs),
          child: Align(alignment: Alignment.bottomLeft, child: label),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final _Item item;
  final bool collapsed;
  const _ItemRow({required this.item, required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final art = item.playlist != null && item.artUrl == null
        ? PlaylistCover(playlist: item.playlist!, size: 40, radius: Radii.thumb, compact: true)
        : item.artUrl == null
        ? Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: t.bgElevated, borderRadius: BorderRadius.circular(item.circular ? 20 : Radii.thumb)),
            alignment: Alignment.center,
            child: NaviIcon(item.placeholder, size: 20, color: t.textSecondary),
          )
        : CoverArt(url: item.artUrl, size: 40, radius: Radii.thumb, circular: item.circular, placeholderIcon: item.placeholder);
    return DragTarget<SongDrag>(
      onWillAcceptWithDetails: (_) => item.onDrop != null,
      onAcceptWithDetails: (d) => item.onDrop?.call(d.data.songs),
      builder: (context, candidates, _) {
        final dropping = candidates.isNotEmpty;
        final row = Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: dropping ? Border.all(color: t.textPrimary, width: 1.5) : null,
            color: dropping ? t.bgOverlay : null,
          ),
          child: Row(
            mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              art,
              if (!collapsed) ...[
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w500)),
                      Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption1),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
        return NaviFocusable(
          radius: 8,
          onTap: item.onTap,
          onSecondaryTap: item.onMenu,
          semanticLabel: '${item.title}, ${item.subtitle}',
          child: collapsed ? Tooltip(message: item.title, child: row) : row,
        );
      },
    );
  }
}

// ── Shared rail row ──────────────────────────────────────────────────────────

/// A destination in the rail: glyph and label, a wash on hover, a fill when selected.
class RailRow extends StatelessWidget {
  final NaviGlyph? icon;
  final Widget? art;
  final String label;
  final bool selected;
  final bool iconOnly;

  /// A small dot on the glyph: something is live or waiting here.
  final bool dot;
  final VoidCallback onTap;
  const RailRow({
    super.key,
    this.icon,
    this.art,
    required this.label,
    this.selected = false,
    this.iconOnly = false,
    this.dot = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final row = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      decoration: BoxDecoration(color: selected ? t.bgOverlay : Colors.transparent, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisAlignment: iconOnly ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              art ?? NaviIcon(icon!, size: 20, filled: selected, color: selected ? t.accent : t.textSecondary),
              if (dot)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(width: 8, height: 8, decoration: BoxDecoration(color: t.textPrimary, shape: BoxShape.circle, border: Border.all(color: t.bgSurface, width: 1.5))),
                ),
            ],
          ),
          if (!iconOnly) ...[
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.subheadline.copyWith(color: selected ? t.textPrimary : t.textSecondary, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
    // The active destination also carries a short white bar on its left edge:
    // in the icon-only rail a faint wash is the only other cue, and the glyph
    // alone is not enough to tell where you are.
    final marked = Stack(
      children: [
        row,
        if (selected)
          Positioned(
            left: 0,
            top: 10,
            bottom: 10,
            child: Container(width: 3, decoration: BoxDecoration(color: t.accentFill, borderRadius: BorderRadius.circular(2))),
          ),
      ],
    );
    return Semantics(
      selected: selected,
      child: NaviFocusable(
        radius: 6,
        onTap: onTap,
        semanticLabel: label,
        hoverTint: !selected,
        child: iconOnly ? Tooltip(message: label, child: marked) : marked,
      ),
    );
  }
}

/// "Downloads" while anything from Search online is (or was, this session)
/// downloading, with a thin progress ring.
class _DownloadsRow extends ConsumerWidget {
  const _DownloadsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    if (!ref.watch(onlineFetchAvailableProvider) || ref.watch(fetchJobsProvider.select((d) => d.isEmpty))) {
      return const SizedBox.shrink();
    }
    return RailRow(
      art: SizedBox(
        width: 20,
        height: 20,
        child: FetchActivityRing(child: NaviIcon(NaviGlyph.download, size: 12, color: t.accent)),
      ),
      label: 'Downloads',
      onTap: () => showFetchDownloads(context),
    );
  }
}
