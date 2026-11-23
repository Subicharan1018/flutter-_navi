import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../cover_art.dart';

/// A soft ground made from one of the listener's own covers: the cover is
/// decoded tiny and scaled up (soft without any blur filter), then dimmed by a
/// scrim so white type and other covers sit on it. With no cover it is the
/// plain elevated surface.
class BlurGround extends StatelessWidget {
  final String? url;
  final double scrim;
  const BlurGround({super.key, this.url, this.scrim = 0.55});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final has = url != null && url!.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: t.bgElevated),
        if (has)
          ClipRect(
            child: Transform.scale(
              scale: 1.3,
              child: FittedBox(fit: BoxFit.cover, child: CoverArt(url: url, size: 36, radius: 0)),
            ),
          ),
        if (has) ColoredBox(color: t.bgBase.withValues(alpha: scrim)),
      ],
    );
  }
}
