import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/motion/play_once.dart';
import 'stat_card.dart' show figureStyle;

/// The listening streak as a paper ticket: white stock with a notch cut into
/// each side at the perforation, the streak as the big stub number in black
/// ink, and the last fourteen days as a strip of holes punched one after
/// another (a punched day is a day you listened). The form is the metaphor: a
/// streak is a run of punches on a card.
///
/// The punches play once on entry; there is no loop.
class StreakTicket extends StatelessWidget {
  static const int days = 14;
  final int streak;

  /// The last [days] days, oldest first, true where something was played.
  /// Without the history, the days of the streak are the ones punched.
  final List<bool>? listened;
  const StreakTicket({super.key, required this.streak, this.listened});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final punched = listened ??
        [for (var i = 0; i < days; i++) i >= days - streak.clamp(0, days)];
    final ink = t.onAccent;
    return Semantics(
      container: true,
      label: '$streak day listening streak',
      child: ExcludeSemantics(
        child: ClipPath(
          clipper: const _TicketClipper(stub: 108, notch: 9),
          child: ColoredBox(
            color: t.accent,
            child: SizedBox(
              height: 92,
              child: Row(
                children: [
                  SizedBox(
                    width: 108,
                    child: Padding(
                      padding: const EdgeInsets.only(left: Space.lg),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$streak', style: figureStyle(t, 40).copyWith(color: ink, height: 0.95)),
                          const SizedBox(height: Space.xxs),
                          Text(
                            streak == 1 ? 'DAY STREAK' : 'DAY STREAK',
                            style: t.caption2.copyWith(color: ink.withValues(alpha: 0.6), letterSpacing: 1.1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.lg + 4, 0, Space.lg, 0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 14,
                            child: PlayOnce(
                              duration: const Duration(milliseconds: 1200),
                              curve: Curves.linear,
                              builder: (context, p) => AnimatedBuilder(
                                animation: p,
                                builder: (context, _) => CustomPaint(
                                  size: const Size(double.infinity, 14),
                                  painter: _PunchPainter(punched, ink, p.value),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.sm),
                          Text(
                            'Last 14 days',
                            style: t.caption2.copyWith(color: ink.withValues(alpha: 0.6), letterSpacing: 0.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketClipper extends CustomClipper<Path> {
  final double stub;
  final double notch;
  const _TicketClipper({required this.stub, required this.notch});

  @override
  Path getClip(Size size) {
    final body = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)));
    // Half-circle bites at the perforation, top and bottom.
    final bites = Path()
      ..addOval(Rect.fromCircle(center: Offset(stub, 0), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(stub, size.height), radius: notch));
    return Path.combine(PathOperation.difference, body, bites);
  }

  @override
  bool shouldReclip(_TicketClipper old) => old.stub != stub || old.notch != notch;
}

class _PunchPainter extends CustomPainter {
  final List<bool> punched;
  final Color ink;
  final double t;
  const _PunchPainter(this.punched, this.ink, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const n = StreakTicket.days;
    final slot = size.width / n;
    final r = (slot / 2 - 1.5).clamp(2.0, 5.5);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: 0.25);
    final hole = Paint()..color = ink;
    final lit = punched.where((p) => p).length;
    var order = 0;
    for (var i = 0; i < n; i++) {
      final c = Offset(slot * (i + 0.5), size.height / 2);
      canvas.drawCircle(c, r, ring);
      if (!punched[i]) continue;
      final k = ((t * (lit + 2) - order++) / 2).clamp(0.0, 1.0);
      if (k > 0) canvas.drawCircle(c, r * k, hole);
    }
  }

  @override
  bool shouldRepaint(_PunchPainter old) =>
      old.t != t || !listEquals(old.punched, punched) || old.ink != ink;
}
