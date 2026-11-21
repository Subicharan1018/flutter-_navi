import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../../online_fetch/data/online_fetch_api.dart' show OnlineFetchException;
import '../logic/weekly_providers.dart';
import 'weekly_exploration_screen.dart';

/// The weekly download limits to choose from. 0 keeps the list but downloads nothing.
const List<int> kWeeklyCapChoices = [0, 3, 5, 10, 15, 25];

String _capLabel(int n) => n == 0 ? 'None' : '$n songs';

/// Settings › Weekly Exploration. Shown only to accounts that may download. On/off and the weekly limit
/// live on the server (it does the downloading); "Wi-Fi only" is this device's.
class WeeklyExplorationSettings extends ConsumerWidget {
  const WeeklyExplorationSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(weeklyAvailableProvider)) return const SizedBox.shrink();
    final w = ref.watch(weeklyExplorationProvider).asData?.value;
    final c = ref.read(weeklyExplorationProvider.notifier);
    Future<void> run(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        if (context.mounted) {
          showToast(context, e is OnlineFetchException ? e.message : 'That didn’t work. Check your connection and try again.');
        }
      }
    }

    final enabled = w?.enabled ?? true;
    return GroupedSection(
      header: 'Weekly Exploration',
      footer: 'About twenty songs a week you haven’t heard, picked from what you play. Songs you keep download at night, '
          'up to the limit below. Songs you leave alone go after two weeks.',
      children: [
        GroupedSwitchRow(
          title: 'Weekly Exploration',
          icon: NaviGlyph.explore,
          value: enabled,
          onChanged: w == null ? (_) {} : (v) => run(() => c.setEnabled(v)),
        ),
        if (enabled && w != null) ...[
          GroupedRow(
            title: 'Downloads a Week',
            icon: NaviGlyph.downloadCircle,
            value: _capLabel(w.cap),
            onTap: () async {
              final choices = [for (final n in kWeeklyCapChoices) if (n <= w.maxCap) n];
              final v = await showChoiceSheet<int>(
                context,
                title: 'Downloads a Week',
                options: choices,
                selected: choices.contains(w.cap) ? w.cap : choices.last,
                label: _capLabel,
              );
              if (v != null) await run(() => c.setCap(v));
            },
          ),
          GroupedSwitchRow(
            title: 'Wi-Fi Only Previews',
            icon: NaviGlyph.wifi,
            value: ref.watch(weeklyWifiOnlyProvider),
            onChanged: ref.read(weeklyWifiOnlyProvider.notifier).set,
          ),
          GroupedRow(
            title: 'Open Weekly Exploration',
            icon: NaviGlyph.note,
            onTap: () => navigateInApp(context, const WeeklyExplorationScreen(), title: 'Weekly Exploration'),
          ),
        ],
      ],
    );
  }
}
