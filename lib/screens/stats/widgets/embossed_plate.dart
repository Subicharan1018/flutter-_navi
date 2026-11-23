import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/motion/play_once.dart';

/// A soft embossed plate for the listening dial: a slightly raised dark slab
/// lit from the top-left (a pale shadow up there, a deep one below right), so
/// the 24-hour dial reads as a physical instrument. One light sweep crosses
/// it on entry, then it rests; there is no loop.
class EmbossedPlate extends StatelessWidget {
  final Widget child;
  final double radius;
  const EmbossedPlate({super.key, required this.child, this.radius = 28});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final slab = Color.lerp(t.bgBase, t.textPrimary, 0.07)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: slab,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(color: t.textPrimary.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(-6, -6)),
          BoxShadow(color: t.bgBase.withValues(alpha: 0.9), blurRadius: 18, offset: const Offset(8, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Padding(padding: const EdgeInsets.all(Space.md), child: child),
            Positioned.fill(
              child: IgnorePointer(
                child: PlayOnce(
                  duration: const Duration(milliseconds: 1400),
                  delay: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  builder: (context, p) => AnimatedBuilder(
                    animation: p,
                    builder: (context, _) => CustomPaint(painter: _SweepPainter(t.textPrimary, p.value)),
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

class _SweepPainter extends CustomPainter {
  final Color light;
  final double t;
  const _SweepPainter(this.light, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final x = -size.width * 0.4 + size.width * 1.8 * t;
    final band = size.width * 0.35;
    final rect = Rect.fromLTWH(x - band, 0, band * 2, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [light.withValues(alpha: 0), light.withValues(alpha: 0.07), light.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.t != t || old.light != light;
}
