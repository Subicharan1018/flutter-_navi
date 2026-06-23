import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';

// =============================================================================
// PALETTE CACHE — LRU, max 50 entries
//
// Singleton that survives navigation pushes/pops so NowPlayingScreen always
// gets the correct album colours on its very first frame — no flash.
//
// Usage:
//   Read current  → PaletteCache.instance.colors
//   Read specific → PaletteCache.instance.getColorsFor(songId)
//   Write         → PaletteCache.instance.update(songId, colors)
//   Check         → PaletteCache.instance.hasColorsFor(songId)
//
// LRU implementation note:
//   Dart's LinkedHashMap is insertion-ordered only — there is NO accessOrder
//   constructor parameter (unlike Java). LRU promotion is achieved via the
//   explicit remove-then-reinsert pattern in getColorsFor() and update().
//   Do NOT remove the _cache.remove() call before _cache[id] = ...; it is
//   intentional and necessary to move the key to the "most recently used"
//   tail position. The eviction policy removes from the head (oldest).
// =============================================================================

class PaletteCache {
  PaletteCache._();
  static final PaletteCache instance = PaletteCache._();

  static const int maxEntries = 50;

  // ── Defaults match the fallback in _extractPaletteIsolate ─────────────────
  static const List<Color> _kFallback = [
    Color(0xFF1A1A2E),
    Color(0xFF16213E),
    Color(0xFF0F3460),
    Color(0xFF533483),
  ];

  // Insertion-ordered map used as an LRU cache.
  // Access (read or write) promotes an entry to the tail via remove+reinsert.
  // Eviction removes from the head (first inserted / least recently used).
  final LinkedHashMap<String, List<Color>> _cache = LinkedHashMap();

  // Tracks the "current" song for backward-compatible getters.
  String? _currentSongId;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// The four colours for the currently loaded song.
  /// Returns the fallback palette if no song has been cached yet.
  List<Color> get colors => _currentSongId != null
      ? (_cache[_currentSongId!] ?? _kFallback)
      : _kFallback;

  /// The song ID whose colours are currently active, or null if empty.
  String? get songId => _currentSongId;

  /// The current number of entries in the cache.
  @visibleForTesting
  int get length => _cache.length;

  /// Returns true when [id] is present in the cache — safe to skip extraction.
  bool hasColorsFor(String id) => _cache.containsKey(id);

  /// Returns cached colours for [id] and promotes it to most-recently-used.
  /// Returns null on a cache miss.
  List<Color>? getColorsFor(String id) {
    final entry = _cache.remove(id); // ← intentional LRU promotion step 1/2
    if (entry != null) {
      _cache[id] =
          entry; // ← intentional LRU promotion step 2/2 (moves to tail)
      return entry;
    }
    return null;
  }

  /// Returns cached colours for [id] WITHOUT promoting it to most-recently-used.
  /// Returns null on a cache miss.
  List<Color>? peekColorsFor(String id) {
    return _cache[id];
  }

  /// Store a new palette and mark [songId] as the active song.
  /// Promotes the entry to most-recently-used and evicts the oldest if needed.
  void update(String songId, List<Color> colors) {
    _currentSongId = songId;
    // Remove before reinserting so the entry moves to the tail (most recent).
    _cache.remove(songId); // ← intentional LRU promotion (see class comment)
    _cache[songId] = colors;
    _evictIfNeeded();
  }

  /// Reset to defaults (e.g. on sign-out or server switch).
  void clear() {
    _currentSongId = null;
    _cache.clear();
  }

  // ── Private ────────────────────────────────────────────────────────────────

  void _evictIfNeeded() {
    // _cache.keys.first is the least-recently-used entry (insertion-order head).
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Extracts colors from [imageUrl] and caches them for [songId].
  /// Returns the extracted/cached 4-color palette.
  Future<List<Color>> extractAndCache(String songId, String imageUrl) async {
    final existing = getColorsFor(songId);
    if (existing != null) return existing;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(
          CachedNetworkImageProvider(imageUrl),
          width: 120,
          height: 120,
        ),
        size: const Size(60, 60), // standard size for fast extraction
        maximumColorCount: 16,
      );

      Color process(Color base, {double satMul = 1.25, double lightMul = 0.48}) {
        final hsl = HSLColor.fromColor(base);
        return hsl
            .withSaturation((hsl.saturation * satMul).clamp(0.08, 1.0))
            .withLightness((hsl.lightness * lightMul).clamp(0.04, 0.34))
            .toColor();
      }

      Color firstNonNull(List<Color?> candidates, Color fallback) {
        for (final c in candidates) {
          if (c != null) return c;
        }
        return fallback;
      }

      final dominant = firstNonNull([
        palette.dominantColor?.color,
        palette.darkVibrantColor?.color,
        palette.darkMutedColor?.color,
        palette.vibrantColor?.color,
        palette.mutedColor?.color,
        palette.lightMutedColor?.color,
      ], const Color(0xFF202022));

      final dominantHsl = HSLColor.fromColor(dominant);
      final derivedVibrant = dominantHsl
          .withSaturation((dominantHsl.saturation + 0.25).clamp(0.20, 1.0))
          .withLightness((dominantHsl.lightness * 0.95).clamp(0.08, 0.48))
          .toColor();
      final derivedAccent = dominantHsl
          .withSaturation((dominantHsl.saturation + 0.12).clamp(0.14, 1.0))
          .withLightness((dominantHsl.lightness * 1.18).clamp(0.12, 0.58))
          .toColor();

      final vibrant = firstNonNull([
        palette.vibrantColor?.color,
        palette.darkVibrantColor?.color,
        palette.lightVibrantColor?.color,
        palette.mutedColor?.color,
      ], derivedVibrant);

      final darkAccent = firstNonNull([
        palette.darkMutedColor?.color,
        palette.darkVibrantColor?.color,
        palette.mutedColor?.color,
        palette.dominantColor?.color,
      ], dominant);

      final lightAccent = firstNonNull([
        palette.lightVibrantColor?.color,
        palette.lightMutedColor?.color,
        palette.vibrantColor?.color,
        palette.mutedColor?.color,
      ], derivedAccent);

      final colors = [
        process(dominant, satMul: 1.10, lightMul: 0.44),
        process(vibrant, satMul: 1.35, lightMul: 0.52),
        process(darkAccent, satMul: 1.05, lightMul: 0.40),
        process(lightAccent, satMul: 1.20, lightMul: 0.58),
      ];

      update(songId, colors);
      return colors;
    } catch (_) {
      final fallback = _kFallback;
      update(songId, fallback);
      return fallback;
    }
  }
}
