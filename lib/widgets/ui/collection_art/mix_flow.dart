import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../art/generated_cover.dart';
import '../../cover_art.dart';
import '../../motion/play_once.dart';
import 'blur_ground.dart';

/// The mark of a Smart Shuffle mix: its own picks laid out in the order they
/// will play, flowing corner to corner over a soft ground of the lead cover.
/// Covers swell toward the middle of the run and tilt with the curve, so the
/// tile reads as the mix's arc rather than a grid. Covers slide into place
/// once, in play order. With no covers it falls back to the generated cover.
class MixFlow extends StatelessWidget {
  final List<String?> urls;
  final double size;
  final double radius;
  final String seed;

  const MixFlow({super.key, required this.urls, required this.size, required this.seed, this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final picks = <String>{
      for (final u in urls)
        if (u != null && u.isNotEmpty) u,
    }.take(7).toList();
    if (picks.isEmpty) {
      return SizedBox.square(dimension: size, child: GeneratedCover.seeded(seed: seed, borderRadius: radius));
    }
    final t = ThemeTokens.of(context);
    final n = picks.length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Positioned.fill(child: BlurGround(url: picks.first, scrim: 0.5)),
            Positioned.fill(
              child: PlayOnce(
                duration: Duration(milliseconds: 700 + 110 * n),
                curve: Curves.linear,
                builder: (context, p) => AnimatedBuilder(
                  animation: p,
                  builder: (context, _) => Stack(
                    children: [
                      for (var i = 0; i < n; i++) _pick(t, picks[i], i, n, p.value),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pick(AppThemeTokens t, String url, int i, int n, double clock) {
    final f = n == 1 ? 0.5 : i / (n - 1);
    final k = Curves.easeOutCubic.transform(((clock - i * 0.08) / 0.5).clamp(0.0, 1.0));
    final c = size * (0.28 + 0.12 * math.sin(math.pi * f));
    // Along a gentle S from bottom-left to top-right.
    final cx = size * (0.20 + 0.60 * f);
    final cy = size * (0.74 - 0.48 * f + 0.05 * math.sin(f * math.pi * 3));
    final from = Offset(size * 0.20, size * 0.74);
    final x = from.dx + (cx - from.dx) * k;
    final y = from.dy + (cy - from.dy) * k;
    return Positioned(
      left: x - c / 2,
      top: y - c / 2,
      child: Opacity(
        opacity: k,
        child: Transform.rotate(
          angle: (f - 0.5) * 0.35,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.cover),
              boxShadow: [BoxShadow(color: t.bgBase.withValues(alpha: 0.55), blurRadius: size * 0.05)],
            ),
            child: CoverArt(url: url, size: c, radius: Radii.cover),
          ),
        ),
      ),
    );
  }
}
