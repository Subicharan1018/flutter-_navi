import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/focus/navi_focus.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../providers/catalog_provider.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/format.dart';
import '../utils/platform_utils.dart';
import 'art/navi_icons.dart';
import 'cover_art.dart';
import 'now_playing_bars.dart';
import 'options_menu.dart';

/// The one song row used across the app (Apple Music list style).
///
/// Tap plays. Long-press (touch) or right-click (mouse) opens the song menu,
/// as does the trailing `…` button. The playing song shows animated bars over
/// its artwork and an accent title.
///
/// Album track lists pass [trackNumber] and `showArtwork: false`.
class SongTile extends ConsumerStatefulWidget {
  final Song song;
  final VoidCallback onTap;
  final String? playlistId;
  final VoidCallback? onRemoveFromPlaylist;
  final bool showArtwork;
  final int? trackNumber;
  final bool showDuration;
  final bool showSeparator;

  /// Albums hide the artist line unless a track's artist differs from the
  /// album's, as Apple Music does.
  final bool showArtist;

  /// Kept for call sites that open a custom menu; defaults to the song menu.
  final VoidCallback? onLongPress;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onLongPress,
    this.playlistId,
    this.onRemoveFromPlaylist,
    this.showArtwork = true,
    this.trackNumber,
    this.showDuration = false,
    this.showSeparator = true,
    this.showArtist = true,
  });

  /// Fixed row height so lists can use `itemExtent` (cheaper scrolling).
  static const double extent = 58;

  static const double _art = 46;

  @override
  ConsumerState<SongTile> createState() => _SongTileState();
}

class _SongTileState extends ConsumerState<SongTile> {
  bool _pressed = false;
  bool _hovered = false;

  void _openMenu() {
    HapticFeedback.mediumImpact();
    if (widget.onLongPress != null) return widget.onLongPress!();
    showSongActions(
      context,
      widget.song,
      playlistId: widget.playlistId,
      onRemoveFromPlaylist: widget.onRemoveFromPlaylist,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final song = widget.song;
    final isCurrent = ref.watch(
      playerProvider.select((s) => s.currentSong?.id == song.id),
    );
    final isPlaying =
        isCurrent && ref.watch(playerProvider.select((s) => s.isPlaying));
    final textInset = widget.showArtwork
        ? Space.gutter + SongTile._art + Space.md
        : Space.gutter + 32;

    final leading = widget.showArtwork
        ? Stack(
            alignment: Alignment.center,
            children: [
              CoverArt(
                url: ref
                    .read(subsonicServiceProvider)
                    .getCoverArtUrl(
                      song.coverArt.isNotEmpty ? song.coverArt : song.id,
                    ),
                size: SongTile._art,
                radius: Radii.thumb,
              ),
              if (isCurrent)
                Container(
                  width: SongTile._art,
                  height: SongTile._art,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(Radii.thumb),
                  ),
                  child: Center(
                    child: NowPlayingBars(
                      isPlaying: isPlaying,
                      color: t.textPrimary,
                      size: 16,
                    ),
                  ),
                ),
            ],
          )
        : SizedBox(
            width: 32 - Space.md,
            child: isCurrent
                ? NowPlayingBars(
                    isPlaying: isPlaying,
                    color: t.accent,
                    size: 13,
                  )
                : Text(
                    '${widget.trackNumber ?? ''}',
                    style: t.callout.copyWith(
                      color: t.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          );

    final artist = shortArtists(displayArtist(song, ref.watch(catalogSongProvider(song.id))));

    return Semantics(
      button: true,
      label: '${song.title}, $artist${isCurrent ? ', now playing' : ''}',
      onLongPressHint: 'Show song options',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: NaviFocusRing(
          radius: Radii.thumb,
          onTap: widget.onTap,
          onLongPress: _openMenu,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: widget.onTap,
            onLongPress: _openMenu,
            onSecondaryTap: _openMenu,
            child: AnimatedContainer(
              duration: _pressed ? Duration.zero : Motion.fast,
              height: SongTile.extent,
              color: _pressed
                  ? t.bgSurface
                  : (_hovered
                        ? t.bgSurface.withValues(alpha: 0.6)
                        : Colors.transparent),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: Space.gutter,
                      right: Space.xs,
                    ),
                    child: Row(
                      children: [
                        // The cover dips under the finger; the row tint alone
                        // would be the only cue on a dark theme.
                        AnimatedScale(
                          scale: _pressed ? pressedScale(context, 0.92) : 1,
                          duration: _pressed ? Motion.press : Motion.fast,
                          curve: Motion.ease,
                          child: leading,
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.body.copyWith(
                                  color: isCurrent ? t.accent : t.textPrimary,
                                ),
                              ),
                              if (widget.showArtist) ...[
                                const SizedBox(height: 1),
                                Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.subheadline,
                                ),
                              ],
                            ],
                          ),
                        ),
                        _DownloadBadge(songId: song.id),
                        if (widget.showDuration)
                          Padding(
                            padding: const EdgeInsets.only(left: Space.sm),
                            child: Text(
                              formatTrackDuration(song.duration),
                              style: t.footnote,
                            ),
                          ),
                        // On a TV the menu is the long-press / Menu key; no extra stop per row.
                        ExcludeFocus(
                          excluding: PlatformUtils.isTv,
                          child: IconButton(
                            tooltip: 'More',
                            onPressed: _openMenu,
                            icon: NaviIcon(
                              NaviGlyph.more,
                              size: 20,
                              color: t.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.showSeparator)
                    Positioned(
                      left: textInset,
                      right: 0,
                      bottom: 0,
                      child: Container(height: 0.5, color: t.outline),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small download-state glyph shown before the `…` button.
class _DownloadBadge extends ConsumerWidget {
  final String songId;
  const _DownloadBadge({required this.songId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final state = ref.watch(downloadStateProvider.select((m) => m[songId]));
    final status = state?.status ?? SongDownloadStatus.notDownloaded;
    return switch (status) {
      SongDownloadStatus.notDownloaded => const SizedBox.shrink(),
      SongDownloadStatus.queued || SongDownloadStatus.downloading => Padding(
        padding: const EdgeInsets.only(left: Space.sm),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            value:
                status == SongDownloadStatus.downloading &&
                    (state?.progress ?? 0) > 0
                ? state!.progress
                : null,
            strokeWidth: 1.6,
            color: t.textSecondary,
          ),
        ),
      ),
      SongDownloadStatus.downloaded => Padding(
        padding: const EdgeInsets.only(left: Space.sm),
        child: NaviIcon(
          NaviGlyph.downloadCircle,
          size: 15,
          color: t.textSecondary,
          filled: true,
        ),
      ),
      SongDownloadStatus.failed => Padding(
        padding: const EdgeInsets.only(left: Space.sm),
        child: NaviIcon(NaviGlyph.alert, size: 15, color: t.danger),
      ),
    };
  }
}
