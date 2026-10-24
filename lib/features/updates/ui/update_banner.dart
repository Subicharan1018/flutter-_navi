import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/ui/ion.dart';
import '../logic/update_providers.dart';
import 'updates_screen.dart';

/// A dismissible line on Home: "Update available · 3.2 MB". Shows nothing
/// while updates are off, the check is running or failed, or this build was
/// already dismissed.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(updateCheckProvider).asData?.value;
    final dismissed = ref.watch(dismissedUpdateProvider);
    if (check == null || !check.available || check.manifest.build <= dismissed) {
      return const SizedBox.shrink();
    }
    final t = ThemeTokens.of(context);
    final size = updateDownloadSize(check);
    final notes = check.manifest.notes.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
      child: Row(children: [
        Expanded(
          child: CupertinoClickable(
            onTap: () => navigateInApp(context, const UpdatesScreen()),
            scaleFactor: 0.99,
            semanticLabel: 'Update available. Open updates.',
            child: Row(children: [
              IonIcon(Ion.download, size: 22, color: t.accent),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    size == null ? 'Update available' : 'Update available, ${formatUpdateSize(size)}',
                    style: t.headline,
                  ),
                  Text(
                    notes.isEmpty ? 'NaviVibe ${check.manifest.version}' : notes.replaceFirst(RegExp(r'^[-*]\s*'), ''),
                    style: t.footnote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ]),
          ),
        ),
        CupertinoClickable(
          onTap: () => ref.read(dismissedUpdateProvider.notifier).dismiss(check.manifest.build),
          semanticLabel: 'Dismiss',
          child: Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: IonIcon(Ion.remove, size: 20, color: t.textSecondary),
          ),
        ),
      ]),
    );
  }
}
