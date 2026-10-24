import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../logic/jam_controller.dart';
import '../logic/social_providers.dart';
import 'blend_screens.dart';
import 'collab_screens.dart';
import 'friend_activity.dart';
import 'jam_screen.dart';
import 'social_widgets.dart';

/// Everything shared with other people on the server: Jam, friend activity,
/// shared playlists and Blends. Friend activity and Blends stay hidden until
/// the person turns social features on.
class SocialScreen extends ConsumerWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(socialSettingsProvider);
    final enabled = ref.watch(socialEnabledProvider);
    final jam = ref.watch(jamControllerProvider.select((s) => s.jam));
    final t = ThemeTokens.of(context);

    return LargeTitlePage(
      title: 'Social',
      onRefresh: () async {
        ref.invalidate(socialSettingsProvider);
        ref.invalidate(friendFeedProvider);
        ref.invalidate(collabListProvider);
        ref.invalidate(blendListProvider);
      },
      slivers: [
        SliverToBoxAdapter(
          child: CollectionRow(
            title: jam == null ? 'Jam' : 'Jam · ${jam.code}',
            subtitle: jam == null
                ? 'Listen together, in sync'
                : '${jam.members.length} listening${jam.youAreHost ? ' · you’re the host' : ''}',
            leading: SizedBox(width: 30, child: NaviIcon(NaviGlyph.group, size: 26, color: t.accent)),
            showSeparator: false,
            onTap: () => navigateInApp(context, const JamScreen()),
          ),
        ),
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
