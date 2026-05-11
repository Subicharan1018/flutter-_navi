import 'dart:collection';
import 'package:flutter/material.dart';

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

  static const int _maxEntries = 50;

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
  List<Color> get colors =>
      _currentSongId != null ? (_cache[_currentSongId!] ?? _kFallback) : _kFallback;

  /// The song ID whose colours are currently active, or null if empty.
  String? get songId => _currentSongId;

  /// Returns true when [id] is present in the cache — safe to skip extraction.
  bool hasColorsFor(String id) => _cache.containsKey(id);

  /// Returns cached colours for [id] and promotes it to most-recently-used.
  /// Returns null on a cache miss.
  List<Color>? getColorsFor(String id) {
    final entry = _cache.remove(id); // ← intentional LRU promotion step 1/2
    if (entry != null) {
      _cache[id] = entry; // ← intentional LRU promotion step 2/2 (moves to tail)
      return entry;
    }
    return null;
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
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}