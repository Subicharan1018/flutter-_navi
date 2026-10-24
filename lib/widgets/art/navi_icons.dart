import 'dart:math' show pi, cos, sin;

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
  heart,
  pause,
  next,
  previous,
  queue,
  download,
  share,
  more,
  repeat,
  sliders,
  clock,
  person,
  trending,
  lyrics,
  mic,
  folder,
  smart,
  plus,
  minus,
  chevron,
  check,
  trash,
  edit,
  pin,
  star,
  close,
  block,
  flow,
  calendar,
  flame,
  sparkle,
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
      case NaviGlyph.heart:
        final p = Path()
          ..moveTo(12, 20)
          ..cubicTo(6, 15.5, 3.5, 12, 3.5, 8.7)
          ..cubicTo(3.5, 6.3, 5.3, 4.5, 7.6, 4.5)
          ..cubicTo(9.5, 4.5, 11.1, 5.5, 12, 7)
          ..cubicTo(12.9, 5.5, 14.5, 4.5, 16.4, 4.5)
          ..cubicTo(18.7, 4.5, 20.5, 6.3, 20.5, 8.7)
          ..cubicTo(20.5, 12, 18, 15.5, 12, 20)
          ..close();
        canvas.drawPath(p, solid);
        if (filled) canvas.drawPath(p, stroke);
      case NaviGlyph.pause:
        for (final x in const [6.5, 14.0]) {
          final rr = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 5, 3.5, 14),
            const Radius.circular(1.5),
          );
          canvas.drawRRect(rr, fill);
          canvas.drawRRect(rr, stroke..strokeWidth = 1.5);
        }
      case NaviGlyph.next:
        _skip(canvas, stroke, fill, forward: true);
      case NaviGlyph.previous:
        _skip(canvas, stroke, fill, forward: false);
      case NaviGlyph.queue:
        canvas.drawLine(const Offset(4, 7), const Offset(20, 7), stroke);
        canvas.drawLine(const Offset(4, 12), const Offset(20, 12), stroke);
        canvas.drawLine(const Offset(4, 17), const Offset(11, 17), stroke);
        final tri = Path()
          ..moveTo(15, 14.5)
          ..lineTo(20, 17.5)
          ..lineTo(15, 20.5)
          ..close();
        canvas.drawPath(tri, solid);
        if (filled) canvas.drawPath(tri, stroke);
      case NaviGlyph.download:
        canvas.drawLine(const Offset(12, 4), const Offset(12, 15), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(7.5, 10.5)
            ..lineTo(12, 15)
            ..lineTo(16.5, 10.5),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(4.5, 15.5)
            ..lineTo(4.5, 19.5)
            ..lineTo(19.5, 19.5)
            ..lineTo(19.5, 15.5),
          stroke,
        );
      case NaviGlyph.share:
        canvas.drawLine(const Offset(12, 14.5), const Offset(12, 4), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(8, 7.5)
            ..lineTo(12, 4)
            ..lineTo(16, 7.5),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8, 11)
            ..lineTo(5.5, 11)
            ..lineTo(5.5, 20)
            ..lineTo(18.5, 20)
            ..lineTo(18.5, 11)
            ..lineTo(16, 11),
          stroke,
        );
      case NaviGlyph.more:
        for (final x in const [5.0, 12.0, 19.0]) {
          canvas.drawCircle(Offset(x, 12), filled ? 2.2 : 1.7, fill);
        }
      case NaviGlyph.repeat:
        canvas.drawPath(
          Path()
            ..moveTo(5, 11)
            ..lineTo(5, 9.5)
            ..cubicTo(5, 8, 6, 7, 7.5, 7)
            ..lineTo(18, 7),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(15.5, 4.5)
            ..lineTo(18, 7)
            ..lineTo(15.5, 9.5),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(19, 13)
            ..lineTo(19, 14.5)
            ..cubicTo(19, 16, 18, 17, 16.5, 17)
            ..lineTo(6, 17),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8.5, 14.5)
            ..lineTo(6, 17)
            ..lineTo(8.5, 19.5),
          stroke,
        );
      case NaviGlyph.sliders:
        const rows = [
          (6.0, 9.0),
          (12.0, 15.0),
          (18.0, 8.0),
        ];
        for (final (y, x) in rows) {
          canvas.drawLine(Offset(4, y), Offset(x - 2.9, y), stroke);
          canvas.drawLine(Offset(x + 2.9, y), Offset(20, y), stroke);
          canvas.drawCircle(Offset(x, y), 2.2, solid);
        }
      case NaviGlyph.clock:
        canvas.drawCircle(const Offset(12, 12), 8, solid);
        canvas.drawPath(
          Path()
            ..moveTo(12, 7.5)
            ..lineTo(12, 12)
            ..lineTo(15.5, 14),
          filled ? (Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 2
            ..color = const Color(0x99000000)) : stroke,
        );
      case NaviGlyph.person:
        canvas.drawCircle(const Offset(12, 8.5), 3.5, solid);
        final body = Path()
          ..moveTo(5, 20)
          ..cubicTo(5, 15.5, 8, 14, 12, 14)
          ..cubicTo(16, 14, 19, 15.5, 19, 20);
        canvas.drawPath(body, filled ? (Paint()..color = color) : stroke);
        if (filled) canvas.drawPath(body, stroke);
      case NaviGlyph.trending:
        canvas.drawPath(
          Path()
            ..moveTo(3.5, 16)
            ..lineTo(9, 10.5)
            ..lineTo(13, 14)
            ..lineTo(20.5, 6.5),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(15.5, 6.5)
            ..lineTo(20.5, 6.5)
            ..lineTo(20.5, 11.5),
          stroke,
        );
      case NaviGlyph.lyrics:
        final bubble = Path()
          ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTRB(4, 5, 20, 16.5),
            const Radius.circular(3),
          ))
          ..moveTo(9, 16.5)
          ..lineTo(8, 20)
          ..lineTo(12.5, 16.5);
        canvas.drawPath(bubble, solid);
        if (filled) canvas.drawPath(bubble, stroke);
        final ink = filled
            ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 1.75
              ..color = const Color(0x99000000))
            : stroke;
        canvas.drawLine(const Offset(8, 9.5), const Offset(16, 9.5), ink);
        canvas.drawLine(const Offset(8, 12.5), const Offset(13, 12.5), ink);
      case NaviGlyph.mic:
        final capsule = RRect.fromRectAndRadius(
          const Rect.fromLTRB(9, 3.5, 15, 14.5),
          const Radius.circular(3),
        );
        canvas.drawRRect(capsule, solid);
        if (filled) canvas.drawRRect(capsule, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(5.5, 11.5)
            ..cubicTo(5.5, 15.5, 8.5, 17.5, 12, 17.5)
            ..cubicTo(15.5, 17.5, 18.5, 15.5, 18.5, 11.5),
          stroke,
        );
        canvas.drawLine(const Offset(12, 17.5), const Offset(12, 20.5), stroke);
      case NaviGlyph.folder:
        final p = Path()
          ..moveTo(3.5, 17.5)
          ..lineTo(3.5, 6.5)
          ..quadraticBezierTo(3.5, 5.5, 4.5, 5.5)
          ..lineTo(9.5, 5.5)
          ..lineTo(11.5, 8)
          ..lineTo(19.5, 8)
          ..quadraticBezierTo(20.5, 8, 20.5, 9)
          ..lineTo(20.5, 17.5)
          ..quadraticBezierTo(20.5, 18.5, 19.5, 18.5)
          ..lineTo(4.5, 18.5)
          ..quadraticBezierTo(3.5, 18.5, 3.5, 17.5)
          ..close();
        canvas.drawPath(p, solid);
        if (filled) canvas.drawPath(p, stroke);
      case NaviGlyph.smart:
        // A four-point sparkle with a small companion.
        final p = Path()
          ..moveTo(10.5, 3.5)
          ..quadraticBezierTo(11.2, 9.8, 17.5, 10.5)
          ..quadraticBezierTo(11.2, 11.2, 10.5, 17.5)
          ..quadraticBezierTo(9.8, 11.2, 3.5, 10.5)
          ..quadraticBezierTo(9.8, 9.8, 10.5, 3.5)
          ..close();
        canvas.drawPath(p, solid);
        if (filled) canvas.drawPath(p, stroke);
        canvas.drawCircle(const Offset(18, 17.5), 1.1, fill);
        canvas.drawLine(const Offset(18, 4.5), const Offset(18, 7.5), stroke);
        canvas.drawLine(const Offset(16.5, 6), const Offset(19.5, 6), stroke);
      case NaviGlyph.plus:
        canvas.drawLine(const Offset(12, 5), const Offset(12, 19), stroke);
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), stroke);
      case NaviGlyph.minus:
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), stroke);
      case NaviGlyph.chevron:
        canvas.drawPath(
          Path()
            ..moveTo(9.5, 5.5)
            ..lineTo(16, 12)
            ..lineTo(9.5, 18.5),
          stroke,
        );
      case NaviGlyph.block:
        canvas.drawCircle(const Offset(12, 12), 8, stroke);
        canvas.drawLine(const Offset(6.4, 6.4), const Offset(17.6, 17.6), stroke);
      case NaviGlyph.flow:
        for (final dy in const [0.0, 5.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(3.5, 9.5 + dy)
              ..cubicTo(6, 5.5 + dy, 9, 5.5 + dy, 12, 9.5 + dy)
              ..cubicTo(15, 13.5 + dy, 18, 13.5 + dy, 20.5, 9.5 + dy),
            stroke,
          );
        }
      case NaviGlyph.calendar:
        final page = RRect.fromRectAndRadius(const Rect.fromLTRB(4, 6, 20, 20), const Radius.circular(3));
        canvas.drawRRect(page, solid);
        if (filled) canvas.drawRRect(page, stroke);
        final rule = filled
            ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 1.75
              ..color = const Color(0x99000000))
            : stroke;
        canvas.drawLine(const Offset(4, 10.5), const Offset(20, 10.5), rule);
        canvas.drawLine(const Offset(8, 3.5), const Offset(8, 7.5), stroke);
        canvas.drawLine(const Offset(16, 3.5), const Offset(16, 7.5), stroke);
      case NaviGlyph.flame:
        final p = Path()
          ..moveTo(12, 3.5)
          ..cubicTo(12, 8, 17, 9.5, 17, 14.5)
          ..cubicTo(17, 17.8, 14.8, 20, 12, 20)
          ..cubicTo(9.2, 20, 7, 17.8, 7, 14.5)
          ..cubicTo(7, 12.5, 8, 11, 9.5, 9.8)
          ..cubicTo(9.7, 11.5, 10.5, 12.3, 11.3, 12.5)
          ..cubicTo(11.2, 9, 11, 6, 12, 3.5)
          ..close();
        canvas.drawPath(p, solid);
        if (filled) canvas.drawPath(p, stroke);
      case NaviGlyph.sparkle:
        final p = Path()
          ..moveTo(12, 3.5)
          ..quadraticBezierTo(12.8, 10.5, 20.5, 12)
          ..quadraticBezierTo(12.8, 13.5, 12, 20.5)
          ..quadraticBezierTo(11.2, 13.5, 3.5, 12)
          ..quadraticBezierTo(11.2, 10.5, 12, 3.5)
          ..close();
        canvas.drawPath(p, solid);
        if (filled) canvas.drawPath(p, stroke);
      case NaviGlyph.check:
        canvas.drawPath(
          Path()
            ..moveTo(5, 12.5)
            ..lineTo(10, 17.5)
            ..lineTo(19, 7),
          stroke,
        );
      case NaviGlyph.trash:
        canvas.drawLine(const Offset(4.5, 7), const Offset(19.5, 7), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(9, 7)
            ..lineTo(9, 4.5)
            ..lineTo(15, 4.5)
            ..lineTo(15, 7),
          stroke,
        );
        final body = Path()
          ..moveTo(6.5, 7)
          ..lineTo(7.5, 19.5)
          ..lineTo(16.5, 19.5)
          ..lineTo(17.5, 7);
        canvas.drawPath(body, stroke);
        canvas.drawLine(const Offset(10.2, 10.5), const Offset(10.2, 16), stroke);
        canvas.drawLine(const Offset(13.8, 10.5), const Offset(13.8, 16), stroke);
      case NaviGlyph.edit:
        final p = Path()
          ..moveTo(5, 19)
          ..lineTo(5.8, 15)
          ..lineTo(15.5, 5.3)
          ..lineTo(18.7, 8.5)
          ..lineTo(9, 18.2)
          ..close();
        canvas.drawPath(p, stroke);
        canvas.drawLine(const Offset(13.6, 7.2), const Offset(16.8, 10.4), stroke);
      case NaviGlyph.pin:
        final p = Path()
          ..moveTo(9, 4.5)
          ..lineTo(15, 4.5)
          ..lineTo(14.2, 9.5)
          ..lineTo(17, 13)
          ..lineTo(7, 13)
          ..lineTo(9.8, 9.5)
          ..close();
        canvas.drawPath(p, solid);
        if (filled) canvas.drawPath(p, stroke);
        canvas.drawLine(const Offset(12, 13), const Offset(12, 19.5), stroke);
      case NaviGlyph.star:
        final p = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? 8.0 : 3.6;
          final a = -pi / 2 + i * pi / 5;
          final o = Offset(12 + r * cos(a), 12.6 + r * sin(a));
          i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
        }
        p.close();
        canvas.drawPath(p, solid);
        if (filled) canvas.drawPath(p, stroke);
      case NaviGlyph.close:
        canvas.drawLine(const Offset(6, 6), const Offset(18, 18), stroke);
        canvas.drawLine(const Offset(18, 6), const Offset(6, 18), stroke);
    }
  }

  void _skip(Canvas canvas, Paint stroke, Paint fill, {required bool forward}) {
    double x(double v) => forward ? v : 24 - v;
    final tri = Path()
      ..moveTo(x(6), 5.5)
      ..lineTo(x(15), 12)
      ..lineTo(x(6), 18.5)
      ..close();
    canvas.drawPath(tri, fill);
    canvas.drawPath(tri, stroke..strokeWidth = 2);
    canvas.drawLine(Offset(x(18.5), 5.5), Offset(x(18.5), 18.5), stroke..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(NaviGlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.filled != filled;
}
