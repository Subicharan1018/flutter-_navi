import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/download_provider.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/states.dart';
import '../logic/auto_download_policy.dart';
import '../logic/auto_download_providers.dart';

String _budgetLabel(int mb) => mb >= 1024 ? '${mb ~/ 1024} GB' : '$mb MB';

/// Settings > Downloads & Storage > Auto Downloads: keep the songs you keep
/// playing available offline, within a storage limit. The rule is spelled out
/// in docs/auto-download.md.
class AutoDownloadSection extends ConsumerWidget {
  const AutoDownloadSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(autoDownloadSettingsProvider);
    final n = ref.read(autoDownloadSettingsProvider.notifier);
    ref.watch(autoLedgerRevisionProvider); // the count below
    final kept = ref.read(autoLedgerProvider).entries.length;
    return GroupedSection(
      header: 'Auto Downloads',
      footer: 'Keeps songs you play again and again on this device, so they work without a connection. '
          'It waits for Wi-Fi and a charger, never touches songs you downloaded yourself, '
          'and removes the least played first when the limit is reached.',
      children: [
        GroupedSwitchRow(
          title: 'Download Songs I Replay',
          icon: NaviGlyph.downloadCircle,
          value: s.enabled,
          onChanged: n.setEnabled,
        ),
        if (s.enabled) ...[
          GroupedSwitchRow(
            title: 'Wi-Fi Only',
            icon: NaviGlyph.wifi,
            value: s.wifiOnly,
            onChanged: n.setWifiOnly,
          ),
          GroupedSwitchRow(
            title: 'Only While Charging',
            icon: NaviGlyph.signal,
            value: s.chargingOnly,
            onChanged: n.setChargingOnly,
          ),
          GroupedRow(
            title: 'Storage Limit',
            icon: NaviGlyph.signal,
            value: _budgetLabel(s.budgetMb),
            onTap: () async {
              final v = await showChoiceSheet<int>(
                context,
                title: 'Storage Limit',
                options: kAutoBudgetChoicesMb,
                selected: kAutoBudgetChoicesMb.contains(s.budgetMb) ? s.budgetMb : kAutoDefaultBudgetMb,
                label: _budgetLabel,
              );
              if (v != null) n.setBudgetMb(v);
            },
          ),
        ],
        if (kept > 0 || s.enabled)
          GroupedRow(
            title: 'What It Downloaded',
            icon: NaviGlyph.note,
            value: kept == 0 ? 'None yet' : '$kept',
            onTap: () => navigateInApp(context, const AutoDownloadedPage(), title: 'What It Downloaded'),
          ),
      ],
    );
  }
}

/// The songs the auto downloader keeps, with a way to remove each one or tell
/// it never to take that song again.
class AutoDownloadedPage extends ConsumerWidget {
  const AutoDownloadedPage({super.key});

  Future<void> _manage(BuildContext context, WidgetRef ref, AutoEntry e) async {
    final service = ref.read(autoDownloadServiceProvider);
    await showPlatformSheet<void>(
      context: context,
      title: e.title,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SheetGroup(children: [
          SheetAction(
            label: 'Remove',
            detail: 'Deletes the download. It may come back in a month if you keep playing it.',
            icon: NaviGlyph.trash,
            onTap: () => service.remove(e.songId),
          ),
          SheetAction(
            label: 'Not This',
            detail: 'Deletes the download and never downloads this song automatically again.',
            icon: NaviGlyph.trash,
            destructive: true,
            onTap: () => service.neverAgain(e.songId),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoLedgerRevisionProvider);
    final offline = ref.read(offlineServiceProvider);
    final entries = [...ref.read(autoLedgerProvider).entries.values]
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return LargeTitlePage(
      title: 'What It Downloaded',
      slivers: [
        if (entries.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: MessageState(
              icon: NaviGlyph.downloadCircle,
              art: EmptyArtKind.record,
              title: 'Nothing yet',
              message: 'Songs you play again and again show up here once they are downloaded.',
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: GroupedSection(
                children: [
                  for (final e in entries)
                    GroupedRow(
                      title: e.title,
                      subtitle: '${e.artist} · ${e.reason} · ${offline.formatSize(e.bytes)}',
                      onTap: () => _manage(context, ref, e),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
