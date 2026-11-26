import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/wrapped/film/film.dart';
import 'package:navivibe/features/wrapped/film/film_export.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/wrapped/film/film_assets.dart';
import 'package:navivibe/features/wrapped/film/scenes.dart';
import 'package:navivibe/features/wrapped/film/scenes_music.dart';
import 'package:navivibe/features/wrapped/data/wrapped_models.dart';
import 'package:navivibe/features/wrapped/logic/wrapped_loader.dart';
import 'package:navivibe/features/wrapped/logic/wrapped_providers.dart';
import 'package:navivibe/features/wrapped/ui/wrapped_screen.dart';
import 'package:navivibe/features/wrapped/ui/wrapped_stage.dart';
import 'package:navivibe/providers/library_provider.dart';

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
      expect(filmScenes(fixtureWrapped()).length, 23);
    });

    test('particles only where they are the thing itself, and no two scenes are drawn the same way', () {
      final s = filmScenes(fixtureWrapped());
      expect([for (final x in s) if (x.particles) x.id], ['minutes', 'artists']);
      expect(s.map((x) => x.technique).toSet().length, s.length);
      expect(WrappedFilm(fixtureWrapped(), FilmAssets()).grains, lessThanOrEqualTo(520));
    });

    test('every scene says how it was worked out, what to share and what to read aloud', () {
      for (final s in filmScenes(fixtureWrapped())) {
        for (final text in [s.why(fixtureWrapped()), s.share(fixtureWrapped()), s.speech(fixtureWrapped())]) {
          expect(text.length, greaterThan(12), reason: s.id);
          expect(text, isNot(contains('null')), reason: s.id);
        }
        expect(s.still, lessThanOrEqualTo(s.length), reason: s.id);
      }
    });

    test('a film’s name is left off its songs', () {
      expect(nice('Hangova (From "DC")'), 'Hangova');
      expect(nice('Song [feat. X]'), 'Song');
      expect(nice('(From "X")'), '(From "X")');
      expect(nice('Love (Remix)'), 'Love (Remix)');
    });

    test('the cards end where their shuffle says, each in its own place', () {
      expect({for (var c = 0; c < 3; c++) CardsScene.place(c, CardsScene.ready).$1}, {0.0, 1.0, 2.0});
      expect([for (var c = 0; c < 3; c++) CardsScene.place(c, 0).$1], [0, 1, 2]);
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
      for (final (id, lands) in [('minutes', 5.4), ('number-one', 5.0), ('top5', 6.7), ('race', 7.6), ('obsession', 5.0), ('era', 4.0), ('week', 3.6), ('streak', 5.4), ('loyalty', 4.0), ('best-day', 5.0), ('discovery', 5.4)]) {
        expect(s[id], greaterThanOrEqualTo(lands), reason: id);
      }
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

    testWidgets('a tap in the middle kicks the scene, and the kick dies away', (tester) async {
      final (_, stage) = await open(tester);
      await tester.tapAt(const Offset(195, 400));
      await tester.pump(const Duration(milliseconds: 50));
      expect(stage.touch.punch(), greaterThan(0.5));
      await run(tester, 2);
      expect(stage.touch.punch(), 0);
    });

    testWidgets('cards cannot be picked while they move; a pick is kept and the film moves on', (tester) async {
      final (_, stage) = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await run(tester, 2);
      await tester.tapAt(const Offset(195, 397));
      await tester.pump();
      expect(stage.touch.guess, isNull);
      await run(tester, 4.5);
      await tester.tapAt(const Offset(195, 397));
      await tester.pump();
      final middle = [0, 1, 2].firstWhere((c) => CardsScene.place(c, 9).$1 == 1);
      expect(stage.touch.guess, middle);
      await run(tester, 4);
      expect(stage.index, 3);
    });

    testWidgets('a tap sends the departures board round again', (tester) async {
      final (_, stage) = await open(tester);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      await run(tester, 5);
      await tester.tapAt(const Offset(195, 400));
      await tester.pump();
      expect(stage.time, lessThan(1.2));
    });

    testWidgets('nothing runs behind an open panel', (tester) async {
      final (_, stage) = await open(tester);
      await run(tester, 1);
      await tester.tap(find.textContaining('Why?'));
      await run(tester, 0.6);
      final t = stage.time;
      await run(tester, 1);
      expect(stage.time, t);
    });

    testWidgets('no words on the stage or its panels wear Flutter’s yellow underline', (tester) async {
      phone(tester);
      final film = (await tester.runAsync(fixtureFilm))!;
      addTearDown(film.dispose);
      // as it is on the phone: a bare route, no Scaffold or Material above it
      await tester.pumpWidget(
        ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(home: WrappedStage(film: film, name: 'Subi', onClose: () {}, waiting: 'Waiting')),
        ),
      );
      void clean(String where) {
        final texts = tester.widgetList<RichText>(find.byType(RichText)).toList();
        expect(texts, isNotEmpty, reason: where);
        for (final r in texts) {
          final style = (r.text as TextSpan).style!;
          expect(style.decoration ?? TextDecoration.none, TextDecoration.none, reason: '$where: ${r.text.toPlainText()}');
        }
      }

      await tester.pump();
      clean('stage');
      for (var i = 0; i < 30; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 30));
        clean('scene $i');
      }
      await tester.tap(find.textContaining('Why?'));
      await run(tester, 0.6);
      clean('why');
      await tester.tapAt(const Offset(195, 100));
      await run(tester, 0.6);
      await tester.tap(find.bySemanticsLabel('Share').first);
      await run(tester, 0.6);
      expect(find.text('Show my name'), findsOneWidget);
      clean('share');
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

  group('opening', () {
    Future<StreamController<WrappedLoad>> screen(WidgetTester tester, {bool reduced = false}) async {
      phone(tester);
      final loads = StreamController<WrappedLoad>();
      addTearDown(loads.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wrappedProvider.overrideWith((ref, year) => loads.stream),
            songCoverUrlProvider.overrideWith((ref, key) async => null),
            artistCoverUrlProvider.overrideWith((ref, key) async => null),
          ],
          child: wrappedApp(const WrappedScreen(year: 2026, name: 'Subi'), reduced: reduced),
        ),
      );
      await tester.pump();
      return loads;
    }

    WrappedStageState stage(WidgetTester tester) => tester.state<WrappedStageState>(find.byType(WrappedStage));

    testWidgets('the intro is on screen before the server has said anything, and says what it waits for', (tester) async {
      await screen(tester);
      await run(tester, 2);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(stage(tester).time, greaterThan(1.5));
      expect(find.text('Gathering your year'), findsOneWidget);
      await run(tester, 30);
      expect(stage(tester).index, 0);
    });

    testWidgets('the year lets it run on; the months add the rest ahead without a restart', (tester) async {
      final loads = await screen(tester);
      await run(tester, 2);
      final t = stage(tester).time;
      loads.add(WrappedLoad(fixtureWrapped(), settled: false, total: 11));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(stage(tester).time, greaterThanOrEqualTo(t));
      expect(stage(tester).widget.film.scenes.last.id, 'journey');
      for (var i = 0; i < 12; i++) {
        await tester.tapAt(const Offset(380, 400));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(stage(tester).index, 8);
      loads.add(WrappedLoad(fixtureWrapped(), settled: false, done: 4, total: 11));
      await run(tester, 0.2);
      expect(find.text('Adding your months, 4 of 11'), findsOneWidget);
      await run(tester, 12);
      expect(stage(tester).index, 8, reason: 'it waits on the last known scene');
      loads.add(WrappedLoad(fixtureWrapped(), settled: true));
      await run(tester, 0.4);
      expect(stage(tester).index, 9);
      expect(stage(tester).widget.film.scenes.length, 23);
      expect(find.textContaining('Adding your months'), findsNothing);
    });

    testWidgets('a failure offers another try, an empty year says so', (tester) async {
      final loads = await screen(tester);
      loads.addError(StateError('offline'));
      await run(tester, 0.2);
      expect(find.text('Wrapped didn’t load'), findsOneWidget);
    });

    testWidgets('an empty year says so', (tester) async {
      final loads = await screen(tester);
      loads.add(WrappedLoad(emptyWrapped(2026), settled: true));
      await run(tester, 0.2);
      expect(find.text('Nothing to wrap yet'), findsOneWidget);
    });

    testWidgets('reduced motion waits on the still and moves when you tap', (tester) async {
      final loads = await screen(tester, reduced: true);
      expect(find.text('Gathering your year'), findsOneWidget);
      loads.add(WrappedLoad(fixtureWrapped(), settled: true));
      await tester.pump();
      await tester.pump();
      await tester.tapAt(const Offset(380, 400));
      await tester.pump();
      expect(stage(tester).index, 1);
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
