import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../controllers/lyrics_controller.dart';
import 'lyric_line_widget.dart';
import 'lyrics_background.dart';
import 'no_lyrics_card.dart';
import 'plain_text_view.dart';

/// Full-screen lyrics bottom sheet — the main entry point for the lyrics feature.
///
/// Open via:
/// ```dart
/// showModalBottomSheet(
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => LyricsView(song: song, imageUrl: imageUrl),
/// );
/// ```
class LyricsView extends ConsumerStatefulWidget {
  final Song song;
  final String imageUrl;

  const LyricsView({super.key, required this.song, required this.imageUrl});

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scroll = ScrollController();

  /// Approximate height of a single lyric line (inactive). Used to compute
  /// the scroll offset needed to centre the active line.
  static const double _kLineHeight = 62.0;

  /// Whether lines have already animated in — prevents re-triggering the
  /// entry animation on every position update.
  bool _hasAnimated = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToLine(int index) {
    if (!_scroll.hasClients) return;
    if (index < 0) return;
    final viewportHeight = _scroll.position.viewportDimension;
    final target =
        (index * _kLineHeight) - (viewportHeight / 2) + (_kLineHeight / 2);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for active-line changes to trigger auto-scroll.
    ref.listen<int>(lyricsControllerProvider.select((s) => s.activeLineIndex), (
      prev,
      next,
    ) {
      if (next >= 0 && next != prev) {
        _scrollToLine(next);
      }
    });

    final lyricsState = ref.watch(lyricsControllerProvider);

    // Mark animation as done once lyrics are ready.
    if (lyricsState.status == LyricsStatus.synced ||
        lyricsState.status == LyricsStatus.plain) {
      if (!_hasAnimated) {
        // Schedule to flip after first build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hasAnimated = true);
        });
      }
    } else {
      // Reset animation flag when song changes / new lyrics load.
      if (_hasAnimated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hasAnimated = false);
        });
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.93,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background ─────────────────────────────────────────────────
          LyricsBackground(imageUrl: widget.imageUrl),

          // ── Content ────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                Expanded(child: _buildBody(lyricsState)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lyrics',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.45),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.song.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.song.artist,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.55),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white70,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ────────────────────────────────────────────────────────────────────

  Widget _buildBody(LyricsState state) {
    return switch (state.status) {
      LyricsStatus.loading => _buildShimmer(),
      LyricsStatus.synced => _buildSyncedList(state),
      LyricsStatus.plain => PlainTextView(
        lyrics: state.lyrics!,
        song: widget.song,
      ),
      LyricsStatus.empty => const NoLyricsCard(),
      LyricsStatus.error => _buildError(state.errorMessage),
    };
  }

  // ── Shimmer skeleton ────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 100, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(5, (i) {
          final widthFraction = [0.85, 0.6, 0.75, 0.5, 0.7][i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _ShimmerBar(widthFraction: widthFraction, delay: i * 80),
          );
        }),
      ),
    );
  }

  // ── Synced lyrics list ──────────────────────────────────────────────────────

  Widget _buildSyncedList(LyricsState state) {
    final lines = state.lyrics!.lines;
    final activeIdx = state.activeLineIndex;

    return ListView.builder(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 160),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final ts = lines[i].timestamp;
            // Skip seek for lines without a meaningful timestamp
            // (e.g. blank separator lines parsed from plain-text LRC).
            if (ts == Duration.zero && i > 0) return;
            final duration =
                ref.read(playerProvider).currentSong?.duration ?? 0;
            final max = Duration(seconds: duration);
            final safe = ts.clamp(Duration.zero, max);
            // Seek the audio — modal stays open per design decision.
            ref.read(playerProvider.notifier).player.seek(safe);
            // Snap the scroll list to the tapped line.
            _scrollToLine(i);
          },
          child: LyricLineWidget(
            key: ValueKey('line_$i'),
            text: lines[i].text,
            isActive: i == activeIdx,
            isPast: activeIdx >= 0 && i < activeIdx,
            index: i,
            animate: !_hasAnimated,
          ),
        );
      },
    );
  }

  // ── Error state ─────────────────────────────────────────────────────────────

  Widget _buildError(String? message) {
    return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: Colors.white.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not load lyrics',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () =>
                      ref.read(lyricsControllerProvider.notifier).retry(),
                  child: const Text(
                    'Retry',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.06, end: 0, duration: 400.ms);
  }
}

// ── Shimmer bar widget ─────────────────────────────────────────────────────────

class _ShimmerBar extends StatefulWidget {
  final double widthFraction;
  final int delay;

  const _ShimmerBar({required this.widthFraction, required this.delay});

  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FadeTransition(
              opacity: Tween<double>(begin: 0.15, end: 0.35).animate(_anim),
              child: Container(
                width: constraints.maxWidth * widget.widthFraction,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            )
            .animate(delay: Duration(milliseconds: widget.delay))
            .fadeIn(duration: 300.ms);
      },
    );
  }
}
