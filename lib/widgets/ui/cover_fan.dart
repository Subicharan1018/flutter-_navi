import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme.dart';
import '../art/generated_cover.dart';
import '../cover_art.dart';
import '../motion/play_once.dart';

/// The mark of a mix: up to three of its covers fanned like a hand of cards
/// on an opaque ground, the newest-picked one in front. Used where a mix is
/// not a playlist (Smart Shuffle), so it does not read as a 2×2 mosaic.
/// With no covers it falls back to NaviVibe's generated cover.
class CoverFan extends StatelessWidget {
  final List<String?> urls;
  final double size;
  final double radius;

  /// Seed for the generated fallback (see `coverSeed`).
  final String seed;

  const CoverFan({super.key, required this.urls, required this.size, required this.seed, this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final distinct = <String>{
      for (final u in urls)
        if (u != null && u.isNotEmpty) u,
    }.take(3).toList();
    if (distinct.isEmpty) {
      return SizedBox.square(dimension: size, child: GeneratedCover.seeded(seed: seed, borderRadius: radius));
    }
    final t = ThemeTokens.of(context);
    final c = size * 0.54;
    // Back to front: left, right, centre. Fewer covers keep the same slots.
    const slots = [(-0.06, 0.12, -0.16), (0.26, 0.14, 0.14), (0.11, 0.30, 0.0)];
    final order = distinct.length == 1 ? [2] : (distinct.length == 2 ? [0, 2] : [0, 1, 2]);
    // The cards start stacked in the middle and open into the fan once.
    final home = Offset(size * 0.19, size * 0.30);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: t.bgElevated,
        child: SizedBox.square(
          dimension: size,
          child: PlayOnce(
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutBack,
            builder: (context, p) => AnimatedBuilder(
              animation: p,
              builder: (context, _) {
                final k = p.value;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final (i, slot) in order.indexed)
                      Positioned(
                        left: home.dx + (size * slots[slot].$1 + size * 0.08 - home.dx) * k,
                        top: home.dy + (size * slots[slot].$2 - home.dy) * k,
                        child: Transform.rotate(
                          angle: slots[slot].$3 * math.pi / 3 * k,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.cover),
                              boxShadow: [BoxShadow(color: t.bgBase.withValues(alpha: 0.5), blurRadius: size * 0.06)],
                            ),
                            child: CoverArt(url: distinct[i], size: c, radius: Radii.cover),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
