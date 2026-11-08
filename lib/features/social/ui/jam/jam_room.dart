import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/motion.dart';
import '../../../../core/theme.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../screens/song_picker_screen.dart';
import '../../../../widgets/art/empty_art.dart' show EmptyArtKind;
import '../../../../widgets/art/generated_cover.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/cover_art.dart';
import '../../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../../widgets/mascot/microduck.dart';
import '../../../../widgets/mascot/microduck_pose.dart';
import '../../../../widgets/ui/action_sheet.dart';
import '../../data/social_models.dart';
import '../../logic/jam_controller.dart';
import '../../logic/jam_hints.dart';
import '../../logic/social_rules.dart';
import '../collab_screens.dart' show saveQueueAsCollab;
import '../social_widgets.dart';
import 'code_entry.dart';
import 'room_ring.dart';

/// The text a person sends to invite someone.
String jamInviteText(String code) => 'Join my Jam on NaviVibe. Open Jam, tap “Join with a code” and enter $code.';

/// What a person in the room can do, in the words the screens use.
String jamRoleLine(JamState jam) {
  if (jam.isCollab) return jam.youAreAdmin ? 'Collab · you’re the admin' : 'Collab · everyone edits the queue';
  return jam.youAreAdmin ? 'Jam · you’re the admin' : 'Jam · ${jam.admin} controls the queue';
}

// ── actions shared by the phone and the Windows room ────────────────────────

/// Opens the song picker and adds what is picked to the room. Everyone in the
/// room may add, whatever their role.
Future<void> addSongsToJam(BuildContext context, WidgetRef ref) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    CupertinoPageRoute(
      fullscreenDialog: true,
      builder: (_) => SongPickerScreen.custom(
        destination: 'the Jam',
        onPicked: (songs) async {
          final ok = await ref.read(jamControllerProvider.notifier).addSongs(songs);
          if (!ok && context.mounted) {
            showToast(context, ref.read(jamControllerProvider).notice ?? 'Couldn’t add songs. Try again.');
          }
          return ok;
        },
      ),
    ),
  );
}

void copyJamInvite(BuildContext context, String code) {
  Clipboard.setData(ClipboardData(text: jamInviteText(code)));
  HapticFeedback.selectionClick();
  showToast(context, 'Invite copied. Send it to your friends.');
}

void shareJamInvite(String code) =>
    SharePlus.instance.share(ShareParams(text: jamInviteText(code), subject: 'Join my Jam'));

/// Leave, End for everyone (admin) and Clear queue (whoever may edit).
Future<void> showJamRoomMenu(BuildContext context, WidgetRef ref, JamState jam) {
  final c = ref.read(jamControllerProvider.notifier);
  final container = ProviderScope.containerOf(context);
  return showPlatformSheet(
    context: context,
    title: jam.isCollab ? 'Collab room' : 'Jam room',
    builder: (_) => Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (jam.isCollab && jam.queue.isNotEmpty)
          SheetGroup(children: [
            SheetAction(
              label: 'Save queue as collab playlist',
              onTap: () => saveQueueAsCollab(context, container, [for (final q in jam.queue) q.songId]),
            ),
          ]),
        if (jam.youAreAdmin)
          SheetGroup(children: [
            SheetAction(
              label: jam.open ? 'Hide from People' : 'Show in People',
              detail: jam.open ? 'Friends can no longer join without the code' : 'Friends can join from People, without the code',
              onTap: () => c.setOpen(!jam.open),
            ),
          ]),
        if (jam.youCanEdit && jam.queue.isNotEmpty)
          SheetGroup(children: [
            SheetAction(
              label: 'Clear queue',
              destructive: true,
              onTap: () async {
                final sure = await confirmDestructive(
                  context,
                  title: 'Clear the queue?',
                  message: 'Every song is removed for everyone in the room.',
                  confirmLabel: 'Clear',
                );
                if (sure) await c.clearQueue();
              },
            ),
          ]),
        SheetGroup(children: [
          SheetAction(
            label: 'Leave room',
            onTap: () async {
              await c.leave();
              if (context.mounted) showToast(context, 'You left the room');
            },
          ),
          if (jam.youAreAdmin)
            SheetAction(
              label: 'End for everyone',
              destructive: true,
              onTap: () async {
                final sure = await confirmDestructive(
                  context,
                  title: 'End this room?',
                  message: 'Everyone is disconnected and the queue is gone.',
                  confirmLabel: 'End room',
                );
                if (sure) await c.end();
              },
            ),
        ]),
      ]),
    ),
  );
}

