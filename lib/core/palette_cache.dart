import 'package:flutter/material.dart';

// =============================================================================
// PALETTE CACHE
// Singleton that survives navigation pushes/pops so NowPlayingScreen always
// gets the correct album colours on its very first frame — no flash.
//
// Usage:
//   Read  → PaletteCache.instance.colors
//   Write → PaletteCache.instance.update(songId, colors)
//   Check → PaletteCache.instance.hasColorsFor(songId)
// =============================================================================

class PaletteCache {
  PaletteCache._();
  static final PaletteCache instance = PaletteCache._();

  // ── Defaults match the fallback in _extractPaletteIsolate ─────────────────
  static const List<Color> _kFallback = [
    Color(0xFF1A1A2E),
    Color(0xFF16213E),
    Color(0xFF0F3460),
    Color(0xFF533483),
  ];

  String? _songId;
  List<Color> _colors = _kFallback;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// The four jewel-tone colours for the current song.
  /// Returns the fallback palette if no song has been cached yet.
  List<Color> get colors => _colors;

  /// The song ID whose colours are currently cached, or null if empty.
  String? get songId => _songId;

  /// Returns true when [id] matches the cached song — safe to skip extraction.
  bool hasColorsFor(String id) => _songId == id;

  /// Store a new palette. Call this after [_extractPaletteIsolate] resolves.
  void update(String songId, List<Color> colors) {
    _songId = songId;
    _colors = colors;
  }

  /// Reset to defaults (e.g. on sign-out or server switch).
  void clear() {
    _songId = null;
    _colors = _kFallback;
  }
}