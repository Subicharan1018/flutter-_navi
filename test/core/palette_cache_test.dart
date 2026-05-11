// =============================================================================
// palette_cache_test.dart
//
// Tests for the LRU palette cache in lib/core/palette_cache.dart.
//
// Covers:
//   1. Cache hit returns stored colors
//   2. Cache miss returns null via getColorsFor
//   3. LRU eviction at max capacity
//   4. clear() resets all entries
//   5. hasColorsFor guards palette extraction
//   6. update() promotes existing entries to most-recently-used
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/palette_cache.dart';

// ── Test data ─────────────────────────────────────────────────────────────────

List<Color> _palette(int seed) => [
  Color(0xFF000000 + seed),
  Color(0xFF000000 + seed + 1),
  Color(0xFF000000 + seed + 2),
  Color(0xFF000000 + seed + 3),
];

void main() {
  late PaletteCache cache;

  setUp(() {
    // Reset the singleton between tests.
    cache = PaletteCache.instance;
    cache.clear();
  });

  group('PaletteCache', () {
    test('colors returns fallback when empty', () {
      expect(cache.colors.length, 4);
      expect(cache.songId, isNull);
    });

    test('update stores and retrieves palette', () {
      final palette = _palette(100);
      cache.update('song_1', palette);

      expect(cache.hasColorsFor('song_1'), isTrue);
      expect(cache.getColorsFor('song_1'), equals(palette));
      expect(cache.songId, 'song_1');
      expect(cache.colors, equals(palette));
    });

    test('getColorsFor returns null for uncached song', () {
      cache.update('song_1', _palette(100));
      expect(cache.getColorsFor('song_999'), isNull);
      expect(cache.hasColorsFor('song_999'), isFalse);
    });

    test('multiple entries are stored independently', () {
      final p1 = _palette(100);
      final p2 = _palette(200);
      cache.update('song_1', p1);
      cache.update('song_2', p2);

      expect(cache.getColorsFor('song_1'), equals(p1));
      expect(cache.getColorsFor('song_2'), equals(p2));
      expect(cache.length, 2);
    });

    test('LRU eviction removes oldest entry at max capacity', () {
      // Fill to max capacity.
      for (int i = 0; i < PaletteCache.maxEntries; i++) {
        cache.update('song_$i', _palette(i));
      }
      expect(cache.length, PaletteCache.maxEntries);

      // Adding one more should evict the first (song_0).
      cache.update('song_new', _palette(999));
      expect(cache.length, PaletteCache.maxEntries);
      expect(cache.hasColorsFor('song_0'), isFalse,
          reason: 'Oldest entry should be evicted');
      expect(cache.hasColorsFor('song_new'), isTrue);
      // Second-oldest should still be present.
      expect(cache.hasColorsFor('song_1'), isTrue);
    });

    test('getColorsFor promotes entry to most-recently-used', () {
      // Fill to max capacity.
      for (int i = 0; i < PaletteCache.maxEntries; i++) {
        cache.update('song_$i', _palette(i));
      }

      // Access song_0 to promote it to most-recently-used.
      cache.getColorsFor('song_0');

      // Now add a new entry — should evict song_1 (the new oldest), not song_0.
      cache.update('song_new', _palette(999));
      expect(cache.hasColorsFor('song_0'), isTrue,
          reason: 'Accessed entry should be promoted and not evicted');
      expect(cache.hasColorsFor('song_1'), isFalse,
          reason: 'Unpromoted oldest entry should be evicted');
    });

    test('update promotes existing entry on re-update', () {
      for (int i = 0; i < PaletteCache.maxEntries; i++) {
        cache.update('song_$i', _palette(i));
      }

      // Re-update song_0 with new colors — should promote it.
      final newPalette = _palette(5000);
      cache.update('song_0', newPalette);
      expect(cache.getColorsFor('song_0'), equals(newPalette));

      // Add a new entry — should evict song_1, not song_0.
      cache.update('song_extra', _palette(9999));
      expect(cache.hasColorsFor('song_0'), isTrue);
      expect(cache.hasColorsFor('song_1'), isFalse);
    });

    test('clear removes all entries', () {
      cache.update('song_1', _palette(100));
      cache.update('song_2', _palette(200));
      expect(cache.length, 2);

      cache.clear();
      expect(cache.length, 0);
      expect(cache.songId, isNull);
      expect(cache.hasColorsFor('song_1'), isFalse);
    });

    test('colors getter returns current song palette after update', () {
      final p1 = _palette(100);
      final p2 = _palette(200);

      cache.update('song_1', p1);
      expect(cache.colors, equals(p1));

      cache.update('song_2', p2);
      expect(cache.colors, equals(p2),
          reason: 'colors should reflect the most recently updated song');
    });
  });
}
