import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/album_palette.dart';

/// A 64×64 cover of one solid colour, as raw RGBA.
Uint8List _solid(Color c) {
  final bytes = Uint8List(64 * 64 * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = (c.r * 255).round();
    bytes[i + 1] = (c.g * 255).round();
    bytes[i + 2] = (c.b * 255).round();
    bytes[i + 3] = 255;
  }
  return bytes;
}

void main() {
  group('Hue guard', () {
    test('purple and pink hues are pulled out of the band; others pass', () {
      expect(AlbumPalette.guardHue(270), 215);
      expect(AlbumPalette.guardHue(320), 8);
      expect(AlbumPalette.guardHue(120), 120);
      expect(AlbumPalette.guardHue(30), 30);
    });

    test('a purple cover never produces a purple or pink palette', () {
      final palette = albumPaletteFromInts(extractAlbumPalette(_solid(const Color(0xFF7B2FBE))));
      for (final role in [palette.deep, palette.base, palette.vibrant, palette.glow, palette.ground]) {
        expect(AlbumPalette.isGuardedHue(HSLColor.fromColor(role).hue), isFalse, reason: '$role');
      }
    });
  });
}
