import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/player_provider.dart';
import '../../../providers/library_provider.dart';
import '../data/models/recommended_song.dart';
import '../logic/shuffle_providers.dart';
import 'widgets/server_status_bar.dart';
import 'widgets/recommendation_card.dart';
import 'widgets/song_profile_sheet.dart';
import 'widgets/session_controls_sheet.dart';

class AiShuffleScreen extends ConsumerStatefulWidget {
  const AiShuffleScreen({super.key});

  @override
  ConsumerState<AiShuffleScreen> createState() => _AiShuffleScreenState();
}

class _AiShuffleScreenState extends ConsumerState<AiShuffleScreen> {
  final TextEditingController _songController = TextEditingController();
  String _currentSong = '';

  @override
  void dispose() {
    _songController.dispose();
    super.dispose();
  }

  void _fetchRecommendations() {
    if (_currentSong.isEmpty) return;
    ref.read(shuffleQueueProvider.notifier).fetchNext(current: _currentSong);
  }

  Future<void> _enqueueSong(RecommendedSong song) async {
    try {
      final allSongs = await ref.read(allSongsProvider.future);
      // Try to find the exact song in the local library.
      // A more robust implementation would use fuzzy matching or Subsonic search API.
      final localSong = allSongs.cast<dynamic>().firstWhere(
            (s) => s.title.toLowerCase() == song.title.toLowerCase() &&
                   s.artist.toLowerCase() == song.artist.toLowerCase(),
            orElse: () => null,
          );

      if (localSong != null) {
        await ref.read(playerProvider.notifier).addToQueue(localSong);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${song.title}" to queue')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Song not found in library: ${song.title}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding song: $e')),
      );
    }
  }

  void _showProfileSheet(String songTitle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SongProfileSheet(songTitle: songTitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(shuffleQueueProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Shuffle'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'session') {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => const SessionControlsSheet(),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'session', child: Text('Session Controls')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const ServerStatusBar(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _songController,
              decoration: const InputDecoration(
                labelText: 'Current Song',
                hintText: 'Type song title...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _currentSong = v.trim()),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _fetchRecommendations(),
            ),
          ),
          Expanded(
            child: queueAsync.when(
              loading: () => _buildSkeletonList(colorScheme),
              error: (e, _) => _buildErrorState(e.toString(), colorScheme),
              data: (songs) {
                if (songs.isEmpty) return _buildEmptyState(theme, colorScheme);
                return ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return RecommendationCard(
                      song: song,
                      onTap: () => _enqueueSong(song),
                      onLongPress: () => _showProfileSheet(song.title),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchRecommendations,
        tooltip: 'Refresh recommendations',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildSkeletonList(ColorScheme colorScheme) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: ListTile(
            leading: const Icon(Icons.music_note, color: Colors.transparent),
            title: Container(
              height: 14,
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            subtitle: Container(
              height: 10,
              width: 150,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.queue_music, size: 64, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('Pick a song to start', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Type a song title above and tap search',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _fetchRecommendations,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
