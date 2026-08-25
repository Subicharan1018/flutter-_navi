// =============================================================================
// RecommendationCard — redesigned AI Shuffle song row (v2)
// -----------------------------------------------------------------------------
// Replaces the old flat "number + grey square + two lines + stray icon" row.
//
// What changed and why:
//   - Real cover art instead of a static music-note placeholder. Resolved by
//     matching the recommendation against the local library, same lookup
//     `_enqueueSong` already does in ai_shuffle_screen.dart.
//   - No more leading numeric index. A shuffled AI queue isn't a fixed track
//     list. Rank only shows as a tiny badge on the art for the top 3.
//   - Currently-playing state swaps the art for a small animated equalizer.
//   - Trailing action collapsed to a single quick-add `+`.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';

import '../../../../core/theme.dart';
import '../../../../models/song.dart';
import '../../../../providers/library_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../data/models/recommended_song.dart';

class RecommendationCard extends ConsumerWidget {
  const RecommendationCard({
    super.key,
    required this.song,
    required this.onTap,
    required this.onLongPress,
    this.rank,
    this.isPlaying = false,
    this.subtitleOverride,
    this.badgeLabel,
  });

  final RecommendedSong song;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 0-based position in the list. Only used to show a tiny "strong pick"
  /// badge for the first three rows — pass null to suppress it entirely.
  final int? rank;

  /// Whether this is the track currently loaded in the player. Swaps the
  /// art for an animated equalizer glyph when true.
  final bool isPlaying;

  /// Optional replacement for the artist line — falls back to composer/artist.
  final String? subtitleOverride;

  /// Optional small text badge rendered next to the title (e.g. "92%", "New").
  final String? badgeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    final allSongsAsync = ref.watch(allSongsProvider);
    final svc = ref.watch(subsonicServiceProvider);

    final localSong = allSongsAsync.maybeWhen(
      data: (allSongs) => _resolveLocal(allSongs),
      orElse: () => null,
    );

    final coverUrl = (localSong != null && localSong.coverArt.isNotEmpty)
        ? svc.getCoverArtUrl(localSong.coverArt)
        : null;

    final showRankBadge = rank != null && rank! < 3;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              // ── Art / equalizer ──────────────────────────────────────
              _ArtTile(
                coverUrl: coverUrl,
                isPlaying: isPlaying,
                accent: tokens.accent,
                rankBadge: showRankBadge ? rank! + 1 : null,
              ),
              const SizedBox(width: 12),

              // ── Title / subtitle ─────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isPlaying
                                  ? tokens.accent
                                  : tokens.textPrimary,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (badgeLabel != null) ...[
                          const SizedBox(width: 6),
                          _Badge(label: badgeLabel!, accent: tokens.accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleOverride ?? song.composer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Quick add ─────────────────────────────────────────────
              IconButton(
                onPressed: onTap,
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  color: tokens.textSecondary,
                  size: 22,
                ),
                tooltip: 'Add to queue',
                splashRadius: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Song? _resolveLocal(List<Song> allSongs) {
    return allSongs.firstWhereOrNull(
          (s) =>
              s.title.toLowerCase() == song.title.toLowerCase() &&
              s.artist.toLowerCase() == song.composer.toLowerCase(),
        ) ??
        allSongs.firstWhereOrNull(
          (s) => s.title.toLowerCase() == song.title.toLowerCase(),
        );
  }
}

// =============================================================================
// Art tile — real cover art, rank badge overlay, or playing equalizer
// =============================================================================

class _ArtTile extends StatelessWidget {
  const _ArtTile({
    required this.coverUrl,
    required this.isPlaying,
    required this.accent,
    required this.rankBadge,
  });

  final String? coverUrl;
  final bool isPlaying;
  final Color accent;
  final int? rankBadge;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: _size,
              height: _size,
              child: coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: coverUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 96,
                      memCacheHeight: 96,
                      placeholder: (context, url) => _placeholder(),
                      errorWidget: (context, url, error) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),

          // Playing-state scrim + equalizer
          if (isPlaying)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: _EqualizerGlyph(color: accent),
                ),
              ),
            ),

          // Rank badge (top pick indicator, top 3 only)
          if (rankBadge != null && !isPlaying)
            Positioned(
              left: 2,
              top: 2,
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rankBadge',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.45),
              accent.withValues(alpha: 0.15),
            ],
          ),
        ),
        child: const Icon(
          Icons.music_note_rounded,
          color: Colors.white38,
          size: 20,
        ),
      );
}

// =============================================================================
// Tiny animated equalizer — 3 bars, staggered, loops while visible
// =============================================================================

class _EqualizerGlyph extends StatefulWidget {
  const _EqualizerGlyph({required this.color});
  final Color color;

  @override
  State<_EqualizerGlyph> createState() => _EqualizerGlyphState();
}

class _EqualizerGlyphState extends State<_EqualizerGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final phase = (_controller.value + i * 0.33) % 1.0;
              final height = 4 + (12 * (0.5 - (phase - 0.5).abs()) * 2);
              return Container(
                width: 3,
                height: height.clamp(4, 16),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Small inline badge (match %, "New", etc.) — unused until backend sends data
// =============================================================================

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}
