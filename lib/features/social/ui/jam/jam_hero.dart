import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion.dart';
import '../../../../core/theme.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../widgets/app_scaffold.dart' show AppTab, selectAppTab;
import '../../../../widgets/art/generated_cover.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/cover_art.dart';
import '../../logic/jam_controller.dart';
import '../../logic/social_providers.dart';
import 'room_ring.dart';

/// Jam's place on Home. Live: the room, with who is in it and what is playing.
/// Otherwise: the way in. Invitations waiting show as a line under it.
class JamHero extends ConsumerStatefulWidget {
  const JamHero({super.key});

  @override
  ConsumerState<JamHero> createState() => _JamHeroState();
}

class _JamHeroState extends ConsumerState<JamHero> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(jamControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final jam = ref.watch(jamControllerProvider.select((s) => s.jam));
    final invites = ref.watch(invitationCountProvider);
    final t = ThemeTokens.of(context);
    final svc = ref.read(subsonicServiceProvider);
    final cur = jam?.current;

    final title = jam == null ? 'Start a Jam' : 'Jam is live';
    final detail = jam == null
        ? 'Listen together, in sync. Share a code and everyone hears the same song.'
        : (cur == null
            ? '${jam.members.length} in the room · add the first song'
            : '${cur.title} · ${jam.members.length} in the room');

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
      child: Column(children: [
        CupertinoClickable(
          onTap: () => selectAppTab(AppTab.jam),
          scaleFactor: 0.98,
          semanticLabel: '$title. $detail',
          child: Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              color: t.fill,
              borderRadius: BorderRadius.circular(Radii.hero + 8),
              border: Border.all(color: t.outline, width: 0.5),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (jam != null)
                    Row(children: [
                      _LiveDot(motion: context.motionFull),
                      const SizedBox(width: Space.sm),
                      Text(jam.code, style: t.footnote.copyWith(color: t.textPrimary, letterSpacing: 2)),
                    ]),
                  if (jam != null) const SizedBox(height: Space.xs),
                  Text(title, style: t.title2),
                  const SizedBox(height: Space.xs),
                  Text(detail, style: t.subheadline, maxLines: 3, overflow: TextOverflow.ellipsis),
                  if (jam == null) ...[
                    const SizedBox(height: Space.md),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
                      decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(Radii.capsule)),
                      child: Text('Start', style: t.headline.copyWith(color: t.onAccent)),
                    ),
                  ],
                ]),
              ),
              const SizedBox(width: Space.md),
              RoomRing(
                members: jam?.members ?? const [],
                size: 124,
                playing: jam?.playing ?? false,
                minSeats: 5,
                center: cur != null && cur.coverArt.isNotEmpty
                    ? CoverArt(url: svc.getCoverArtUrl(cur.coverArt), size: 70, radius: 0)
                    : GeneratedCover(name: jam == null ? 'jam hero' : 'jam ${jam.code}'),
              ),
            ]),
          ),
        ),
        if (invites > 0)
          CupertinoClickable(
            onTap: () => selectAppTab(AppTab.jam),
            scaleFactor: 0.99,
            semanticLabel: invites == 1 ? '1 invitation waiting' : '$invites invitations waiting',
            child: Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Row(children: [
                NaviIcon(NaviGlyph.group, size: 20, color: t.textPrimary),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    invites == 1 ? '1 invitation waiting' : '$invites invitations waiting',
                    style: t.callout,
                  ),
                ),
                NaviIcon(NaviGlyph.chevron, size: 16, color: t.textMuted),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _LiveDot extends StatefulWidget {
  final bool motion;
  const _LiveDot({required this.motion});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.motion) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: t.textPrimary.withValues(alpha: 1 - _c.value * 0.6)),
      ),
    );
  }
}
