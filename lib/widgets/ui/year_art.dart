import 'package:flutter/widgets.dart';

import '../../core/theme.dart';
import '../cover_art.dart';

/// A year as art: the number set huge in black on a white ground, with a
/// ribbon of overlapping covers (the year's top songs) running along the
/// foot. Replay's identity is the year, not a grid of covers.
class YearArt extends StatelessWidget {
  final int year;
  final String label;
  final List<String?> urls;
  final double size;
  final double radius;

  const YearArt({super.key, required this.year, required this.urls, required this.size, this.label = 'Replay', this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final covers = <String>{
      for (final u in urls)
        if (u != null && u.isNotEmpty) u,
    }.take(5).toList();
    final pad = size * 0.09;
    final c = size * 0.22;
    final step = c * 0.62;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: t.accent,
        child: SizedBox.square(
          dimension: size,
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.title3.copyWith(color: t.bgBase.withValues(alpha: 0.6), fontSize: size * 0.085)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$year',
                    style: t.largeTitle.copyWith(color: t.bgBase, fontSize: size * 0.30, height: 1.0, letterSpacing: -size * 0.012),
                  ),
                ),
                const Spacer(),
                if (covers.isNotEmpty)
                  SizedBox(
                    height: c,
                    width: step * (covers.length - 1) + c,
                    child: Stack(
                      children: [
                        // Later covers sit under earlier ones: the top song is in front.
                        for (var i = covers.length - 1; i >= 0; i--)
                          Positioned(
                            left: step * i,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(Radii.thumb),
                                border: Border.all(color: t.accent, width: size * 0.012),
                              ),
                              child: CoverArt(url: covers[i], size: c, radius: Radii.thumb),
                            ),
                          ),
                      ],
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
