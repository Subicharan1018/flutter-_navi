/// Wrapped, scene by scene, as a strip of four moments: mid-flight, forming, formed, and the still that is shared.
///
///   flutter test test/goldens/wrapped_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/wrapped/film/film.dart';

import '../features/wrapped/wrapped_fixture.dart';
import 'golden_fonts.dart';

class _Strip extends CustomPainter {
  final WrappedFilm film;
  final int index;
  _Strip(this.film, this.index);

  @override
  void paint(Canvas canvas, Size size) {
    final s = film.scenes[index];
    final times = [0.65, s.length * 0.3, s.length * 0.55, s.still];
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(i * 364.0, 0);
      film.paint(canvas, const Size(360, 640), index: index, t: times[i], from: index == 0 ? null : index - 1, fromT: index == 0 ? 0 : film.scenes[index - 1].length);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Strip old) => false;
}

class _Square extends CustomPainter {
  final WrappedFilm film;
  _Square(this.film);
  @override
  void paint(Canvas canvas, Size size) => film.paint(canvas, const Size(360, 360), index: film.scenes.length - 1, t: film.scenes.last.still, name: 'Subi');
  @override
  bool shouldRepaint(_Square old) => false;
}

void main() {
  setUpAll(loadGoldenFonts);

  void view(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final (i, id) in ['intro', 'minutes', 'guess', 'number-one', 'top5', 'artists', 'genres', 'clock', 'streak', 'discovery', 'personality', 'journey', 'best-day', 'finale'].indexed) {
    testWidgets(id, (tester) async {
      view(tester, const Size(1452, 640));
      final film = (await tester.runAsync(fixtureFilm))!;
      addTearDown(film.dispose);
      expect(film.scenes[i].id, id);
      await tester.pumpWidget(wrappedApp(RepaintBoundary(child: CustomPaint(size: const Size(1452, 640), painter: _Strip(film, i)))));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('wrapped/$id.png'));
    });
  }

  testWidgets('square', (tester) async {
    view(tester, const Size(360, 360));
    final film = (await tester.runAsync(fixtureFilm))!;
    addTearDown(film.dispose);
    await tester.pumpWidget(wrappedApp(CustomPaint(size: const Size(360, 360), painter: _Square(film))));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('wrapped/square.png'));
  });
}
