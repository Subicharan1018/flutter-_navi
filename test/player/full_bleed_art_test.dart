import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/album_palette.dart';
import 'package:navivibe/player/cover_quality.dart';
import 'package:navivibe/player/full_bleed_art.dart';

double _lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _luminance(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Source-over in sRGB space, as the compositor does.
Color _over(Color top, Color under) => Color.alphaBlend(top, under);

void main() {
  group('the fade', () {
    test('is clear up in the picture, solid at the bottom, and never steps back', () {
      expect(fadeAlphaAt(kTitleZone + 400), 0);
      expect(fadeAlphaAt(0), 1);
      var last = 0.0;
      for (var d = kTitleZone + 200.0; d >= 0; d -= 2) {
        final a = fadeAlphaAt(d);
        expect(a, greaterThanOrEqualTo(last), reason: 'at $d dp above the bottom');
        last = a;
      }
    });

    // Text sits on the bottom kTitleZone dp. Whatever the cover, the colour
    // behind it must hold 4.5:1 for the title (white) and the quieter artist
    // line (white at 58 %), with the worst cover there is: pure white, under
    // the lightest tint a palette can produce.
    final palettes = {
      'fallback (black)': AlbumPalette.fallback,
      // The brightest page the extractor can make: a yellow ground at its
      // lightness cap (0.19) over its deepest tone (lightness 0.085, saturated).
      'light cover': const AlbumPalette(
        deep: Color(0xFF2A2A06),
        base: Color(0xFFE6E600),
        vibrant: Color(0xFFFFFFFF),
        glow: Color(0xFFFFFFFF),
      ),
    };
    for (final MapEntry(:key, :value) in palettes.entries) {
      test('keeps text above 4.5:1 over a pure white cover, $key', () {
        const white = Color(0xFFFFFFFF);
        // Lines of the title block, as dp above the bottom of the art (the
        // block is 86 tall: title 32 + 2, composer 22, artist 19), with the
        // white each is drawn in.
        const lines = [
          ('title', 86.0, 54.0, 1.0),
          ('composer', 54.0, 32.0, 0.82),
          ('artist', 32.0, 0.0, 0.58),
        ];
        for (final (name, from, to, alpha) in lines) {
          for (var d = from; d >= to; d -= 1) {
            final tint = nowPlayingTintAt(value, 0.65).withValues(alpha: fadeAlphaAt(d));
            final behind = _over(tint, white);
            final text = _over(white.withValues(alpha: alpha), behind);
            expect(_contrast(text, behind), greaterThanOrEqualTo(4.5), reason: '$name at $d dp');
          }
        }
      });
    }

    test('the page tint is opaque and runs from lighter to deeper', () {
      const p = AlbumPalette(
        deep: Color(0xFF0E0A26),
        base: Color(0xFF3A2F8F),
        vibrant: Color(0xFFFFFFFF),
        glow: Color(0xFF2D33E0),
      );
      for (final y in [0.0, 0.3, 0.65, 1.0]) {
        expect(nowPlayingTintAt(p, y).a, 1);
      }
      expect(_luminance(nowPlayingTintAt(p, 0)), greaterThan(_luminance(nowPlayingTintAt(p, 1))));
      expect(nowPlayingTintAt(p, 1), p.deep);
      expect(nowPlayingTint(p).colors.every((c) => c.a == 1), isTrue);
    });
  });

  group('which look a cover gets', () {
    const request = NowPlayingCoverRequest('https://x/getCoverArt?id=a&size=1080', 'cover_a_1080', 1080);
    const missing = NowPlayingCoverRequest('', 'cover_a', 1080);

    test('a sharp cover fills the screen', () {
      expect(coverFitsFullBleed(const AsyncData(1080), request), isTrue);
      expect(coverFitsFullBleed(const AsyncData(kFullBleedMinSourcePx), request), isTrue);
    });

    test('a small cover keeps the square layout instead of being upscaled', () {
      expect(coverFitsFullBleed(const AsyncData(kFullBleedMinSourcePx - 1), request), isFalse);
      expect(coverFitsFullBleed(const AsyncData(300), request), isFalse);
    });

    test('a missing or failed cover keeps the square layout', () {
      expect(coverFitsFullBleed(const AsyncData(0), request), isFalse);
      expect(coverFitsFullBleed(const AsyncData(1080), missing), isFalse);
      expect(coverFitsFullBleed(AsyncError<int>('x', StackTrace.empty), request), isFalse);
    });

    test('while it loads the layout does not flip to the square cover and back', () {
      expect(coverFitsFullBleed(const AsyncLoading<int>(), request), isTrue);
    });
  });
}
