import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../cover_art.dart';
import '../../motion/play_once.dart';

/// Start Listening as three of the library's covers changing places: they
/// start in a column on the left and ride crossing lines to swapped rows on
/// the right, on a white ground. They travel once and rest at the far end.
class ShuffleTrails extends StatelessWidget {
  final List<String?> urls;
  final double size;
  final double radius;
  const ShuffleTrails({super.key, required this.size, this.urls = const [], this.radius = 0});

  static const _from = [0.22, 0.50, 0.78];
  static const _to = [0.78, 0.22, 0.50];

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final picks = <String?>[
      ...{
        for (final u in urls)
          if (u != null && u.isNotEmpty) u,
      }.take(3),
    ];
    while (picks.length < 3) {
      picks.add(null);
    }
    final c = size * 0.24;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: t.accent,
        child: SizedBox.square(
          dimension: size,
          child: PlayOnce(
            duration: const Duration(milliseconds: 1500),
            curve: Curves.linear,
            builder: (context, p) => AnimatedBuilder(
              animation: p,
              builder: (context, _) => Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _LinesPainter(t.onAccent))),
                  for (var i = 0; i < 3; i++) _rider(picks[i], i, c, p.value),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rider(String? url, int i, double c, double clock) {
    final k = Curves.easeInOutCubic.transform(((clock - i * 0.12) / 0.76).clamp(0.0, 1.0));
    final a = Offset(size * 0.17, size * _from[i]);
    final b = Offset(size * 0.83, size * _to[i]);
    final u = 1 - k;
    final pos = Offset(
      a.dx * u * u * u + 3 * size * 0.5 * u * u * k + 3 * size * 0.5 * u * k * k + b.dx * k * k * k,
      a.dy * (u * u * u + 3 * u * u * k) + b.dy * (3 * u * k * k + k * k * k),
    );
    return Positioned(
      left: pos.dx - c / 2,
      top: pos.dy - c / 2,
      child: CoverArt(url: url, size: c, radius: Radii.cover),
    );
  }
}

class _LinesPainter extends CustomPainter {
  final Color ink;
  const _LinesPainter(this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.008
      ..color = ink.withValues(alpha: 0.85);
    for (var i = 0; i < 3; i++) {
      final a = Offset(w * 0.17, w * ShuffleTrails._from[i]);
      final b = Offset(w * 0.83, w * ShuffleTrails._to[i]);
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..cubicTo(w * 0.5, a.dy, w * 0.5, b.dy, b.dx, b.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => old.ink != ink;
}
