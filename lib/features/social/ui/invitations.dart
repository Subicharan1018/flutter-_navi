import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/media.dart';
import '../data/social_models.dart';
import '../logic/jam_controller.dart';
import '../logic/social_providers.dart';
import '../logic/social_rules.dart';
import 'blend_screens.dart';
import 'collab_screens.dart';
import 'social_widgets.dart';

/// Jam invites, shared-playlist invites and Blend requests, on top of the
/// Sessions page where they can't be missed. Nothing renders when there are none.
class InvitationsSection extends ConsumerWidget {
  const InvitationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jams = latestJamInvites(ref.watch(jamInvitesProvider).asData?.value ?? const []);
    final collabs = [
      for (final p in ref.watch(collabListProvider).asData?.value ?? const []) if (p.invited) p,
    ];
    final blends = [
      for (final b in ref.watch(blendListProvider).asData?.value ?? const []) if (b.pending && b.incoming) b,
    ];
    if (jams.isEmpty && collabs.isEmpty && blends.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader(title: 'Invitations'),
      for (final i in jams) JamInviteRow(invite: i),
      for (final p in collabs) CollabRow(playlist: p),
      for (final b in blends) BlendRow(blend: b),
    ]);
  }
}

/// "maya invited you to a Jam" with Decline and a one-tap Join.
class JamInviteRow extends ConsumerStatefulWidget {
  final JamInvite invite;
  const JamInviteRow({super.key, required this.invite});

  @override
  ConsumerState<JamInviteRow> createState() => _JamInviteRowState();
}

class _JamInviteRowState extends ConsumerState<JamInviteRow> {
  bool _busy = false;

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(jamControllerProvider.notifier).join(widget.invite.code);
    ref.invalidate(jamInvitesProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) showToast(context, ref.read(jamControllerProvider).notice ?? 'Couldn’t join that room.');
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(socialApiProvider).jamInviteDecline(widget.invite.code);
    } catch (_) {
      // The invite expires on its own; the row just goes away on the next read.
    }
    ref.invalidate(jamInvitesProvider);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final i = widget.invite;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
      child: Row(children: [
        PersonAvatar(i.from, size: 52),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(jamInviteLine(i), style: t.headline, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(jamInviteDetail(i), style: t.footnote),
          ]),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          minimumSize: const Size(44, 44),
          onPressed: _busy ? null : _decline,
          child: Text('Decline', style: t.body.copyWith(color: t.textSecondary)),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          minimumSize: const Size(44, 44),
          onPressed: _busy ? null : _join,
          child: Text('Join', style: t.headline.copyWith(color: t.accent)),
        ),
      ]),
    );
  }
}
