import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/ui/action_sheet.dart';
import '../../../../widgets/ui/large_title_page.dart';
import '../../../../widgets/ui/states.dart';
import '../../logic/jam_controller.dart';
import '../../logic/social_providers.dart';
import '../blend_screens.dart';
import '../collab_screens.dart';
import '../friend_activity.dart';
import '../invitations.dart';
import '../social_widgets.dart';
import 'jam_room.dart';

/// The Jam tab. A live room when you are in one, otherwise the empty room with
/// a way in. Below it, the people side of NaviVibe: invitations, what friends
/// are playing, shared playlists and Blends (hidden until social is on).
class JamTabScreen extends ConsumerStatefulWidget {
  const JamTabScreen({super.key});

  @override
  ConsumerState<JamTabScreen> createState() => _JamTabScreenState();
}

class _JamTabScreenState extends ConsumerState<JamTabScreen> {
  @override
  void initState() {
    super.initState();
    // Picks up a Jam this account is already in (app restarted, new phone).
    Future.microtask(() {
      if (mounted) ref.read(jamControllerProvider.notifier).restore();
    });
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
    final settings = ref.watch(socialSettingsProvider);
    final enabled = ref.watch(socialEnabledProvider);

    return LargeTitlePage(
      title: 'Jam',
      onRefresh: () async {
        ref.invalidate(socialSettingsProvider);
        ref.invalidate(friendFeedProvider);
        ref.invalidate(collabListProvider);
        ref.invalidate(blendListProvider);
      },
      slivers: [
        if (ui.jam == null)
          SliverToBoxAdapter(child: JamStage(busy: ui.busy))
        else
          ...jamRoomSlivers(context, ref, ui),
        if (settings.isLoading && !settings.hasValue)
          const SliverToBoxAdapter(child: LoadingState())
        else if (settings.hasError && !settings.hasValue)
          SliverToBoxAdapter(
            child: SocialNote(
              glyph: NaviGlyph.group,
              title: 'Couldn’t reach the server',
              message: 'Check your connection, then try again.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(socialSettingsProvider),
            ),
          )
        else if (!enabled)
          SliverToBoxAdapter(child: _Intro())
        else ...[
          const SliverToBoxAdapter(child: InvitationsSection()),
          const SliverToBoxAdapter(child: FriendActivitySection()),
          const SliverToBoxAdapter(child: CollabSection()),
          const SliverToBoxAdapter(child: BlendSection()),
          const SliverToBoxAdapter(
            child: SocialFootnote(
              'Only people who turned on social features can see you here. Hide your activity any time in Settings.',
            ),
          ),
        ],
      ],
    );
  }
}

class _Intro extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Intro> createState() => _IntroState();
}

class _IntroState extends ConsumerState<_Intro> {
  bool _busy = false;

  Future<void> _turnOn() async {
    setState(() => _busy = true);
    try {
      await ref.read(socialSettingsProvider.notifier).save(enabled: true);
    } catch (_) {
      if (mounted) showToast(context, 'Couldn’t turn on social features. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SocialNote(
        glyph: NaviGlyph.group,
        title: 'Share music with friends',
        message:
            'See what friends on this server are playing, make playlists together and get a Blend of your tastes. '
            'Nothing is shared until you turn this on, and only others who turned it on can see you.',
      ),
      SocialButton(label: 'Turn on', busy: _busy, onPressed: _turnOn),
    ]);
  }
}
