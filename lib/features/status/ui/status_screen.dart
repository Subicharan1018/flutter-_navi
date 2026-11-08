import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../logic/status_model.dart';
import '../logic/status_providers.dart';

/// Settings > About > Connection & status: every service the app leans on,
/// checked when the page opens and again on request. Phone and Windows share
/// this page; [GroupedSection] switches to flat desktop rows by itself.
class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final text = buildDiagnostics(
      rows: ref.read(statusControllerProvider),
      appVersion: ref.read(statusAppVersionProvider).asData?.value ?? 'unknown',
      platform: statusPlatform(),
      now: ref.read(statusClockProvider)(),
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showToast(context, 'Diagnostics copied');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final rows = ref.watch(statusControllerProvider);
    final version = ref.watch(statusAppVersionProvider).asData?.value ?? '…';
    final now = ref.read(statusClockProvider)();
    final ctl = ref.read(statusControllerProvider.notifier);
    final checking = rows.any((r) => r.busy);

    return LargeTitlePage(
      title: 'Connection & status',
      clearPlayer: false,
      onRefresh: ctl.refreshAll,
      slivers: [
        SliverList.list(children: [
          GroupedSection(
            header: 'Services',
            footer: 'Checked when this page opens, and when you refresh or retry. Nothing runs in the background.',
            children: [
              for (final r in rows)
                GroupedRow(
                  key: ValueKey('status-${r.id}'),
                  title: r.title,
                  subtitle: [
                    if (r.detail.isNotEmpty) r.detail,
                    'Checked ${formatAgo(r.checkedAt, now)}',
                  ].join('\n'),
                  value: r.level.label,
                  trailing: CupertinoButton(
                    key: ValueKey('retry-${r.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    minimumSize: const Size(44, 36),
                    onPressed: r.busy ? null : () => ctl.retry(r.id),
                    child: Text('Retry', style: t.body.copyWith(color: r.busy ? t.textMuted : t.accent)),
                  ),
                ),
            ],
          ),
          GroupedSection(
            header: 'This app',
            children: [
              GroupedRow(title: 'Version', value: version),
              GroupedRow(
                key: const ValueKey('refresh-all'),
                title: checking ? 'Checking…' : 'Check everything again',
                icon: NaviGlyph.signal,
                onTap: checking ? null : ctl.refreshAll,
                showChevron: false,
              ),
              GroupedRow(
                key: const ValueKey('copy-diagnostics'),
                title: 'Copy diagnostics',
                subtitle: 'A report for support. Passwords and tokens are never included.',
                icon: NaviGlyph.doc,
                onTap: () => _copy(context, ref),
                showChevron: false,
              ),
            ],
          ),
        ]),
      ],
    );
  }
}
