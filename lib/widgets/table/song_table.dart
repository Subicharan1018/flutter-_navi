import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show GestureBinding, PointerCancelEvent, PointerEvent, PointerMoveEvent, PointerUpEvent, kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/focus/navi_focus.dart';
import '../shell/desktop/desktop_layout.dart';
import '../../core/theme.dart';
import '../../features/online_fetch/ui/fetch_activity.dart' show showAddSongsToPlaylist;
import '../../models/song.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/format.dart';
import '../../utils/platform_utils.dart';
import '../../utils/queue_actions.dart';
import '../art/navi_icons.dart';
import '../cover_art.dart';
import '../desktop_dialogs.dart';
import '../now_playing_bars.dart';
import '../options_menu.dart';
import '../ui/action_sheet.dart';

// =============================================================================
// song_table.dart — the Windows song list.
//
// A table, not tall cards: #, title + artist, album, date added, duration, with
// a pinned header you can sort by. Rows are 48 px. Click selects, Ctrl/Shift
// extend, double-click or Enter plays, right-click opens the menu, rows drag to
// reorder (in a playlist) or onto a playlist in the sidebar. Phones, tablets and
// TVs keep [SongTile]; pages choose with [useSongTable].
// =============================================================================

/// Windows and Linux windows get the table, at any width. A narrow window drops
/// columns; it never falls back to phone rows.
bool useSongTable() => PlatformUtils.isDesktop;

/// What is being dragged out of a table: the selected songs, and the playlist
/// they came from (so dropping inside it reorders instead of adding).
class SongDrag {
  final List<Song> songs;
  final List<int> indexes;
  final String? sourcePlaylistId;
  const SongDrag(this.songs, this.indexes, this.sourcePlaylistId);
}

enum SongSort { none, title, album, added, duration }

class SongTableSliver extends ConsumerStatefulWidget {
  final List<Song> songs;

  /// Plays [song] with [ordered] (the rows as shown, sorted and filtered) as the queue.
  final void Function(Song song, List<Song> ordered) onPlay;

  final String? playlistId;

  /// Delete / "Remove from Playlist". Null where songs cannot be removed.
  final void Function(List<Song> songs)? onRemove;

  /// Reorder by drag: move the rows at [from] (indexes into [songs]) so they sit
  /// before [before] (an index into [songs], `songs.length` for the end).
  final void Function(List<int> from, int before)? onReorder;

  final bool showArtwork;
  final bool showAlbum;

  /// "Added": when the song entered the library. Shown where the list is not
  /// one album's tracks.
  final bool showDateAdded;

  const SongTableSliver({
    super.key,
    required this.songs,
    required this.onPlay,
    this.playlistId,
    this.onRemove,
    this.onReorder,
    this.showArtwork = true,
    this.showAlbum = true,
    this.showDateAdded = false,
  });

  @override
  ConsumerState<SongTableSliver> createState() => SongTableState();

  static const double rowHeight = 48;
  static const double headerHeight = 32;

  /// Ctrl+F: finds in the table on screen. Returns false when there is none.
  static bool tryFind() {
    for (final s in SongTableState._live.toList().reversed) {
      if (s._visible) {
        s.openFind();
        return true;
      }
    }
    return false;
  }
}

class SongTableState extends ConsumerState<SongTableSliver> {
  static final _live = <SongTableState>[];

  final _focus = FocusNode(debugLabel: 'SongTable');
  final _find = TextEditingController();
  final _findFocus = FocusNode();
  bool _finding = false;

  SongSort _sort = SongSort.none;
  bool _asc = true;

  /// Selected rows, as indexes into [_rows]; [_anchor] and [_cursor] drive Shift ranges and arrows.
  final _selected = <int>{};
  int _anchor = -1;
  int _cursor = -1;
  List<String> _idsAtSelection = const [];
  final _rowContexts = <int, BuildContext>{};

  bool get _visible => mounted && TickerMode.valuesOf(context).enabled;

  @override
  void initState() {
    super.initState();
    _live.add(this);
    _idsAtSelection = [for (final s in widget.songs) s.id];
    _find.addListener(() => setState(_clearSelection));
    _focus.addListener(() => setState(() {})); // the cursor outline follows focus
    DesktopLayout.hiddenColumns.addListener(_columnsChanged);
  }

