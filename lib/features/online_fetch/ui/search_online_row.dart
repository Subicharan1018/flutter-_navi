import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/ui/media.dart';
import '../logic/online_fetch_providers.dart';
import 'online_search_sheet.dart';

/// "Can't find it? Search online" under the library results. Renders nothing
/// unless the server allows this account to search online.
class SearchOnlineRow extends ConsumerWidget {
  final String query;
  const SearchOnlineRow({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(onlineFetchEnabledProvider).asData?.value ?? false;
    if (!enabled) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.lg),
      child: CollectionRow(
        title: 'Search online for “$query”',
        subtitle: 'Can’t find it? Add it to your library',
        leading: Icon(CupertinoIcons.globe, size: 22, color: t.accent),
        titleColor: t.accent,
        showSeparator: false,
        onTap: () => showOnlineSearch(context, query),
      ),
    );
  }
}
