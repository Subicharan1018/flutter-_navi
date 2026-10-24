// The golden comparator must forgive rasteriser noise and nothing else.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'anti_alias_comparator.dart';

Future<Uint8List> _png(void Function(Canvas c) paint, {int w = 600, int h = 160}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF1C1C1E));
  paint(c);
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// Sizes are the goldens' 3× device pixels: 60 px ≈ 20 pt text.
void _text(Canvas c, String s, Offset at) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: const TextStyle(fontFamily: 'Inter', fontSize: 60, color: Colors.white)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, at);
}

void main() {
  setUpAll(() async {
    // Real glyphs — the test font draws every letter as the same box.
    final loader = FontLoader('Inter')
      ..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Inter-Regular.ttf').readAsBytesSync())));
    await loader.load();
  });

  test('identical images pass', () async {
    final a = await _png((c) => _text(c, 'Thaniye 2:47', const Offset(10, 40)));
    final d = await comparePng(a, a);
    expect(d.different, 0);
  });

  test('sub-pixel and 1 px text shifts (another rasteriser) pass', () async {
    final a = await _png((c) => _text(c, 'Thaniye 2:47', const Offset(10, 40)));
    final b = await _png((c) => _text(c, 'Thaniye 2:47', const Offset(10.4, 40.3)));
    final shifted = await _png((c) => _text(c, 'Thaniye 2:47', const Offset(11, 40)));
    expect((await comparePng(a, b)).different, 0);
    expect((await comparePng(a, shifted)).different, 0);
  });

  test('a missing or replaced icon fails', () async {
    // A 60 px icon (20 pt at 3×), like the queue pills.
    void ring(Canvas c) => c.drawCircle(const Offset(500, 80), 26,
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 6);
    void star(Canvas c) => c.drawPath(
        Path()..moveTo(500, 50)..lineTo(510, 72)..lineTo(530, 80)..lineTo(510, 88)
          ..lineTo(500, 110)..lineTo(490, 88)..lineTo(470, 80)..lineTo(490, 72)..close(),
        Paint()..color = Colors.white);
    final a = await _png((c) {
      _text(c, 'Queue', const Offset(10, 40));
      ring(c);
    });
    final missing = await _png((c) => _text(c, 'Queue', const Offset(10, 40)));
    final replaced = await _png((c) {
      _text(c, 'Queue', const Offset(10, 40));
      star(c);
    });
    expect((await comparePng(a, missing)).different, greaterThan(minCluster));
    expect((await comparePng(a, replaced)).different, greaterThan(0));
  });

  test('content moved by more than a pixel fails', () async {
    final a = await _png((c) => c.drawRect(const Rect.fromLTWH(40, 40, 60, 60), Paint()..color = Colors.white));
    final b = await _png((c) => c.drawRect(const Rect.fromLTWH(46, 40, 60, 60), Paint()..color = Colors.white));
    expect((await comparePng(a, b)).different, greaterThan(0));
  });

  test('changed text fails', () async {
    final a = await _png((c) => _text(c, 'Shuffle', const Offset(10, 40)));
    final b = await _png((c) => _text(c, 'Shufflx', const Offset(10, 40)));
    expect((await comparePng(a, b)).different, greaterThan(0));
  });

  test('different sizes fail', () async {
    final a = await _png((c) {});
    final b = await _png((c) {}, w: 301);
    expect((await comparePng(a, b)).sizeMatches, isFalse);
  });
}
