import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/motion/play_once.dart';

/// Cells that fill in one after another, each as bright as its value (0..1;
/// 0 stays an empty outline-tone cell). The calendar strip, the streak
/// squares and the hour-of-day grid are all this widget with different data.
///
/// Cells run left to right in [rows] rows (column-major when [vertical],
/// which is how a calendar week reads). One painter, one controller.
class HeatGrid extends StatelessWidget {
  final List<double> values;
  final int rows;
  final double gap;
  final double radius;

  /// Cell edge; null fits the cells to the available width.
  final double? cell;
  final Color? color;
  final Color? emptyColor;

  /// Fill left to right, row by row (streaks), instead of down each column (calendars).
  final bool rowMajor;
  final Duration duration;
  final Animation<double>? progress;
  final String? semanticLabel;

  const HeatGrid({
    super.key,
    required this.values,
    this.rows = 1,
    this.gap = 3,
    this.radius = 3,
    this.cell,
    this.color,
    this.emptyColor,
    this.rowMajor = false,
    this.duration = const Duration(milliseconds: 1400),
    this.progress,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final cols = (values.length / rows).ceil();
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: LayoutBuilder(
        builder: (context, c) {
          final edge = cell ?? ((c.maxWidth - gap * (cols - 1)) / cols);
          final size = Size(cols * edge + (cols - 1) * gap, rows * edge + (rows - 1) * gap);
          return SizedBox(
            width: size.width,
            height: size.height,
            child: PlayOnce(
              progress: progress,
              duration: duration,
              curve: Curves.linear,
              builder: (context, p) => AnimatedBuilder(
                animation: p,
                builder: (context, _) => CustomPaint(
                  painter: HeatGridPainter(
                    values: values,
                    rows: rows,
                    gap: gap,
                    radius: radius,
                    edge: edge,
                    ink: color ?? t.accent,
                    empty: emptyColor ?? t.fill,
                    rowMajor: rowMajor,
                    cols: cols,
                    t: p.value,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HeatGridPainter extends CustomPainter {
  final List<double> values;
  final int rows;
  final double gap;
  final double radius;
  final double edge;
  final Color ink;
  final Color empty;
  final bool rowMajor;
  final int cols;
  final double t;
  const HeatGridPainter({
    required this.values,
    required this.rows,
    required this.gap,
    required this.radius,
    required this.edge,
    required this.ink,
    required this.empty,
    required this.rowMajor,
    required this.cols,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    // Cell i starts at i/n of the run and takes a few cells' worth to pop in.
    final pop = (6 / n).clamp(0.05, 0.4);
    final paint = Paint();
    for (var i = 0; i < n; i++) {
      final col = rowMajor ? i % cols : i ~/ rows, row = rowMajor ? i ~/ cols : i % rows;
      final start = (i / n) * (1 - pop);
      final k = sliceOf(t, start, start + pop, Curves.easeOutBack);
      final v = values[i].clamp(0.0, 1.0);
      final center = Offset(col * (edge + gap) + edge / 2, row * (edge + gap) + edge / 2);
      final half = edge / 2 * (0.4 + 0.6 * k.clamp(0.0, 1.2));
      paint.color = Color.lerp(empty, ink, v == 0 ? 0 : 0.28 + 0.72 * v)!.withValues(alpha: k.clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: half * 2, height: half * 2), Radius.circular(radius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(HeatGridPainter old) =>
      old.t != t || old.rowMajor != rowMajor || old.values != values || old.ink != ink || old.empty != empty || old.edge != edge;
}