  @override
  void dispose() {
    _live.remove(this);
    DesktopLayout.hiddenColumns.removeListener(_columnsChanged);
    _unroute();
    _stopAutoScroll();
    _focus.dispose();
    _find.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _columnsChanged() {
    if (mounted) setState(() {});
  }

  void openFind() {
    setState(() => _finding = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _findFocus.requestFocus());
  }

  void _closeFind() {
    setState(() {
      _finding = false;
      _find.clear();
    });
    _focus.requestFocus();
  }

  // ── The rows as shown ─────────────────────────────────────────────────────

  List<Song> _rowsCache = const [];
  List<Song>? _rowsFrom;
  SongSort _rowsSort = SongSort.none;
  bool _rowsAsc = true;
  String _rowsQuery = '';

  List<Song> get _rows {
    final q = _find.text.trim().toLowerCase();
    if (identical(_rowsFrom, widget.songs) && _rowsSort == _sort && _rowsAsc == _asc && _rowsQuery == q) {
      return _rowsCache;
    }
    var list = widget.songs;
    if (q.isNotEmpty) {
      list = [
        for (final s in list)
          if (s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q) || s.album.toLowerCase().contains(q))
            s,
      ];
    }
    if (_sort != SongSort.none) {
      int cmp(Song a, Song b) => switch (_sort) {
            SongSort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            SongSort.album => a.album.toLowerCase().compareTo(b.album.toLowerCase()),
            SongSort.added => (a.created ?? DateTime(0)).compareTo(b.created ?? DateTime(0)),
            SongSort.duration => a.duration.compareTo(b.duration),
            SongSort.none => 0,
          };
      list = [...list]..sort(_asc ? cmp : (a, b) => cmp(b, a));
    }
    _rowsFrom = widget.songs;
    _rowsSort = _sort;
    _rowsAsc = _asc;
    _rowsQuery = q;
    return _rowsCache = list;
  }

  /// Rows may be dragged to reorder only in the playlist's own order.
  bool get _canReorder => widget.onReorder != null && _sort == SongSort.none && _find.text.trim().isEmpty;

  @override
  void didUpdateWidget(SongTableSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = [for (final s in widget.songs) s.id];
    if (!_sameIds(ids, _idsAtSelection)) _clearSelection();
    _idsAtSelection = ids;
  }

  /// True when [b] is [a] with more rows added at the end (a list that paged
  /// in): the selection survives that, and nothing else.
  static bool _sameIds(List<String> a, List<String> b) {
    if (b.length > a.length) return false;
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _clearSelection() {
    _selected.clear();
    _anchor = _cursor = -1;
  }

  // ── Which row is playing ──────────────────────────────────────────────────

  /// Whether the row at [index] showing [song] is the one playing. A song can
  /// be in a playlist twice, so the song id alone is not enough: when the queue
  /// is this table's rows in this order, the queue position says which row.
  /// Otherwise the first row with that song is the playing one.
  bool _isPlayingRow(PlayerState s, Song song, int index) {
    if (s.currentSong?.id != song.id) return false;
    final rows = _rows;
    if (s.queue.length == rows.length) {
      var same = true;
      for (var i = 0; i < rows.length && same; i++) {
        same = s.queue[i].id == rows[i].id;
      }
      if (same) return s.currentIndex == index;
    }
    return rows.indexWhere((r) => r.id == song.id) == index;
  }

  // ── Auto-scroll while dragging ────────────────────────────────────────────

  Timer? _autoScroll;
  double _autoScrollSpeed = 0;

  /// Called as a dragged row moves: near the top or bottom edge of the list the
  /// page scrolls, faster the closer the pointer is to the edge.
  void _dragMoved(Offset global) {
    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject();
    if (scrollable == null || box is! RenderBox || !box.attached) return;
    final local = box.globalToLocal(global);
    const zone = 72.0;
    // The pinned header covers the top rows; start a little below it.
    final top = SongTableSliver.headerHeight + 8;
    double speed = 0;
    if (local.dy < top + zone) {
      speed = -((top + zone - local.dy) / zone).clamp(0.0, 1.5) * 18;
    } else if (local.dy > box.size.height - zone) {
      speed = ((local.dy - (box.size.height - zone)) / zone).clamp(0.0, 1.5) * 18;
    }
    _autoScrollSpeed = speed;
    if (speed == 0) {
      _stopAutoScroll();
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final p = scrollable.position;
      final next = (p.pixels + _autoScrollSpeed).clamp(p.minScrollExtent, p.maxScrollExtent);
      if (next != p.pixels) p.jumpTo(next);
    });
  }

