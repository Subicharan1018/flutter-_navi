// =============================================================================
// RecommendationCard — displays a single Smart Shuffle recommendation.
// =============================================================================

import 'package:flutter/material.dart';
import '../../data/models/recommended_song.dart';

class RecommendationCard extends StatelessWidget {
  final RecommendedSong song;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const RecommendationCard({
    super.key,
    required this.song,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: title + rank + badges ──────────────────────────
              Row(
                children: [
                  // Rank chip
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${song.rank}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song.composer.isNotEmpty
                              ? song.composer
                              : 'Unknown Composer',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Genre bucket + cold-start badges
                  if (song.genreBucket.isNotEmpty)
                    _Chip(
                      label: _genreLabel(song.genreBucket),
                      color: _genreColor(song.genreBucket, cs),
                      textColor: cs.onSecondary,
                    ),
                  if (song.isColdStart) ...[
                    const SizedBox(width: 4),
                    _Chip(
                      label: 'NEW',
                      color: cs.tertiaryContainer,
                      textColor: cs.onTertiaryContainer,
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // ── Score bar ─────────────────────────────────────────────────
              Row(
                children: [
                  Text(
                    'Match',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: song.scores.finalScore.clamp(0.0, 1.0),
                        backgroundColor: cs.surfaceContainerHighest,
                        color: _scoreColor(song.scores.finalScore, cs),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(song.scores.finalScore * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // ── Why caption ───────────────────────────────────────────────
              if (song.why.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  song.why,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _scoreColor(double score, ColorScheme cs) {
    if (score >= 0.7) return cs.primary;
    if (score >= 0.4) return cs.secondary;
    return cs.tertiary;
  }

  Color _genreColor(String bucket, ColorScheme cs) {
    switch (bucket) {
      case 'melody':
        return cs.primary;
      case 'kuthu':
        return cs.error;
      case 'devotional':
        return cs.tertiary;
      default:
        return cs.secondary;
    }
  }

  String _genreLabel(String bucket) {
    switch (bucket) {
      case 'melody':
        return '♪ Melody';
      case 'kuthu':
        return '🥁 Kuthu';
      case 'devotional':
        return '🙏 Devotional';
      default:
        return bucket;
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _Chip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}
