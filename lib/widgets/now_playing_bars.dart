import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/motion.dart';

/// Three-bar equalizer marking the loaded track in a list. Moves only while
/// audio is playing (and never under reduced motion), so a paused queue
/// costs no frames.
class NowPlayingBars extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double size;

  const NowPlayingBars({
    super.key,
    required this.isPlaying,
    required this.color,
    this.size = 14,
  });

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars>
    with SingleTickerProviderStateMixin {
  static const _phases = [0.0, 2.1, 4.2];
  static const _rest = [0.45, 0.8, 0.3];
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.isPlaying && context.motionFull;
    if (animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!animate && _c.isAnimating) {
      _c.stop();
    }
    final s = widget.size;
    return Semantics(
      label: widget.isPlaying ? 'Now playing' : 'Paused',
      child: RepaintBoundary(
        child: SizedBox(
          width: s,
          height: s,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: s * 0.2,
                    height: s *
                        (0.22 +
                            0.78 *
                                (animate
                                    ? (math.sin(_c.value * math.pi * 2 + _phases[i]) + 1) / 2
                                    : _rest[i])),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(s * 0.1),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
