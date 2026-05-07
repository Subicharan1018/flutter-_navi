import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/palette_cache.dart';

void main() {
  setUp(() {
    // Reset singleton state before each test to prevent cross-test contamination.
    PaletteCache.instance.clear();
  });

  group('PaletteCache initial state', () {
    test('songId is null initially', () {
      expect(PaletteCache.instance.songId, isNull);
    });

    test('colors returns 4-color fallback palette initially', () {
      final colors = PaletteCache.instance.colors;
      expect(colors.length, equals(4));
      expect(colors[0], equals(const Color(0xFF1A1A2E)));
      expect(colors[1], equals(const Color(0xFF16213E)));
      expect(colors[2], equals(const Color(0xFF0F3460)));
      expect(colors[3], equals(const Color(0xFF533483)));
    });

    test('hasColorsFor returns false for any ID initially', () {
      expect(PaletteCache.instance.hasColorsFor('song1'), isFalse);
      expect(PaletteCache.instance.hasColorsFor(''), isFalse);
    });
  });

  group('PaletteCache update', () {
    test('update sets songId and colors', () {
      PaletteCache.instance.update('song1', [Colors.red, Colors.blue]);
      expect(PaletteCache.instance.songId, equals('song1'));
      expect(PaletteCache.instance.colors, equals([Colors.red, Colors.blue]));
    });

    test('hasColorsFor returns true after update', () {
      PaletteCache.instance.update('song1', [Colors.red]);
      expect(PaletteCache.instance.hasColorsFor('song1'), isTrue);
    });

    test('hasColorsFor returns false for different ID after update', () {
      PaletteCache.instance.update('song1', [Colors.red]);
      expect(PaletteCache.instance.hasColorsFor('song2'), isFalse);
    });

    test('update overwrites previous song entirely', () {
      PaletteCache.instance.update('song1', [Colors.red]);
      PaletteCache.instance.update('song2', [Colors.blue]);

      expect(PaletteCache.instance.songId, equals('song2'));
      expect(PaletteCache.instance.colors, equals([Colors.blue]));
      expect(PaletteCache.instance.hasColorsFor('song1'), isFalse);
      expect(PaletteCache.instance.hasColorsFor('song2'), isTrue);
    });

    test('update with empty colors list is allowed', () {
      PaletteCache.instance.update('song1', []);
      expect(PaletteCache.instance.colors, isEmpty);
      expect(PaletteCache.instance.songId, equals('song1'));
    });
  });

  group('PaletteCache clear', () {
    test('clear resets songId to null', () {
      PaletteCache.instance.update('song1', [Colors.red]);
      PaletteCache.instance.clear();
      expect(PaletteCache.instance.songId, isNull);
    });

    test('clear resets colors to 4-color fallback', () {
      PaletteCache.instance.update('song1', [Colors.red]);
      PaletteCache.instance.clear();

      final colors = PaletteCache.instance.colors;
      expect(colors.length, equals(4));
      expect(colors[0], equals(const Color(0xFF1A1A2E)));
    });

    test('hasColorsFor returns false after clear', () {
      PaletteCache.instance.update('song1', [Colors.red]);
      PaletteCache.instance.clear();
      expect(PaletteCache.instance.hasColorsFor('song1'), isFalse);
    });

    test('clear on already-cleared instance is a no-op', () {
      // Already cleared in setUp — clearing again must not throw.
      expect(() => PaletteCache.instance.clear(), returnsNormally);
      expect(PaletteCache.instance.songId, isNull);
    });
  });
}
