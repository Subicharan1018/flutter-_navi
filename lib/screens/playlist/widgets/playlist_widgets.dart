import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../models/playlist.dart';
import '../../../models/song.dart';
import '../../../models/download_state.dart';
import '../../../providers/download_provider.dart';
import '../../../core/theme.dart';

// ===========================================================================
// Sub-widgets extracted from playlist_details_screen.dart (God Node Reduction)
// All const-constructable / stateless for zero rebuild overhead
// ===========================================================================

// ---------------------------------------------------------------------------
// Collapsed app-bar title (fades in when scrolled up)
// ---------------------------------------------------------------------------
class CollapsedTitle extends StatelessWidget {
  final String title;
  const CollapsedTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: tokens.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton placeholder shown while songs are loading
// ---------------------------------------------------------------------------
class SongListSkeleton extends StatelessWidget {
  const SongListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 10,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (_, i) => SkeletonTile()
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: 1200.ms,
            delay: (i * 60).ms,
            color: ThemeTokens.of(context).textPrimary.withOpacity(0.06),
          ),
    );
  }
}

class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tokens.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 13,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: tokens.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 11,
                  width: 120,
                  decoration: BoxDecoration(
                    color: tokens.bgSurface.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state header (shown while _isLoading)
// ---------------------------------------------------------------------------
class LoadingHeader extends StatelessWidget {
  final Playlist playlist;
  const LoadingHeader({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Container(
      decoration: BoxDecoration(color: tokens.bgBase),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: tokens.bgSurface,
                borderRadius: BorderRadius.circular(16),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 600.ms)
                .then()
                .fadeOut(duration: 600.ms),
            const SizedBox(height: 24),
            Container(
              width: 160,
              height: 20,
              decoration: BoxDecoration(
                color: tokens.bgSurface,
                borderRadius: BorderRadius.circular(8),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 600.ms, delay: 100.ms)
                .then()
                .fadeOut(duration: 600.ms),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fully expanded header (shown after songs are loaded)
// ---------------------------------------------------------------------------
class ExpandedHeader extends ConsumerWidget {
  final Playlist playlist;
  final String coverImageUrl;
  final String coverCacheKey;
  final Color vibrantColor;
  final int songCount;
  final String totalDuration;
  final List<Song> songs;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffleAll;
  final VoidCallback onDownloadAll;

  const ExpandedHeader({
    super.key,
    required this.playlist,
    required this.coverImageUrl,
    required this.coverCacheKey,
    required this.vibrantColor,
    required this.songCount,
    required this.totalDuration,
    required this.songs,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onDownloadAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double topPadding =
        MediaQuery.of(context).padding.top + kToolbarHeight;
    final tokens = ThemeTokens.of(context);

    // ── Download button state (derived from per-song statuses)
    final dlMap = ref.watch(downloadStateProvider);
    final int totalSongs = songs.length;
    final int downloadedCount = songs
        .where((s) =>
            dlMap[s.id]?.status == SongDownloadStatus.downloaded)
        .length;
    final int activeCount = songs
        .where((s) =>
            dlMap[s.id]?.status == SongDownloadStatus.queued ||
            dlMap[s.id]?.status == SongDownloadStatus.downloading)
        .length;
    final bool allDownloaded =
        totalSongs > 0 && downloadedCount == totalSongs;
    final bool isActive = activeCount > 0;
    final double dlFraction =
        totalSongs > 0 ? (downloadedCount + activeCount / 2) / totalSongs : 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Blurred background
        if (coverImageUrl.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.55), BlendMode.darken),
                child: CachedNetworkImage(
                  imageUrl: coverImageUrl,
                  cacheKey: '${coverCacheKey}_bg',
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),

        // ── Gradient scrim
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.4, 0.78, 1.0],
                colors: [
                  vibrantColor.withOpacity(0.55),
                  vibrantColor.withOpacity(0.08),
                  tokens.bgBase.withOpacity(0.8),
                  tokens.bgBase,
                ],
              ),
            ),
          ),
        ),

        // ── Content
        Positioned(
          top: topPadding + 12,
          left: 0,
          right: 0,
          child: Column(
            children: [
              // Artwork
              Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.65),
                      blurRadius: 36,
                      spreadRadius: 2,
                      offset: const Offset(0, 12),
                    ),
                    if (vibrantColor != tokens.bgSurface)
                      BoxShadow(
                        color: vibrantColor.withOpacity(0.28),
                        blurRadius: 48,
                        offset: const Offset(0, 8),
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: coverImageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: coverImageUrl,
                          cacheKey: coverCacheKey,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                              color: tokens.bgSurface,
                              child: Icon(Icons.music_note_rounded,
                                  size: 72, color: tokens.textMuted)),
                          errorWidget: (_, __, ___) => Container(
                              color: tokens.bgSurface,
                              child: Icon(Icons.music_note_rounded,
                                  size: 72, color: tokens.textMuted)),
                        )
                      : Container(
                          color: tokens.bgSurface,
                          child: Icon(Icons.music_note_rounded,
                              size: 72, color: tokens.textMuted)),
                ),
              ),
              const SizedBox(height: 20),

              // Playlist name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: tokens.textPrimary,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Subtitle
              Text(
                '$songCount songs • $totalDuration',
                style: TextStyle(
                  fontSize: 13,
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 20),

              // Play / Shuffle / Download buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HeaderButton(
                    size: 52,
                    onTap: onShuffleAll,
                    filled: false,
                    child: Icon(Icons.shuffle_rounded,
                        color: tokens.textPrimary, size: 22),
                  ),
                  const SizedBox(width: 20),
                  HeaderButton(
                    size: 64,
                    onTap: onPlayAll,
                    filled: true,
                    child: Icon(Icons.play_arrow_rounded,
                        color: ThemeTokens.of(context).textPrimary, size: 36),
                  ),
                  const SizedBox(width: 20),
                  DownloadAllButton(
                    tokens: tokens,
                    isActive: isActive,
                    allDownloaded: allDownloaded,
                    downloadedCount: downloadedCount,
                    totalSongs: totalSongs,
                    dlFraction: dlFraction,
                    onTap: allDownloaded || isActive ? null : onDownloadAll,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable header button (filled = accent gradient, unfilled = ghost)
// ---------------------------------------------------------------------------
class HeaderButton extends StatelessWidget {
  final double size;
  final VoidCallback onTap;
  final bool filled;
  final Widget child;

  const HeaderButton({
    super.key,
    required this.size,
    required this.onTap,
    required this.filled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: filled
              ? const LinearGradient(
                  colors: [Color(0xFFF54EA2), Color(0xFFFF7676)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: filled ? null : ThemeTokens.of(context).textPrimary.withOpacity(0.10),
          border: filled
              ? null
              : Border.all(
                  color: tokens.textPrimary.withOpacity(0.55),
                  width: 1.5,
                ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: const Color(0xFFF54EA2).withOpacity(0.40),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dismiss background (swipe-to-delete)
// ---------------------------------------------------------------------------
class DismissBackground extends StatelessWidget {
  const DismissBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.redAccent.withOpacity(0.85),
          ],
        ),
      ),
      child: Icon(Icons.delete_outline_rounded,
          color: ThemeTokens.of(context).textPrimary, size: 24),
    );
  }
}

// ---------------------------------------------------------------------------
// Search field
// ---------------------------------------------------------------------------
class PlaylistSearchField extends StatelessWidget {
  final TextEditingController controller;
  const PlaylistSearchField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: TextField(
            controller: controller,
            style: TextStyle(color: tokens.textPrimary, fontSize: 15),
            cursorColor: tokens.accent,
            decoration: InputDecoration(
              hintText: 'Search in playlist',
              hintStyle: TextStyle(
                  color: tokens.textMuted.withOpacity(0.6), fontSize: 15),
              prefixIcon: Icon(Icons.search_rounded,
                  color: tokens.textMuted, size: 18),
              suffixIcon: value.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () => controller.clear(),
                      child: Icon(Icons.cancel_rounded,
                          color: tokens.textMuted, size: 18),
                    )
                  : null,
              filled: true,
              fillColor: tokens.bgSurface.withOpacity(0.55),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: tokens.outline.withOpacity(0.25), width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: tokens.outline.withOpacity(0.25), width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: tokens.accent.withOpacity(0.55), width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Add songs row
// ---------------------------------------------------------------------------
class AddSongsRow extends StatelessWidget {
  final VoidCallback onTap;
  const AddSongsRow({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withOpacity(0.12),
              border: Border.all(
                  color: Colors.green.withOpacity(0.45), width: 1.5),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.green, size: 24),
          ),
          const SizedBox(width: 14),
          Text(
            'Add Songs',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bulk-download button for the playlist header
// ---------------------------------------------------------------------------
class DownloadAllButton extends StatelessWidget {
  final AppThemeTokens tokens;
  final bool isActive;
  final bool allDownloaded;
  final int downloadedCount;
  final int totalSongs;
  final double dlFraction;
  final VoidCallback? onTap;

  const DownloadAllButton({
    super.key,
    required this.tokens,
    required this.isActive,
    required this.allDownloaded,
    required this.downloadedCount,
    required this.totalSongs,
    required this.dlFraction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: allDownloaded
                  ? tokens.accent.withOpacity(0.15)
                  : tokens.textPrimary.withOpacity(0.10),
              border: Border.all(
                color: allDownloaded
                    ? tokens.accent.withOpacity(0.55)
                    : tokens.textPrimary.withOpacity(0.55),
                width: 1.5,
              ),
            ),
            child: isActive
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: CircularProgressIndicator(
                          value: dlFraction > 0 ? dlFraction : null,
                          strokeWidth: 2.5,
                          color: tokens.accent,
                        ),
                      ),
                      Text(
                        '$downloadedCount',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : Icon(
                    allDownloaded
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_download_rounded,
                    color: allDownloaded ? tokens.accent : tokens.textPrimary,
                    size: 22,
                  ),
          ),
          if (isActive) ...[
            const SizedBox(height: 4),
            Text(
              '$downloadedCount/$totalSongs',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable circular icon button (app bar back / add / more)
// ---------------------------------------------------------------------------
class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tokens.bgSurface.withOpacity(0.55),
        ),
        child: Icon(icon, color: tokens.textPrimary, size: size),
      ),
    );
  }
}
