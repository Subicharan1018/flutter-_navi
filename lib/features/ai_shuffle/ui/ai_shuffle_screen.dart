// =============================================================================
// Smart Shuffle — the app's own "station": a mix tuned to the moment (time,
// season, weather, your habits) from the Smart Shuffle server, presented the
// way Apple Music presents a personal mix: a card in the mix's own colours
// that says what it's tuned for, one Play button, then the songs.
// =============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../screens/now_playing_screen.dart';
import '../../../widgets/song_tile.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/controls.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/mosaic_art.dart';
import '../../../widgets/ui/states.dart';
import '../data/models/next_response.dart';
import '../data/models/predict_response.dart';
import '../logic/recommendation_resolver.dart';
import '../logic/shuffle_providers.dart';
import 'widgets/smart_shuffle_status.dart';

class AiShuffleScreen extends ConsumerStatefulWidget {
  const AiShuffleScreen({super.key});

  @override
  ConsumerState<AiShuffleScreen> createState() => _AiShuffleScreenState();
}

class _AiShuffleScreenState extends ConsumerState<AiShuffleScreen> {
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  /// Fresh /predict for [mode] (default: the current one). Drops any /next
  /// reshuffle preview first so a stale batch never shows over the new
  /// picks. Only the preview: a mix that's already playing keeps its session.
  void _fetch([PredictMode? mode]) {
    ref.read(shuffleQueueProvider.notifier).clearPreview();
    ref.read(predictQueueProvider.notifier).fetchPredict(mode: mode ?? ref.read(predictQueueProvider).mode);
  }

  /// New songs for the same moment: everything on screen is banned.
  Future<void> _reshuffle(List<Song> visible) async {
    HapticFeedback.selectionClick();
    try {
      await ref
          .read(shuffleQueueProvider.notifier)
          .reshuffle(source: 'smart', visibleTitles: [for (final s in visible) s.title]);
    } catch (_) {
      if (mounted) showToast(context, 'Couldn’t get new picks. Check your connection and try again.');
    }
  }

