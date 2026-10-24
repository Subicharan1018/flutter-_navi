import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/download_state.dart';
import '../../../models/song.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/player_provider.dart';
import '../../../utils/format.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/queue_actions.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/song_tile.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/artwork_page.dart';
import '../../../widgets/ui/collection_hero.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../../../widgets/ui/swipe_actions.dart';
import '../data/smart_rules.dart';
import '../logic/smart_playlist_providers.dart';
import 'rule_editor_screen.dart';
import 'smart_actions.dart';
import 'smart_widgets.dart';

/// A smart playlist: its matches right now, with Play / Shuffle, Edit Rules
/// and Save as Playlist. The list is re-evaluated each time the page opens
/// (and when the rules change), so new plays and new songs show up.
class SmartPlaylistScreen extends ConsumerWidget {
  final String playlistId;
  const SmartPlaylistScreen({super.key, required this.playlistId});

  Future<void> _play(BuildContext context, WidgetRef ref, SmartPlaylist playlist, List<Song> songs,
      {Song? from, bool shuffle = false}) async {
    var playable = songs;
    // Offline, only downloaded songs can play.
    if (ref.read(isOfflineProvider)) {
      final dl = ref.read(downloadStateProvider);
      playable = songs.where((s) => dl[s.id]?.status == SongDownloadStatus.downloaded).toList();
    }
    if (playable.isEmpty) {
      showToast(context, 'None of these songs are downloaded yet');
      return;
    }
    final n = ref.read(playerProvider.notifier);
    if (shuffle) return n.playPlaylist(playable, shuffle: true, playlistName: playlist.name);
    final start = from == null ? 0 : playable.indexOf(from);
    await n.setQueue(playable, start < 0 ? 0 : start, playlistName: playlist.name, unshuffledSongs: songs);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(smartPlaylistsProvider.select((l) => l.where((p) => p.id == playlistId).firstOrNull));
    if (playlist == null) {
      // Deleted from the More menu: the page is on its way out.
      return const SizedBox.shrink();
    }
    final result = ref.watch(smartSongsProvider(playlistId));
    final songs = result.asData?.value ?? const <Song>[];
    final ids = {for (final s in songs) s.id};
    final playingThis = ref.watch(playerProvider.select((s) => s.isPlaying && s.currentSong != null && ids.contains(s.currentSong!.id)));
    final t = ThemeTokens.of(context);

    return ArtworkPage(
      paletteCoverId: null,
      art: (size) => SmartCover(id: playlist.id, size: size, radius: 0),
      title: playlist.name,
      subtitle: 'Smart Playlist',
      detail: result.hasValue ? '${songCount(songs.length)} · ${formatLongDuration(songs.fold(0, (n, s) => n + s.duration))}' : null,
      buttons: PlayShuffleButtons(
        playing: playingThis,
        onPlay: songs.isEmpty
            ? null
            : () => playingThis ? ref.read(playerProvider.notifier).player.pause() : _play(context, ref, playlist, songs),
        onShuffle: songs.isEmpty ? null : () => _play(context, ref, playlist, songs, shuffle: true),
        trailing: CollectionDownloadButton(songs: songs),
      ),
      actions: [
        BarCircleButton(
          icon: CupertinoIcons.slider_horizontal_3,
          label: 'Edit Rules',
          onTap: () => showSmartPlaylistEditor(context, playlist: playlist),
          child: NaviIcon(NaviGlyph.sliders, size: 18, color: t.textPrimary),
        ),
        BarCircleButton(
          icon: CupertinoIcons.ellipsis,
          label: 'More',
          onTap: () => showSmartPlaylistActions(context, playlist, onDeleted: () => Navigator.of(context).maybePop()),
          child: NaviIcon(NaviGlyph.more, size: 18, color: t.textPrimary),
        ),
      ],
      onRefresh: () async => ref.invalidate(smartFactsProvider),
      slivers: [
        if (result.isLoading && !result.hasValue)
          const SliverToBoxAdapter(child: TrackListSkeleton())
        else if (result.hasError && !result.hasValue)
          SliverToBoxAdapter(
            child: MessageState.error(
              title: 'Couldn’t read your library',
              onRetry: () => ref.invalidate(smartFactsProvider),
            ),
          )
        else if (songs.isEmpty)
          SliverToBoxAdapter(
            child: MessageState(
              icon: CupertinoIcons.slider_horizontal_3,
              title: 'No songs match yet',
              message: 'Loosen a rule, or wait until more songs fit.',
              actionLabel: 'Edit Rules',
              onAction: () => showSmartPlaylistEditor(context, playlist: playlist),
            ),
          )
        else
          SliverFixedExtentList(
            itemExtent: SongTile.extent,
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final song = songs[i];
                return SwipeActions.queue(
                  rowKey: ValueKey('smart_${song.id}_$i'),
                  context: context,
                  onPlayNext: () => queueSongs(context, ref, [song], next: true),
                  onPlayLast: () => queueSongs(context, ref, [song], next: false),
                  child: SongTile(
                    song: song,
                    showDuration: PlatformUtils.isDesktop,
                    onTap: () => _play(context, ref, playlist, songs, from: song),
                  ),
                );
              },
              childCount: songs.length,
            ),
          ),
      ],
    );
  }
}
