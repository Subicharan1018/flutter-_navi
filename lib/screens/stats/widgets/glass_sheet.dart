import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/motion/ambient_loop.dart';

/// A frosted sheet over the listener's own art: the top artist's picture,
/// decoded tiny and scaled up so it is soft without a blur filter, drifting
/// very slowly behind a dark scrim and a hairline edge. The picture is the
/// data (who you listened to), and the drift is the card's own surface.
///
/// The only motion is a slow pan/zoom of one pre-rasterised bitmap at about
/// 30 fps, while the card is on screen and Motion is Full; otherwise the
/// still frame shows, which is composed to look finished.
class GlassSheet extends StatelessWidget {
  final String? coverUrl;
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  const GlassSheet({
    super.key,
    required this.child,
    this.coverUrl,
    this.radius = 22,
    this.padding = const EdgeInsets.all(Space.xl),
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final has = coverUrl != null && coverUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: t.outline, width: 0.5),
        ),
        child: Stack(
          children: [
            if (has)
              Positioned.fill(
                child: AmbientLoop(
                  period: const Duration(seconds: 24),
                  builder: (context, phase) {
                    final a = phase * 6.2831853;
                    return Transform.translate(
                      offset: Offset(18 * math.sin(a), 12 * math.sin(a + 1.6)),
                      child: Transform.scale(
                        scale: 1.35 + 0.05 * math.sin(a * 0.5),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: CoverArt(url: coverUrl, size: 36, radius: 0),
                        ),
                      ),
                    );
                  },
                ),
              ),
            // Scrim: keeps the white type readable on any cover.
            Positioned.fill(child: ColoredBox(color: t.bgBase.withValues(alpha: has ? 0.62 : 0))),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
