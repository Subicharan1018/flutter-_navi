// Renders the robot to PNG contact sheets under build/mascot_frames/ so its
// poses can be looked at, not just assumed. Always passes; the sheets are the
// output.
//
//   flutter test test/widgets/microduck_frames_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/widgets/mascot/microduck_mesh.dart';
import 'package:navivibe/widgets/mascot/microduck_painter.dart';
import 'package:navivibe/widgets/mascot/microduck_pose.dart';
import 'package:navivibe/widgets/mascot/microduck_rig.dart';

class _Cell {
  final MicroduckPose pose;
  final double t;
  final MicroduckSkin skin;
  final void Function(MicroduckInput)? setup;
  const _Cell(this.pose, this.t, {this.skin = MicroduckSkin.white, this.setup});
}

Future<void> _sheet(WidgetTester tester, String name, List<_Cell> cells, {int columns = 4, double cell = 240, int bpm = 120}) async {
  final rows = (cells.length / columns).ceil();
  final w = (columns * cell).toInt(), h = (rows * cell).toInt();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF16181C));
  for (var i = 0; i < cells.length; i++) {
    final c = cells[i];
    final col = i % columns, row = i ~/ columns;
    canvas.save();
    canvas.translate(col * cell, row * cell);
    canvas.clipRect(Rect.fromLTWH(0, 0, cell, cell));
    canvas.drawRect(
      Rect.fromLTWH(1, 1, cell - 2, cell - 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x22FFFFFF),
    );
    final input = MicroduckInput();
    c.setup?.call(input);
    MicroduckPainter(
      pose: c.pose,
      time: ValueNotifier(c.t),
      input: input,
      skin: c.skin,
      bpm: bpm,
    ).paint(canvas, Size(cell, cell));
    canvas.restore();
  }
  final image = await tester.runAsync(() => recorder.endRecording().toImage(w, h));
  final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  final dir = Directory('build/mascot_frames')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  const beat = 0.5; // 120 bpm

  testWidgets('dance contact sheet', (tester) async {
    // Two frames from each of the nine moves, in routine order (the first
    // block eases in from the last move, so it starts at beat 0.9).
    final beats = [
      1.2, 2.6, // shuffle
      4.9, 6.2, // moonwalk
      9.0, 10.3, // hip twist
      13.2, 14.4, // pop and lock
      16.5, 17.5, // bounce-jump
      20.9, 22.1, // spin
      25.0, 26.5, // side wave
      28.6, 30.1, // head-bang
      32.9, 34.5, // sit-down groove
    ];
    await _sheet(tester, 'dance', [for (final b in beats) _Cell(MicroduckPose.dance, b * beat)], columns: 6, cell: 200);
  });

  testWidgets('pose sheet', (tester) async {
    await _sheet(tester, 'poses', [
      const _Cell(MicroduckPose.idle, 0.4),
      const _Cell(MicroduckPose.idle, 2.6),
      const _Cell(MicroduckPose.walk, 0.0),
      const _Cell(MicroduckPose.walk, 0.22),
      const _Cell(MicroduckPose.run, 0.1),
      const _Cell(MicroduckPose.sit, 0.3),
      const _Cell(MicroduckPose.sleep, 0.8),
      const _Cell(MicroduckPose.idle, 8.6), // a fidget: tapping a foot
      const _Cell(MicroduckPose.dance, 1.0, skin: MicroduckSkin.grey),
      const _Cell(MicroduckPose.idle, 0.4, skin: MicroduckSkin.grey),
      const _Cell(MicroduckPose.walk, 0.22, skin: MicroduckSkin.grey),
      const _Cell(MicroduckPose.sleep, 0.8, skin: MicroduckSkin.grey),
    ]);
  });

  testWidgets('reaction sheet', (tester) async {
    _Cell tap(int count, double u, {double dur = MicroduckInput.hopSeconds}) => _Cell(
          MicroduckPose.idle,
          10 + u * dur,
          setup: (i) => i
            ..tapAt = 10
            ..tapCount = count,
        );
    await _sheet(tester, 'reactions', [
      tap(0, 0.2), // hop
      tap(0, 0.35),
      tap(1, 0.3), // wave
      tap(1, 0.55),
      _Cell(MicroduckPose.idle, 10 + 0.9, setup: (i) => i.bowAt = 10), // bow
      _Cell(MicroduckPose.walk, 10 + 0.25, setup: (i) => i.startleAt = 10), // startle
      _Cell(MicroduckPose.idle, 10 + 0.8, setup: (i) => i.loveAt = 10), // heart on screen
      _Cell(MicroduckPose.idle, 10, setup: (i) => i
        ..lookX = -1
        ..lookUntil = 1000), // looking at a finger
    ]);
  });

  testWidgets('detail close-ups', (tester) async {
    await _sheet(tester, 'detail', [
      const _Cell(MicroduckPose.idle, 0.4),
      _Cell(MicroduckPose.idle, 10.8, setup: (i) => i.loveAt = 10),
      const _Cell(MicroduckPose.dance, 0.9, skin: MicroduckSkin.grey),
      const _Cell(MicroduckPose.walk, 0.1, skin: MicroduckSkin.grey),
    ], columns: 2, cell: 600);
  });

  test('every pose is finite across a minute', () {
    for (final pose in MicroduckPose.values) {
      final input = MicroduckInput();
      for (var t = 0.0; t < 60; t += 0.037) {
        input.rig.solve(pose, t, beat, input);
        for (final v in input.rig.pose.v) {
          expect(v.isFinite, isTrue, reason: '$pose at $t');
        }
        expect(input.rig.squash.isFinite, isTrue);
      }
    }
  });

  test('frame cost stays small', () {
    // CPU side of a frame (rig + transform + sort + cull), without raster:
    // record into a picture, which still runs the whole painter.
    final painter = MicroduckPainter(
      pose: MicroduckPose.dance,
      time: ValueNotifier(0),
      input: MicroduckInput(),
      bpm: 120,
    );
    final time = painter.time as ValueNotifier<double>;
    for (final size in [36.0, 88.0, 140.0]) {
      final sw = Stopwatch()..start();
      const frames = 300;
      for (var f = 0; f < frames; f++) {
        time.value = f / 60;
        final r = ui.PictureRecorder();
        painter.paint(Canvas(r), Size(size, size));
        r.endRecording().dispose();
      }
      final ms = sw.elapsedMicroseconds / 1000 / frames;
      // ignore: avoid_print
      print('microduck frame at ${size.toInt()}px: ${ms.toStringAsFixed(2)} ms (JIT, host CPU)');
      expect(ms, lessThan(8), reason: 'a frame must fit comfortably in 16 ms on a phone');
    }
  });
}
