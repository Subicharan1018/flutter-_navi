import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../cover_art.dart';
import '../../motion/play_once.dart';
import 'blur_ground.dart';

/// A year as a poster: the number cut in two, "20" over "26", set huge in
/// white over a soft ground of the year's top cover, with a band of the
/// year's top songs running between the halves. The covers slide in from the
/// right once. Replay's identity is the year and what you played in it.
class YearPoster extends StatelessWidget {
  final int year;
  final List<String?> urls;
  final double size;
  final double radius;
  final String label;

  const YearPoster({
    super.key,
    required this.year,
    required this.urls,
    required this.size,
    this.label = 'REPLAY',
    this.radius = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final covers = <String>{
      for (final u in urls)
        if (u != null && u.isNotEmpty) u,
    }.take(4).toList();
    final s = '$year';
    final head = s.length >= 4 ? s.substring(0, s.length - 2) : s;
    final tail = s.length >= 4 ? s.substring(s.length - 2) : '';
    final fs = size * 0.33;
    final band = size * 0.22;
    final style = t.largeTitle.copyWith(color: t.accent, fontSize: fs, height: 0.86, letterSpacing: -fs * 0.04);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Positioned.fill(child: BlurGround(url: covers.firstOrNull, scrim: 0.45)),
            Positioned(left: size * 0.08, top: size * 0.07, child: Text(head, style: style)),
            Positioned(left: size * 0.08, bottom: size * 0.07, child: Text(tail, style: style)),
            Positioned(
              right: size * 0.08,
              top: size * 0.08,
              child: Text(label, style: t.caption2.copyWith(color: t.accent, letterSpacing: 1.4)),
            ),
            if (covers.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: (size - band) / 2,
                height: band,
                child: PlayOnce(
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.linear,
                  builder: (context, p) => AnimatedBuilder(
                    animation: p,
                    builder: (context, _) => Row(
                      children: [
                        for (final (i, u) in covers.indexed)
                          Expanded(
                            child: Transform.translate(
                              offset: Offset(
                                size * 0.6 * (1 - Curves.easeOutCubic.transform(((p.value - i * 0.12) / 0.6).clamp(0.0, 1.0))),
                                0,
                              ),
                              child: CoverArt(url: u, size: size / covers.length, radius: 0),
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
