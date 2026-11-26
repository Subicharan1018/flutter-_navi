/// One sheet of every Wrapped scene for review: three moments each (forming, mid-way, the shared still), labelled with how
/// it is drawn and whether it uses particles. Written to docs/wrapped/contact-sheet.png.
///
///   flutter test test/goldens/wrapped_contact_sheet_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/wrapped/film/film.dart';

import '../features/wrapped/wrapped_fixture.dart';
import 'golden_fonts.dart';

const _fw = 150.0, _fh = 325.0;
const _frame = Size(_fw, _fh);
const _gap = 6.0, _label = 54.0, _pad = 22.0, _cols = 5;
const _cellW = _fw * 3 + _gap * 2;
const _cellH = _fh + _label;

class _Sheet extends CustomPainter {
  final WrappedFilm film;
  _Sheet(this.film);

  static Size sizeFor(int n) => Size(_pad * 2 + _cols * _cellW + (_cols - 1) * _pad, 70 + ((n + _cols - 1) ~/ _cols) * (_cellH + _pad) + _pad);

  void _text(Canvas c, String s, Offset at, double size, Color color, {FontWeight weight = FontWeight.w600, double width = _cellW}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: weight, color: color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    tp.paint(c, at);
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF111114));
    _text(canvas, 'NaviVibe Wrapped: ${film.scenes.length} scenes, in playing order. Three moments each: forming, mid-way, the still that is shared.', const Offset(_pad, 22), 20, Colors.white, weight: FontWeight.w700, width: size.width);
    for (var i = 0; i < film.scenes.length; i++) {
      final s = film.scenes[i];
      final x = _pad + (i % _cols) * (_cellW + _pad), y = 70 + (i ~/ _cols) * (_cellH + _pad);
      for (var k = 0; k < 3; k++) {
        final t = [s.length * 0.25, s.length * 0.55, s.still][k];
        canvas.save();
        canvas.translate(x + k * (_frame.width + _gap), y);
        canvas.clipRect(Offset.zero & _frame);
        film.paint(canvas, _frame, index: i, t: t);
        canvas.restore();
      }
      _text(canvas, '${i + 1}. ${s.id}  ·  ${s.particles ? 'PARTICLES' : 'drawn, no particles'}', Offset(x, y + _frame.height + 8), 15, s.particles ? const Color(0xFFFFB627) : Colors.white, weight: FontWeight.w800);
      _text(canvas, s.technique, Offset(x, y + _frame.height + 30), 13, const Color(0xFFB0B0B8));
    }
  }

  @override
  bool shouldRepaint(_Sheet old) => false;
}

void main() {
  setUpAll(loadGoldenFonts);

  testWidgets('contact sheet', (tester) async {
    final film = (await tester.runAsync(fixtureFilm))!;
    addTearDown(film.dispose);
    final size = _Sheet.sizeFor(film.scenes.length);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrappedApp(RepaintBoundary(child: CustomPaint(size: size, painter: _Sheet(film)))));
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('../../docs/wrapped/contact-sheet.png'));
  });
}
