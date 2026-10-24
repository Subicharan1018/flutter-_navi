import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
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
import '../../../../widgets/ui/media.dart';
import '../../data/social_models.dart';
import '../../logic/jam_controller.dart';
import '../social_widgets.dart';
import 'code_entry.dart';
import 'room_ring.dart';

/// The text a person sends to invite someone.
String jamInviteText(String code) => 'Join my Jam on NaviVibe. Open Jam, tap “Join with a code” and enter $code.';

// ── a live room ──────────────────────────────────────────────────────────────

/// Slivers for the Jam you are in: the ring with its people and the song,
/// who is in sync, the code to share, the host's controls and the shared queue.
List<Widget> jamRoomSlivers(BuildContext context, WidgetRef ref, JamUiState ui) {
  final jam = ui.jam!;
  return [
    SliverToBoxAdapter(child: _RoomHero(jam: jam, driftMs: ui.driftMs)),
    SliverToBoxAdapter(child: _CodeStrip(code: jam.code)),
    SliverToBoxAdapter(child: _Transport(jam: jam)),
    SliverToBoxAdapter(
      child: SectionHeader(title: 'Up next'),
    ),
    if (jam.queue.isEmpty)
      const SliverToBoxAdapter(
        child: SocialNote(
          glyph: NaviGlyph.queue,
          art: EmptyArtKind.record,
          title: 'The queue is empty',
          message: 'Anyone in the room can add songs. Add the first one.',
        ),
      )
    else if (jam.youAreHost)
      _HostQueue(jam: jam)
    else
      SliverList.builder(
        itemCount: jam.queue.length,
        itemBuilder: (context, i) => _QueueRow(jam: jam, index: i, key: ValueKey(jam.queue[i].id)),
      ),
    SliverToBoxAdapter(child: _AddSongs(code: jam.code)),
    SliverToBoxAdapter(child: _LeaveButtons(jam: jam, busy: ui.busy)),
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
    if (jam.youAreHost) return (jam.playing ? 'You’re the host · everyone follows you' : 'You’re the host', true);
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
          Text(text, style: t.footnote.copyWith(color: t.textPrimary)),
        ]),
      ),
    );
  }
}

class _CodeStrip extends StatelessWidget {
  final String code;
  const _CodeStrip({required this.code});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        CupertinoClickable(
          onTap: () {
            Clipboard.setData(ClipboardData(text: jamInviteText(code)));
            HapticFeedback.selectionClick();
            showToast(context, 'Copied. Send it to your friends.');
          },
          scaleFactor: 0.98,
          semanticLabel: 'Jam code ${code.split('').join(' ')}. Tap to copy an invite.',
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
        const SizedBox(width: Space.sm),
        _RoundAction(
          glyph: NaviGlyph.share,
          label: 'Share invite',
          onTap: () => SharePlus.instance.share(ShareParams(text: jamInviteText(code), subject: 'Join my Jam')),
        ),
      ]),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final NaviGlyph glyph;
  final String label;
  final VoidCallback onTap;
  const _RoundAction({required this.glyph, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onTap,
        child: NaviIcon(glyph, size: 22, color: t.textPrimary),
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
    if (!jam.youAreHost) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.md),
        child: Center(child: Text('${jam.host} controls playback. Add songs to the queue.', style: t.footnote)),
      );
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      button(NaviGlyph.previous, 'Previous', c.previous),
      button(jam.playing ? NaviGlyph.pause : NaviGlyph.play, jam.playing ? 'Pause' : 'Play', c.togglePlay, size: 42),
      button(NaviGlyph.next, 'Next', c.next),
    ]);
  }
}

// ── queue ────────────────────────────────────────────────────────────────────

