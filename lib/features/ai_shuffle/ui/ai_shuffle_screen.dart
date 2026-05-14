import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
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

  /// True while _applyAiShuffle() is resolving songs and setting the queue.
  /// Disables both action buttons to prevent double-tap races.
  bool _isApplyingQueue = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentSong = ref.read(playerProvider).currentSong;
      if (currentSong != null) {
        setState(() {
          _currentSong = currentSong.title;
          _songController.text = _currentSong;
        });
        _fetchRecommendations();
      }
    });
  }

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
        await ref.read(playerProvider.notifier).addToQueue(localSong as Song);
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

  /// Resolves all currently displayed recommendations against the local library,
  /// replaces the playback queue with the resolved songs, and pops this screen.
  ///
  /// Errors are shown as snackbars — the screen stays open so the user can
  /// retry or adjust the query.
  Future<void> _applyAiShuffle() async {
    if (_isApplyingQueue) return; // guard against double-tap
    setState(() => _isApplyingQueue = true);

    try {
      final recommendations = ref.read(shuffleQueueProvider).valueOrNull;

      if (recommendations == null || recommendations.isEmpty) {
        _showSnackBar('No recommendations to shuffle — refresh first');
        return;
      }

      // Resolve recommendations against the full local library.
      // Same matching strategy as _enqueueSong for consistency.
      final allSongs = await ref.read(allSongsProvider.future);
      final resolved = recommendations
          .map((rec) {
            try {
              return allSongs.firstWhere(
                (s) =>
                    s.title.toLowerCase() == rec.title.toLowerCase() &&
                    s.artist.toLowerCase() == rec.artist.toLowerCase(),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<Song>()
          .toList();

      if (resolved.isEmpty) {
        _showSnackBar('None of the recommendations were found in your library');
        return;
      }

      await ref
          .read(playerProvider.notifier)
          .setQueue(resolved, 0);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      debugPrint('[AiShuffle] _applyAiShuffle error: $e\n$st');
      _showSnackBar('Failed to apply shuffle — please try again');
    } finally {
      if (mounted) setState(() => _isApplyingQueue = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
    ref.listen(
      playerProvider.select((s) => s.currentSong),
      (previous, next) {
        if (next != null && next.title != _currentSong) {
          setState(() {
            _currentSong = next.title;
            _songController.text = _currentSong;
          });
          _fetchRecommendations();
        }
      },
    );

    final queueAsync = ref.watch(shuffleQueueProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      // FAB removed — replaced by sticky footer row below.
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

          // ── Sticky footer: Refresh + Shuffle Now ─────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  // Refresh recommendations (replaces old FAB)
                  IconButton.outlined(
                    onPressed: _isApplyingQueue ? null : _fetchRecommendations,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh recommendations',
                  ),
                  const SizedBox(width: 12),
                  // Shuffle Now — replace queue with all resolved recommendations
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isApplyingQueue ? null : _applyAiShuffle,
                      icon: _isApplyingQueue
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.shuffle),
                      label: Text(
                        _isApplyingQueue ? 'Applying…' : 'Shuffle Now',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
