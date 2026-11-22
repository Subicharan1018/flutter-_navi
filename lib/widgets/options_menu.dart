import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../features/everyday/dont_count.dart';
import '../features/everyday/play_stats_providers.dart';
import '../features/everyday/song_trim_providers.dart';
import '../features/everyday/song_trim_sheet.dart';
import '../features/moods/ui/not_this_mood_action.dart';
import '../features/share/share_sheet.dart';
import '../features/social/logic/jam_controller.dart';
import '../features/social/ui/collab_screens.dart' show showAddToCollab;
import '../features/social/ui/share_now_playing_action.dart' show runShareNowPlaying;
import '../features/taste/ui/never_recommend.dart';
import '../models/album.dart';
import '../models/composer.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../providers/catalog_provider.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../utils/queue_actions.dart' show addToUpNext;
import '../providers/settings_provider.dart';
import '../screens/album_details_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/composer_screen.dart';
import '../utils/platform_utils.dart';
import 'add_to_playlist_dialog.dart';
import 'app_scaffold.dart' show navigateInApp;
import 'desktop_dialogs.dart';
import 'art/navi_icons.dart';
import 'ui/action_sheet.dart';

/// Opens the song context menu. Pass [playlistId] + [onRemoveFromPlaylist]
/// when the song is shown inside a playlist, and [mood] when the list is a
/// mood list (it adds "Not this mood").
Future<void> showSongActions(
  BuildContext context,
  Song song, {
  String? playlistId,
  VoidCallback? onRemoveFromPlaylist,
  String? mood,
}) =>
    showPlatformSheet(
      context: context,
      menu: true,
      builder: (_) => OptionsMenu(
        song: song,
        playlistId: playlistId,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
        mood: mood,
      ),
    );

/// The song context menu: queue actions, library actions, Smart Shuffle
/// feedback. Every action confirms with a short toast.
class OptionsMenu extends ConsumerWidget {
  final Song song;
  final String? playlistId;
  final VoidCallback? onRemoveFromPlaylist;

  /// The mood of the list the menu was opened from (see [NotThisMoodAction]).
  final String? mood;

