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
  final double? tap;
  const _Cell(this.pose, this.t, {this.skin = MicroduckSkin.white, this.tap});
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
    if (c.tap != null) input.tapAt = c.tap!;
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
    // Two frames from each of the five moves, plus the in-between of a few.
    final beats = [0.25, 0.75, 4.25, 4.75, 8.4, 9.4, 10.4, 12.2, 12.7, 13.2, 16.1, 16.35];
    await _sheet(tester, 'dance', [for (final b in beats) _Cell(MicroduckPose.dance, b * beat)]);
  });

  testWidgets('pose sheet', (tester) async {
    await _sheet(tester, 'poses', [
      const _Cell(MicroduckPose.idle, 0.4),
      const _Cell(MicroduckPose.idle, 2.6),
      const _Cell(MicroduckPose.walk, 0.0),
      const _Cell(MicroduckPose.walk, 0.22),
      const _Cell(MicroduckPose.run, 0.1),
      const _Cell(MicroduckPose.run, 0.3),
      const _Cell(MicroduckPose.sleep, 0.8),
      const _Cell(MicroduckPose.idle, 10.35, tap: 10.0),
      const _Cell(MicroduckPose.dance, 1.0, skin: MicroduckSkin.grey),
      const _Cell(MicroduckPose.idle, 0.4, skin: MicroduckSkin.grey),
      const _Cell(MicroduckPose.walk, 0.22, skin: MicroduckSkin.grey),
      const _Cell(MicroduckPose.sleep, 0.8, skin: MicroduckSkin.grey),
    ]);
  });

  test('every pose is finite across a minute', () {
    final rig = MicroduckRig();
    final input = MicroduckInput();
    for (final pose in MicroduckPose.values) {
      for (var t = 0.0; t < 60; t += 0.037) {
        rig.solve(pose, t, beat, input);
        for (final v in rig.pose.v) {
          expect(v.isFinite, isTrue, reason: '$pose at $t');
        }
      }
    }
  });
}
