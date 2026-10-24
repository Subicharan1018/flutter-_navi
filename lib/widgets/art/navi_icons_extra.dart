import 'dart:math' show pi, cos, sin;

import 'package:flutter/material.dart';

import 'navi_icons.dart';

// Second half of NaviVibe's glyph set (see navi_icons.dart for the grid and
// stroke rules). Split out so no single painter file grows past reading size.

Paint _ink(Paint stroke, bool filled, [double? width]) {
  if (!filled) return stroke;
  return Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = width ?? stroke.strokeWidth
    ..color = const Color(0x99000000);
}

void _arc(Canvas c, Offset center, double r, double mid, double half, Paint p) =>
    c.drawArc(Rect.fromCircle(center: center, radius: r), mid - half, half * 2, false, p);

/// Paints the glyphs that are not in the primary switch. [stroke] is the
/// outline paint, [fill] a plain fill, [solid] fill-or-stroke by `filled`.
void paintNaviGlyphExtra(
  Canvas canvas,
  NaviGlyph glyph,
  Paint stroke,
  Paint fill,
  Paint solid,
  bool filled,
) {
  final ink = _ink(stroke, filled);
  switch (glyph) {
    case NaviGlyph.note:
      canvas.drawCircle(const Offset(8.5, 17.5), 3, solid);
      canvas.drawPath(
        Path()
          ..moveTo(11.5, 17.5)
          ..lineTo(11.5, 5)
          ..cubicTo(13, 7.5, 17.5, 7.5, 18, 11),
        stroke,
      );
    case NaviGlyph.playlist:
      canvas.drawLine(const Offset(4, 7), const Offset(14, 7), stroke);
      canvas.drawLine(const Offset(4, 12), const Offset(14, 12), stroke);
      canvas.drawLine(const Offset(4, 17), const Offset(9, 17), stroke);
      canvas.drawCircle(const Offset(16.5, 17), 2.2, fill);
      canvas.drawLine(const Offset(18.7, 17), const Offset(18.7, 8.5), stroke);
    case NaviGlyph.stack:
      canvas.drawLine(const Offset(7, 4.5), const Offset(17, 4.5), stroke);
      canvas.drawLine(const Offset(5.5, 8), const Offset(18.5, 8), stroke);
      final rr = RRect.fromRectAndRadius(const Rect.fromLTRB(4, 11, 20, 20), const Radius.circular(3));
      canvas.drawRRect(rr, solid);
      if (filled) canvas.drawRRect(rr, stroke);
    case NaviGlyph.rewind:
    case NaviGlyph.fastForward:
      double x(double v) => glyph == NaviGlyph.fastForward ? v : 24 - v;
      for (final shift in const [0.0, 9.0]) {
        final tri = Path()
          ..moveTo(x(3.5 + shift), 6)
          ..lineTo(x(12 + shift), 12)
          ..lineTo(x(3.5 + shift), 18)
          ..close();
        canvas.drawPath(tri, fill);
        canvas.drawPath(tri, stroke..strokeWidth = 2);
      }
    case NaviGlyph.speakerLow:
      final body = Path()
        ..moveTo(4, 9.5)
        ..lineTo(8, 9.5)
        ..lineTo(12.5, 5.5)
        ..lineTo(12.5, 18.5)
        ..lineTo(8, 14.5)
        ..lineTo(4, 14.5)
        ..close();
      canvas.drawPath(body, solid);
      if (filled) canvas.drawPath(body, stroke);
      _arc(canvas, const Offset(12.5, 12), 4.5, 0, 0.9, stroke);
    case NaviGlyph.infinite:
      canvas.drawPath(
        Path()
          ..moveTo(12, 12)
          ..cubicTo(10, 8, 4, 8, 4, 12)
          ..cubicTo(4, 16, 10, 16, 12, 12)
          ..cubicTo(14, 8, 20, 8, 20, 12)
          ..cubicTo(20, 16, 14, 16, 12, 12),
        stroke,
      );
    case NaviGlyph.phone:
      final body = RRect.fromRectAndRadius(const Rect.fromLTRB(7, 3.5, 17, 20.5), const Radius.circular(2.6));
      canvas.drawRRect(body, solid);
      if (filled) canvas.drawRRect(body, stroke);
      canvas.drawLine(const Offset(10.8, 17.4), const Offset(13.2, 17.4), ink);
    case NaviGlyph.desktop:
      final screen = RRect.fromRectAndRadius(const Rect.fromLTRB(3.5, 5, 20.5, 16), const Radius.circular(2));
      canvas.drawRRect(screen, solid);
      if (filled) canvas.drawRRect(screen, stroke);
      canvas.drawLine(const Offset(12, 16), const Offset(12, 19.5), stroke);
      canvas.drawLine(const Offset(8, 19.5), const Offset(16, 19.5), stroke);
    case NaviGlyph.headphones:
      _arc(canvas, const Offset(12, 13), 7.5, -pi / 2, pi / 2 + 0.05, stroke);
      for (final x in const [4.5, 16.5]) {
        final cup = RRect.fromRectAndRadius(Rect.fromLTWH(x, 12.5, 3, 6.5), const Radius.circular(1.5));
        canvas.drawRRect(cup, solid);
        if (filled) canvas.drawRRect(cup, stroke);
      }
    case NaviGlyph.speaker:
      final body = Path()
        ..moveTo(4, 9.5)
        ..lineTo(8, 9.5)
        ..lineTo(12.5, 5.5)
        ..lineTo(12.5, 18.5)
        ..lineTo(8, 14.5)
        ..lineTo(4, 14.5)
        ..close();
      canvas.drawPath(body, solid);
      if (filled) canvas.drawPath(body, stroke);
      _arc(canvas, const Offset(12.5, 12), 4.5, 0, 0.9, stroke);
      _arc(canvas, const Offset(12.5, 12), 8, 0, 0.85, stroke);
    case NaviGlyph.link:
      canvas.save();
      canvas.translate(12, 12);
      canvas.rotate(-pi / 4);
      for (final r in const [
        Rect.fromLTRB(-9.5, -3.5, 0.5, 3.5),
        Rect.fromLTRB(-0.5, -3.5, 9.5, 3.5),
      ]) {
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3.5)), stroke);
      }
      canvas.drawLine(const Offset(-3, 0), const Offset(3, 0), stroke);
      canvas.restore();
    case NaviGlyph.alert:
      canvas.drawCircle(const Offset(12, 12), 8, solid);
      canvas.drawLine(const Offset(12, 7.5), const Offset(12, 12.8), ink);
      canvas.drawCircle(const Offset(12, 16.2), 1.1, filled ? (Paint()..color = const Color(0x99000000)) : fill);
    case NaviGlyph.info:
      canvas.drawCircle(const Offset(12, 12), 8, solid);
      canvas.drawCircle(const Offset(12, 8.2), 1.1, filled ? (Paint()..color = const Color(0x99000000)) : fill);
      canvas.drawLine(const Offset(12, 11.4), const Offset(12, 16.5), ink);
    case NaviGlyph.checkCircle:
      canvas.drawCircle(const Offset(12, 12), 8, solid);
      canvas.drawPath(
        Path()
          ..moveTo(8.3, 12.3)
          ..lineTo(11, 15)
          ..lineTo(15.8, 9.3),
        ink,
      );
    case NaviGlyph.ring:
      canvas.drawCircle(const Offset(12, 12), 8, solid);
    case NaviGlyph.downloadCircle:
      canvas.drawCircle(const Offset(12, 12), 8, solid);
      canvas.drawLine(const Offset(12, 7.5), const Offset(12, 15.5), ink);
      canvas.drawPath(
        Path()
          ..moveTo(8.8, 12.4)
          ..lineTo(12, 15.6)
          ..lineTo(15.2, 12.4),
        ink,
      );
    case NaviGlyph.chevronLeft:
      canvas.drawPath(
        Path()
          ..moveTo(14.5, 5.5)
          ..lineTo(8, 12)
          ..lineTo(14.5, 18.5),
        stroke,
      );
    case NaviGlyph.chevronDown:
      canvas.drawPath(
        Path()
          ..moveTo(5.5, 9.5)
          ..lineTo(12, 16)
          ..lineTo(18.5, 9.5),
        stroke,
      );
    case NaviGlyph.caretUp:
      final up = Path()
        ..moveTo(12, 7)
        ..lineTo(18, 16)
        ..lineTo(6, 16)
        ..close();
      canvas.drawPath(up, fill);
      canvas.drawPath(up, stroke..strokeWidth = 1.5);
    case NaviGlyph.caretDown:
      final down = Path()
        ..moveTo(12, 17)
        ..lineTo(18, 8)
        ..lineTo(6, 8)
        ..close();
      canvas.drawPath(down, fill);
      canvas.drawPath(down, stroke..strokeWidth = 1.5);
    case NaviGlyph.playCircle:
      canvas.drawCircle(const Offset(12, 12), 8, solid);
      final tri = Path()
        ..moveTo(10, 8.5)
        ..lineTo(15.8, 12)
        ..lineTo(10, 15.5)
        ..close();
      canvas.drawPath(tri, filled ? (Paint()..color = const Color(0x99000000)) : stroke);
    case NaviGlyph.playNext:
      canvas.drawLine(const Offset(4, 6), const Offset(20, 6), stroke);
      canvas.drawLine(const Offset(12, 12), const Offset(20, 12), stroke);
      canvas.drawLine(const Offset(4, 18), const Offset(20, 18), stroke);
      canvas.drawLine(const Offset(4, 12), const Offset(8.5, 12), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(6.3, 9.7)
          ..lineTo(8.6, 12)
          ..lineTo(6.3, 14.3),
        stroke,
      );
    case NaviGlyph.playLast:
      canvas.drawLine(const Offset(4, 6), const Offset(20, 6), stroke);
      canvas.drawLine(const Offset(4, 11), const Offset(20, 11), stroke);
      canvas.drawLine(const Offset(4, 17), const Offset(17, 17), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(14.8, 14.6)
          ..lineTo(17.2, 17)
          ..lineTo(14.8, 19.4),
        stroke,
      );
    case NaviGlyph.photo:
      final frame = RRect.fromRectAndRadius(const Rect.fromLTRB(3.5, 5, 20.5, 19), const Radius.circular(3));
      canvas.drawRRect(frame, solid);
      if (filled) canvas.drawRRect(frame, stroke);
      canvas.drawCircle(const Offset(9, 10), 1.5, filled ? (Paint()..color = const Color(0x99000000)) : fill);
      canvas.drawPath(
        Path()
          ..moveTo(4.5, 17)
          ..lineTo(10, 12.5)
          ..lineTo(14, 16)
          ..lineTo(16.2, 14)
          ..lineTo(19.5, 17),
        ink,
      );
    case NaviGlyph.camera:
      final body = RRect.fromRectAndRadius(const Rect.fromLTRB(3.5, 7, 20.5, 19.5), const Radius.circular(3));
      canvas.drawRRect(body, solid);
      if (filled) canvas.drawRRect(body, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(8, 7)
          ..lineTo(9.5, 4.5)
          ..lineTo(14.5, 4.5)
          ..lineTo(16, 7),
        stroke,
      );
      canvas.drawCircle(const Offset(12, 13.2), 3.2, ink);
    case NaviGlyph.copy:
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTRB(4.5, 4.5, 15, 15), const Radius.circular(2.5)),
        stroke,
      );
      canvas.drawPath(
        Path()
          ..moveTo(15, 9)
          ..lineTo(17, 9)
          ..quadraticBezierTo(19.5, 9, 19.5, 11.5)
          ..lineTo(19.5, 17)
          ..quadraticBezierTo(19.5, 19.5, 17, 19.5)
          ..lineTo(11.5, 19.5)
          ..quadraticBezierTo(9, 19.5, 9, 17)
          ..lineTo(9, 15),
        stroke,
      );
    case NaviGlyph.doc:
      final page = Path()
        ..moveTo(6.5, 3.5)
        ..lineTo(14, 3.5)
        ..lineTo(18.5, 8)
        ..lineTo(18.5, 20.5)
        ..lineTo(6.5, 20.5)
        ..close();
      canvas.drawPath(page, solid);
      if (filled) canvas.drawPath(page, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(14, 3.5)
          ..lineTo(14, 8)
          ..lineTo(18.5, 8),
        stroke,
      );
      canvas.drawLine(const Offset(9.5, 12.5), const Offset(15.5, 12.5), ink);
      canvas.drawLine(const Offset(9.5, 16), const Offset(15.5, 16), ink);
    case NaviGlyph.gear:
      for (var i = 0; i < 8; i++) {
        final a = i * pi / 4;
        canvas.drawLine(
          Offset(12 + 6.8 * cos(a), 12 + 6.8 * sin(a)),
          Offset(12 + 9 * cos(a), 12 + 9 * sin(a)),
          stroke,
        );
      }
      canvas.drawCircle(const Offset(12, 12), 5.6, solid);
      canvas.drawCircle(const Offset(12, 12), 2.2, filled ? (Paint()..color = const Color(0x99000000)) : stroke);
    case NaviGlyph.lock:
      final body = RRect.fromRectAndRadius(const Rect.fromLTRB(5.5, 10.5, 18.5, 20), const Radius.circular(2.5));
      canvas.drawRRect(body, solid);
      if (filled) canvas.drawRRect(body, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(8.5, 10.5)
          ..lineTo(8.5, 8)
          ..cubicTo(8.5, 4.2, 15.5, 4.2, 15.5, 8)
          ..lineTo(15.5, 10.5),
        stroke,
      );
    case NaviGlyph.unlock:
      final body = RRect.fromRectAndRadius(const Rect.fromLTRB(5.5, 10.5, 18.5, 20), const Radius.circular(2.5));
      canvas.drawRRect(body, solid);
      if (filled) canvas.drawRRect(body, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(8.5, 10.5)
          ..lineTo(8.5, 8)
          ..cubicTo(8.5, 4.2, 15.5, 4.2, 15.5, 8),
        stroke,
      );
    case NaviGlyph.eye:
      _eye(canvas, stroke, solid, filled);
    case NaviGlyph.eyeOff:
      _eye(canvas, stroke, solid, filled);
      canvas.drawLine(const Offset(5, 19), const Offset(19, 5), stroke);
    case NaviGlyph.globe:
      canvas.drawCircle(const Offset(12, 12), 8, stroke);
      canvas.drawOval(Rect.fromCenter(center: const Offset(12, 12), width: 8, height: 16), stroke);
      canvas.drawLine(const Offset(4, 12), const Offset(20, 12), stroke);
    case NaviGlyph.cloud:
      final p = Path()
        ..moveTo(7.5, 18.5)
        ..cubicTo(4.5, 18.5, 3.5, 14.5, 6.5, 13.3)
        ..cubicTo(6.3, 9.5, 10, 7.5, 12.8, 9.2)
        ..cubicTo(14.5, 5.8, 19.5, 7.5, 19, 12.2)
        ..cubicTo(21.5, 12.5, 21.5, 18.5, 17.5, 18.5)
        ..close();
      canvas.drawPath(p, solid);
      if (filled) canvas.drawPath(p, stroke);
    case NaviGlyph.sun:
      canvas.drawCircle(const Offset(12, 12), 4, solid);
      for (var i = 0; i < 8; i++) {
        final a = i * pi / 4;
        canvas.drawLine(
          Offset(12 + 6.8 * cos(a), 12 + 6.8 * sin(a)),
          Offset(12 + 9 * cos(a), 12 + 9 * sin(a)),
          stroke,
        );
      }
    case NaviGlyph.thermometer:
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTRB(10, 3.5, 14, 15), const Radius.circular(2)),
        stroke,
      );
      canvas.drawCircle(const Offset(12, 17.5), 3.2, solid);
      canvas.drawLine(const Offset(12, 8.5), const Offset(12, 16), stroke);
    case NaviGlyph.drop:
      final p = Path()
        ..moveTo(12, 3.5)
        ..cubicTo(14, 7, 18.5, 10.5, 18.5, 14.5)
        ..cubicTo(18.5, 18.1, 15.6, 20.5, 12, 20.5)
        ..cubicTo(8.4, 20.5, 5.5, 18.1, 5.5, 14.5)
        ..cubicTo(5.5, 10.5, 10, 7, 12, 3.5)
        ..close();
      canvas.drawPath(p, solid);
      if (filled) canvas.drawPath(p, stroke);
    case NaviGlyph.radio:
      canvas.drawCircle(const Offset(12, 12), 1.9, fill);
      for (final r in const [5.0, 8.5]) {
        _arc(canvas, const Offset(12, 12), r, 0, 0.7, stroke);
        _arc(canvas, const Offset(12, 12), r, pi, 0.7, stroke);
      }
    case NaviGlyph.wifi:
      _wifi(canvas, stroke, fill);
    case NaviGlyph.wifiOff:
      _wifi(canvas, stroke, fill);
      canvas.drawLine(const Offset(4.5, 4.5), const Offset(19.5, 19.5), stroke);
    case NaviGlyph.thumbUp:
      _thumb(canvas, stroke, solid, filled);
    case NaviGlyph.thumbDown:
      canvas.save();
      canvas.translate(0, 24);
      canvas.scale(1, -1);
      _thumb(canvas, stroke, solid, filled);
      canvas.restore();
    case NaviGlyph.minusCircle:
      canvas.drawCircle(const Offset(12, 12), 8, solid);
      canvas.drawLine(const Offset(8, 12), const Offset(16, 12), ink);
    case NaviGlyph.plusCircle:
      canvas.drawCircle(const Offset(12, 12), 8, solid);
      canvas.drawLine(const Offset(12, 8), const Offset(12, 16), ink);
      canvas.drawLine(const Offset(8, 12), const Offset(16, 12), ink);
    case NaviGlyph.grip:
      canvas.drawLine(const Offset(4, 7), const Offset(20, 7), stroke);
      canvas.drawLine(const Offset(4, 12), const Offset(20, 12), stroke);
      canvas.drawLine(const Offset(4, 17), const Offset(20, 17), stroke);
    case NaviGlyph.expand:
      canvas.drawLine(const Offset(13.5, 10.5), const Offset(19.5, 4.5), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(14.5, 4.5)
          ..lineTo(19.5, 4.5)
          ..lineTo(19.5, 9.5),
        stroke,
      );
      canvas.drawLine(const Offset(10.5, 13.5), const Offset(4.5, 19.5), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(4.5, 14.5)
          ..lineTo(4.5, 19.5)
          ..lineTo(9.5, 19.5),
        stroke,
      );
    case NaviGlyph.swap:
      canvas.drawLine(const Offset(5, 8), const Offset(19, 8), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(16, 5.2)
          ..lineTo(19, 8)
          ..lineTo(16, 10.8),
        stroke,
      );
      canvas.drawLine(const Offset(19, 16), const Offset(5, 16), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(8, 13.2)
          ..lineTo(5, 16)
          ..lineTo(8, 18.8),
        stroke,
      );
    case NaviGlyph.metronome:
      final body = Path()
        ..moveTo(9.2, 4.5)
        ..lineTo(14.8, 4.5)
        ..lineTo(19, 20)
        ..lineTo(5, 20)
        ..close();
      canvas.drawPath(body, solid);
      if (filled) canvas.drawPath(body, stroke);
      canvas.drawLine(const Offset(12, 16), const Offset(15, 8.5), ink);
    case NaviGlyph.grid:
      for (final o in const [Offset(4.5, 4.5), Offset(13.5, 4.5), Offset(4.5, 13.5), Offset(13.5, 13.5)]) {
        final rr = RRect.fromRectAndRadius(Rect.fromLTWH(o.dx, o.dy, 6, 6), const Radius.circular(1.8));
        canvas.drawRRect(rr, solid);
        if (filled) canvas.drawRRect(rr, stroke);
      }
    case NaviGlyph.personCircle:
      canvas.drawCircle(const Offset(12, 12), 9, stroke);
      canvas.drawCircle(const Offset(12, 10), 3, solid);
      canvas.drawPath(
        Path()
          ..moveTo(6.3, 18.2)
          ..quadraticBezierTo(12, 13.2, 17.7, 18.2),
        stroke,
      );
    case NaviGlyph.gauge:
      _arc(canvas, const Offset(12, 13.5), 8.5, -pi / 2, pi * 0.7, stroke);
      canvas.drawLine(const Offset(12, 13.5), const Offset(16, 8.5), stroke);
      canvas.drawCircle(const Offset(12, 13.5), 1.4, fill);
    case NaviGlyph.moon:
      final p = Path()
        ..moveTo(20, 13.8)
        ..arcToPoint(const Offset(10.2, 4), radius: const Radius.circular(8.5), largeArc: true)
        ..arcToPoint(const Offset(20, 13.8), radius: const Radius.circular(6.5), clockwise: false)
        ..close();
      canvas.drawPath(p, solid);
      if (filled) canvas.drawPath(p, stroke);
    default:
      break;
  }
}

