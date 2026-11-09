import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_notifier.dart' show AppNotifier;
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../data/social_api.dart';
import '../logic/people_providers.dart';
import '../logic/social_providers.dart';

/// Quiet-hours choices: from, to (minutes after midnight) and how it reads.
const quietHourChoices = <(String, int?, int?)>[
  ('Off', null, null),
  ('10 pm to 7 am', 22 * 60, 7 * 60),
  ('11 pm to 8 am', 23 * 60, 8 * 60),
  ('Midnight to 9 am', 0, 9 * 60),
];

String quietHoursLabel(int? from, int? to) {
  for (final c in quietHourChoices) {
    if (c.$2 == from && c.$3 == to) return c.$1;
  }
  return 'Custom';
}

/// Settings → Social: the privacy switches (they save at once) and friend
/// alerts (saved on this device).
class SocialSettingsSection extends ConsumerWidget {
  const SocialSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(socialSettingsProvider).asData?.value;
    final loaded = s != null;
    final alerts = ref.watch(friendAlertSettingsProvider);
    final alertsCtl = ref.read(friendAlertSettingsProvider.notifier);

    Future<void> save({bool? enabled, bool? hideActivity, bool? hideListening}) async {
      try {
        await ref
            .read(socialSettingsProvider.notifier)
            .save(enabled: enabled, hideActivity: hideActivity, hideListening: hideListening);
      } on SocialException catch (e) {
        if (context.mounted) showToast(context, e.message);
      }
    }

    return GroupedSection(
      header: 'Social',
      footer: loaded && s.enabled
          ? 'Friends who also turned this on can see what you’re playing, invite you to playlists and Blend with you. '
              'Friend alerts are checked about once a minute while NaviVibe is running.'
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
        if (loaded && s.enabled)
          GroupedSwitchRow(
            title: 'Hide What I’m Listening To',
            subtitle: 'You stay in People as “Not sharing”: no song, no room, no alerts about you.',
            value: s.hideListening,
            onChanged: (v) => save(hideListening: v),
          ),
        if (loaded && s.enabled)
          GroupedSwitchRow(
            title: 'Friend Alerts',
            subtitle: 'A notification when a friend starts listening or reacts to your song. At most one start alert per friend every 30 minutes.',
            value: alerts.enabled,
            onChanged: (v) {
              alertsCtl.setEnabled(v);
              if (v) AppNotifier.prime(); // asks for the Android notification permission while the app is on screen
            },
          ),
        if (loaded && s.enabled && alerts.enabled)
          GroupedRow(
            title: 'Quiet Hours',
            value: quietHoursLabel(alerts.quietFromMin, alerts.quietToMin),
            onTap: () => showPlatformSheet<void>(
              context: context,
              title: 'Quiet hours',
              builder: (_) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SheetGroup(children: [
                  for (final c in quietHourChoices)
                    SheetAction(label: c.$1, onTap: () => alertsCtl.setQuietHours(c.$2, c.$3)),
                ]),
              ),
            ),
          ),
        if (loaded && s.enabled && alerts.enabled && alerts.muted.isNotEmpty)
          GroupedRow(
            title: 'Muted Friends',
            value: alerts.muted.length == 1 ? alerts.muted.first : '${alerts.muted.length} friends',
            showChevron: false,
          ),
      ],
    );
  }
}
