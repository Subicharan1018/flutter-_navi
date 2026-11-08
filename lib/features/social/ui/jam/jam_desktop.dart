import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, ReorderableDragStartListener, ReorderableListView;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../widgets/art/generated_cover.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/cover_art.dart';
import '../../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../../widgets/ui/action_sheet.dart';
import '../../data/social_models.dart';
import '../../logic/jam_controller.dart';
import '../social_widgets.dart';
import 'jam_room.dart';
import 'room_ring.dart';

/// The room on Windows: two panes. Left, the room itself (ring, what is
/// playing, code, controls, who is in it). Right, the shared queue as a table
/// with hover, right-click and the keyboard (Up/Down, Enter plays, Delete
/// removes, Space plays or pauses) for whoever may edit.
class JamDesktopRoom extends ConsumerWidget {
  final JamUiState ui;
  const JamDesktopRoom({super.key, required this.ui});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final jam = ui.jam!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xxl, Space.md, Space.xxl, Space.xl),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 340, child: _RoomPane(jam: jam, driftMs: ui.driftMs)),
        Container(width: 0.5, margin: const EdgeInsets.symmetric(horizontal: Space.xl), height: 520, color: t.outline),
        Expanded(child: _QueuePane(jam: jam)),
      ]),
    );
  }
}

class _RoomPane extends ConsumerWidget {
  final JamState jam;
  final int? driftMs;
  const _RoomPane({required this.jam, required this.driftMs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final svc = ref.read(subsonicServiceProvider);
    final cur = jam.current;
    final c = ref.read(jamControllerProvider.notifier);
    Widget transport(NaviGlyph g, String label, VoidCallback onTap, {double size = 24}) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: onTap,
            child: NaviIcon(g, size: size, color: t.textPrimary),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      RoomRing(
        members: jam.members,
        size: 260,
        playing: jam.playing,
        center: cur != null && cur.coverArt.isNotEmpty
            ? CoverArt(url: svc.getCoverArtUrl(cur.coverArt), size: 150, radius: 0)
            : GeneratedCover(name: 'jam ${jam.code}'),
      ),
      const SizedBox(height: Space.md),
      Text(cur?.title ?? 'Nothing playing yet', style: t.title3, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      if (cur != null)
        Text(
          cur.artist.isEmpty ? 'Added by ${cur.addedBy}' : '${cur.artist} · added by ${cur.addedBy}',
          style: t.subheadline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      const SizedBox(height: Space.sm),
      SyncPill(jam: jam, driftMs: driftMs),
      const SizedBox(height: Space.xs),
      Text(jamRoleLine(jam), style: t.caption1, maxLines: 1, overflow: TextOverflow.ellipsis),
      JamCodeStrip(code: jam.code),
      const SizedBox(height: Space.md),
      if (jam.youCanEdit)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          transport(NaviGlyph.previous, 'Previous', c.previous),
          transport(jam.playing ? NaviGlyph.pause : NaviGlyph.play, jam.playing ? 'Pause' : 'Play', c.togglePlay, size: 32),
          transport(NaviGlyph.next, 'Next', c.next),
        ])
      else
        Text(
          'The admin controls the queue. ${jam.admin} plays, skips and reorders. You can add songs.',
          style: t.footnote,
          textAlign: TextAlign.center,
        ),
      Align(alignment: Alignment.centerLeft, child: JamMembers(jam: jam)),
    ]);
  }
}

class _QueuePane extends ConsumerStatefulWidget {
  final JamState jam;
  const _QueuePane({required this.jam});

  @override
  ConsumerState<_QueuePane> createState() => _QueuePaneState();
}

