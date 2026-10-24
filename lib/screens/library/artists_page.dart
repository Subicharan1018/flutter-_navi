import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/artist.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/app_scaffold.dart' show navigateInApp;
import '../../widgets/cover_art.dart';
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/media.dart';
import '../../widgets/ui/states.dart';
import '../artist_screen.dart';

/// Every artist on the server, alphabetical.
final libraryArtistsProvider = FutureProvider.autoDispose<List<Artist>>((ref) async {
  final raw = await ref.watch(subsonicServiceProvider).getArtists();
  return [for (final m in raw) Artist.fromJson(m)]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// Library › Artists: round portraits in a list, as in Apple Music.
class ArtistsPage extends ConsumerWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(libraryArtistsProvider);
    final svc = ref.read(subsonicServiceProvider);
    return LargeTitlePage(
      title: 'Artists',
      onRefresh: () async => ref.invalidate(libraryArtistsProvider),
      slivers: artists.when(
        loading: () => const [SliverFillRemaining(hasScrollBody: false, child: LoadingState())],
        error: (_, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: MessageState.error(
              title: 'Couldn’t load artists',
              onRetry: () => ref.invalidate(libraryArtistsProvider),
            ),
          ),
        ],
        data: (list) => list.isEmpty
            ? const [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageState(
                    icon: CupertinoIcons.music_mic,
                    title: 'No artists yet',
                    message: 'Artists on your server appear here.',
                  ),
                ),
              ]
            : [
                SliverFixedExtentList(
                  itemExtent: 62,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final a = list[i];
                      return CollectionRow(
                        title: a.name,
                        subtitle: a.albumCount == 0 ? null : (a.albumCount == 1 ? '1 album' : '${a.albumCount} albums'),
                        leading: CoverArt(
                          url: svc.getCoverArtUrl(a.coverArtId),
                          size: 46,
                          circular: true,
                          placeholderIcon: CupertinoIcons.person_fill,
                        ),
                        showSeparator: i < list.length - 1,
                        onTap: () => navigateInApp(context, ArtistScreen(artistId: a.id, name: a.name)),
                      );
                    },
                    childCount: list.length,
                  ),
                ),
              ],
      ),
    );
  }
}
