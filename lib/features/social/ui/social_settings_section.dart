import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../data/social_api.dart';
import '../logic/social_providers.dart';

/// Settings → Social: the two privacy switches. Both save at once.
class SocialSettingsSection extends ConsumerWidget {
  const SocialSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(socialSettingsProvider).asData?.value;
    final loaded = s != null;

    Future<void> save({bool? enabled, bool? hideActivity}) async {
      try {
        await ref.read(socialSettingsProvider.notifier).save(enabled: enabled, hideActivity: hideActivity);
      } on SocialException catch (e) {
        if (context.mounted) showToast(context, e.message);
      }
    }

    return GroupedSection(
      header: 'Social',
      footer: loaded && s.enabled
          ? 'Friends who also turned this on can see what you’re playing, invite you to playlists and Blend with you.'
          : 'Off by default. Turn it on to see friend activity, share playlists and get Blends. Jam works without it.',
      children: [
        GroupedSwitchRow(
          title: 'Friends & Sharing',
          subtitle: 'Friend activity, shared playlists and Blends.',
          value: loaded && s.enabled,
          onChanged: loaded ? (v) => save(enabled: v) : (_) {},
        ),
        if (loaded && s.enabled)
          GroupedSwitchRow(
            title: 'Hide My Activity',
            subtitle: 'You still see friends, but they don’t see what you play.',
            value: s.hideActivity,
            onChanged: (v) => save(hideActivity: v),
          ),
      ],
    );
  }
}
