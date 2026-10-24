import 'package:flutter/material.dart';

// =============================================================================
// NaviVibe's own glyphs. Drawn on a 24-unit grid with round caps and a 1.75
// stroke so they sit together as one family. Tabs use the outline form when
// idle and a heavier/filled form when selected.
//
// Glyphs size and tint like an Icon; the caller owns the tap target (every
// call site already wraps these in a >= 44 button).
// =============================================================================

enum NaviGlyph {
  home,
  search,
  aiShuffle,
  dashboard,
  library,
  play,
  shuffle,
  addToPlaylist,
}

class NaviIcon extends StatelessWidget {
  final NaviGlyph glyph;
  final double size;
  final Color? color;
  final bool filled;

  const NaviIcon(
    this.glyph, {
    super.key,
    this.size = 24,
    this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? Colors.white;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: NaviGlyphPainter(glyph, tint, filled),
      ),
    );
  }
}

class NaviGlyphPainter extends CustomPainter {
  final NaviGlyph glyph;
  final Color color;
  final bool filled;
  const NaviGlyphPainter(this.glyph, this.color, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = filled ? 2.3 : 1.75
      ..color = color;
    final fill = Paint()..color = color;
    final solid = filled ? fill : stroke;

    switch (glyph) {
      case NaviGlyph.home:
        final p = Path()
          ..moveTo(4, 10.5)
          ..lineTo(12, 4)
          ..lineTo(20, 10.5)
          ..lineTo(20, 19.5)
          ..lineTo(14.5, 19.5)
          ..lineTo(14.5, 14)
          ..lineTo(9.5, 14)
          ..lineTo(9.5, 19.5)
          ..lineTo(4, 19.5)
          ..close();
        canvas.drawPath(p, solid);
        if (filled) canvas.drawPath(p, stroke);
      case NaviGlyph.search:
        canvas.drawCircle(const Offset(10.5, 10.5), 6.2, stroke);
        canvas.drawLine(const Offset(15.2, 15.2), const Offset(20, 20), stroke);
      case NaviGlyph.aiShuffle:
        const xs = [4.0, 8.0, 12.0, 16.0, 20.0];
        const half = [2.0, 5.0, 8.0, 4.0, 2.5];
        for (var i = 0; i < xs.length; i++) {
          canvas.drawLine(
            Offset(xs[i], 12 - half[i]),
            Offset(xs[i], 12 + half[i]),
            stroke..strokeWidth = filled ? 2.6 : 1.9,
          );
        }
      case NaviGlyph.dashboard:
        const bars = [
          Rect.fromLTRB(4, 12, 8.5, 20),
          Rect.fromLTRB(9.75, 7, 14.25, 20),
          Rect.fromLTRB(15.5, 3.5, 20, 20),
        ];
        for (final r in bars) {
          final rr = RRect.fromRectAndRadius(r, const Radius.circular(1.5));
          canvas.drawRRect(rr, solid);
          if (filled) canvas.drawRRect(rr, stroke);
        }
      case NaviGlyph.library:
        canvas.drawLine(const Offset(7, 3.5), const Offset(17, 3.5), stroke);
        canvas.drawCircle(const Offset(12, 13.5), 7, solid);
        canvas.drawCircle(
          const Offset(12, 13.5),
          2.2,
          filled ? (Paint()..color = const Color(0x66000000)) : stroke,
        );
      case NaviGlyph.play:
        final p = Path()
          ..moveTo(8, 5.5)
          ..lineTo(18.5, 12)
          ..lineTo(8, 18.5)
          ..close();
        canvas.drawPath(p, fill);
        canvas.drawPath(p, stroke..strokeWidth = 2);
      case NaviGlyph.shuffle:
        final a = Path()
          ..moveTo(4, 7)
          ..lineTo(7.5, 7)
          ..cubicTo(12.5, 7, 11.5, 17, 16.5, 17)
          ..lineTo(20, 17);
        final b = Path()
          ..moveTo(4, 17)
          ..lineTo(7.5, 17)
          ..cubicTo(9, 17, 10, 16.4, 10.8, 15.4);
        final c = Path()
          ..moveTo(13.2, 8.6)
          ..cubicTo(14, 7.6, 15, 7, 16.5, 7)
          ..lineTo(20, 7);
        canvas.drawPath(a, stroke);
        canvas.drawPath(b, stroke);
        canvas.drawPath(c, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(18, 4.5)
            ..lineTo(20.5, 7)
            ..lineTo(18, 9.5),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(18, 14.5)
            ..lineTo(20.5, 17)
            ..lineTo(18, 19.5),
          stroke,
        );
      case NaviGlyph.addToPlaylist:
        canvas.drawLine(const Offset(4, 7), const Offset(14, 7), stroke);
        canvas.drawLine(const Offset(4, 12), const Offset(14, 12), stroke);
        canvas.drawLine(const Offset(4, 17), const Offset(10, 17), stroke);
        canvas.drawLine(const Offset(18, 12), const Offset(18, 18.5), stroke);
        canvas.drawLine(const Offset(14.75, 15.25), const Offset(21.25, 15.25), stroke);
    }
  }

  @override
  bool shouldRepaint(NaviGlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.filled != filled;
}