class _HostQueue extends ConsumerWidget {
  final JamState jam;
  const _HostQueue({required this.jam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(jamControllerProvider.notifier);
    return SliverReorderableList(
      itemCount: jam.queue.length,
      onReorderItem: (from, to) {
        if (to != from) c.moveItem(jam.queue[from].id, to);
      },
      proxyDecorator: (child, _, _) => Material(color: const Color(0x00000000), child: child),
      itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
        key: ValueKey(jam.queue[i].id),
        index: i,
        child: _QueueRow(jam: jam, index: i),
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  final JamState jam;
  final int index;
  const _QueueRow({super.key, required this.jam, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final item = jam.queue[index];
    final me = ref.read(settingsProvider).username.toLowerCase();
    final current = index == jam.index;
    final canRemove = jam.youAreHost || item.addedBy.toLowerCase() == me;
    final svc = ref.read(subsonicServiceProvider);
    final c = ref.read(jamControllerProvider.notifier);
    return Entrance(
      group: 'jam-queue',
      index: index,
      child: CupertinoClickable(
        onTap: jam.youAreHost ? () => c.jumpTo(index) : null,
        onLongPress: canRemove
            ? () => showPlatformSheet(
                  context: context,
                  title: item.title,
                  builder: (_) => Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: SheetGroup(children: [
                      SheetAction(label: 'Remove from Jam', destructive: true, onTap: () => c.removeItem(item.id)),
                    ]),
                  ),
                )
            : null,
        scaleFactor: 0.99,
        semanticLabel: '${item.title}, ${item.artist}, added by ${item.addedBy}${current ? ', playing now' : ''}',
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
                Text(item.artist, style: t.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: Space.sm),
            // Who put it there.
            PersonAvatar(item.addedBy, size: 24),
          ]),
        ),
      ),
    );
  }
}

class _AddSongs extends ConsumerWidget {
  final String code;
  const _AddSongs({required this.code});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Center(
        child: SocialButton(
          label: 'Add songs',
          quiet: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).push<bool>(
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
          ),
        ),
      ),
    );
  }
}

class _LeaveButtons extends ConsumerWidget {
  final JamState jam;
  final bool busy;
  const _LeaveButtons({required this.jam, required this.busy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(jamControllerProvider.notifier);
    return Column(children: [
      const SizedBox(height: Space.sm),
      SocialButton(
        label: 'Leave Jam',
        quiet: true,
        busy: busy,
        onPressed: () async {
          await c.leave();
          if (context.mounted) showToast(context, 'You left the Jam');
        },
      ),
      if (jam.youAreHost) const SizedBox(height: Space.sm),
      if (jam.youAreHost)
        SocialButton(
          label: 'End for everyone',
          quiet: true,
          destructive: true,
          busy: busy,
          onPressed: () async {
            final sure = await confirmDestructive(
              context,
              title: 'End this Jam?',
              message: 'Everyone is disconnected and the queue is gone.',
              confirmLabel: 'End Jam',
            );
            if (sure) await c.end();
          },
        ),
    ]);
  }
}

// ── no room yet ──────────────────────────────────────────────────────────────

/// Before a Jam: an empty room with Microduck sitting in it, one way to start
/// one and one way to join.
class JamStage extends ConsumerStatefulWidget {
  final bool busy;
  const JamStage({super.key, required this.busy});

  @override
  ConsumerState<JamStage> createState() => _JamStageState();
}

class _JamStageState extends ConsumerState<JamStage> {
  final _entry = GlobalKey<JamCodeEntryState>();

  Future<void> _join(String code) async {
    final ok = await ref.read(jamControllerProvider.notifier).join(code);
    if (!ok && mounted) {
      showToast(context, ref.read(jamControllerProvider).notice ?? 'Couldn’t join that Jam.');
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
            'Start a room, share its code, and everyone hears the same song at the same moment. You hold the controls; anyone can add songs.',
            style: t.subheadline,
            textAlign: TextAlign.center,
          ),
        ]),
      ),
      const SizedBox(height: Space.lg),
      SocialButton(
        label: 'Start a Jam',
        busy: widget.busy,
        onPressed: () async {
          if (!await ref.read(jamControllerProvider.notifier).start() && context.mounted) {
            showToast(context, ref.read(jamControllerProvider).notice ?? 'Couldn’t start a Jam.');
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