  /// A drag began. Its source row may scroll out of view and be disposed (which
  /// silences the row's own drag callbacks), so the pointer is followed here instead.
  void _dragStarted() {
    if (_routed) return;
    _routed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  bool _routed = false;

  void _unroute() {
    if (!_routed) return;
    _routed = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  void _onPointer(PointerEvent e) {
    if (e is PointerMoveEvent) {
      _dragMoved(e.position);
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _unroute();
      _stopAutoScroll();
    }
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _autoScrollSpeed = 0;
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void _select(int i, {bool ctrl = false, bool shift = false}) {
    setState(() {
      if (shift && _anchor >= 0) {
        final lo = math.min(_anchor, i), hi = math.max(_anchor, i);
        if (!ctrl) _selected.clear();
        _selected.addAll([for (var k = lo; k <= hi; k++) k]);
      } else if (ctrl) {
        if (!_selected.remove(i)) _selected.add(i);
        _anchor = i;
      } else {
        _selected
          ..clear()
          ..add(i);
        _anchor = i;
      }
      _cursor = i;
    });
    _focus.requestFocus();
  }

  List<Song> get _selectedSongs {
    final rows = _rows;
    final idx = _selected.where((i) => i < rows.length).toList()..sort();
    return [for (final i in idx) rows[i]];
  }

  void _move(int delta, {bool shift = false}) {
    final n = _rows.length;
    if (n == 0) return;
    final to = (_cursor < 0 ? (delta > 0 ? 0 : n - 1) : _cursor + delta).clamp(0, n - 1);
    if (shift) {
      _select(to, shift: true);
    } else {
      _select(to);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(to));
  }

  /// Scroll [i] into view, below the pinned header.
  void _reveal(int i) {
    final ctx = _rowContexts[i];
    final box = ctx?.findRenderObject();
    if (box is RenderBox && box.attached) {
      box.showOnScreen(
        rect: Rect.fromLTRB(0, -SongTableSliver.headerHeight, box.size.width, box.size.height),
        duration: const Duration(milliseconds: 80),
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final rows = _rows;
    if (k == LogicalKeyboardKey.arrowDown) {
      _move(1, shift: shift);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1, shift: shift);
    } else if (k == LogicalKeyboardKey.pageDown) {
      _move(10, shift: shift);
    } else if (k == LogicalKeyboardKey.pageUp) {
      _move(-10, shift: shift);
    } else if (k == LogicalKeyboardKey.home && rows.isNotEmpty) {
      _select(0, shift: shift);
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(0));
    } else if (k == LogicalKeyboardKey.end && rows.isNotEmpty) {
      _select(rows.length - 1, shift: shift);
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(rows.length - 1));
    } else if (ctrl && k == LogicalKeyboardKey.keyA) {
      setState(() {
        _selected
          ..clear()
          ..addAll([for (var i = 0; i < rows.length; i++) i]);
        _anchor = 0;
        _cursor = rows.length - 1;
      });
    } else if (ctrl && k == LogicalKeyboardKey.keyF) {
      openFind();
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (_cursor >= 0 && _cursor < rows.length) widget.onPlay(rows[_cursor], rows);
    } else if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      final remove = widget.onRemove;
      if (remove == null || _selected.isEmpty) return KeyEventResult.ignored;
      final songs = _selectedSongs;
      setState(_clearSelection);
      remove(songs);
    } else if (k == LogicalKeyboardKey.escape && _selected.isNotEmpty) {
      setState(_clearSelection);
    } else if (k == LogicalKeyboardKey.contextMenu && _cursor >= 0) {
      _menu(_cursor);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── Menus ─────────────────────────────────────────────────────────────────

  void _menu(int i) {
    final rows = _rows;
    if (i >= rows.length) return;
    if (!_selected.contains(i)) _select(i);
    final songs = _selectedSongs;
    if (songs.length <= 1) {
      final song = rows[i];
      showSongActions(
        context,
        song,
        playlistId: widget.playlistId,
        onRemoveFromPlaylist: widget.onRemove == null ? null : () => widget.onRemove!([song]),
      );
      return;
    }
    final page = context;
    showDesktopMenu<void>(
      context: context,
      builder: (_) => SheetGroup(children: [
        SheetAction(
          label: 'Play ${songs.length} Songs',
          hint: 'Enter',
          icon: NaviGlyph.play,
          onTap: () => widget.onPlay(songs.first, songs),
        ),
        SheetAction(
          label: 'Play Next',
          icon: NaviGlyph.playNext,
          onTap: () => queueSongs(page, ref, songs, next: true),
        ),
        SheetAction(
          label: 'Add to Queue',
          icon: NaviGlyph.queue,
          onTap: () => queueSongs(page, ref, songs, next: false),
        ),
        SheetAction(
          label: 'Add to a Playlist…',
          icon: NaviGlyph.addToPlaylist,
          onTap: () => showAddSongsToPlaylist(page, songs),
        ),
        if (widget.onRemove != null)
          SheetAction(
            label: 'Remove ${songs.length} from Playlist',
            hint: 'Del',
            icon: NaviGlyph.minus,
            destructive: true,
            onTap: () {
              setState(_clearSelection);
              widget.onRemove!(songs);
            },
          ),
      ]),
    );
  }

  // ── Several rows selected: a count and what to do with them ───────────────

  Widget _selectionBar(List<Song> songs) {
    final page = context;
    return Builder(builder: (context) {
      final t = ThemeTokens.of(context);
      Widget action(String label, NaviGlyph icon, VoidCallback onTap, {bool danger = false}) => Semantics(
            button: true,
            label: label,
            child: NaviPressable(
              onTap: onTap,
              radius: 6,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NaviIcon(icon, size: 15, color: danger ? t.danger : t.textPrimary),
                      const SizedBox(width: 6),
                      Text(label, style: t.footnote.copyWith(color: danger ? t.danger : t.textPrimary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          );
      return Row(
        children: [
          Text('${songs.length} selected', style: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(width: Space.lg),
          action('Play', NaviGlyph.play, () => widget.onPlay(songs.first, songs)),
          action('Add to…', NaviGlyph.addToPlaylist, () {
            showDesktopMenu<void>(
              context: page,
              builder: (_) => SheetGroup(children: [
                SheetAction(label: 'Play Next', icon: NaviGlyph.playNext, onTap: () => queueSongs(page, ref, songs, next: true)),
                SheetAction(label: 'Add to Queue', icon: NaviGlyph.queue, onTap: () => queueSongs(page, ref, songs, next: false)),
                SheetAction(label: 'A Playlist…', icon: NaviGlyph.addToPlaylist, onTap: () => showAddSongsToPlaylist(page, songs)),
              ]),
            );
          }),
          if (widget.onRemove != null)
            action('Remove', NaviGlyph.minus, () {
              setState(_clearSelection);
              widget.onRemove!(songs);
            }, danger: true),
          const Spacer(),
          action('Clear', NaviGlyph.close, () => setState(_clearSelection)),
        ],
      );
    });
  }

  // ── Which columns show ────────────────────────────────────────────────────

  void _columnsMenu() {
    showDesktopMenu<void>(
      context: context,
      width: 200,
      builder: (_) => SheetGroup(children: [
        if (widget.showAlbum)
          SheetAction(
            label: 'Album',
            icon: DesktopLayout.hiddenColumns.value.contains('album') ? null : NaviGlyph.check,
            keepOpen: false,
            onTap: () => DesktopLayout.toggleColumn('album'),
          ),
        if (widget.showDateAdded)
          SheetAction(
            label: 'Date added',
            icon: DesktopLayout.hiddenColumns.value.contains('added') ? null : NaviGlyph.check,
            keepOpen: false,
            onTap: () => DesktopLayout.toggleColumn('added'),
          ),
      ]),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  void _toggleSort(SongSort s) => setState(() {
        _clearSelection();
        if (_sort != s) {
          _sort = s;
          _asc = true;
        } else if (_asc) {
          _asc = false;
        } else {
          _sort = SongSort.none;
          _asc = true;
        }
      });

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return SliverLayoutBuilder(
      builder: (context, c) {
        final w = c.crossAxisExtent;
        final hidden = DesktopLayout.hiddenColumns.value;
        final cols = _Columns(
          album: widget.showAlbum && w >= 640 && !hidden.contains('album'),
          added: widget.showDateAdded && w >= 900 && !hidden.contains('added'),
          width: w,
        );
        final picked = _selectedSongs;
        return SliverMainAxisGroup(
          slivers: [
            if (_finding) SliverToBoxAdapter(child: _FindBar(controller: _find, focus: _findFocus, onClose: _closeFind)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeaderDelegate(
                columns: cols,
                sort: _sort,
                asc: _asc,
                focus: _focus,
                onKey: _onKey,
                onSort: _toggleSort,
                showArtwork: widget.showArtwork,
                onColumns: (widget.showAlbum || widget.showDateAdded) ? _columnsMenu : null,
                selectionCount: picked.length,
                selectionBar: picked.length > 1 ? _selectionBar(picked) : null,
              ),
            ),
            if (rows.isEmpty && _find.text.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xxl),
                  child: Text('No songs match “${_find.text.trim()}”.', style: ThemeTokens.of(context).footnote),
                ),
              )
            else
              SliverFixedExtentList(
                itemExtent: SongTableSliver.rowHeight,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _Row(
                    key: ValueKey('row_${rows[i].id}_$i'),
                    table: this,
                    index: i,
                    song: rows[i],
                    columns: cols,
                  ),
                  childCount: rows.length,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Which columns fit, and how wide the fixed ones are.
class _Columns {
  final bool album;
  final bool added;
  final double width;
  const _Columns({required this.album, required this.added, required this.width});

  static const double num = 56;
  static const double dateW = 112;
  static const double durW = 64;
  static const double menuW = 44;
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final _Columns columns;
  final SongSort sort;
  final bool asc;
  final FocusNode focus;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final void Function(SongSort) onSort;
  final bool showArtwork;
  final VoidCallback? onColumns;

  /// With several rows picked the header becomes this bar (a count, Play, Add to, Remove).
  final Widget? selectionBar;
  final int selectionCount;

  _HeaderDelegate({
    required this.columns,
    required this.sort,
    required this.asc,
    required this.focus,
    required this.onKey,
    required this.onSort,
    required this.showArtwork,
    this.onColumns,
    this.selectionBar,
    this.selectionCount = 0,
  });

  @override
  double get minExtent => SongTableSliver.headerHeight;
  @override
  double get maxExtent => SongTableSliver.headerHeight;

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.columns.album != columns.album ||
      old.columns.added != columns.added ||
      old.sort != sort ||
      old.asc != asc ||
      old.selectionCount != selectionCount ||
      old.showArtwork != showArtwork;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = ThemeTokens.of(context);
    Widget cell(String label, SongSort? s, {TextAlign align = TextAlign.left}) {
      final on = s != null && sort == s;
      final text = Text(
        label,
        style: t.caption1.copyWith(color: on ? t.textPrimary : t.textSecondary, fontWeight: FontWeight.w600),
      );
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          text,
          if (on) ...[
            const SizedBox(width: 4),
            Transform.rotate(angle: asc ? math.pi : 0, child: NaviIcon(NaviGlyph.chevronDown, size: 11, color: t.textPrimary)),
          ],
        ],
      );
      if (s == null) return content;
      // A real control: focusable (Tab, then Enter or Space sorts), labelled, with the
      // sort direction named for a screen reader and drawn on the active column.
      return Semantics(
        button: true,
        label: 'Sort by $label',
        value: on ? (asc ? 'ascending' : 'descending') : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: NaviPressable(
            onTap: () => onSort(s),
            radius: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
              child: Center(widthFactor: 1, child: content),
            ),
          ),
        ),
      );
    }

    return Focus(
      focusNode: focus,
      onKeyEvent: onKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bgBase.withValues(alpha: 0.94),
          border: Border(bottom: BorderSide(color: t.outline, width: 0.5)),
        ),
        child: Padding(
          // No inset: the labels start at the page's left edge, like the title above them.
          padding: EdgeInsets.zero,
          child: selectionBar != null
              ? SizedBox(height: SongTableSliver.headerHeight, child: selectionBar)
              :
              Row(
            children: [
              SizedBox(width: _Columns.num, child: Align(alignment: Alignment.centerLeft, child: cell('#', null))),
              Expanded(flex: 5, child: Align(alignment: Alignment.centerLeft, child: cell('Title', SongSort.title))),
              if (columns.album) Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: cell('Album', SongSort.album))),
              if (columns.added) SizedBox(width: _Columns.dateW, child: Align(alignment: Alignment.centerLeft, child: cell('Added', SongSort.added))),
              SizedBox(width: _Columns.durW, child: Align(alignment: Alignment.centerRight, child: cell('Time', SongSort.duration))),
              SizedBox(
                width: _Columns.menuW,
                child: onColumns == null
                    ? null
                    : Align(
                        alignment: Alignment.centerRight,
                        child: Tooltip(
                          message: 'Choose columns',
                          child: Semantics(
                            button: true,
                            label: 'Choose columns',
                            child: NaviPressable(
                              onTap: onColumns,
                              radius: 6,
                              child: SizedBox(
                                width: 32,
                                height: 28,
                                child: Center(child: NaviIcon(NaviGlyph.listView, size: 15, color: t.textSecondary)),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onClose;
  const _FindBar({required this.controller, required this.focus, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Space.xs, 0, Space.sm),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
        child: SizedBox(
          height: 34,
          child: TextField(
            controller: controller,
            focusNode: focus,
            style: t.subheadline.copyWith(color: t.textPrimary),
            cursorColor: t.textPrimary,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Find in this list',
              hintStyle: t.subheadline,
              filled: true,
              fillColor: t.fill,
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 8),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: NaviIcon(NaviGlyph.search, size: 16, color: t.textSecondary),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              suffixIcon: IconButton(
                tooltip: 'Close (Esc)',
                onPressed: onClose,
                icon: NaviIcon(NaviGlyph.close, size: 14, color: t.textSecondary),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends ConsumerStatefulWidget {
  final SongTableState table;
  final int index;
  final Song song;
  final _Columns columns;
  const _Row({super.key, required this.table, required this.index, required this.song, required this.columns});

  @override
  ConsumerState<_Row> createState() => _RowState();
}

class _RowState extends ConsumerState<_Row> {
  bool _hover = false;

  /// While a drag is over this row: show the insertion line above or below it.
  bool? _dropBelow;

  SongTableState get _t => widget.table;
  bool get _selected => _t._selected.contains(widget.index);

  /// The row the keyboard is on: outlined while the table has focus and keys,
  /// not the mouse, are driving.
  bool get _cursorRow =>
      _t._cursor == widget.index &&
      _t._focus.hasFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    _t._rowContexts[widget.index] = context;
  }

  @override
  void dispose() {
    if (_t._rowContexts[widget.index] == context) _t._rowContexts.remove(widget.index);
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (e.buttons == kPrimaryButton) {
      // Pressing inside a multi-selection keeps it, so it can be dragged as a group.
      if (_selected && !ctrl && !shift && _t._selected.length > 1) {
        _t._focus.requestFocus();
        return;
      }
      _t._select(widget.index, ctrl: ctrl, shift: shift);
    } else if (e.buttons == kSecondaryButton && !_selected) {
      _t._select(widget.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    _t._rowContexts[widget.index] = context;
    final t = ThemeTokens.of(context);
    final song = widget.song;
    final cols = widget.columns;
    final selected = _selected;
    final isCurrent = ref.watch(playerProvider.select((s) => _t._isPlayingRow(s, song, widget.index)));
    final isPlaying = isCurrent && ref.watch(playerProvider.select((s) => s.isPlaying));
    final artist = shortArtists(displayArtist(song, ref.watch(catalogSongProvider(song.id))));
    final svc = ref.read(subsonicServiceProvider);
    final rows = _t._rows;

    final numCell = SizedBox(
      width: _Columns.num,
      child: Align(
        alignment: Alignment.centerLeft,
        child: _hover
            ? MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _t.widget.onPlay(song, rows),
                  child: Tooltip(
                    message: 'Play',
                    child: SizedBox(width: 32, height: 32, child: Center(child: NaviIcon(NaviGlyph.play, size: 16, color: t.textPrimary, filled: true))),
                  ),
                ),
              )
            : isCurrent
                ? NowPlayingBars(isPlaying: isPlaying, color: t.textPrimary, size: 14)
                : Text(
                    '${widget.index + 1}',
                    style: t.footnote.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
      ),
    );

    final title = Expanded(
      flex: 5,
      child: Row(
        children: [
          if (_t.widget.showArtwork) ...[
            CoverArt(
              url: svc.getCoverArtUrl(song.coverArt.isNotEmpty ? song.coverArt : song.id),
              size: 36,
              radius: 4,
            ),
            const SizedBox(width: Space.md),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.subheadline.copyWith(
                    color: isCurrent ? t.accent : t.textPrimary,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
              ],
            ),
          ),
        ],
      ),
    );

    // The row's text starts exactly at the page's left edge (the same x as the page
    // title); the hover / selected wash and the focus outline reach [_wash] px beyond it.
    const wash = 8.0;
    late Widget Function() content; // the row's columns, defined just below
    Widget body = SizedBox(
      height: SongTableSliver.rowHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -wash,
            right: -wash,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              // Three states that cannot be mistaken for each other: hover is a 9% wash,
              // selected a stronger 16% fill, the keyboard cursor a 2 px outline inside the row.
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.16)
                    : (_hover ? Colors.white.withValues(alpha: 0.09) : Colors.transparent),
                borderRadius: BorderRadius.circular(6),
                border: _dropBelow == null
                    ? null
                    : Border(
                        top: _dropBelow! ? BorderSide.none : BorderSide(color: t.textPrimary, width: 2),
                        bottom: _dropBelow! ? BorderSide(color: t.textPrimary, width: 2) : BorderSide.none,
                      ),
              ),
              position: DecorationPosition.background,
              child: _cursorRow
                  ? DecoratedBox(
                      key: const Key('row-cursor'),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: t.accent, width: 2)),
                    )
                  : null,
            ),
          ),
          Positioned.fill(child: Builder(builder: (_) => content())),
        ],
      ),
    );

    content = () => Row(
        children: [
          numCell,
          title,
          if (cols.album)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: Space.md),
                child: Text(song.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
              ),
            ),
          if (cols.added)
            SizedBox(
              width: _Columns.dateW,
              child: Text(song.created == null ? '' : _date(song.created!), style: t.footnote),
            ),
          SizedBox(
            width: _Columns.durW,
            child: Text(
              formatTrackDuration(song.duration),
              textAlign: TextAlign.right,
              style: t.footnote.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          SizedBox(
            width: _Columns.menuW,
            child: Visibility(
              visible: _hover || selected,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: IconButton(
                tooltip: 'More',
                visualDensity: VisualDensity.compact,
                onPressed: () => _t._menu(widget.index),
                icon: NaviIcon(NaviGlyph.more, size: 18, color: t.textSecondary),
              ),
            ),
          ),
        ],
      );

    body = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _t.widget.onPlay(song, rows),
        onSecondaryTapUp: (_) => _t._menu(widget.index),
        child: body,
      ),
    );

    // Drag out: this row, or the whole selection if it is part of one.
    final dragged = selected ? _t._selectedSongs : [song];
    final dragIdx = selected ? (_t._selected.toList()..sort()) : [widget.index];
    body = Draggable<SongDrag>(
      data: SongDrag(dragged, dragIdx, _t.widget.playlistId),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      maxSimultaneousDrags: 1,
      onDragStarted: _t._dragStarted,
      onDragEnd: (_) => _t._stopAutoScroll(),
      onDraggableCanceled: (_, _) => _t._stopAutoScroll(),
      onDragCompleted: _t._stopAutoScroll,
      feedback: _DragChip(label: dragged.length == 1 ? song.title : '${dragged.length} songs'),
      childWhenDragging: Opacity(opacity: 0.45, child: body),
      child: body,
    );

    if (_t._canReorder) {
      final inner = body;
      body = DragTarget<SongDrag>(
        onWillAcceptWithDetails: (d) => d.data.sourcePlaylistId != null && d.data.sourcePlaylistId == _t.widget.playlistId,
        onMove: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final below = box.globalToLocal(d.offset).dy > box.size.height / 2;
          if (_dropBelow != below) setState(() => _dropBelow = below);
        },
        onLeave: (_) => setState(() => _dropBelow = null),
        onAcceptWithDetails: (d) {
          final below = _dropBelow ?? false;
          setState(() => _dropBelow = null);
          _t.widget.onReorder!(d.data.indexes, widget.index + (below ? 1 : 0));
        },
        builder: (_, _, _) => inner,
      );
    }

    return Semantics(
      selected: selected,
      label: '${song.title}, $artist${isCurrent ? ', now playing' : ''}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: body,
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

class _DragChip extends StatelessWidget {
  final String label;
  const _DragChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(left: 12, top: 12),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.outline, width: 0.5),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline.copyWith(color: t.textPrimary)),
      ),
    );
  }
}