  /// Plays the resolved mix from [start] and opens Now Playing.
  Future<void> _play(List<Song> mix, {int start = 0}) async {
    if (_applying || mix.isEmpty) return;
    setState(() => _applying = true);
    try {
      final shuffle = ref.read(shuffleQueueProvider.notifier);
      shuffle.clearQueue(); // drop preview batches before real playback
      await ref.read(playerProvider.notifier).setQueue(mix, start, playlistName: 'Smart Shuffle');
      shuffle.initSession(); // fresh session for real playback
      if (mounted) openNowPlaying(context);
    } catch (_) {
      if (mounted) showToast(context, 'Couldn’t start the mix. Try again.');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shuffleState = ref.watch(shuffleQueueProvider);
    final predict = ref.watch(predictQueueProvider);
    final library = ref.watch(allSongsProvider).asData?.value ?? const <Song>[];
    // Picks resolve against the library mirror; on a first launch it may
    // still be syncing, which is "not ready yet", not "no picks".
    final syncing = library.isEmpty && ref.watch(librarySyncProvider.select((s) => s.syncing));

    // After a reshuffle the /next batches are newest; otherwise /predict.
    final recs = shuffleState.batches.isNotEmpty ? shuffleState.allRecommendedSongs : predict.songs;
    final resolver = RecommendationResolver(library);
    final mix = resolver.resolveAll(recs);
    final missing = recs.length - mix.length;
    final starter = shuffleState.batches.map((b) => b.sessionStarter).whereType<SessionStarter>().firstOrNull;
    final loading = shuffleState.isLoading || predict.isLoading || syncing;
    final error = shuffleState.error ?? (predict.hasError ? predict.errorMessage : null);

    return LargeTitlePage(
      title: 'Smart Shuffle',
      trailing: const SmartShuffleStatusButton(),
      onRefresh: () async => _fetch(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.lg),
          sliver: SliverToBoxAdapter(
            child: NaviSegmented<PredictMode>(
              segments: {for (final m in PredictMode.values) m: m.displayLabel},
              value: predict.mode,
              onChanged: _fetch,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          sliver: SliverToBoxAdapter(
            child: _MixCard(
              context: predict.context,
              mode: predict.mode,
              mix: mix,
              busy: _applying || loading,
              onPlay: mix.isEmpty ? null : () => _play(mix),
              onReshuffle: loading ? null : () => _reshuffle(mix),
            ),
          ),
        ),
        if (starter != null) SliverToBoxAdapter(child: _StarterRow(starter: starter)),
        if (syncing)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: Space.xxl),
              child: LoadingState(label: 'Getting your library ready for Smart Shuffle…'),
            ),
          )
        else if (loading && mix.isEmpty)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: Space.lg), child: TrackListSkeleton()))
        else if (error != null && mix.isEmpty)
          SliverToBoxAdapter(
            child: MessageState.error(
              title: 'Smart Shuffle isn’t reachable',
              message: 'Check that your Smart Shuffle server is running, then try again.',
              onRetry: _fetch,
            ),
          )
        else if (mix.isEmpty)
          SliverToBoxAdapter(
            child: MessageState(
              icon: CupertinoIcons.sparkles,
              title: 'No picks yet',
              message: predict.mode.emptyMessage,
            ),
          )
        else ...[
          const SliverToBoxAdapter(child: SectionHeader(title: 'In This Mix')),
          SliverFixedExtentList(
            itemExtent: SongTile.extent,
            delegate: SliverChildBuilderDelegate(
              (context, i) => SongTile(song: mix[i], onTap: () => _play(mix, start: i)),
              childCount: mix.length,
            ),
          ),
          if (missing > 0)
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) => Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
                  child: Text(
                    missing == 1
                        ? '1 pick isn’t in your library yet.'
                        : '$missing picks aren’t in your library yet.',
                    style: ThemeTokens.of(context).footnote,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// The mix itself: cover mosaic, the moment it's tuned for, and the
/// transport.
class _MixCard extends ConsumerWidget {
  final PredictContext? context;
  final PredictMode mode;
  final List<Song> mix;
  final bool busy;
  final VoidCallback? onPlay;

  /// Swaps every pick on screen for new ones tuned to the same moment.
  final VoidCallback? onReshuffle;

  const _MixCard({
    required this.context,
    required this.mode,
    required this.mix,
    required this.busy,
    required this.onPlay,
    required this.onReshuffle,
  });

  static const double _buttonHeight = 50;

  static String _titleCase(String s) =>
      s.split('_').where((w) => w.isNotEmpty).map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  /// "late_morning__summer__cloudy" → ("Late Morning", ["Summer", "Cloudy"]).
  static (String, List<String>) _moment(PredictContext? c) {
    if (c == null) return ('Right Now', const []);
    final parts = c.bucket.split('__').where((p) => p.isNotEmpty).map(_titleCase).toList();
    return (parts.isEmpty ? 'Right Now' : parts.first, parts.skip(1).toList());
  }

  static String _confidence(PredictContext c) => switch (c.fallbackLevel) {
        0 => 'Tuned from ${c.nInProfile} plays at moments like this',
        1 => 'Based on what you play this season',
        2 => 'Based on what you play at this time of day',
        _ => 'Still learning your taste. The more you listen, the closer it gets.',
      };

  @override
  Widget build(BuildContext buildContext, WidgetRef ref) {
    final t = ThemeTokens.of(buildContext);
    final svc = ref.read(subsonicServiceProvider);
    final (title, extras) = _moment(context);
    final c = context;
    final details = [
      ...extras,
      if (c?.temperatureC != null) '${c!.temperatureC!.round()}°',
    ].join(', ');

    // The mix as an Apple playlist header: art, name, why, transport. No
    // card around it; the page is the surface.
    return Column(
      children: [
        MosaicArt(
          urls: [for (final s in mix.take(12)) svc.getCoverArtUrl(s.coverArt)],
          size: _art,
          radius: Radii.hero,
          placeholderIcon: CupertinoIcons.sparkles,
        ),
        const SizedBox(height: Space.lg),
        Text(
          mode == PredictMode.discovery ? 'Discoveries for $title' : 'Your Mix for $title',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.title1,
        ),
        if (details.isNotEmpty) ...[
          const SizedBox(height: Space.xxs),
          Text(details, textAlign: TextAlign.center, style: t.title3.copyWith(color: t.accent, fontWeight: FontWeight.w500)),
        ],
        if (c != null) ...[
          const SizedBox(height: Space.sm),
          Text(_confidence(c), textAlign: TextAlign.center, style: t.footnote),
        ],
        const SizedBox(height: Space.xl),
        // Apple's paired capsules: play this mix, or reshuffle it into new
        // picks for the same moment.
        Row(
          children: [
            Expanded(
              child: TintedButton(
                filled: true,
                height: _buttonHeight,
                icon: CupertinoIcons.play_fill,
                label: 'Play',
                onTap: busy ? null : onPlay,
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: TintedButton(
                height: _buttonHeight,
                icon: CupertinoIcons.shuffle,
                label: 'Reshuffle',
                onTap: onReshuffle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const double _art = 220;
}

/// "Your evening opener" — the song you usually start this time of day with.
class _StarterRow extends StatelessWidget {
  final SessionStarter starter;
  const _StarterRow({required this.starter});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
      child: Row(
        children: [
          Icon(CupertinoIcons.sunrise, size: 18, color: t.accent),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Your ${starter.timeArcLabel} opener: ', style: t.subheadline),
                TextSpan(text: starter.title, style: t.subheadline.copyWith(color: t.textPrimary)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('${starter.sessionsStarted}×', style: t.footnote),
        ],
      ),
    );
  }
}
