import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../../online_fetch/logic/online_fetch_providers.dart';
import 'exportify_import_screen.dart';

/// Settings › Import. Shown only to accounts that may fetch songs (the wishlist is fetched through
/// the same bot as Search online), and never in a public build.
class ExportifyImportSection extends ConsumerWidget {
  const ExportifyImportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(onlineFetchEnabledProvider).asData?.value != true) return const SizedBox.shrink();
    return GroupedSection(
      header: 'Import',
      footer: 'Bring a Spotify playlist over: what you have is matched, the rest is fetched a little at a time.',
      children: [
        GroupedRow(
          title: 'Import a Spotify Playlist',
          subtitle: 'From an Exportify CSV',
          icon: NaviGlyph.doc,
          onTap: () => navigateInApp(context, const ExportifyImportScreen(), title: 'Import a Playlist'),
        ),
      ],
    );
  }
}
