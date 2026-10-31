import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/player/mode_buttons.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';

const _white = Color(0xFFFFFFFF);

Future<ByteData> _render(NaviGlyph g, double size, {bool filled = false, double scale = 4}) async {
  final rec = PictureRecorder();
  final canvas = Canvas(rec)..scale(scale);
  NaviGlyphPainter(g, _white, filled).paint(canvas, Size(size, size));
  final px = (size * scale).round();
  final img = await rec.endRecording().toImage(px, px);
  return (await img.toByteData())!;
}

/// Ink (alpha > 0) inside the rect given in 24-unit glyph coordinates.
int _ink(ByteData d, double size, Rect unit, {double scale = 4}) {
  final px = (size * scale).round();
  final k = px / 24;
  var n = 0;
  for (var y = (unit.top * k).floor(); y < (unit.bottom * k).ceil(); y++) {
    for (var x = (unit.left * k).floor(); x < (unit.right * k).ceil(); x++) {
      if (d.getUint8((y * px + x) * 4 + 3) > 0) n++;
    }
  }
  return n;
}

void main() {
  // Where the spark sits on the 24-unit grid, and a corner the shuffle glyph
  // leaves empty.
  const sparkBox = Rect.fromLTRB(14.5, 1.2, 22.7, 9.6);

  test('Smart Shuffle is the shuffle arrows plus a spark in the top-right', () async {
    final smart = await _render(NaviGlyph.smartShuffle, 48);
    final plain = await _render(NaviGlyph.shuffle, 48);
    expect(_ink(smart, 48, sparkBox), greaterThan(60), reason: 'spark is drawn');
    expect(
      _ink(smart, 48, const Rect.fromLTRB(1, 11, 23, 23)),
      greaterThan(100),
      reason: 'the crossed arrows are still there below it',
    );
    expect(smart.buffer.asUint8List(), isNot(plain.buffer.asUint8List()));
  });

  test('is deterministic and non-empty at 16, 24, 32 and 48 px, outline and selected', () async {
    for (final size in [16.0, 24.0, 32.0, 48.0]) {
      for (final filled in [false, true]) {
        final a = await _render(NaviGlyph.smartShuffle, size, filled: filled);
        final b = await _render(NaviGlyph.smartShuffle, size, filled: filled);
        expect(a.buffer.asUint8List(), b.buffer.asUint8List());
        expect(_ink(a, size, const Rect.fromLTRB(0, 0, 24, 24)), greaterThan(40), reason: '$size filled=$filled');
      }
    }
  });

  test('stays inside its 24-unit box', () async {
    final d = await _render(NaviGlyph.smartShuffle, 24, filled: true, scale: 8);
    final px = 24 * 8;
    for (var i = 0; i < px; i++) {
      // Outermost row and column are empty: nothing is clipped at the edge.
      expect(d.getUint8((0 * px + i) * 4 + 3), 0, reason: 'top row, x=$i');
      expect(d.getUint8((i * px + px - 1) * 4 + 3), 0, reason: 'right column, y=$i');
    }
  });

  test('the shuffle control shows the smart glyph only for Smart Shuffle while shuffling', () {
    expect(isSmartShuffleOn(shuffleOn: true, algorithm: ShuffleAlgorithm.smartLocal), isTrue);
    expect(isSmartShuffleOn(shuffleOn: false, algorithm: ShuffleAlgorithm.smartLocal), isFalse);
    expect(isSmartShuffleOn(shuffleOn: true, algorithm: ShuffleAlgorithm.standard), isFalse);
  });
}
