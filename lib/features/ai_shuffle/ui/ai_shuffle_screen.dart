// =============================================================================
// AiShuffleScreen — Smart Shuffle UI (v3.0.0)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../screens/now_playing_screen.dart';
import '../data/models/recommended_song.dart';
import '../logic/shuffle_providers.dart';
import 'widgets/server_status_bar.dart';
import 'widgets/recommendation_card.dart';
import 'widgets/model_status_sheet.dart';
import '../../../widgets/desktop_dialogs.dart';

// Source mode options for the Smart Shuffle
enum _ShuffleSource { smart, playlist, allSongs }

extension _SourceExt on _ShuffleSource {
  String get label {
    switch (this) {
      case _ShuffleSource.smart:    return 'Smart';
      case _ShuffleSource.playlist: return 'Playlist';
      case _ShuffleSource.allSongs: return 'All Songs';
    }
  }

  String get apiValue {
    switch (this) {
      case _ShuffleSource.smart:    return 'smart';
      case _ShuffleSource.playlist: return 'playlist';
      case _ShuffleSource.allSongs: return 'all_songs';
    }
  }
}

class AiShuffleScreen extends ConsumerStatefulWidget {
  const AiShuffleScreen({super.key});

  @override
  ConsumerState<AiShuffleScreen> createState() => _AiShuffleScreenState();
}

class _AiShuffleScreenState extends ConsumerState<AiShuffleScreen> {
  _ShuffleSource _selectedSource = _ShuffleSource.smart;

  /// True while _applyAiShuffle() is resolving songs and setting the queue.
  bool _isApplyingQueue = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRecommendations();
    });
  }

  void _fetchRecommendations() {
    ref.read(shuffleQueueProvider.notifier).fetchNext(
          source: _selectedSource.apiValue,
        );
  }

  Future<void> _enqueueSong(RecommendedSong song) async {
    try {
      final allSongs = await ref.read(allSongsProvider.future);
      final localSong = allSongs.cast<dynamic>().firstWhere(
            (s) => s.title.toLowerCase() == song.title.toLowerCase(),
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
          SnackBar(content: Text('Not found in library: ${song.title}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding song: $e')),
      );
    }
  }

  /// Resolves all recommendations against the local library, replaces the
  /// playback queue with the resolved songs, then navigates to Now Playing.
  Future<void> _applyAiShuffle() async {
    if (_isApplyingQueue) return;
    setState(() => _isApplyingQueue = true);

    try {
      final queueState    = ref.read(shuffleQueueProvider);
      final recommendations =
          queueState.allSongs.whereType<RecommendedSong>().toList();

      if (recommendations.isEmpty) {
        _showSnackBar('No recommendations — tap refresh first');
        return;
      }

      final allSongs = await ref.read(allSongsProvider.future);
      final resolved = recommendations
          .map((rec) {
            try {
              return allSongs.firstWhere(
                (s) => s.title.toLowerCase() == rec.title.toLowerCase(),
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

      await ref.read(playerProvider.notifier).setQueue(resolved, 0);

      if (!mounted) return;
      // Navigate to Now Playing screen instead of popping to a black screen
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
      );
    } catch (e, st) {
      debugPrint('[SmartShuffle] _applyAiShuffle error: $e\n$st');
      _showSnackBar('Failed to apply shuffle — please try again');
    } finally {
      if (mounted) setState(() => _isApplyingQueue = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showModelStatus() {
    showPlatformSheet(
      context: context,
      title: 'Model Status',
      builder: (_) => const ModelStatusSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final cs         = theme.colorScheme;
    final queueState = ref.watch(shuffleQueueProvider);
    final songs      = queueState.allSongs.whereType<RecommendedSong>().toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Shuffle'),
        actions: [
          // Only keep the Model Status action — no "Reconnect" needed
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Model Status',
            onPressed: _showModelStatus,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Server status bar ──────────────────────────────────────────────
          const ServerStatusBar(),

          // ── Context info strip ─────────────────────────────────────────────
          if (queueState.lastContext != null ||
              queueState.lastWeather != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: cs.surfaceContainerHigh,
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    [
                      if (queueState.lastContext != null)
                        queueState.lastContext!,
                      if (queueState.lastWeather != null)
                        queueState.lastWeather!,
                    ].join(' · '),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],

          // ── Mode selector ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: _ShuffleSource.values.map((src) {
                final selected = _selectedSource == src;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(src.label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedSource = src);
                      ref.read(shuffleQueueProvider.notifier).clearQueue();
                      _fetchRecommendations();
                    },
                    // FIX: Use surface-based selected color — not primary fill
                    selectedColor: cs.secondaryContainer,
                    checkmarkColor: cs.onSecondaryContainer,
                    backgroundColor: cs.surfaceContainerLow,
                    side: BorderSide(
                      color: selected
                          ? cs.secondary
                          : cs.outline.withValues(alpha: 0.4),
                      width: selected ? 1.5 : 1,
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    showCheckmark: false, // icon-free, just color change
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),

          // ── Recommendations list ───────────────────────────────────────────
          Expanded(
            child: Builder(
              builder: (context) {
                if (queueState.isLoading && songs.isEmpty) {
                  return _buildSkeletonList(cs);
                }
                if (queueState.error != null && songs.isEmpty) {
                  return _buildErrorState(queueState.error!, cs);
                }
                if (songs.isEmpty) {
                  return _buildEmptyState(theme, cs);
                }
                return ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return RecommendationCard(
                      song: song,
                      onTap: () => _enqueueSong(song),
                      onLongPress: () => _enqueueSong(song),
                    );
                  },
                );
              },
            ),
          ),

          // ── Sticky footer ──────────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  IconButton.outlined(
                    onPressed: _isApplyingQueue
                        ? null
                        : () {
                            ref
                                .read(shuffleQueueProvider.notifier)
                                .clearQueue();
                            _fetchRecommendations();
                          },
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh recommendations',
                  ),
                  const SizedBox(width: 12),
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

  Widget _buildSkeletonList(ColorScheme cs) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        child: ListTile(
          leading: const Icon(Icons.music_note, color: Colors.transparent),
          title: Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          subtitle: Container(
            height: 10,
            width: 150,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No recommendations yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Tap refresh to fetch Smart Shuffle results',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: cs.error),
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
