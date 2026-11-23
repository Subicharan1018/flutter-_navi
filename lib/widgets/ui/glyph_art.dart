import 'package:flutter/widgets.dart';

import '../../core/theme.dart';
import '../art/navi_icons.dart';
import '../cover_art.dart';

/// Art for a smart collection that is not a playlist (Favorites, Highlights,
/// Start Listening): a tinted opaque ground with its glyph set large, and the
/// lead cover tucked into the corner as a small tile. Colour comes from the
/// [tint] token, so each collection has its own warmth without new literals.
class GlyphArt extends StatelessWidget {
  final NaviGlyph glyph;
  final Color tint;
  final String? coverUrl;
  final double size;
  final double radius;

  const GlyphArt({
    super.key,
    required this.glyph,
    required this.tint,
    required this.size,
    this.coverUrl,
    this.radius = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final ground = Color.lerp(t.bgBase, tint, 0.88)!;
    final ink = t.bgBase;
    final c = size * 0.30;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: ground,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              Positioned(
                left: size * 0.10,
                top: size * 0.10,
                child: NaviIcon(glyph, size: size * 0.46, color: ink),
              ),
              if (coverUrl != null && coverUrl!.isNotEmpty)
                Positioned(
                  right: size * 0.09,
                  bottom: size * 0.09,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.cover),
                      boxShadow: [BoxShadow(color: ink.withValues(alpha: 0.35), blurRadius: size * 0.05)],
                    ),
                    child: CoverArt(url: coverUrl, size: c, radius: Radii.cover),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
