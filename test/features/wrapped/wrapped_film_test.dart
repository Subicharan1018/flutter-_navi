import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/wrapped/film/film.dart';
import 'package:navivibe/features/wrapped/film/film_export.dart';
import 'package:navivibe/features/wrapped/film/scenes.dart';
import 'package:navivibe/features/wrapped/ui/wrapped_stage.dart';

import 'wrapped_fixture.dart';

class _Sink implements FrameSink {
  final frames = <int>[];
  bool finished = false, cancelled = false;
  int width = 0, height = 0;
  @override
  Future<void> start(int w, int h, int fps, String name) async {
    width = w;
    height = h;
  }

  @override
  Future<void> add(Uint8List rgba) async => frames.add(rgba.length);
  @override
  Future<String> finish() async {
    finished = true;
    return 'film.mp4';
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

Future<Uint8List> _raw(WrappedFilm film, int index, double t, {int? from}) async {
  final rec = ui.PictureRecorder();
  film.paint(Canvas(rec), const Size(90, 160), index: index, t: t, from: from);
  final image = await rec.endRecording().toImage(90, 160);
  return (await image.toByteData())!.buffer.asUint8List();
}

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<(WrappedFilm, WrappedStageState)> open(WidgetTester tester, {bool reduced = false, VoidCallback? onClose}) async {
    phone(tester);
    final film = (await tester.runAsync(fixtureFilm))!;
    addTearDown(film.dispose);
    await tester.pumpWidget(wrappedApp(WrappedStage(film: film, name: 'Subi', onClose: onClose ?? () {}), reduced: reduced));
    await tester.pump();
    return (film, tester.state<WrappedStageState>(find.byType(WrappedStage)));
  }

  Future<void> run(WidgetTester tester, double seconds) async {
    for (var i = 0; i < seconds * 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('the film', () {
    test('a thin year keeps only the scenes it can fill', () {
      expect(filmScenes(fixtureWrapped(thin: true)).map((s) => s.id), ['intro', 'minutes', 'discovery', 'personality', 'finale']);
      expect(filmScenes(fixtureWrapped()).length, 14);
    });

    testWidgets('the same moment always paints the same picture', (tester) async {
      await tester.runAsync(() async {
        final film = await fixtureFilm();
        for (var i = 0; i < film.scenes.length; i++) {
          final a = await _raw(film, i, 2.3, from: i == 0 ? null : i - 1);
          await _raw(film, (i + 3) % film.scenes.length, 1.1);
          expect(await _raw(film, i, 2.3, from: i == 0 ? null : i - 1), a, reason: film.scenes[i].id);
        }
        film.dispose();
      });
    });

    testWidgets('every scene moves: two moments are never the same picture', (tester) async {
      await tester.runAsync(() async {
        final film = await fixtureFilm();
        for (var i = 0; i < film.scenes.length; i++) {
          expect(await _raw(film, i, film.scenes[i].still), isNot(await _raw(film, i, film.scenes[i].still + 0.4)), reason: film.scenes[i].id);
        }
        film.dispose();
      });
    });

    testWidgets('paints with no artwork at all, and for a thin year', (tester) async {
      await tester.runAsync(() async {
        for (final data in [fixtureWrapped(), fixtureWrapped(thin: true)]) {
          final film = await fixtureFilm(data: data, art: false);
          for (var i = 0; i < film.scenes.length; i++) {
            for (final t in [0.0, 0.5, 2.0, film.scenes[i].length]) {
              await _raw(film, i, t, from: i == 0 ? null : i - 1);
            }
          }
          film.dispose();
        }
      });
    });

    test('a still is taken after the numbers have landed', () {
      final s = {for (final s in filmScenes(fixtureWrapped())) s.id: s.still};
      expect(s['minutes'], greaterThanOrEqualTo(5.4));
      expect(s['number-one'], greaterThanOrEqualTo(6.0));
      expect(s['streak'], greaterThanOrEqualTo(5.2));
      expect(s['discovery'], greaterThanOrEqualTo(3.6));
      expect(s['best-day'], greaterThanOrEqualTo(5.0));
    });
  });

  group('touch', () {
    testWidgets('plays on by itself and stops on the last scene', (tester) async {
      final (film, stage) = await open(tester);
      await run(tester, 7.5);
      expect(stage.index, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(stage.index, 2);
      for (var i = 0; i < 20; i++) {
        await tester.tapAt(const Offset(380, 400));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(stage.index, film.scenes.length - 1);
      await run(tester, 12);
      expect(stage.index, film.scenes.length - 1);
    });

    testWidgets('holding pauses', (tester) async {
      final (_, stage) = await open(tester);
      final g = await tester.startGesture(const Offset(195, 400));
      await run(tester, 1);
      final t = stage.time;
      await run(tester, 2);
      expect(stage.time, t);
      await g.up();
      await run(tester, 1);
      expect(stage.time, greaterThan(t));
    });

    testWidgets('a tap in the middle sends a blast through the swarm, which dies away', (tester) async {
      final (_, stage) = await open(tester);
      await tester.tapAt(const Offset(195, 400));
      await tester.pump(const Duration(milliseconds: 50));
      expect(stage.touch.blasts, hasLength(1));
      await run(tester, 2);
      expect(stage.touch.blasts, isEmpty);
    });

    testWidgets('a right guess is kept and the film moves on', (tester) async {
      final (film, stage) = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await run(tester, 2);
      final right = guessOrder(film.data).indexOf(0);
      await tester.tapAt(GuessScene.card(const Size(390, 844), right, stage.time).center);
      await tester.pump();
      expect(stage.touch.guess, right);
      await run(tester, 4);
      expect(stage.index, 3);
    });

    testWidgets('a tap in the countdown smashes to the next song', (tester) async {
      final (_, stage) = await open(tester);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      await run(tester, 1.4);
      await tester.tapAt(const Offset(195, 400));
      await tester.pump();
      expect(stage.time, greaterThanOrEqualTo(3.0));
    });

    testWidgets('dragging the clock chooses an hour, and lets go of it', (tester) async {
      final (_, stage) = await open(tester);
      for (var i = 0; i < 7; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      final g = await tester.startGesture(const Offset(100, 400));
      await g.moveBy(const Offset(40, 0));
      await g.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(stage.touch.scrubX, closeTo(200 / 390, 0.06));
      await g.up();
      await tester.pump(const Duration(milliseconds: 50));
      expect(stage.touch.scrubX, isNull);
    });

    testWidgets('reduced motion shows stills and nothing runs', (tester) async {
      final (film, stage) = await open(tester, reduced: true);
      await tester.pump(const Duration(seconds: 30));
      expect(stage.index, 0);
      expect(stage.time, film.scenes.first.still);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.tapAt(const Offset(380, 400));
      await tester.pump();
      expect(stage.index, 1);
    });

    testWidgets('Esc closes, and closing while a panel was open does not throw', (tester) async {
      var closed = 0;
      await open(tester, onClose: () => closed++);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);
      await tester.tap(find.textContaining('Why?'));
      await run(tester, 0.6);
      expect(find.text('How this was worked out'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });

  group('export', () {
    testWidgets('stills are 1080 x 1920 and the poster also 1080 x 1080', (tester) async {
      await tester.runAsync(() async {
        final film = await fixtureFilm();
        final tall = await decodeImageFromList(await renderStill(film, 4));
        expect((tall.width, tall.height), (1080, 1920));
        final square = await decodeImageFromList(await renderStill(film, film.scenes.length - 1, square: true));
        expect((square.width, square.height), (1080, 1080));
        film.dispose();
      });
    });

    testWidgets('your name is on a picture only when it is given', (tester) async {
      await tester.runAsync(() async {
        final film = await fixtureFilm();
        final last = film.scenes.length - 1;
        expect(await renderStill(film, last), isNot(await renderStill(film, last, name: 'Subi')));
        expect(await renderStill(film, 3), await renderStill(film, 3, name: 'Subi'));
        film.dispose();
      });
    });

    testWidgets('a video is every frame of the clip, whole frames, in order', (tester) async {
      await tester.runAsync(() async {
        final film = await fixtureFilm();
        final sink = _Sink();
        final seen = <double>[];
        final path = await renderVideo(film, const [FilmClip(0, 1, 0.5), FilmClip(1, 1, 0.5)], sink, size: const Size(90, 160), onProgress: seen.add);
        expect(path, 'film.mp4');
        expect(sink.frames, List.filled(24, 90 * 160 * 4));
        expect(seen.last, 1);
        expect((sink.width, sink.height, sink.finished, sink.cancelled), (90, 160, true, false));
        film.dispose();
      });
    });

    testWidgets('cancelling stops and clears up', (tester) async {
      await tester.runAsync(() async {
        final film = await fixtureFilm();
        final sink = _Sink();
        await expectLater(
          renderVideo(film, const [FilmClip(0, 5, 5)], sink, size: const Size(90, 160), cancelled: () => sink.frames.length >= 3),
          throwsA(isA<ExportCancelled>()),
        );
        expect((sink.frames.length, sink.finished, sink.cancelled), (3, false, true));
        film.dispose();
      });
    });

    testWidgets('the whole film fits in one Instagram story', (tester) async {
      await tester.runAsync(() async {
        final film = await fixtureFilm();
        expect(wholeFilm(film).fold<double>(0, (a, c) => a + c.seconds), lessThanOrEqualTo(60));
        film.dispose();
      });
    });
  });
}