/// What the admin can do with another member.
Future<void> showMemberActions(BuildContext context, WidgetRef ref, JamMember m) {
  final c = ref.read(jamControllerProvider.notifier);
  return showPlatformSheet(
    context: context,
    title: m.username,
    builder: (_) => Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: SheetGroup(children: [
        SheetAction(
          label: 'Make admin',
          onTap: () async {
            final sure = await confirmDestructive(
              context,
              title: 'Make ${m.username} the admin?',
              message: 'They take over the queue and playback. You become a member.',
              confirmLabel: 'Make admin',
            );
            if (sure) await c.makeAdmin(m.username);
          },
        ),
        SheetAction(label: 'Remove from room', destructive: true, onTap: () => c.removeMember(m.username)),
      ]),
    ),
  );
}

/// Whether [m] is the person using this phone.
bool isMe(WidgetRef ref, JamMember m) =>
    m.username.toLowerCase() == ref.read(settingsProvider).username.toLowerCase();

// ── a live room ──────────────────────────────────────────────────────────────

/// Slivers for the room you are in: the ring with its people and the song, who
/// is in sync, the code to share, the controls (or who holds them), the shared
/// queue and who is in the room.
List<Widget> jamRoomSlivers(BuildContext context, WidgetRef ref, JamUiState ui) {
  final jam = ui.jam!;
  return [
    SliverToBoxAdapter(child: _RoomHero(jam: jam, driftMs: ui.driftMs)),
    SliverToBoxAdapter(child: JamCodeStrip(code: jam.code)),
    SliverToBoxAdapter(child: _Transport(jam: jam)),
    SliverToBoxAdapter(child: _QueueHeader(jam: jam)),
    if (jam.queue.isEmpty)
      SliverToBoxAdapter(
        child: SocialNote(
          glyph: NaviGlyph.queue,
          art: EmptyArtKind.record,
          title: 'The queue is empty',
          message: jam.youCanEdit ? 'Anyone in the room can add songs. Add the first one.' : 'Add the first song.',
        ),
      )
    else if (jam.youCanEdit) ...[
      if (jam.queue.length > 1) const SliverToBoxAdapter(child: JamQueueHintLine()),
      _EditableQueue(jam: jam),
    ]
    else
      SliverList.builder(
        itemCount: jam.queue.length,
        itemBuilder: (context, i) => JamQueueRow(jam: jam, index: i, key: ValueKey(jam.queue[i].id)),
      ),
    SliverToBoxAdapter(child: JamMembers(jam: jam)),
    SliverToBoxAdapter(child: JamRecentlyLeft(jam: jam)),
    const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
  ];
}

