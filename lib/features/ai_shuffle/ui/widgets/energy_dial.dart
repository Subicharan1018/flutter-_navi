import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
import 'taste_math.dart';

/// Calm ↔ Lively. Drag the knob and the mix reshapes around that energy. Until
/// it is touched the knob rests (dim) where the picks average out and the word
/// says "As picked".
class EnergyDial extends StatelessWidget {
  /// Where the knob rests / is held, 0..1.
  final double value;

  /// False until the listener has moved it.
  final bool active;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  const EnergyDial({super.key, required this.value, required this.active, required this.onChanged, required this.onReset});

  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      slider: true,
      label: 'Energy',
      value: active ? energyWord(value) : 'As picked',
      increasedValue: energyWord((value + 0.1).clamp(0.0, 1.0)),
      decreasedValue: energyWord((value - 0.1).clamp(0.0, 1.0)),
      onIncrease: () => onChanged((value + 0.1).clamp(0.0, 1.0)),
      onDecrease: () => onChanged((value - 0.1).clamp(0.0, 1.0)),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: Row(
              children: [
                Text(active ? energyWord(value) : 'As picked', style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (active)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 22),
                    onPressed: onReset,
                    child: Text('Reset', style: t.footnote.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          LayoutBuilder(builder: (context, box) {
            double at(Offset local) => (local.dx / box.maxWidth).clamp(0.0, 1.0);
            var lastStep = (value * 10).round();
            void move(Offset local) {
              final v = at(local);
              final step = (v * 10).round();
              if (step != lastStep) {
                lastStep = step;
                HapticFeedback.selectionClick();
              }
              onChanged(v);
            }

            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => move(d.localPosition),
                onHorizontalDragStart: (d) => move(d.localPosition),
                onHorizontalDragUpdate: (d) => move(d.localPosition),
                child: RepaintBoundary(
                  child: SizedBox(
                    height: height,
                    width: double.infinity,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: value),
                      // Follows the finger at once; eases only when it is set
                      // from outside (reset, accessibility steps).
                      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => CustomPaint(
                        painter: _DialPainter(v, active, t.textPrimary, t.textMuted.withValues(alpha: 0.45), t.caption2),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double v;
  final bool active;
  final Color ink;
  final Color dim;
  final TextStyle label;
  const _DialPainter(this.v, this.active, this.ink, this.dim, this.label);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final w = size.width - pad * 2;
    final y = 16.0;
    final knobX = pad + v * w;
    final p = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    // 21 ticks (every 5%); the ones the knob has passed are bright.
    for (var i = 0; i <= 20; i++) {
      final x = pad + i / 20 * w;
      final major = i % 5 == 0;
      final h = major ? 14.0 : 8.0;
      p.color = active && x <= knobX ? ink : dim;
      canvas.drawLine(Offset(x, y - h / 2), Offset(x, y + h / 2), p);
    }
    // The knob: a white disc on the ticks; dim and hollow while untouched.
    if (active) {
      canvas.drawCircle(Offset(knobX, y), 8, Paint()..color = ink);
    } else {
      canvas.drawCircle(
          Offset(knobX, y),
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = ink.withValues(alpha: 0.6));
    }
    for (final e in [(('Calm'), 0.0), (('Lively'), 1.0)]) {
      final tp = TextPainter(text: TextSpan(text: e.$1, style: label.copyWith(color: dim.withValues(alpha: 0.9))), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(e.$2 == 0 ? 0 : size.width - tp.width, 32));
    }
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.v != v || o.active != active || o.ink != ink || o.dim != dim;
}
