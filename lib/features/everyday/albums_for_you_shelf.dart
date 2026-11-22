import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/pins_provider.dart';
import '../../providers/settings_provider.dart' show subsonicServiceProvider;
import '../../screens/album_details_screen.dart';
import '../../utils/queue_actions.dart' show playCollection;
import '../../widgets/app_scaffold.dart' show navigateInApp;
import '../../widgets/art/navi_icons.dart';
import '../../widgets/collection_actions.dart';
import '../../widgets/ui/action_sheet.dart' show SheetAction;
import '../../widgets/ui/media.dart';
import 'album_picks.dart';
import 'album_picks_providers.dart';

/// Home shelf (R10): albums where you love a song or two and haven't heard
/// the rest. Draws nothing until there is something to offer.
class AlbumsForYouShelf extends ConsumerWidget {
  const AlbumsForYouShelf({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(albumsForYouProvider).asData?.value ?? const <AlbumPick>[];
    if (picks.isEmpty) return const SizedBox.shrink();
    final service = ref.read(subsonicServiceProvider);
    return MediaShelf(
      title: 'Albums for You',
      cardSize: ArtSize.of(context).tile,
      itemCount: picks.length,
      itemBuilder: (context, i) {
        final p = picks[i];
        final art = p.album.coverArt.isEmpty ? null : service.getCoverArtUrl(p.album.coverArt);
        return MediaCard(
          key: ValueKey('afy_${p.album.id}'),
          title: p.album.name,
          subtitle: '${p.unheard} to discover',
          artUrl: art,
          size: ArtSize.of(context).tile,
          placeholderIcon: NaviGlyph.library,
          onTap: () => navigateInApp(context, AlbumDetailsScreen(album: p.album)),
          onPlay: () => playCollection(context, ref, () => service.getAlbum(p.album.id), p.album.name),
          onLongPress: () => showCollectionActions(
            context,
            title: p.album.name,
            subtitle: p.reason,
            artUrl: art,
            placeholderIcon: NaviGlyph.library,
            loadSongs: () => service.getAlbum(p.album.id),
            pin: Pin.album(p.album),
            extraActions: [
              _NotForMe(albumId: p.album.id),
            ],
          ),
        );
      },
    );
  }
}

class _NotForMe extends ConsumerWidget {
  const _NotForMe({required this.albumId});
  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SheetAction(
    label: 'Not for Me',
    icon: NaviGlyph.thumbDown,
    onTap: () => ref.read(hiddenAlbumsProvider.notifier).hide(albumId),
  );
}
