import 'package:flutter/widgets.dart';

import '../../../../core/theme.dart';

/// The hour (0–24, fractional) in an ISO timestamp, read as written so the
/// server's own clock isn't shifted into the phone's time zone. Null when the
/// string has no time.
double? hourOfTimestamp(String iso) {
  final m = RegExp(r'[T ](\d{2}):(\d{2})').firstMatch(iso);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h + min / 60;
}

String clockLabel(double hour) {
  final h = hour.floor();
  final m = ((hour - h) * 60).round().clamp(0, 59);
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// The day as a hairline ruler: hours already lived are bright, hours to come
/// are dim, and the current hour is a taller tick that settles into place.
class MomentLine extends StatelessWidget {
  final double hour;
  const MomentLine({super.key, required this.hour});

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Now ${clockLabel(hour)}',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduce ? hour : 0, end: hour),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (context, h, _) => SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _MomentPainter(
              hour: h,
              lived: t.textPrimary,
              ahead: t.textMuted.withValues(alpha: 0.45),
              labelStyle: t.caption2,
            ),
          ),
        ),
      ),
    );
  }
}

class _MomentPainter extends CustomPainter {
  final double hour;
  final Color lived;
  final Color ahead;
  final TextStyle labelStyle;
  const _MomentPainter({required this.hour, required this.lived, required this.ahead, required this.labelStyle});

  static const _labels = {0: '12 AM', 6: '6 AM', 12: 'Noon', 18: '6 PM'};

  @override
  void paint(Canvas canvas, Size size) {
    const ticks = 49; // every half hour, 0..24
    const tickTop = 0.0;
    const base = 18.0;
    final step = size.width / (ticks - 1);
    final p = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < ticks; i++) {
      final h = i / 2;
      final x = i * step;
      final major = i % 12 == 0; // 0, 6, 12, 18, 24
      final hourly = i.isEven;
      final len = major ? 14.0 : (hourly ? 9.0 : 5.0);
      final isNow = (h - hour).abs() < 0.25;
      p.color = h <= hour ? lived : ahead;
      if (isNow) continue; // drawn below
      canvas.drawLine(Offset(x, base - len + tickTop), Offset(x, base), p);
    }
    // The current moment: a taller, heavier tick exactly at [hour].
    final nowX = (hour / 24 * size.width).clamp(1.5, size.width - 1.5);
    canvas.drawLine(
      Offset(nowX, 0),
      Offset(nowX, base + 2),
      Paint()
        ..color = lived
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    for (final e in _labels.entries) {
      final tp = TextPainter(
        text: TextSpan(text: e.value, style: labelStyle.copyWith(color: ahead.withValues(alpha: 0.9))),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = e.key / 24 * size.width;
      final dx = (cx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(e.key == 0 ? 0 : dx, base + 8));
    }
  }

  @override
  bool shouldRepaint(_MomentPainter old) =>
      old.hour != hour || old.lived != lived || old.ahead != ahead || old.labelStyle != labelStyle;
}

/// Four short bars: how closely the mix is tuned (4 = this exact moment,
/// 1 = a cold start), beside the plain-language sentence.
class Closeness extends StatelessWidget {
  final int level; // PredictContext.fallbackLevel: 0 exact … 3 global
  final String label;
  const Closeness({super.key, required this.level, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final filled = (4 - level).clamp(1, 4);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < 4; i++) ...[
            Container(
              width: 4,
              height: 6.0 + i * 3,
              decoration: BoxDecoration(
                color: i < filled ? t.textPrimary : t.textMuted.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: 3),
          ],
          const SizedBox(width: Space.sm - 3),
          Expanded(child: Text(label, style: t.footnote)),
        ],
      ),
    );
  }
}