  const OptionsMenu({
    super.key,
    required this.song,
    this.playlistId,
    this.onRemoveFromPlaylist,
    this.mood,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider.notifier);
    final service = ref.read(subsonicServiceProvider);
    // Actions run after the sheet closes, so they act through the page's
    // context (captured here), not the sheet's.
    final page = Navigator.of(context).context;
    final starred = ref.watch(playerProvider.select((s) => s.starredIds.contains(song.id)));
    final inJam = ref.watch(jamControllerProvider.select((s) => s.active));
    final isPlayingNow = ref.watch(playerProvider.select((s) => s.currentSong?.id == song.id));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: song.title,
          subtitle: song.album.isEmpty ? song.artist : '${song.artist} — ${song.album}',          detail: catalogDetailLine(ref.watch(catalogSongProvider(song.id)), song),
          artUrl: service.getCoverArtUrl(song.coverArt),
        ),
        _CreditRows(song: song, page: page),
        _PlayStatsRow(song: song),
        SheetGroup(children: [
          SheetAction(
            label: 'Play Next',
            icon: NaviGlyph.playNext,
            onTap: () {
              addToUpNext(ref, [song], next: true);
              showToast(page, 'Playing next');
            },
          ),
          SheetAction(
            label: 'Play Last',
            icon: NaviGlyph.playLast,
            onTap: () {
              addToUpNext(ref, [song], next: false);
              showToast(page, 'Added to the end of the queue');
            },
          ),
        ]),
        SheetGroup(children: [
          SheetAction(
            label: 'Add to Playlist…',
            trailing: NaviIcon(
              NaviGlyph.addToPlaylist,
              size: 21,
              color: ThemeTokens.of(context).textPrimary,
            ),
            onTap: () => showAddToPlaylist(page, song),
          ),
          SheetAction(
            label: 'Add to Shared Playlist…',
            trailing: NaviIcon(NaviGlyph.group, size: 21, color: ThemeTokens.of(context).textPrimary),
            onTap: () => showAddToCollab(page, ProviderScope.containerOf(page), [song]),
          ),
          if (inJam)
            SheetAction(
              label: 'Add to Jam',
              trailing: NaviIcon(NaviGlyph.queue, size: 21, color: ThemeTokens.of(context).textPrimary),
              onTap: () async {
                final ok = await ref.read(jamControllerProvider.notifier).addSongs([song]);
                if (page.mounted) showToast(page, ok ? 'Added to the Jam' : 'Couldn’t add to the Jam');
              },
            ),
          SheetAction(
            label: starred ? 'Remove from Favorites' : 'Favorite',
            hint: 'L',
            icon: starred ? NaviGlyph.starOff : NaviGlyph.star,
            onTap: () {
              player.toggleStar(song.id);
              showToast(page, starred ? 'Removed from Favorites' : 'Added to Favorites');
            },
          ),
          // The browser build streams only: no download folder to save into.
          if (PlatformUtils.supportsOfflineFiles) _DownloadAction(song: song, toastContext: page),
          SheetAction(
            label: 'Share…',
            icon: NaviGlyph.share,
            onTap: () => showShareSheet(page, ShareTarget.song(song)),
          ),
          if (isPlayingNow)
            SheetAction(
              label: ref.watch(dontCountProvider) ? 'Count My Listening Again' : 'Don’t Count This Listening',
              icon: ref.watch(dontCountProvider) ? NaviGlyph.eye : NaviGlyph.eyeOff,
              onTap: () {
                final off = !ref.read(dontCountProvider);
                ref.read(dontCountProvider.notifier).set(off);
                showToast(page, off ? 'Not counting this listening' : 'Counting your listening again');
              },
            ),
          if (isPlayingNow)
            SheetAction(
              label: 'Share now playing',
              icon: NaviGlyph.share,
              onTap: () => runShareNowPlaying(page, song),
            ),
          if (song.albumId.isNotEmpty)
            SheetAction(
              label: 'Go to Album',
              icon: NaviGlyph.library,
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
              icon: NaviGlyph.mic,
              onTap: () => navigateInApp(page, ArtistScreen(artistId: song.artistId, name: song.artist)),
            ),
        ]),
        SheetGroup(children: [
          SheetAction(
            label: ref.watch(songTrimsProvider.select((t) => t.of(song.id).isNone))
                ? 'Start and End…'
                : 'Start and End (set)…',
            icon: NaviGlyph.sliders,
            onTap: () => showSongTrimSheet(page, song),
          ),
        ]),
        SheetGroup(children: [
          SheetAction(
            label: 'Suggest More Like This',
            icon: NaviGlyph.thumbUp,
            onTap: () {
              player.handleSuggestAction(song, true);
              showToast(page, 'Smart Shuffle will play this more often');
            },
          ),
          SheetAction(
            label: 'Suggest Less Like This',
            icon: NaviGlyph.thumbDown,
            onTap: () {
              player.handleSuggestAction(song, false);
              showToast(page, 'Smart Shuffle will play this less often');
            },
          ),
        ]),
        NotThisMoodAction(song: song, mood: mood, page: page),
        SheetGroup(children: [
          SheetAction(
            label: 'Never Recommend…',
            trailing: NaviIcon(NaviGlyph.block, size: 21, color: ThemeTokens.of(context).textPrimary),
            onTap: () => showNeverRecommend(page, ProviderScope.containerOf(page), song),
          ),
        ]),
        if (playlistId != null && onRemoveFromPlaylist != null)
          SheetGroup(children: [
            SheetAction(
              label: 'Remove from Playlist',
              hint: 'Del',
              icon: NaviGlyph.minusCircle,
              destructive: true,
              onTap: onRemoveFromPlaylist,
            ),
          ]),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}

/// "12 plays" with "last played yesterday" under the sheet header (R5).
class _PlayStatsRow extends ConsumerWidget {
  const _PlayStatsRow({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(songPlayStatsProvider(song));
    if (stats.isEmpty) return const SizedBox.shrink();
    final last = stats.lastPlayedLabel(DateTime.now());
    return SheetGroup(children: [
      SheetInfoRow(label: 'Plays', value: stats.countLabel),
      if (last != null) SheetInfoRow(label: 'Last played', value: last),
    ]);
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
          icon: NaviGlyph.downloadCircle,
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
          icon: NaviGlyph.trash,
          destructive: true,
          onTap: () {
            notifier.deleteSong(song.id);
            showToast(toastContext, 'Download removed');
          },
        ),
      SongDownloadStatus.failed => SheetAction(
          label: 'Download Failed',
          detail: 'Tap to try again',
          icon: NaviGlyph.alert,
          keepOpen: true,
          onTap: () => notifier.downloadSong(song),
        ),
    };
  }
}
