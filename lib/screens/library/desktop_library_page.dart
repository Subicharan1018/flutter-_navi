import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../../widgets/art/navi_icons.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/desktop_dialogs.dart';
import '../../widgets/shell/desktop/desktop_layout.dart';
import '../../widgets/ui/action_sheet.dart';
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/media.dart';
import '../../widgets/ui/states.dart';
import '../../widgets/ui/sort_menu_button.dart';
import '../../widgets/ui/playlist_cover.dart';
import 'library_entries.dart';
import '../../utils/format.dart';
import '../../providers/pins_provider.dart';
import '../library_screen.dart' show PinsGrid;

// =============================================================================
// desktop_library_page.dart — Library on Windows: the whole collection as a
// page you can read, not a menu. Playlists, Albums or Artists, as tiles or as a
// sortable list, with right-click menus and a Play button on hover.
// =============================================================================

enum LibSort { library, name, artist, count, duration, year }

class DesktopLibraryPage extends ConsumerStatefulWidget {
  const DesktopLibraryPage({super.key});

  @override
  ConsumerState<DesktopLibraryPage> createState() => _DesktopLibraryPageState();
}

class _DesktopLibraryPageState extends ConsumerState<DesktopLibraryPage> {
  LibKind _kind = LibKind.playlists;
  LibSort _sort = LibSort.library;
  bool _asc = true;

  void _pickSort(LibSort s) => setState(() {
        if (_sort == s && s != LibSort.library) {
          _asc = !_asc;
        } else {
          _sort = s;
          _asc = true;
        }
      });

  List<LibEntry> _sorted(List<LibEntry> list) {
    if (_sort == LibSort.library) return list;
    int cmp(LibEntry a, LibEntry b) => switch (_sort) {
          LibSort.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          LibSort.artist => a.secondary.toLowerCase().compareTo(b.secondary.toLowerCase()),
          LibSort.count => a.count.compareTo(b.count),
          LibSort.duration => a.duration.compareTo(b.duration),
          LibSort.year => a.year.compareTo(b.year),
          LibSort.library => 0,
        };
    return [...list]..sort(_asc ? cmp : (a, b) => cmp(b, a));
  }


