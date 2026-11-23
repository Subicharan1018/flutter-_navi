import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Distinct, textured stand-ins for album covers (two-tone gradients with
/// rings, stripes or dots) so goldens show how art-driven tiles really look.
/// Keys are `c0`, `c1`, … ; hand them to `debugCoverImageOverride`.
Future<Map<String, ImageProvider>> texturedCovers([int count = 12]) async {
  const hues = [14.0, 24.0, 38.0, 200.0, 210.0, 220.0, 12.0, 30.0, 205.0, 18.0, 215.0, 35.0];
  final out = <String, ImageProvider>{};
  for (var i = 0; i < count; i++) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const s = 96.0;
    final a = HSLColor.fromAHSL(1, hues[i % hues.length], 0.34, 0.42).toColor();
    final b = HSLColor.fromAHSL(1, (hues[i % hues.length] + 30) % 360, 0.30, 0.20).toColor();
    c.drawRect(
      const Rect.fromLTWH(0, 0, s, s),
      Paint()..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(s, s), [a, b]),
    );
    final ink = Paint()
      ..color = const Color(0x22FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    switch (i % 3) {
      case 0:
        for (var r = 14.0; r < 80; r += 14) {
          c.drawCircle(Offset(s * (0.3 + 0.1 * (i % 4)), s * 0.6), r, ink);
        }
      case 1:
        for (var x = -s; x < s * 2; x += 14) {
          c.drawLine(Offset(x, s), Offset(x + s, 0), ink);
        }
      default:
        for (var k = 0; k < 14; k++) {
          c.drawCircle(Offset((k * 37 + i * 11) % s, (k * 53 + i * 7) % s), 4 + (k % 3) * 3, ink..style = PaintingStyle.fill);
        }
    }
    final pic = rec.endRecording();
    final img = await pic.toImage(s.toInt(), s.toInt());
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    out['c$i'] = MemoryImage(bytes.buffer.asUint8List());
  }
  // `math` keeps the import honest for future patterns.
  assert(math.pi > 3);
  return out;
}
