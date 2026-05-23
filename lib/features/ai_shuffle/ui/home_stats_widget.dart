import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../logic/shuffle_providers.dart';

/// Shows top songs for the given [period] from the Smart Shuffle stats API.
/// Migrated to listeningStatsProvider (v3.0.0).
class HomeStatsWidget extends ConsumerWidget {
  final String period; // 'weekly' or 'monthly'

  const HomeStatsWidget({super.key, required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(listeningStatsProvider(period));
    final theme = Theme.of(context);
    final tokens = ThemeTokens.of(context);

    return statsAsync.when(
      loading: () => _buildSkeleton(tokens),
      error: (e, _) => _buildErrorCard(context, ref, e.toString(), tokens),
      data: (stats) {
        final topSongs = stats.topTracks;

        if (topSongs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                period == 'weekly' ? 'Weekly Top Songs' : 'Monthly Top Songs',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            ...topSongs.take(5).map((songMap) {
              final title = songMap['title']?.toString() ?? 'Unknown';
              final artist = songMap['artist']?.toString() ?? 'Unknown';
              final playCount = songMap['play_count']?.toString() ?? '0';

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.bgElevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.music_note, color: tokens.textMuted),
                ),
                title: Text(
                  title,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  artist,
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  '$playCount plays',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildSkeleton(AppThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Container(
            height: 20,
            width: 150,
            decoration: BoxDecoration(
              color: tokens.bgElevated,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        ...List.generate(3, (index) => _buildSkeletonRow(tokens)),
      ],
    );
  }

  Widget _buildSkeletonRow(AppThemeTokens tokens) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      title: Container(
        height: 14,
        width: double.infinity,
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      subtitle: Container(
        height: 10,
        width: 100,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildErrorCard(
      BuildContext context, WidgetRef ref, String error, AppThemeTokens tokens) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Failed to load stats: $error',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(listeningStatsProvider(period)),
              style: TextButton.styleFrom(
                foregroundColor:
                    Theme.of(context).colorScheme.onErrorContainer,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