class _QueuePaneState extends ConsumerState<_QueuePane> {
  int? _selected; // queue item id
  final _focus = FocusNode(debugLabel: 'jam-queue');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  JamState get jam => widget.jam;

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || jam.queue.isEmpty) return KeyEventResult.ignored;
    final c = ref.read(jamControllerProvider.notifier);
    final at = _selected == null ? -1 : jam.queue.indexWhere((i) => i.id == _selected);
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      final next = (at + (k == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(0, jam.queue.length - 1);
      setState(() => _selected = jam.queue[next].id);
      return KeyEventResult.handled;
    }
    // The rest changes the room: only for someone who may edit (the server agrees).
    if (!jam.youCanEdit) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.space) {
      c.togglePlay();
      return KeyEventResult.handled;
    }
    if (at < 0) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.enter) {
      c.jumpTo(at);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      c.removeItem(jam.queue[at].id);
      final keep = (at).clamp(0, jam.queue.length - 2);
      setState(() => _selected = jam.queue.length > 1 ? jam.queue[keep == at ? at + 1 : keep].id : null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final c = ref.read(jamControllerProvider.notifier);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Up next', style: t.title2)),
          JamChipButton(glyph: NaviGlyph.plus, label: 'Add songs', onTap: () => addSongsToJam(context, ref)),
          const SizedBox(width: Space.xs),
          Semantics(
            button: true,
            label: 'Room options',
            excludeSemantics: true,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () => showJamRoomMenu(context, ref, jam),
              child: NaviIcon(NaviGlyph.more, size: 22, color: t.textPrimary),
            ),
          ),
        ]),
        const SizedBox(height: Space.sm),
        _Header(canEdit: jam.youCanEdit),
        if (jam.queue.isEmpty)
          const SocialNote(
            glyph: NaviGlyph.queue,
            title: 'The queue is empty',
            message: 'Anyone in the room can add songs. Add the first one.',
          )
        else if (jam.youCanEdit)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: jam.queue.length,
            onReorderItem: (from, to) {
              if (to != from) c.moveItem(jam.queue[from].id, to);
            },
            proxyDecorator: (child, _, _) => Material(color: const Color(0x00000000), child: child),
            itemBuilder: (context, i) => _Row(
              key: ValueKey(jam.queue[i].id),
              jam: jam,
              index: i,
              selected: _selected == jam.queue[i].id,
              onSelect: () {
                setState(() => _selected = jam.queue[i].id);
                _focus.requestFocus();
              },
            ),
          )
        else
          for (var i = 0; i < jam.queue.length; i++)
            _Row(
              key: ValueKey(jam.queue[i].id),
              jam: jam,
              index: i,
              selected: _selected == jam.queue[i].id,
              onSelect: () {
                setState(() => _selected = jam.queue[i].id);
                _focus.requestFocus();
              },
            ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  final bool canEdit;
  const _Header({required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final style = t.caption1.copyWith(color: t.textMuted);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
      child: Row(children: [
        SizedBox(width: 32, child: Text('#', style: style)),
        const SizedBox(width: 44 + Space.md),
        Expanded(flex: 4, child: Text('Title', style: style)),
        Expanded(flex: 2, child: Text('Added by', style: style)),
        SizedBox(width: 56, child: Text('Time', style: style, textAlign: TextAlign.right)),
        if (canEdit) const SizedBox(width: 32),
      ]),
    );
  }
}

class _Row extends ConsumerStatefulWidget {
  final JamState jam;
  final int index;
  final bool selected;
  final VoidCallback onSelect;
  const _Row({super.key, required this.jam, required this.index, required this.selected, required this.onSelect});

  @override
  ConsumerState<_Row> createState() => _RowState();
}

class _RowState extends ConsumerState<_Row> {
  bool _hover = false;

  String _time(int s) => s <= 0 ? '' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  void _menu(BuildContext context) {
    final item = widget.jam.queue[widget.index];
    final c = ref.read(jamControllerProvider.notifier);
    if (!widget.jam.youCanEdit) return; // nothing to offer a member here
    showPlatformSheet(
      context: context,
      title: item.title,
      builder: (_) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: SheetGroup(children: [
          SheetAction(label: 'Play now', hint: 'Enter', onTap: () => c.jumpTo(widget.index)),
          SheetAction(label: 'Remove from room', hint: 'Del', destructive: true, onTap: () => c.removeItem(item.id)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final jam = widget.jam;
    final item = jam.queue[widget.index];
    final current = widget.index == jam.index;
    final svc = ref.read(subsonicServiceProvider);
    final c = ref.read(jamControllerProvider.notifier);
    final bg = widget.selected ? t.fill : (_hover ? t.fill.withValues(alpha: 0.5) : null);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onDoubleTap: jam.youCanEdit ? () => c.jumpTo(widget.index) : null,
        onSecondaryTapDown: (_) {
          widget.onSelect();
          _menu(context);
        },
        child: Semantics(
          label: '${item.title}, ${item.artist}, added by ${item.addedBy}${current ? ', playing now' : ''}',
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            color: bg,
            child: Row(children: [
              SizedBox(
                width: 32,
                child: current
                    ? NaviIcon(NaviGlyph.play, size: 14, color: t.textPrimary)
                    : Text('${widget.index + 1}', style: t.footnote),
              ),
              CoverArt(url: svc.getCoverArtUrl(item.coverArt), size: 44, radius: Radii.thumb),
              const SizedBox(width: Space.md),
              Expanded(
                flex: 4,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    item.title,
                    style: t.body.copyWith(fontWeight: current ? FontWeight.w700 : FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(item.artist, style: t.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Expanded(
                flex: 2,
                child: Row(children: [
                  PersonAvatar(item.addedBy, size: 22),
                  const SizedBox(width: Space.sm),
                  Flexible(child: Text(item.addedBy, style: t.footnote, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
              SizedBox(width: 56, child: Text(_time(item.durationS), style: t.footnote, textAlign: TextAlign.right)),
              if (jam.youCanEdit)
                SizedBox(
                  width: 32,
                  child: Opacity(
                    opacity: _hover || widget.selected ? 1 : 0,
                    child: ReorderableDragStartListener(
                      index: widget.index,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Center(child: NaviIcon(NaviGlyph.more, size: 18, color: t.textMuted)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
