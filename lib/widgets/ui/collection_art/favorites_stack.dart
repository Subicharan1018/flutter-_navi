import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../art/navi_icons.dart';
import '../../cover_art.dart';
import '../../motion/play_once.dart';
import 'blur_ground.dart';

/// Favorites, kept simple: the song you starred most recently as one large
/// cover, a second starred cover peeking out behind it, and a single white
/// star badge on the front one. A soft ground of the same art sits behind.
/// The front cover settles into place once; nothing else moves.
class FavoritesStack extends StatelessWidget {
  final List<String?> urls;
  final double size;
  final double radius;

  const FavoritesStack({super.key, required this.urls, required this.size, this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final picks = <String>{
      for (final u in urls)
        if (u != null && u.isNotEmpty) u,
    }.take(2).toList();
    final front = size * 0.62;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Positioned.fill(child: BlurGround(url: picks.firstOrNull, scrim: 0.55)),
            if (picks.length > 1)
              Positioned(
                right: size * 0.10,
                top: size * 0.10,
                child: Opacity(opacity: 0.85, child: CoverArt(url: picks[1], size: front * 0.8, radius: Radii.cover)),
              ),
            if (picks.isNotEmpty)
              Positioned(
                left: size * 0.10,
                bottom: size * 0.10,
                child: PlayOnce(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, p) => AnimatedBuilder(
                    animation: p,
                    builder: (context, child) => Transform.translate(offset: Offset(0, 14 * (1 - p.value)), child: Opacity(opacity: p.value, child: child)),
                    child: Stack(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Radii.cover),
                            boxShadow: [BoxShadow(color: t.bgBase.withValues(alpha: 0.5), blurRadius: size * 0.06)],
                          ),
                          child: CoverArt(url: picks.first, size: front, radius: Radii.cover),
                        ),
                        Positioned(
                          left: front * 0.07,
                          bottom: front * 0.07,
                          child: Container(
                            width: front * 0.2,
                            height: front * 0.2,
                            decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                            child: Center(child: NaviIcon(NaviGlyph.star, size: front * 0.12, color: t.onAccent)),
                          ),
                        ),
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
}