class _RoomHero extends ConsumerWidget {
  final JamState jam;
  final int? driftMs;
  const _RoomHero({required this.jam, required this.driftMs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final svc = ref.read(subsonicServiceProvider);
    final cur = jam.current;
    final width = MediaQuery.sizeOf(context).width;
    final size = (width - Space.gutter * 2).clamp(240.0, 360.0);
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(children: [
        Center(
          child: RoomRing(
            members: jam.members,
            size: size,
            playing: jam.playing,
            center: cur != null && cur.coverArt.isNotEmpty
                ? CoverArt(url: svc.getCoverArtUrl(cur.coverArt), size: size * 0.6, radius: 0)
                : GeneratedCover(name: 'jam ${jam.code}'),
          ),
        ),
        const SizedBox(height: Space.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(children: [
            Text(cur?.title ?? 'Nothing playing yet', style: t.title2, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (cur != null)
              Text(
                cur.artist.isEmpty ? 'Added by ${cur.addedBy}' : '${cur.artist} · added by ${cur.addedBy}',
                style: t.subheadline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ]),
        ),
        const SizedBox(height: Space.sm),
        SyncPill(jam: jam, driftMs: driftMs),
        const SizedBox(height: Space.xs),
        Text(jamRoleLine(jam), style: t.caption1, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// Whether this phone is keeping up with the room.
class SyncPill extends StatelessWidget {
  final JamState jam;
  final int? driftMs;
  const SyncPill({super.key, required this.jam, required this.driftMs});

  static (String, bool) status(JamState jam, int? driftMs) {
    if (jam.youAreHost) return (jam.playing ? 'You’re the admin · everyone follows you' : 'You’re the admin', true);
    if (!jam.playing) return ('Waiting for ${jam.host}', false);
    if (driftMs == null) return ('Syncing…', false);
    return driftMs <= 1500 ? ('In sync with ${jam.host}', true) : ('Catching up…', false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final (text, good) = status(jam, driftMs);
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - Space.gutter * 2),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs + 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.capsule),
          border: Border.all(color: t.outline, width: 0.5),
          color: t.fill,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // Filled dot when in step, hollow when not: shape, not colour, says it.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: good ? t.textPrimary : null,
              border: Border.all(color: t.textPrimary, width: 1.2),
            ),
          ),
          const SizedBox(width: Space.sm),
          Flexible(child: Text(text, style: t.footnote.copyWith(color: t.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

/// The room's code with a visible Copy and Share beside it.
class JamCodeStrip extends StatelessWidget {
  final String code;
  const JamCodeStrip({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
      child: Column(children: [
        Semantics(
          label: 'Room code ${code.split('').join(' ')}',
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final ch in code.split(''))
                Container(
                  width: 34,
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.fill,
                    borderRadius: BorderRadius.circular(Radii.thumb + 3),
                    border: Border.all(color: t.outline, width: 0.5),
                  ),
                  child: Text(ch, style: t.title3),
                ),
            ]),
          ),
        ),
        const SizedBox(height: Space.sm),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          JamChipButton(glyph: NaviGlyph.copy, label: 'Copy', onTap: () => copyJamInvite(context, code)),
          const SizedBox(width: Space.sm),
          JamChipButton(glyph: NaviGlyph.share, label: 'Share', onTap: () => shareJamInvite(code)),
        ]),
      ]),
    );
  }
}

/// A small capsule with a glyph and a word; at least 44 pt tall to tap.
class JamChipButton extends StatelessWidget {
  final NaviGlyph? glyph;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  const JamChipButton({super.key, this.glyph, required this.label, required this.onTap, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final color = destructive ? t.danger : t.textPrimary;
    return CupertinoClickable(
      onTap: onTap,
      scaleFactor: 0.97,
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Center(
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            decoration: BoxDecoration(
              color: t.fill,
              borderRadius: BorderRadius.circular(Radii.capsule),
              border: Border.all(color: t.outline, width: 0.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (glyph != null) ...[
                NaviIcon(glyph!, size: 18, color: color),
                const SizedBox(width: Space.xs + 2),
              ],
              Text(label, style: t.subheadline.copyWith(color: color, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Transport extends ConsumerWidget {
  final JamState jam;
  const _Transport({required this.jam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final c = ref.read(jamControllerProvider.notifier);
    Widget button(NaviGlyph g, String label, VoidCallback onTap, {double size = 30}) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(56, 56),
            onPressed: onTap,
            child: NaviIcon(g, size: size, color: t.textPrimary),
          ),
        );
    if (!jam.youCanEdit) {
      // No dead controls: say who holds them and point at what a member can do.
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
          child: Center(
            child: Text(
              'The admin controls the queue. ${jam.admin} plays, skips and reorders. You can add songs.',
              style: t.footnote,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        JamAskToSkip(jam: jam),
      ]);
    }
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        button(NaviGlyph.previous, 'Previous', c.previous),
        button(jam.playing ? NaviGlyph.pause : NaviGlyph.play, jam.playing ? 'Pause' : 'Play', c.togglePlay, size: 42),
        button(NaviGlyph.next, 'Next', c.next),
      ]),
      JamSkipRequests(jam: jam),
    ]);
  }
}

// ── queue ────────────────────────────────────────────────────────────────────

/// "Up next" with the one place to add songs and the room's menu.
class _QueueHeader extends ConsumerWidget {
  final JamState jam;
  const _QueueHeader({required this.jam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.sm, Space.sm),
      child: Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text('Up next', style: t.title2, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
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
    );
  }
}

class _EditableQueue extends ConsumerWidget {
  final JamState jam;
  const _EditableQueue({required this.jam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(jamControllerProvider.notifier);
    return SliverReorderableList(
      itemCount: jam.queue.length,
      onReorderItem: (from, to) {
        if (to == from) return;
        ref.read(jamQueueHintProvider.notifier).done();
        c.moveItem(jam.queue[from].id, to);
      },
      proxyDecorator: (child, _, _) => Material(color: const Color(0x00000000), child: child),
      itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
        key: ValueKey(jam.queue[i].id),
        index: i,
        child: JamQueueRow(jam: jam, index: i),
      ),
    );
  }
}

/// One song in the shared queue, with the person who put it there.
class JamQueueRow extends ConsumerWidget {
  final JamState jam;
  final int index;
  const JamQueueRow({super.key, required this.jam, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final item = jam.queue[index];
    final current = index == jam.index;
    final svc = ref.read(subsonicServiceProvider);
    final c = ref.read(jamControllerProvider.notifier);
    final by = item.addedBy.isEmpty ? '' : 'Added by ${item.addedBy}';
    return Entrance(
      group: 'jam-queue',
      index: index,
      // Screen readers get the same actions the long press and the drag give.
      child: Semantics(
        customSemanticsActions: jam.youCanEdit
            ? {
                if (index > 0) const CustomSemanticsAction(label: 'Reorder: move up'): () => moveInRoom(ref, jam, index, index - 1),
                if (index < jam.queue.length - 1)
                  const CustomSemanticsAction(label: 'Reorder: move down'): () => moveInRoom(ref, jam, index, index + 1),
                const CustomSemanticsAction(label: 'Remove from room'): () => removeFromRoom(context, ref, jam, item),
              }
            : const {},
        child: CupertinoClickable(
        onTap: jam.youCanEdit ? () => c.jumpTo(index) : null,
        onLongPress: jam.youCanEdit
            ? () => showPlatformSheet(
                  context: context,
                  title: item.title,
                  builder: (_) => Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Reordering without dragging: the same thing, one step at a time.
                      if (index > 0 || index < jam.queue.length - 1)
                        SheetGroup(children: [
                          if (index > 0) SheetAction(label: 'Move up', onTap: () => moveInRoom(ref, jam, index, index - 1)),
                          if (index < jam.queue.length - 1)
                            SheetAction(label: 'Move down', onTap: () => moveInRoom(ref, jam, index, index + 1)),
                        ]),
                      SheetGroup(children: [
                        SheetAction(label: 'Remove from room', destructive: true, onTap: () => removeFromRoom(context, ref, jam, item)),
                      ]),
                    ]),
                  ),
                )
            : null,
        scaleFactor: 0.99,
        semanticLabel: '${item.title}, ${item.artist}, ${by.toLowerCase()}${current ? ', playing now' : ''}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xs + 2),
          color: current ? t.fill : null,
          child: Row(children: [
            CoverArt(url: svc.getCoverArtUrl(item.coverArt), size: 46, radius: Radii.thumb),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  item.title,
                  style: t.body.copyWith(fontWeight: current ? FontWeight.w700 : FontWeight.w400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.artist.isEmpty ? by : '${item.artist} · $by',
                  style: t.footnote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            const SizedBox(width: Space.sm),
            // Who put it there.
            PersonAvatar(item.addedBy, size: 24),
          ]),
        ),
      ),
      ),
    );
  }
}

/// Removes [item] and says so, with Undo for whoever may put it back.
Future<void> removeFromRoom(BuildContext context, WidgetRef ref, JamState jam, JamItem item) async {
  final c = ref.read(jamControllerProvider.notifier);
  ref.read(jamQueueHintProvider.notifier).done(); // they found it
  final toast = removalToast(jam, item.title);
  if (!await c.removeItem(item.id) || !context.mounted) return;
  if (toast.canUndo) {
    showToastWithAction(
      context,
      toast.text,
      actionLabel: 'Undo',
      onAction: () => c.undoRemove(item.id),
    );
  } else {
    showToast(context, toast.text);
  }
}

/// Moves the song at [from] to [to] (the long-press sheet and the screen
/// reader's Reorder actions; dragging does the same).
void moveInRoom(WidgetRef ref, JamState jam, int from, int to) {
  ref.read(jamQueueHintProvider.notifier).done();
  ref.read(jamControllerProvider.notifier).moveItem(jam.queue[from].id, to);
}

/// A quiet first-run line above the queue: how to reorder and remove. Goes
/// away for good once dismissed or once the person reorders or removes.
class JamQueueHintLine extends ConsumerWidget {
  const JamQueueHintLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(jamQueueHintProvider)) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.sm, Space.sm),
      child: Row(children: [
        Expanded(
          child: Text('Press and hold a song to reorder or remove it.', style: t.footnote),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          minimumSize: const Size(44, 44),
          onPressed: ref.read(jamQueueHintProvider.notifier).done,
          child: Text('Got it', style: t.subheadline.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ── requests to skip ─────────────────────────────────────────────────────────

/// For the admin: a quiet line when members ask to skip, with Approve and Dismiss.
class JamSkipRequests extends ConsumerWidget {
  final JamState jam;
  const JamSkipRequests({super.key, required this.jam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!jam.youAreAdmin || jam.skipRequests.isEmpty) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final c = ref.read(jamControllerProvider.notifier);
    final text = skipRequestSummary(jam.skipRequests);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.sm, 0),
      child: Semantics(
        liveRegion: true,
        label: text,
        child: Row(children: [
          Expanded(child: Text(text, style: t.footnote.copyWith(color: t.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis)),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            minimumSize: const Size(44, 44),
            onPressed: () => c.resolveSkip(approve: false),
            child: Text('Dismiss', style: t.subheadline.copyWith(color: t.textSecondary)),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            minimumSize: const Size(44, 44),
            onPressed: () => c.resolveSkip(approve: true),
            child: Text('Approve', style: t.subheadline.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

/// For a Jam member: ask the admin to skip the song that is playing.
class JamAskToSkip extends ConsumerWidget {
  final JamState jam;
  const JamAskToSkip({super.key, required this.jam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canRequestSkip(jam)) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final asked = jam.youRequestedSkip;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Center(
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          minimumSize: const Size(44, 44),
          onPressed: asked ? null : () => ref.read(jamControllerProvider.notifier).requestSkip(),
          child: Text(
            asked ? 'Skip requested' : 'Ask to skip this song',
            style: t.subheadline.copyWith(color: asked ? t.textMuted : t.accent, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ── people ───────────────────────────────────────────────────────────────────

/// Who left or was removed lately, newest first.
class JamRecentlyLeft extends StatelessWidget {
  final JamState jam;
  const JamRecentlyLeft({super.key, required this.jam});

  @override
  Widget build(BuildContext context) {
    if (jam.recentlyLeft.isEmpty) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.xs),
        child: Semantics(header: true, child: Text('Recently left', style: t.title3)),
      ),
      for (final m in jam.recentlyLeft)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xs),
          child: Semantics(
            label: '${m.username}. ${leftLine(m)}',
            excludeSemantics: true,
            child: Row(children: [
              PersonAvatar(m.username, size: 28),
              const SizedBox(width: Space.md),
              Expanded(child: Text(m.username, style: t.body.copyWith(color: t.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(leftLine(m), style: t.footnote),
            ]),
          ),
        ),
    ]);
  }
}

/// Who is in the room and what each person is. The admin can open a member's
/// actions (make admin, remove).
class JamMembers extends ConsumerWidget {
  final JamState jam;
  const JamMembers({super.key, required this.jam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, Space.sm),
        child: Semantics(
          header: true,
          child: Text('In the room · ${jam.members.length}', style: t.title2, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      for (final m in jam.members) JamMemberRow(jam: jam, member: m),
    ]);
  }
}

class JamMemberRow extends ConsumerWidget {
  final JamState jam;
  final JamMember member;
  const JamMemberRow({super.key, required this.jam, required this.member});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final me = isMe(ref, member);
    final canManage = jam.youAreAdmin && !me;
    return CupertinoClickable(
      onTap: canManage ? () => showMemberActions(context, ref, member) : null,
      scaleFactor: 0.99,
      semanticLabel: '${member.username}${me ? ', you' : ''}, ${member.role}${canManage ? '. Double tap for actions.' : ''}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xs + 2),
        child: Row(children: [
          PersonAvatar(member.username, size: 36),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              me ? '${member.username} (you)' : member.username,
              style: t.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Space.sm),
          Text(member.role, style: t.footnote.copyWith(color: member.isAdmin ? t.textPrimary : t.textMuted)),
          if (canManage) ...[
            const SizedBox(width: Space.xs),
            SizedBox(width: 32, height: 44, child: Center(child: NaviIcon(NaviGlyph.more, size: 20, color: t.textMuted))),
          ],
        ]),
      ),
    );
  }
}

// ── no room yet ──────────────────────────────────────────────────────────────

/// Before a room: an empty room with Microduck sitting in it, a choice between
/// a Jam and a Collab, one way to start and one way to join.
class JamStage extends ConsumerStatefulWidget {
  final bool busy;
  const JamStage({super.key, required this.busy});

  @override
  ConsumerState<JamStage> createState() => _JamStageState();
}

class _JamStageState extends ConsumerState<JamStage> {
  final _entry = GlobalKey<JamCodeEntryState>();
  JamMode _mode = JamMode.jam;

  Future<void> _join(String code) async {
    final ok = await ref.read(jamControllerProvider.notifier).join(code);
    if (!ok && mounted) {
      showToast(context, ref.read(jamControllerProvider).notice ?? 'Couldn’t join that room.');
      _entry.currentState?.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final size = (width - Space.gutter * 4).clamp(220.0, 300.0);
    final duckOn = ref.watch(settingsProvider.select((s) => s.microduckEnabled));
    return Column(children: [
      const SizedBox(height: Space.md),
      RoomRing(
        members: const [],
        size: size,
        playing: false,
        center: duckOn
            ? ColoredBox(
                color: t.fill,
                child: Center(
                  child: Microduck(
                    pose: MicroduckPose.idle,
                    size: size * 0.5,
                    interactive: true,
                  ),
                ),
              )
            : GeneratedCover(name: 'empty jam room'),
      ),
      const SizedBox(height: Space.lg),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
        child: Column(children: [
          Text('Listen together', style: t.title1, textAlign: TextAlign.center),
          const SizedBox(height: Space.xs),
          Text(
            'Start a room, share its code, and everyone hears the same song at the same moment.',
            style: t.subheadline,
            textAlign: TextAlign.center,
          ),
        ]),
      ),
      const SizedBox(height: Space.lg),
      JamModePicker(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
      const SizedBox(height: Space.md),
      SocialButton(
        label: 'Start a ${_mode.label}',
        busy: widget.busy,
        onPressed: () async {
          if (!await ref.read(jamControllerProvider.notifier).start(mode: _mode) && context.mounted) {
            showToast(context, ref.read(jamControllerProvider).notice ?? 'Couldn’t start a room.');
          }
        },
      ),
      const SizedBox(height: Space.md),
      Text('Have a code?', style: t.footnote),
      const SizedBox(height: Space.sm),
      JamCodeEntry(key: _entry, enabled: !widget.busy, onComplete: _join),
      const SizedBox(height: Space.lg),
    ]);
  }
}

/// Jam (you hold the controls) or Collab (everyone edits).
class JamModePicker extends StatelessWidget {
  final JamMode mode;
  final ValueChanged<JamMode> onChanged;
  const JamModePicker({super.key, required this.mode, required this.onChanged});

  static String describe(JamMode m) => m == JamMode.jam
      ? 'You hold the controls. Friends can add songs to the queue.'
      : 'Everyone is an equal editor: add, reorder, remove and skip.';

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(children: [
        CupertinoSlidingSegmentedControl<JamMode>(
          groupValue: mode,
          onValueChanged: (m) {
            if (m != null) onChanged(m);
          },
          children: {
            for (final m in JamMode.values)
              m: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
                child: Text(m.label, style: t.subheadline.copyWith(fontWeight: FontWeight.w600)),
              ),
          },
        ),
        const SizedBox(height: Space.sm),
        Text(describe(mode), style: t.footnote, textAlign: TextAlign.center),
      ]),
    );
  }
}
