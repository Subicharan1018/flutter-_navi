import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/motion/play_once.dart';

/// A streak as a row of days: the last fourteen, lit gold for each day of the
/// streak, lighting up one after another from the oldest. A streak longer
/// than fourteen days shows a full row. Replaces a bare number with the thing
/// itself.
class StreakDots extends StatelessWidget {
  static const int days = 14;
  final int streak;
  const StreakDots({super.key, required this.streak});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final lit = streak.clamp(0, days);
    return SizedBox(
      height: 10,
      child: PlayOnce(
        duration: const Duration(milliseconds: 1100),
        curve: Curves.linear,
        builder: (context, p) => AnimatedBuilder(
          animation: p,
          builder: (context, _) => CustomPaint(
            size: const Size(double.infinity, 10),
            painter: _DotsPainter(lit, t.gold, t.fill, p.value),
          ),
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final int lit;
  final Color on;
  final Color off;
  final double t;
  const _DotsPainter(this.lit, this.on, this.off, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const n = StreakDots.days;
    final r = (size.width / n / 2 - 1.5).clamp(1.5, 4.5);
    final slot = size.width / n;
    for (var i = 0; i < n; i++) {
      // Days run oldest to newest; the lit ones are the newest `lit`.
      final isLit = i >= n - lit;
      final order = i - (n - lit); // 0 for the first lit day
      final k = isLit ? ((t * (lit + 2) - order) / 2).clamp(0.0, 1.0) : 0.0;
      canvas.drawCircle(Offset(slot * (i + 0.5), size.height / 2), r, Paint()..color = off);
      if (k > 0) canvas.drawCircle(Offset(slot * (i + 0.5), size.height / 2), r * k, Paint()..color = on);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.t != t || old.lit != lit || old.on != on || old.off != off;
}
