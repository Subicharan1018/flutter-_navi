import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/song.dart';
import '../../providers/settings_provider.dart';
import '../../services/subsonic_service.dart';
import '../models/lyric_line.dart';
import '../models/lyrics_result.dart';
import 'lrc_parser.dart';
import 'lrclib_service.dart';

/// Cache key prefix — bump the version suffix to invalidate all stored lyrics.
const _kCachePrefix = 'lyrics_v1_';

/// Orchestrates the 3-step lyrics waterfall:
///   1. Local shared_preferences cache
///   2. Subsonic getLyrics (artist + title)
///   3. LRCLIB public API
///
/// Always returns a [LyricsResult]; never throws to the caller.
class LyricsRepository {
  final SubsonicService _subsonic;
  final LrcLibService _lrcLib;

  LyricsRepository({required SubsonicService subsonic, LrcLibService? lrcLib})
    : _subsonic = subsonic,
      _lrcLib = lrcLib ?? LrcLibService();

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<LyricsResult> getLyrics(Song song) async {
    // Step 1 — local cache
    final cached = await _fromCache(song.id);
    if (cached != null) {
      debugPrint('[LyricsRepository] Cache hit for "${song.title}"');
      return cached;
    }

    // Step 2 — OpenSubsonic getLyricsBySongId (reads FLAC tags + sidecar .lrc)
    try {
      final entry = await _subsonic.getLyricsBySongId(song.id);
      if (entry != null) {
        final isSynced = entry['synced'] == true;
        final lines = entry['line'];
        final offsetMs = (entry['offset'] as num?)?.toInt() ?? 0;

        if (lines is List && lines.isNotEmpty) {
          final syncedLyrics = SyncedLyrics.fromStructuredLines(
            lines,
            offsetMs: offsetMs,
            synced: isSynced,
          );

          if (syncedLyrics.isNotEmpty) {
            // Serialise as plain LRC text for cache compatibility.
            // We encode the raw lines JSON as the rawText so _parseCached can
            // restore them without re-fetching the network.
            final rawText = _structuredLinesToLrc(lines, offsetMs, isSynced);
            final result = LyricsResult(
              type: isSynced ? LyricsType.synced : LyricsType.plain,
              lyrics: syncedLyrics,
              rawText: rawText,
            );
            debugPrint(
              '[LyricsRepository] OpenSubsonic hit (${result.type.name}) for "${song.title}"',
            );
            await _cache(song.id, result);
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('[LyricsRepository] getLyricsBySongId error: $e');
    }

    // Step 3 — LRCLIB
    final lrcLibResult = await _lrcLib.fetch(song);
    await _cache(song.id, lrcLibResult);
    debugPrint(
      '[LyricsRepository] LRCLIB result (${lrcLibResult.type.name}) for "${song.title}"',
    );
    return lrcLibResult;
  }

  /// Converts a structured-lyrics line list back to plain LRC text for caching.
  /// This avoids a separate serialisation format — we just write an LRC string
  /// that the existing [LrcParser.parseLrc] can restore on cache-hit.
  static String _structuredLinesToLrc(
    List<dynamic> lines,
    int offsetMs,
    bool synced,
  ) {
    if (!synced) {
      // Plain text — one line per entry
      return lines
          .whereType<Map>()
          .map((l) => (l['value'] ?? '').toString().trim())
          .where((t) => t.isNotEmpty)
          .join('\n');
    }
    final buf = StringBuffer();
    for (final item in lines) {
      if (item is! Map) continue;
      final text = (item['value'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final startMs = (item['start'] as num?)?.toInt() ?? 0;
      final adjusted = (startMs + offsetMs).clamp(0, 9999999);
      final d = Duration(milliseconds: adjusted);
      final mm = d.inMinutes.toString().padLeft(2, '0');
      final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
      final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
      buf.writeln('[$mm:$ss.$ms]$text');
    }
    return buf.toString().trim();
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────

  Future<void> _cache(String songId, LyricsResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(result.toJson());
      await prefs.setString('$_kCachePrefix$songId', json);
    } catch (e) {
      debugPrint('[LyricsRepository] Cache write error: $e');
    }
  }

  Future<LyricsResult?> _fromCache(String songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_kCachePrefix$songId');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      return LyricsResult.fromJson(json, _parseCached);
    } catch (e) {
      debugPrint('[LyricsRepository] Cache read error: $e');
      return null;
    }
  }

  /// Restores a [SyncedLyrics] from cached raw text + type name.
  static SyncedLyrics? _parseCached(String typeName, String text) {
    if (text.isEmpty) return null;
    try {
      if (typeName == LyricsType.synced.name) {
        return LrcParser.parseLrc(text);
      } else if (typeName == LyricsType.plain.name) {
        return LrcParser.parsePlain(text);
      }
    } catch (e) {
      debugPrint('[LyricsRepository] Cache parse error: $e');
    }
    return null;
  }
}

// ── Riverpod provider ────────────────────────────────────────────────────────

final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  final subsonic = ref.watch(subsonicServiceProvider);
  return LyricsRepository(subsonic: subsonic);
});
