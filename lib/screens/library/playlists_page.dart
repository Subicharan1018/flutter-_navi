import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/playlist.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/format.dart';
import '../../utils/playlist_actions.dart';
import '../../widgets/app_scaffold.dart' show navigateInApp;
import '../../widgets/collection_actions.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/create_playlist_dialog.dart';
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/media.dart';
import '../../widgets/ui/states.dart';
import '../edit_playlist_screen.dart';
import '../favorites_screen.dart';
import '../playlist_details_screen.dart';

/// Playlists: "New Playlist…" first, then Favorites, then the user's own.
class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final playlists = ref.watch(sortedPlaylistsProvider);
    final svc = ref.read(subsonicServiceProvider);

    Widget glyphTile(IconData icon) => Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: t.bgSurface, borderRadius: BorderRadius.circular(Radii.cover)),
          child: Icon(icon, color: t.accent, size: 26),
        );

    return LargeTitlePage(
      title: 'Playlists',
      onRefresh: () async => ref.invalidate(playlistsProvider),
      slivers: [
        SliverList.list(children: [
          CollectionRow(
            title: 'New Playlist…',
            titleColor: t.accent,
            leading: glyphTile(CupertinoIcons.add),
            showChevron: false,
            onTap: () => showDialog(context: context, builder: (_) => const CreatePlaylistDialog()),
          ),
          CollectionRow(
            title: 'Favorites',
            subtitle: 'Songs you starred',
            leading: glyphTile(CupertinoIcons.star_fill),
            onTap: () => navigateInApp(context, const FavoritesScreen()),
          ),
        ]),
        ...playlists.when(
          loading: () => const [SliverToBoxAdapter(child: LoadingState())],
          error: (_, _) => [
            SliverToBoxAdapter(
              child: MessageState.error(title: 'Couldn’t load playlists', onRetry: () => ref.invalidate(playlistsProvider)),
            ),
          ],
          data: (list) => [
            SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final p = list[i];
                final art = (p.coverArt ?? '').isEmpty ? null : svc.getCoverArtUrl(p.coverArt);
                return CollectionRow(
                  title: p.name,
                  subtitle: songCount(p.songCount),
                  leading: CoverArt(url: art, size: 56, radius: Radii.cover, placeholderIcon: CupertinoIcons.music_note_list),
                  onTap: () => navigateInApp(context, PlaylistDetailsScreen(playlist: p)),
                  onLongPress: () => _actions(context, ref, p, art),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  void _actions(BuildContext context, WidgetRef ref, Playlist p, String? art) {
    showCollectionActions(
      context,
      title: p.name,
      subtitle: songCount(p.songCount),
      artUrl: art,
      loadSongs: () => ref.read(subsonicServiceProvider).getPlaylistSongs(p.id),
      onEdit: () => navigateInApp(context, EditPlaylistScreen(playlist: p)),
      onDelete: () => deletePlaylistWithConfirm(context, ref, p),
    );
  }
}
