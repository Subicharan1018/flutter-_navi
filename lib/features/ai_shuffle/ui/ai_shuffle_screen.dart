// =============================================================================
// AiShuffleScreen — Smart Shuffle UI (v4.0.0)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../screens/now_playing_screen.dart';
import '../data/models/recommended_song.dart';
import '../data/models/predict_response.dart';
import '../data/models/next_response.dart';
import '../logic/shuffle_providers.dart';
import 'widgets/server_status_bar.dart';
import 'widgets/recommendation_card.dart';
import 'widgets/model_status_sheet.dart';
import '../../../widgets/desktop_dialogs.dart';

class AiShuffleScreen extends ConsumerStatefulWidget {
  const AiShuffleScreen({super.key});

  @override
  ConsumerState<AiShuffleScreen> createState() => _AiShuffleScreenState();
}

class _AiShuffleScreenState extends ConsumerState<AiShuffleScreen> {
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
    // Clear any previous /next reshuffle batch FIRST so the screen never renders
    // a stale frame of the playback engine's batches. On first open those batches
    // are populated by playPlaylist's fetchNext (/next); clearing before fetching
    // stops the screen from briefly showing /next data before /predict/always-hear.
    ref.read(shuffleQueueProvider.notifier).clearQueue();
    final state = ref.read(predictQueueProvider);
    ref.read(predictQueueProvider.notifier).fetchPredict(mode: state.mode);
  }

  Future<void> _enqueueSong(RecommendedSong song) async {
    try {
      final allSongs = await ref.read(allSongsProvider.future);
      final localSong = allSongs.firstWhereOrNull(
        (s) =>
            s.title.toLowerCase() == song.title.toLowerCase() &&
            s.artist.toLowerCase() == song.composer.toLowerCase(),
      ) ?? allSongs.firstWhereOrNull(
        (s) => s.title.toLowerCase() == song.title.toLowerCase(),
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
          SnackBar(content: Text('Not found in library: ${song.title}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error adding song: $e')));
    }
  }

  /// Resolves all recommendations against the local library, replaces the
  /// playback queue with the resolved songs, then navigates to Now Playing.
  Future<void> _applyAiShuffle() async {
    if (_isApplyingQueue) return;
    setState(() => _isApplyingQueue = true);

    try {
      // After reshuffle, use the shuffle queue; otherwise use predict queue.
      final shuffleState = ref.read(shuffleQueueProvider);
      final predictState = ref.read(predictQueueProvider);
      final recommendations = shuffleState.batches.isNotEmpty
          ? shuffleState.allRecommendedSongs
          : predictState.songs;

      if (recommendations.isEmpty) {
        _showSnackBar('No recommendations — tap refresh first');
        return;
      }

      final allSongs = await ref.read(allSongsProvider.future);
      final resolved = recommendations
          .map((rec) {
            return allSongs.firstWhereOrNull(
              (s) =>
                  s.title.toLowerCase() == rec.title.toLowerCase() &&
                  s.artist.toLowerCase() == rec.composer.toLowerCase(),
            ) ?? allSongs.firstWhereOrNull(
              (s) => s.title.toLowerCase() == rec.title.toLowerCase(),
            );
          })
          .whereType<Song>()
          .toList();

      if (resolved.isEmpty) {
        _showSnackBar('None of the recommendations were found in your library');
        return;
      }

      // Clean preview batches BEFORE playback starts
      final notifier = ref.read(shuffleQueueProvider.notifier);
      notifier.clearQueue();  // Wipes preview batches + playedTitles

      await ref.read(playerProvider.notifier).setQueue(resolved, 0);

      // Fresh sessionId for real playback AFTER setQueue clears history
      notifier.initSession();

      if (!mounted) return;
      // Navigate to Now Playing screen instead of popping to a black screen
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
    } catch (e, st) {
      debugPrint('[SmartShuffle] _applyAiShuffle error: $e\n$st');
      _showSnackBar('Failed to apply shuffle — please try again');
    } finally {
      if (mounted) setState(() => _isApplyingQueue = false);
    }
  }

  /// Fetches 16 new songs from POST /next (reshuffle: true),
  /// excluding the current visible queue. Session state is preserved.
  Future<void> _doReshuffle() async {
    if (_isApplyingQueue) return;
    try {
      await ref.read(shuffleQueueProvider.notifier).reshuffle(source: 'smart');
    } catch (_) {
      _showSnackBar('Reshuffle failed — please try again');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    final theme = Theme.of(context);
    final tokens = ThemeTokens.of(context);
    final cs = theme.colorScheme;
    final shuffleState = ref.watch(shuffleQueueProvider);
    final queueState   = ref.watch(predictQueueProvider);
    final playerState  = ref.watch(playerProvider);
    final notifier     = ref.read(predictQueueProvider.notifier);

    // After a reshuffle the shuffle queue has data — display it.
    // Otherwise fall back to the predict queue.
    final songs     = shuffleState.batches.isNotEmpty
        ? shuffleState.allRecommendedSongs
        : queueState.songs;

    // Session starter pinned by the server (v3.1), if any.
    final sessionStarter = shuffleState.batches
        .map((b) => b.sessionStarter)
        .firstWhereOrNull((s) => s != null);
    final isLoading = shuffleState.isLoading || queueState.isLoading;
    final hasError  = shuffleState.error != null ||
        (queueState.hasError && songs.isEmpty);
    final errorMsg  = shuffleState.error ?? queueState.errorMessage ?? 'Error';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Shuffle'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.info_outline_rounded,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip: 'Model Status',
            onPressed: _showModelStatus,
          ),
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ── Server status bar ──────────────────────────────────────────
              const SliverToBoxAdapter(
                child: ServerStatusBar(),
              ),

              // ── Session starter banner ─────────────────────────────────────
              if (sessionStarter != null)
                SliverToBoxAdapter(
                  child: _SessionStarterBanner(starter: sessionStarter),
                ),

              // ── Context info strip ─────────────────────────────────────────
              if (queueState.context != null)
                SliverToBoxAdapter(
                  child: _PredictContextStrip(
                    ctx: queueState.context!,
                    mode: queueState.mode,
                  ),
                ),

              // ── Mode selector ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: PredictMode.values.map((mode) {
                        final isSelected = queueState.mode == mode;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: FilterChip(
                            label: Text(mode.displayLabel),
                            selected: isSelected,
                            onSelected: (_) {
                              notifier.setMode(mode);
                              notifier.fetchPredict(mode: mode);
                            },
                            selectedColor: const Color(0xFFFFFFFF),
                            backgroundColor: tokens.bgElevated,
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF000000)
                                  : tokens.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 12,
                            ),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),

              // ── Fallback Warning ───────────────────────────────────────────
              if (queueState.context?.fallbackLevel == 3)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Using your global taste profile. '
                            'Listen to more music in this time/season to get precise picks.',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Recommendations list ───────────────────────────────────────
              if (isLoading && songs.isEmpty)
                SliverToBoxAdapter(
                  child: _buildSkeletonList(cs),
                )
              else if (hasError && songs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildErrorState(errorMsg, cs),
                )
              else if (songs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(theme, cs, queueState.mode),
                )
              else
                SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    final isPlaying = playerState.isPlaying &&
                        playerState.currentSong?.title.toLowerCase() ==
                            song.title.toLowerCase();
                    return RecommendationCard(
                      song: song,
                      rank: index,
                      isPlaying: isPlaying,
                      onTap: () => _enqueueSong(song),
                      onLongPress: () => _enqueueSong(song),
                    );
                  },
                ),

              // Bottom clearance so sticky footer doesn't obscure last item
              const SliverToBoxAdapter(
                child: SizedBox(height: 96),
              ),
            ],
          ),

          // ── Sticky Floating Footer with frosted glass backdrop ─────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    tokens.bgBase,
                    tokens.bgBase.withValues(alpha: 0.85),
                    tokens.bgBase.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.65, 1.0],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    children: [
                      IconButton.outlined(
                        onPressed: _isApplyingQueue || isLoading
                            ? null
                            : _fetchRecommendations,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh recommendations',
                        style: IconButton.styleFrom(
                          backgroundColor: tokens.bgElevated,
                          side: BorderSide.none,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        onPressed: _isApplyingQueue || isLoading
                            ? null
                            : _doReshuffle,
                        icon: const Icon(Icons.shuffle_rounded),
                        tooltip: 'Reshuffle queue (16 new songs)',
                        style: IconButton.styleFrom(
                          backgroundColor: tokens.bgElevated,
                          side: BorderSide.none,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isApplyingQueue || isLoading
                              ? null
                              : _applyAiShuffle,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          icon: _isApplyingQueue || isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded, size: 22),
                          label: Text(
                            _isApplyingQueue ? 'Applying…' : 'Shuffle Now',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSkeletonList(ColorScheme cs) {
    final tokens = ThemeTokens.of(context);
    return Shimmer.fromColors(
      baseColor: tokens.bgElevated,
      highlightColor: tokens.bgOverlay,
      child: ListView.builder(
        itemCount: 8,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme cs, PredictMode mode) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No recommendations yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              mode.emptyMessage,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
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

class _SessionStarterBanner extends StatelessWidget {
  const _SessionStarterBanner({required this.starter});

  final SessionStarter starter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const accent = Color(0xFF4ADE80);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_fill_rounded, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your ${starter.timeArcLabel} opener',
                  style: textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  starter.title,
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'started ${starter.sessionsStarted}×',
            style: textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PredictContextStrip extends StatelessWidget {
  const _PredictContextStrip({required this.ctx, required this.mode});

  final PredictContext ctx;
  final PredictMode mode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Context bucket row
          Row(children: [
            const Icon(Icons.tune, size: 14),
            const SizedBox(width: 6),
            Text(
              ctx.bucket.split('__').map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1).toLowerCase()).join(' • '),
              style: textTheme.labelMedium,
            ),
          ]),
          const SizedBox(height: 4),
          // Weather + temperature
          Row(children: [
            const Icon(Icons.cloud_outlined, size: 14),
            const SizedBox(width: 6),
            Text(
              '${ctx.weatherMood.isNotEmpty ? ctx.weatherMood[0].toUpperCase() + ctx.weatherMood.substring(1).toLowerCase() : ""}'
              '${ctx.temperatureC != null ? "  ${ctx.temperatureC!.toStringAsFixed(1)} °C" : ""}',
              style: textTheme.labelSmall,
            ),
          ]),
          const SizedBox(height: 4),
          // Profile confidence
          Row(children: [
            Icon(
              ctx.isHighConfidence ? Icons.verified : Icons.info_outline,
              size: 14,
              color: ctx.isHighConfidence ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                ctx.fallbackDescription,
                style: textTheme.labelSmall?.copyWith(
                  color: ctx.isHighConfidence ? Colors.green : Colors.orange,
                ),
              ),
            ),
          ]),
          // Show max_prior_plays badge for discovery mode
          if (mode == PredictMode.discovery && ctx.maxPriorPlays != null) ...[
            const SizedBox(height: 4),
            Text(
              'Showing songs with ≤ ${ctx.maxPriorPlays} prior plays',
              style: textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}
