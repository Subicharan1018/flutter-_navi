import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../cover_art.dart';
import '../../motion/play_once.dart';

/// Favorites as a night sky: one star per favourite scattered on a dark ground
/// (up to a dozen), popping in one after another, with the lead cover as the
/// moon they sit around. Opaque, monochrome, nothing like a cover grid.
class FavoritesSky extends StatelessWidget {
  final String? coverUrl;
  final int count;
  final double size;
  final double radius;

  const FavoritesSky({super.key, required this.size, this.coverUrl, this.count = 12, this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final n = count.clamp(5, 12);
    final moon = size * 0.40;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: t.bgElevated,
        child: SizedBox.square(
          dimension: size,
          child: PlayOnce(
            duration: const Duration(milliseconds: 1600),
            curve: Curves.linear,
            builder: (context, p) => Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: p,
                    builder: (context, _) => CustomPaint(painter: _SkyPainter(n, t.accent, p.value)),
                  ),
                ),
                if (coverUrl != null && coverUrl!.isNotEmpty)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: t.accent, width: size * 0.012),
                    ),
                    child: CoverArt(url: coverUrl, size: moon, circular: true),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  final int n;
  final Color color;
  final double t;
  const _SkyPainter(this.n, this.color, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint();
    for (var i = 0; i < n; i++) {
      // A golden-angle spiral: even spread, the same every time.
      final a = i * 2.39996;
      final r = size.width * (0.24 + 0.13 * ((i * 7) % n) / n);
      final at = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      final start = i / (n + 2);
      final k = Curves.easeOutBack.transform(((t - start) / 0.4).clamp(0.0, 1.0));
      if (k <= 0) continue;
      final s = size.width * (0.022 + 0.014 * ((i * 5) % 4)) * k;
      paint.color = color.withValues(alpha: 0.45 + 0.55 * ((i * 3) % 5) / 4);
      final path = Path()
        ..moveTo(at.dx, at.dy - s * 2)
        ..quadraticBezierTo(at.dx, at.dy, at.dx + s * 2, at.dy)
        ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + s * 2)
        ..quadraticBezierTo(at.dx, at.dy, at.dx - s * 2, at.dy)
        ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - s * 2);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.t != t || old.n != n || old.color != color;
}