void _eye(Canvas canvas, Paint stroke, Paint solid, bool filled) {
  canvas.drawPath(
    Path()
      ..moveTo(3, 12)
      ..quadraticBezierTo(12, 3.5, 21, 12)
      ..quadraticBezierTo(12, 20.5, 3, 12)
      ..close(),
    stroke,
  );
  canvas.drawCircle(const Offset(12, 12), 3, solid);
}

void _wifi(Canvas canvas, Paint stroke, Paint fill) {
  const c = Offset(12, 18.5);
  canvas.drawCircle(c, 1.3, fill);
  for (final r in const [4.5, 8.5, 12.5]) {
    _arc(canvas, c, r, -pi / 2, 0.75, stroke);
  }
}

void _thumb(Canvas canvas, Paint stroke, Paint solid, bool filled) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTRB(4, 10.5, 7.5, 19.5), const Radius.circular(1.5)),
    stroke,
  );
  final hand = Path()
    ..moveTo(7.5, 11)
    ..lineTo(11, 4.5)
    ..quadraticBezierTo(13.8, 4.5, 13, 7.8)
    ..lineTo(12.5, 10)
    ..lineTo(18, 10)
    ..quadraticBezierTo(20.2, 10, 19.8, 12.2)
    ..lineTo(18.8, 18)
    ..quadraticBezierTo(18.5, 19.5, 17, 19.5)
    ..lineTo(7.5, 19.5);
  if (filled) {
    canvas.drawPath(hand, Paint()..color = stroke.color);
  }
  canvas.drawPath(hand, stroke);
}