  void _sortMenu() {
    showDesktopMenu<void>(
      context: context,
      width: 220,
      builder: (_) => SheetGroup(children: [
        for (final (s, label) in [
          (LibSort.library, 'Library order'),
          (LibSort.name, 'Name'),
          if (_kind == LibKind.albums) (LibSort.artist, 'Artist'),
          if (_kind == LibKind.albums) (LibSort.year, 'Year'),
          if (_kind != LibKind.artists) (LibSort.count, 'Number of songs') else (LibSort.count, 'Number of albums'),
          if (_kind != LibKind.artists) (LibSort.duration, 'Length'),
        ])
          SheetAction(
            label: label,
            detail: _sort == s && s != LibSort.library ? (_asc ? 'Ascending' : 'Descending') : null,
            icon: _sort == s ? NaviGlyph.check : null,
            keepOpen: false,
            onTap: () => _pickSort(s),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _sorted(libraryEntries(context, ref, _kind));
    final pins = ref.watch(pinsProvider);
    final columns = _columns(_kind, entries);
    final toolbar = SliverToBoxAdapter(child: _Toolbar(kind: _kind, onKind: (k) => setState(() => _kind = k), onSort: _sortMenu, sort: _sort, asc: _asc));
    return LargeTitlePage(
      title: 'Library',
      slivers: [
        if (pins.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader(title: 'Pinned')),
          SliverPadding(padding: const EdgeInsets.symmetric(horizontal: Space.md), sliver: PinsGrid(pins: pins)),
          const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
        ],
        if (entries.isEmpty) ...[
          toolbar,
          SliverToBoxAdapter(
            child: MessageState(
              icon: NaviGlyph.library,
              title: switch (_kind) {
                LibKind.playlists => 'No playlists yet',
                LibKind.albums => 'No albums yet',
                LibKind.artists => 'No artists yet',
              },
              message: 'What you add to your server appears here.',
            ),
          ),
        ] else
          ValueListenableBuilder<bool>(
            valueListenable: DesktopLayout.libraryGrid,
            builder: (context, grid, _) => grid
                // Tiles: as many columns as the width holds, so a wide window gets
                // more tiles, not bigger gaps.
                ? SliverMainAxisGroup(slivers: [toolbar, _Grid(entries: entries)])
                // List: a table of a few short columns stops being readable when
                // stretched across 1900 px, so it stops at 1200 (left, on the
                // title's edge) and the toolbar's sort and view buttons follow it.
                : SliverConstrainedCrossAxis(
                    maxExtent: _listMaxWidth,
                    sliver: SliverMainAxisGroup(slivers: [
                      toolbar,
                      _ListHeader(kind: _kind, sort: _sort, asc: _asc, onSort: _pickSort, columns: columns),
                      SliverFixedExtentList(
                        itemExtent: 56,
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _ListRow(entry: entries[i], columns: columns),
                          childCount: entries.length,
                        ),
                      ),
                    ]),
                  ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final LibKind kind;
  final ValueChanged<LibKind> onKind;
  final VoidCallback onSort;
  final LibSort sort;
  final bool asc;
  const _Toolbar({required this.kind, required this.onKind, required this.onSort, required this.sort, required this.asc});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pageGutter(context), Space.xs, pageGutter(context), Space.lg),
      child: Row(
        children: [
          Expanded(child: Wrap(runSpacing: Space.sm, children: [
          for (final (k, label) in const [
            (LibKind.playlists, 'Playlists'),
            (LibKind.albums, 'Albums'),
            (LibKind.artists, 'Artists'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Semantics(
                button: true,
                selected: kind == k,
                label: label,
                child: NaviFocusable(
                  radius: Radii.capsule,
                  hoverTint: false,
                  onTap: () => onKind(k),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    decoration: BoxDecoration(
                      color: kind == k ? t.accentFill : t.fill,
                      borderRadius: BorderRadius.circular(Radii.capsule),
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        label,
                        style: t.subheadline.copyWith(
                          color: kind == k ? t.bgBase : t.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ])),
          SortMenuButton(
            label: switch (sort) {
              LibSort.library => 'Library order',
              LibSort.name => asc ? 'Name A–Z' : 'Name Z–A',
              LibSort.artist => asc ? 'Artist A–Z' : 'Artist Z–A',
              LibSort.count => asc ? 'Fewest first' : 'Most first',
              LibSort.duration => asc ? 'Shortest first' : 'Longest first',
              LibSort.year => asc ? 'Oldest first' : 'Newest first',
            },
            onTap: onSort,
          ),
          const SizedBox(width: Space.xs),
          ValueListenableBuilder<bool>(
            valueListenable: DesktopLayout.libraryGrid,
            builder: (context, grid, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewToggle(glyph: NaviGlyph.gridView, label: 'Tiles', on: grid, onTap: () => DesktopLayout.setLibraryGrid(true)),
                _ViewToggle(glyph: NaviGlyph.listView, label: 'List', on: !grid, onTap: () => DesktopLayout.setLibraryGrid(false)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final NaviGlyph glyph;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _ViewToggle({required this.glyph, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: on,
        label: label,
        child: NaviFocusable(
          radius: 8,
          hoverTint: !on,
          onTap: onTap,
          child: Container(
            width: 36,
            height: 32,
            decoration: BoxDecoration(color: on ? t.bgOverlay : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: NaviIcon(glyph, size: 18, color: on ? t.textPrimary : t.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<LibEntry> entries;
  const _Grid({required this.entries});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: pageGutter(context)),
      sliver: SliverLayoutBuilder(
        builder: (context, c) {
          final columns = gridColumns(c.crossAxisExtent, ArtSize.of(context).tile);
          final card = (c.crossAxisExtent - Space.lg * (columns - 1)) / columns;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: Space.lg,
              mainAxisSpacing: Space.xl,
              mainAxisExtent: card + 48,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final e = entries[i];
                return MediaCard(
                  title: e.title,
                  subtitle: switch (e.kind) {
                    LibKind.playlists => songCount(e.count),
                    LibKind.albums => e.secondary,
                    LibKind.artists => 'Artist',
                  },
                  artUrl: e.artUrl,
                  art: e.playlist != null && e.artUrl == null ? PlaylistCover(playlist: e.playlist!, size: card) : null,
                  size: card,
                  circular: e.circular,
                  placeholderIcon: e.placeholder,
                  onTap: e.onTap,
                  onLongPress: e.onMenu,
                  onPlay: e.onPlay,
                );
              },
              childCount: entries.length,
            ),
          );
        },
      ),
    );
  }
}

/// One column of the list view.
class _Col {
  final String label;
  final LibSort sort;
  final double? width; // null: flexible
  final bool right;
  final String Function(LibEntry) text;
  const _Col(this.label, this.sort, this.text, {this.width, this.right = false});
}

/// The list stops growing here: wider than this the eye loses the row.
const double _listMaxWidth = 1200;

List<_Col> _columns(LibKind kind, List<LibEntry> entries) {
  String time(LibEntry e) => e.duration <= 0 ? '' : formatLongDuration(e.duration);
  switch (kind) {
    case LibKind.playlists:
      return [
        // An Owner column with nobody in it is a gap, not information: only when
        // at least one playlist names an owner.
        if (entries.any((e) => e.secondary.trim().isNotEmpty)) _Col('Owner', LibSort.artist, (e) => e.secondary),
        _Col('Songs', LibSort.count, (e) => '${e.count}', width: 80, right: true),
        _Col('Time', LibSort.duration, time, width: 110, right: true),
      ];
    case LibKind.albums:
      return [
        _Col('Artist', LibSort.artist, (e) => e.secondary),
        _Col('Year', LibSort.year, (e) => e.year > 0 ? '${e.year}' : '', width: 70, right: true),
        _Col('Songs', LibSort.count, (e) => '${e.count}', width: 80, right: true),
        _Col('Time', LibSort.duration, time, width: 110, right: true),
      ];
    case LibKind.artists:
      return [_Col('Albums', LibSort.count, (e) => '${e.count}', width: 90, right: true)];
  }
}

class _ListHeader extends StatelessWidget {
  final LibKind kind;
  final LibSort sort;
  final bool asc;
  final void Function(LibSort) onSort;
  final List<_Col> columns;
  const _ListHeader({required this.kind, required this.sort, required this.asc, required this.onSort, required this.columns});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    Widget cell(String label, LibSort s) {
      final on = sort == s;
      return Semantics(
        button: true,
        label: 'Sort by $label',
        child: NaviFocusable(
          radius: 4,
          hoverTint: false,
          onTap: () => onSort(s),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: t.footnote.copyWith(color: on ? t.textPrimary : t.textSecondary, fontWeight: FontWeight.w600)),
                if (on) ...[
                  const SizedBox(width: 4),
                  Transform.rotate(angle: asc ? math.pi : 0, child: NaviIcon(NaviGlyph.chevronDown, size: 11, color: t.textPrimary)),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final g = pageGutter(context);
    return SliverToBoxAdapter(
      child: Container(
        height: 32,
        // The cover and the labels start at the page's left edge (the title's x); the row
        // wash, 8 px wider on each side, reaches just outside it.
        margin: EdgeInsets.symmetric(horizontal: g - Space.sm),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
        child: Row(
          children: [
            const SizedBox(width: 40 + Space.md),
            Expanded(flex: 5, child: Align(alignment: Alignment.centerLeft, child: cell('Name', LibSort.name))),
            for (final c in columns)
              c.width == null
                  ? Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: cell(c.label, c.sort)))
                  : SizedBox(width: c.width, child: Align(alignment: c.right ? Alignment.centerRight : Alignment.centerLeft, child: cell(c.label, c.sort))),
          ],
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  final LibEntry entry;
  final List<_Col> columns;
  const _ListRow({required this.entry, required this.columns});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final e = entry;
    final num = t.footnote.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pageGutter(context) - Space.sm),
      child: HoverBuilder(
        builder: (context, hovered) => NaviFocusable(
          radius: 6,
          onTap: e.onTap,
          onSecondaryTap: e.onMenu,
          semanticLabel: '${e.title}, ${e.subtitle}',
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    children: [
                      e.playlist != null && e.artUrl == null
                          ? PlaylistCover(playlist: e.playlist!, size: 40, radius: Radii.thumb, compact: true)
                          : e.artUrl == null
                          ? Container(
                              decoration: BoxDecoration(color: t.bgElevated, borderRadius: BorderRadius.circular(e.circular ? 20 : Radii.thumb)),
                              alignment: Alignment.center,
                              child: NaviIcon(e.placeholder, size: 20, color: t.textSecondary),
                            )
                          : CoverArt(url: e.artUrl, size: 40, radius: Radii.thumb, circular: e.circular, placeholderIcon: e.placeholder),
                      if (hovered)
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: e.onPlay,
                            child: Tooltip(
                              message: 'Play ${e.title}',
                              child: DecoratedBox(
                                // A 9% white wash (not a black scrim) and a small solid disc that reads on any cover.
                                decoration: BoxDecoration(
                                  color: t.hover,
                                  borderRadius: BorderRadius.circular(e.circular ? 20 : Radii.thumb),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(color: t.accentFill, shape: BoxShape.circle),
                                    alignment: Alignment.center,
                                    child: NaviIcon(NaviGlyph.play, size: 12, filled: true, color: t.onAccent),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  flex: 5,
                  child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w500)),
                ),
                for (final c in columns)
                  c.width == null
                      ? Expanded(flex: 3, child: Text(c.text(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote))
                      : SizedBox(width: c.width, child: Text(c.text(e), textAlign: c.right ? TextAlign.right : TextAlign.left, style: num)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
