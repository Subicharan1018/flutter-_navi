import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../../data_queue/logic/data_queue_providers.dart' show dataQueueAdminProvider;
import '../../data_queue/ui/data_queue_screen.dart';
import '../../history_import/ui/history_import_screen.dart';
import '../../spotify_import/ui/spotify_import_screen.dart';
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
        GroupedRow(
          title: 'Import Listening History',
          subtitle: 'From ListenBrainz or Last.fm',
          icon: NaviGlyph.clock,
          onTap: () => navigateInApp(context, const HistoryImportScreen(), title: 'Listening History'),
        ),
        GroupedRow(
          title: 'Import Spotify History',
          subtitle: 'From your Extended Streaming History',
          icon: NaviGlyph.headphones,
          onTap: () => navigateInApp(context, const SpotifyImportScreen(), title: 'Spotify History'),
        ),
        // Admin only: the hidden weekly queue of songs that still need Spotify's audio features.
        if (ref.watch(dataQueueAdminProvider))
          GroupedRow(
            title: 'Data Queue',
            subtitle: 'Weekly batch for Spotify’s audio features',
            icon: NaviGlyph.stack,
            onTap: () => navigateInApp(context, const DataQueueScreen(), title: 'Data queue'),
          ),
      ],
    );
  }
}
