import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/heart_burst.dart';
import '../logic/preview_feed_providers.dart';
import 'feed_painters.dart';

/// The heart: a ring that fills as the clip plays (how long you have to decide), a burst when it is hearted. Hearted songs
/// stay filled. One repaint island: only the ring repaints as the clip moves.
class FeedHeartButton extends ConsumerWidget {
  final bool hearted;
  final bool active;
  final VoidCallback onTap;
  final double size;
  final Color color;
  final FocusNode? focusNode;
  final bool autofocus;

  const FeedHeartButton({
    super.key,
    required this.hearted,
    required this.active,
    required this.onTap,
    this.size = 76,
    this.color = Colors.white,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: hearted
          ? 'Hearted. Fetching this song'
          : 'Heart to fetch this song',
      child: InkResponse(
        onTap: onTap,
        focusNode: focusNode,
        autofocus: autofocus,
        radius: size * 0.7,
        highlightShape: BoxShape.circle,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (active)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final p = ref.watch(previewFeedProgressProvider);
                        return CustomPaint(
                          painter: RingPainter(progress: p, color: color),
                        );
                      },
                    ),
                  ),
                ),
              HeartBurst(
                active: hearted,
                color: color,
                child: NaviIcon(
                  NaviGlyph.heart,
                  size: size * 0.42,
                  color: color,
                  filled: hearted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The song's waveform: it breathes while the clip plays and is its progress bar. Its ticker runs only while it is playing and
/// decorative motion is allowed; paused or under Reduced motion it is still.
class FeedWaveform extends ConsumerStatefulWidget {
  final String seed;
  final bool playing;
  final double height;
  const FeedWaveform({
    super.key,
    required this.seed,
    required this.playing,
    this.height = 40,
  });

  @override
  ConsumerState<FeedWaveform> createState() => _FeedWaveformState();
}

class _FeedWaveformState extends ConsumerState<FeedWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FeedWaveform old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final go = widget.playing && context.motionFull;
    if (go && !_c.isAnimating) {
      _c.repeat();
    } else if (!go && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.playing && context.motionFull;
    final progress = ref.watch(previewFeedProgressProvider);
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: WaveformPainter(
              seed: widget.seed,
              progress: progress,
              phase: _c.value,
              animate: animate,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
