// Puts the design references next to renders of the robot, to
// build/mascot_frames/compare.png, so the two can be looked at together.
//
// The references are not part of the repo: copy PNG versions of them into
// build/ref_png/ (Robot_Ducks_Pollen, robot-graphite-light, sitting,
// 61XOSA-7DGL) first. Without them this test does nothing.
//
//   flutter test test/widgets/microduck_reference_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/widgets/mascot/microduck_mesh.dart';
import 'package:navivibe/widgets/mascot/microduck_painter.dart';
import 'package:navivibe/widgets/mascot/microduck_pose.dart';
import 'package:navivibe/widgets/mascot/microduck_rig.dart';
import 'package:navivibe/widgets/mascot/microduck_texture.dart';

void main() {
  const dir = 'build/ref_png';

  testWidgets('references beside renders', (tester) async {
    if (!Directory(dir).existsSync()) {
      // ignore: avoid_print
      print('no references in $dir: skipped');
      return;
    }
    await tester.runAsync(MicroduckTexture.ensure);
    Future<ui.Image> load(String name) async {
      final codec = await ui.instantiateImageCodec(File('$dir/$name.png').readAsBytesSync());
      return (await codec.getNextFrame()).image;
    }

    final ducks = (await tester.runAsync(() => load('Robot_Ducks_Pollen')))!;
    final graphite = (await tester.runAsync(() => load('robot-graphite-light')))!;
    final sitting = (await tester.runAsync(() => load('sitting')))!;
    final bb8 = (await tester.runAsync(() => load('61XOSA-7DGL')))!;

    const cell = 420.0;
    // Eyes open: the render's blinks are timed on the clock, so pick a time
    // between them.
    const t0 = 1.3;
    final cells = <(ui.Image, Rect?, MicroduckPose, double, MicroduckSkin, bool)>[
      (ducks, Rect.fromLTWH(0, 0, 215, 445), MicroduckPose.idle, t0, MicroduckSkin.blue, true),
      (ducks, Rect.fromLTWH(200, 0, 215, 445), MicroduckPose.idle, t0, MicroduckSkin.grey, true),
      (ducks, Rect.fromLTWH(430, 0, 215, 445), MicroduckPose.idle, t0, MicroduckSkin.white, true),
      (ducks, Rect.fromLTWH(645, 0, 215, 445), MicroduckPose.idle, t0, MicroduckSkin.lilac, true),
      (graphite, null, MicroduckPose.idle, t0, MicroduckSkin.grey, true),
      (sitting, null, MicroduckPose.sit, t0, MicroduckSkin.white, true),
      (bb8, null, MicroduckPose.idle, t0, MicroduckSkin.white, false),
    ];

    const columns = 4;
    final rows = (cells.length * 2 / columns).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, columns * cell, rows * cell), Paint()..color = const Color(0xFFF1EFEA));
    var slot = 0;
    for (final c in cells) {
      final (img, crop, pose, t, skin, render) = c;
      // The reference.
      canvas.save();
      canvas.translate((slot % columns) * cell, (slot ~/ columns) * cell);
      final src = crop ?? Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      final scale = (cell - 20) / (src.width > src.height ? src.width : src.height);
      final dst = Rect.fromCenter(center: const Offset(cell / 2, cell / 2), width: src.width * scale, height: src.height * scale);
      canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
      slot++;
      // The render, in the same colours and a similar stance, on the dark
      // ground it is designed for.
      canvas.save();
      canvas.translate((slot % columns) * cell, (slot ~/ columns) * cell);
      canvas.clipRect(const Rect.fromLTWH(0, 0, cell, cell));
      canvas.drawRect(const Rect.fromLTWH(0, 0, cell, cell), Paint()..color = const Color(0xFF16181C));
      if (render) {
        MicroduckPainter(pose: pose, time: ValueNotifier(t), input: MicroduckInput(), skin: skin).paint(canvas, const Size(cell, cell));
      } else {
        // BB-8's panel work: the render's decals up close, over the torso and head side.
        MicroduckPainter(pose: MicroduckPose.walk, time: ValueNotifier(0.1), input: MicroduckInput(), facingRight: false)
            .paint(canvas, const Size(cell * 1.6, cell * 1.6));
      }
      canvas.restore();
      slot++;
    }
    final image = await tester.runAsync(() => recorder.endRecording().toImage((columns * cell).toInt(), (rows * cell).toInt()));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    Directory('build/mascot_frames').createSync(recursive: true);
    File('build/mascot_frames/compare.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
