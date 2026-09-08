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

  // In-flight extraction deduplication map to prevent redundant parallel extractions
  final Map<String, Future<List<Color>>> _inFlight = {};

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
      _currentSongId = id;
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
    _inFlight.clear();
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
  /// Deduplicates in-flight calls so multiple widgets don't parallel-decode the same image.
  Future<List<Color>> extractAndCache(String songId, String imageUrl) {
    final existing = getColorsFor(songId);
    if (existing != null) return Future.value(existing);

    if (_inFlight.containsKey(songId)) {
      return _inFlight[songId]!;
    }

    final future = _doExtract(songId, imageUrl).whenComplete(() {
      _inFlight.remove(songId);
    });
    _inFlight[songId] = future;
    return future;
  }

  Future<List<Color>> _doExtract(String songId, String imageUrl) async {
    final existing = getColorsFor(songId);
    if (existing != null) return existing;

    if (imageUrl.isEmpty) {
      final fallback = _kFallback;
      update(songId, fallback);
      return fallback;
    }

    try {
      final imageProvider = ResizeImage(
        CachedNetworkImageProvider(imageUrl),
        width: 120,
        height: 120,
      );
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(60, 60), // standard size for fast extraction
        maximumColorCount: 16,
      );

      try {
        await imageProvider.evict();
      } catch (e) {
        debugPrint('⚠️ Error evicting palette image: $e');
      }

      // Check if dominantColor is a usable accent: reasonably saturated and not near-black or near-white.
      bool isUsableAccent(Color? c) {
        if (c == null) return false;
        final hsl = HSLColor.fromColor(c);
        return hsl.saturation >= 0.18 && hsl.lightness >= 0.12 && hsl.lightness <= 0.88;
      }

      final dominant = palette.dominantColor?.color;
      final dominantIsUsable = isUsableAccent(dominant);

      // Extract candidate colors from palette swatches.
      // If dominantColor is a usable accent, prioritize it first so the primary theme matches
      // the actual dominant artwork hue rather than a tiny high-saturation text/sticker artifact.
      // If dominantColor is too dark/light/desaturated (e.g. black cover with red logo),
      // fall back to vibrant colors.
      final allSwatches = [
        if (dominantIsUsable) dominant!,
        palette.vibrantColor?.color,
        palette.lightVibrantColor?.color,
        palette.darkVibrantColor?.color,
        palette.mutedColor?.color,
        palette.lightMutedColor?.color,
        palette.darkMutedColor?.color,
        if (!dominantIsUsable && dominant != null) dominant,
        ...palette.colors,
      ].whereType<Color>().toList();

      // Find swatches with actual color (saturation > 0.15)
      final colorfulSwatches = allSwatches.where((c) {
        final hsl = HSLColor.fromColor(c);
        return hsl.saturation > 0.15 && hsl.lightness > 0.08 && hsl.lightness < 0.92;
      }).toList();

      Color primary;
      Color vibrant;
      Color accent;
      Color highlight;

      if (colorfulSwatches.isNotEmpty) {
        primary = colorfulSwatches.first;
        vibrant = colorfulSwatches.length > 1 ? colorfulSwatches[1] : primary;
        accent = colorfulSwatches.length > 2 ? colorfulSwatches[2] : vibrant;
        highlight = colorfulSwatches.length > 3 ? colorfulSwatches[3] : accent;
      } else {
        primary = palette.dominantColor?.color ?? const Color(0xFFE50914);
        vibrant = palette.vibrantColor?.color ?? primary;
        accent = palette.lightVibrantColor?.color ?? vibrant;
        highlight = palette.darkVibrantColor?.color ?? accent;
      }

      // Boost saturation & tune lightness for Apple Music luminous glow.
      // Hue shifts are bounded within ±25° of the source hue so the derived palette
      // provides rich analogous depth without shifting into an alien hue family (e.g. red into green).
      Color tuneColor(Color c, {double minLight = 0.35, double maxLight = 0.62, double hueShift = 0.0}) {
        final hsl = HSLColor.fromColor(c);
        final newHue = ((hsl.hue + hueShift) % 360.0 + 360.0) % 360.0;
        final newSat = (hsl.saturation * 1.35).clamp(0.70, 1.0);
        final newLight = hsl.lightness.clamp(minLight, maxLight);
        return HSLColor.fromAHSL(1.0, newHue, newSat, newLight).toColor();
      }

      final c0 = tuneColor(primary, minLight: 0.32, maxLight: 0.48);
      final c1 = tuneColor(vibrant, minLight: 0.45, maxLight: 0.65, hueShift: 12);
      final c2 = tuneColor(accent, minLight: 0.40, maxLight: 0.60, hueShift: -15);
      final c3 = tuneColor(highlight, minLight: 0.35, maxLight: 0.55, hueShift: 24);

      final colors = [c0, c1, c2, c3];
      update(songId, colors);
      return colors;
    } catch (_) {
      final fallback = _kFallback;
      update(songId, fallback);
      return fallback;
    }
  }
}
