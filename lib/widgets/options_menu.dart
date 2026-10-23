import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/album.dart';
import '../models/composer.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../providers/catalog_provider.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/album_details_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/composer_screen.dart';
import 'add_to_playlist_dialog.dart';
import 'app_scaffold.dart' show navigateInApp;
import 'desktop_dialogs.dart';
import 'ui/action_sheet.dart';

/// Opens the song context menu. Pass [playlistId] + [onRemoveFromPlaylist]
/// when the song is shown inside a playlist.
Future<void> showSongActions(
  BuildContext context,
  Song song, {
  String? playlistId,
  VoidCallback? onRemoveFromPlaylist,
}) =>
    showPlatformSheet(
      context: context,
      builder: (_) => OptionsMenu(
        song: song,
        playlistId: playlistId,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
      ),
    );

/// The song context menu: queue actions, library actions, Smart Shuffle
/// feedback. Every action confirms with a short toast.
class OptionsMenu extends ConsumerWidget {
  final Song song;
  final String? playlistId;
  final VoidCallback? onRemoveFromPlaylist;

  const OptionsMenu({
    super.key,
    required this.song,
    this.playlistId,
    this.onRemoveFromPlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider.notifier);
    final service = ref.read(subsonicServiceProvider);
    // Actions run after the sheet closes, so they act through the page's
    // context (captured here), not the sheet's.
    final page = Navigator.of(context).context;
    final starred = ref.watch(playerProvider.select((s) => s.starredIds.contains(song.id)));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: song.title,
          subtitle: song.album.isEmpty ? song.artist : '${song.artist} — ${song.album}',          detail: catalogDetailLine(ref.watch(catalogSongProvider(song.id)), song),
          artUrl: service.getCoverArtUrl(song.coverArt),
        ),
        _CreditRows(song: song, page: page),
        SheetGroup(children: [
          SheetAction(
            label: 'Play Next',
            icon: CupertinoIcons.text_insert,
            onTap: () {
              player.insertNext(song);
              showToast(page, 'Playing next');
            },
          ),
          SheetAction(
            label: 'Play Last',
            icon: CupertinoIcons.text_append,
            onTap: () {
              player.addToQueue(song);
              showToast(page, 'Added to the end of the queue');
            },
          ),
        ]),
        SheetGroup(children: [
          SheetAction(
            label: 'Add to Playlist…',
            icon: CupertinoIcons.text_badge_plus,
            onTap: () => showAddToPlaylist(page, song),
          ),
          SheetAction(
            label: starred ? 'Remove from Favorites' : 'Favorite',
            icon: starred ? CupertinoIcons.star_slash : CupertinoIcons.star,
            onTap: () {
              player.toggleStar(song.id);
              showToast(page, starred ? 'Removed from Favorites' : 'Added to Favorites');
            },
          ),
          _DownloadAction(song: song, toastContext: page),
          if (song.albumId.isNotEmpty)
            SheetAction(
              label: 'Go to Album',
              icon: CupertinoIcons.music_albums,
              onTap: () => navigateInApp(
                page,
                AlbumDetailsScreen(
                  album: Album.fromJson({
                    'id': song.albumId,
                    'name': song.album,
                    'artist': song.artist,
                    'artistId': song.artistId,
                    'coverArt': song.coverArt,
                  }),
                ),
              ),
            ),
          if (song.artistId.isNotEmpty)
            SheetAction(
              label: 'Go to Artist',
              icon: CupertinoIcons.music_mic,
              onTap: () => navigateInApp(page, ArtistScreen(artistId: song.artistId, name: song.artist)),
            ),
        ]),
        SheetGroup(children: [
          SheetAction(
            label: 'Suggest More Like This',
            icon: CupertinoIcons.hand_thumbsup,
            onTap: () {
              player.handleSuggestAction(song, true);
              showToast(page, 'Smart Shuffle will play this more often');
            },
          ),
          SheetAction(
            label: 'Suggest Less Like This',
            icon: CupertinoIcons.hand_thumbsdown,
            onTap: () {
              player.handleSuggestAction(song, false);
              showToast(page, 'Smart Shuffle will play this less often');
            },
          ),
        ]),
        if (playlistId != null && onRemoveFromPlaylist != null)
          SheetGroup(children: [
            SheetAction(
              label: 'Remove from Playlist',
              icon: CupertinoIcons.minus_circle,
              destructive: true,
              onTap: onRemoveFromPlaylist,
            ),
          ]),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}

/// Composer (one row each, opening their page), lyricist and film as labelled
/// rows under the sheet header. Nothing is drawn for a song with no credits.
class _CreditRows extends ConsumerWidget {
  final Song song;
  final BuildContext page;
  const _CreditRows({required this.song, required this.page});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(catalogSongProvider(song.id));
    final composerNames = splitComposers(song.composer.isNotEmpty ? song.composer : (meta?.composer ?? ''));
    final lyricist = meta?.lyricist?.trim() ?? '';
    // The header already names the album; the film is only news when it differs.
    final rawFilm = meta?.film?.trim() ?? '';
    final film = rawFilm.toLowerCase() == song.album.trim().toLowerCase() ? '' : rawFilm;
    if (composerNames.isEmpty && lyricist.isEmpty && film.isEmpty) return const SizedBox.shrink();
    return SheetGroup(children: [
      for (final name in composerNames)
        SheetInfoRow(
          label: 'Composer',
          value: name,
          onTap: () => navigateInApp(page, ComposerScreen(composerKey: nameKey(name), name: name)),
        ),
      if (lyricist.isNotEmpty) SheetInfoRow(label: 'Lyricist', value: lyricist),
      if (film.isNotEmpty) SheetInfoRow(label: 'Film', value: film),
    ]);
  }
}

/// Download row that tracks the song's live download state; stays open so
/// progress is visible.
class _DownloadAction extends ConsumerWidget {
  final Song song;
  final BuildContext toastContext;
  const _DownloadAction({required this.song, required this.toastContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final dl = ref.watch(downloadStateProvider.select((m) => m[song.id]));
    final notifier = ref.read(downloadStateProvider.notifier);
    final status = dl?.status ?? SongDownloadStatus.notDownloaded;

    return switch (status) {
      SongDownloadStatus.notDownloaded => SheetAction(
          label: 'Download',
          icon: CupertinoIcons.arrow_down_circle,
          keepOpen: true,
          onTap: () => notifier.downloadSong(song),
        ),
      SongDownloadStatus.queued => const SheetAction(
          label: 'Waiting to download…',
          trailing: CupertinoActivityIndicator(radius: 9),
        ),
      SongDownloadStatus.downloading => SheetAction(
          label: 'Downloading',
          detail: '${((dl?.progress ?? 0) * 100).round()}%',
          trailing: SizedBox(
            width: 21,
            height: 21,
            child: CircularProgressIndicator(
              value: (dl?.progress ?? 0) > 0 ? dl!.progress : null,
              strokeWidth: 2.5,
              color: t.accent,
              backgroundColor: t.fill,
            ),
          ),
        ),
      SongDownloadStatus.downloaded => SheetAction(
          label: 'Remove Download',
          icon: CupertinoIcons.trash,
          destructive: true,
          onTap: () {
            notifier.deleteSong(song.id);
            showToast(toastContext, 'Download removed');
          },
        ),
      SongDownloadStatus.failed => SheetAction(
          label: 'Download Failed',
          detail: 'Tap to try again',
          icon: CupertinoIcons.exclamationmark_circle,
          keepOpen: true,
          onTap: () => notifier.downloadSong(song),
        ),
    };
  }
}
