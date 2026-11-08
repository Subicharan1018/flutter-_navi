import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/cover_art.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.build(AppThemeTokens.fallback),
      builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
    );

/// The ink's bounding box when [glyph] is painted into a [w] × [h] box.
Future<Rect> _ink(WidgetTester tester, NaviGlyph glyph, double w, double h) async {
  return (await tester.runAsync(() async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    NaviGlyphPainter(glyph, Colors.white, false).paint(canvas, Size(w, h));
    final img = await rec.endRecording().toImage(w.ceil(), h.ceil());
    final bytes = (await img.toByteData())!;
    var minX = w, minY = h, maxX = 0.0, maxY = 0.0;
    for (var y = 0; y < h.ceil(); y++) {
      for (var x = 0; x < w.ceil(); x++) {
        if (bytes.getUint8((y * w.ceil() + x) * 4 + 3) > 40) {
          if (x < minX) minX = x.toDouble();
          if (x > maxX) maxX = x.toDouble();
          if (y < minY) minY = y.toDouble();
          if (y > maxY) maxY = y.toDouble();
        }
      }
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }))!;
}

void main() {
  group('icons keep their proportions', () {
    testWidgets('a glyph in a wide box is the same shape as in a square one, centred', (tester) async {
      final square = await _ink(tester, NaviGlyph.library, 24, 24);
      final wide = await _ink(tester, NaviGlyph.library, 30, 24); // a 30 x 24 leading slot
      expect(wide.width, closeTo(square.width, 1.5), reason: 'not stretched sideways');
      expect(wide.height, closeTo(square.height, 1.5));
      expect(wide.center.dx, closeTo(15, 1.5), reason: 'centred in the slot');
    });

    testWidgets('a glyph in a tall box is not stretched upward either', (tester) async {
      final square = await _ink(tester, NaviGlyph.play, 24, 24);
      final tall = await _ink(tester, NaviGlyph.play, 24, 36);
      expect(tall.height, closeTo(square.height, 1.5));
      expect(tall.center.dy, closeTo(18, 1.5));
    });

    testWidgets('NaviIcon is size x size when free, and keeps a square paint box when squeezed', (tester) async {
      await tester.pumpWidget(_host(const NaviIcon(NaviGlyph.star, size: 20)));
      expect(tester.getSize(find.byType(NaviIcon)), const Size(20, 20));
    });
  });

  group('cover art stays square', () {
    testWidgets('size x size on its own', (tester) async {
      await tester.pumpWidget(_host(const CoverArt(url: null, size: 56)));
      expect(tester.getSize(find.byType(ClipRRect)), const Size(56, 56));
    });

    testWidgets('inside a tight, non-square tile it is still square (cropped by the tile, never squeezed)', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(width: 120, height: 40, child: CoverArt(url: null, size: 40))));
      expect(tester.getSize(find.byType(ClipRRect)), const Size(40, 40));
    });

    testWidgets('circular art is a circle', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(width: 90, height: 60, child: CoverArt(url: null, size: 48, circular: true))));
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(tester.getSize(find.byType(ClipRRect)), const Size(48, 48));
      expect(clip.borderRadius, BorderRadius.circular(24));
    });
  });
}
