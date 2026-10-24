import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/settings_provider.dart';
import '../../../screens/song_picker_screen.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../data/social_models.dart';
import '../logic/jam_controller.dart';
import 'social_widgets.dart';

/// Jam: one shared queue, one set of controls (the host's), everyone listening
/// in step. Starting and joining live here too.
class JamScreen extends ConsumerStatefulWidget {
  const JamScreen({super.key});

  @override
  ConsumerState<JamScreen> createState() => _JamScreenState();
}

class _JamScreenState extends ConsumerState<JamScreen> {
  @override
  void initState() {
    super.initState();
    // Picks up a Jam this account is already in (app restarted, new phone).
    Future.microtask(() => ref.read(jamControllerProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(jamControllerProvider);
    ref.listen(jamControllerProvider.select((s) => s.notice), (_, notice) {
      if (notice != null) {
        showToast(context, notice);
        ref.read(jamControllerProvider.notifier).clearNotice();
      }
    });
    final jam = ui.jam;
    return LargeTitlePage(
      title: 'Jam',
      slivers: jam == null
          ? [SliverToBoxAdapter(child: _StartOrJoin(busy: ui.busy))]
          : [
              SliverToBoxAdapter(child: _CodeCard(jam: jam)),
              SliverToBoxAdapter(child: _Members(jam: jam)),
              SliverToBoxAdapter(child: _NowPlayingControls(jam: jam)),
              const SliverToBoxAdapter(child: SectionHeader(title: 'Up next')),
              if (jam.queue.isEmpty)
                const SliverToBoxAdapter(
                  child: SocialNote(
                    glyph: NaviGlyph.queue,
                    title: 'The queue is empty',
                    message: 'Anyone in the Jam can add songs. Add the first one.',
                  ),
                )
              else
                SliverList.builder(
                  itemCount: jam.queue.length,
                  itemBuilder: (context, i) => _QueueRow(jam: jam, index: i),
                ),
              SliverToBoxAdapter(child: _AddSongs(code: jam.code)),
              SliverToBoxAdapter(child: _LeaveButtons(jam: jam, busy: ui.busy)),
            ],
    );
  }
}

class _StartOrJoin extends ConsumerWidget {
  final bool busy;
  const _StartOrJoin({required this.busy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jam = ref.read(jamControllerProvider.notifier);
    return Column(children: [
      const SocialNote(
        glyph: NaviGlyph.group,
        title: 'Listen together',
        message: 'Start a Jam and share its code. Everyone adds songs to one queue and hears the same thing at the same time. Only you control playback.',
      ),
      SocialButton(
        label: 'Start a Jam',
        busy: busy,
        onPressed: () async {
          if (!await jam.start() && context.mounted) {
            showToast(context, ref.read(jamControllerProvider).notice ?? 'Couldn’t start a Jam.');
          }
        },
      ),
      SocialButton(
        label: 'Join with a code',
        quiet: true,
        onPressed: busy
            ? null
            : () async {
                final code = await askForText(
                  context,
                  title: 'Join a Jam',
                  placeholder: 'Code',
                  action: 'Join',
                  capitalization: TextCapitalization.characters,
                );
                if (code == null) return;
                final ok = await jam.join(code);
                if (!ok && context.mounted) {
                  showToast(context, ref.read(jamControllerProvider).notice ?? 'Couldn’t join that Jam.');
                }
              },
      ),
    ]);
  }
}

class _CodeCard extends StatelessWidget {
  final JamState jam;
  const _CodeCard({required this.jam});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: () {
        Clipboard.setData(ClipboardData(text: 'Join my Jam on NaviVibe with the code ${jam.code}'));
        HapticFeedback.selectionClick();
        showToast(context, 'Copied. Send it to your friends.');
      },
      scaleFactor: 0.98,
      semanticLabel: 'Jam code ${jam.code}. Tap to copy an invite.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
        child: Column(children: [
          Text(
            jam.code.split('').join(' '),
            style: t.largeTitle.copyWith(fontSize: 38, letterSpacing: 2),
          ),
          const SizedBox(height: Space.xs),
          Text('Tap to copy an invite', style: t.footnote),
        ]),
      ),
    );
  }
}

class _Members extends StatelessWidget {
  final JamState jam;
  const _Members({required this.jam});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
      child: Wrap(
        spacing: Space.lg,
        runSpacing: Space.md,
        children: [
          for (final m in jam.members)
            SizedBox(
              width: 64,
              child: Column(children: [
                PersonAvatar(m.username, size: 44),
                const SizedBox(height: Space.xs),
                Text(m.username, style: t.caption1, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (m.isHost) Text('Host', style: t.caption2),
              ]),
            ),
        ],
      ),
    );
  }
}

class _NowPlayingControls extends ConsumerWidget {
  final JamState jam;
  const _NowPlayingControls({required this.jam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final c = ref.read(jamControllerProvider.notifier);
    final cur = jam.current;
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
      child: Column(children: [
        Text(
          cur?.title ?? 'Nothing playing',
          style: t.title3,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (cur != null) Text(cur.artist, style: t.subheadline, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: Space.sm),
        if (jam.youAreHost)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            button(NaviGlyph.previous, 'Previous', c.previous),
            button(jam.playing ? NaviGlyph.pause : NaviGlyph.play, jam.playing ? 'Pause' : 'Play', c.togglePlay,
                size: 40),
            button(NaviGlyph.next, 'Next', c.next),
          ])
        else
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              jam.playing ? '${jam.host} controls playback' : 'Waiting for ${jam.host} to press play',
              style: t.footnote,
            ),
          ),
      ]),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  final JamState jam;
  final int index;
  const _QueueRow({required this.jam, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final item = jam.queue[index];
    final me = ref.read(settingsProvider).username.toLowerCase();
    final current = index == jam.index;
    final canRemove = jam.youAreHost || item.addedBy.toLowerCase() == me;
    final svc = ref.read(subsonicServiceProvider);
    final c = ref.read(jamControllerProvider.notifier);
    return CupertinoClickable(
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
      semanticLabel: '${item.title}, ${item.artist}, added by ${item.addedBy}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xs + 2),
        child: Row(children: [
          CoverArt(url: svc.getCoverArtUrl(item.coverArt), size: 46, radius: Radii.thumb),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                item.title,
                style: t.body.copyWith(color: current ? t.accent : t.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                item.artist.isEmpty ? 'Added by ${item.addedBy}' : '${item.artist} · added by ${item.addedBy}',
                style: t.footnote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
        ]),
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
      SocialButton(
        label: 'Leave Jam',
        quiet: true,
        destructive: !jam.youAreHost,
        busy: busy,
        onPressed: () async {
          await c.leave();
          if (context.mounted) showToast(context, 'You left the Jam');
        },
      ),
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
