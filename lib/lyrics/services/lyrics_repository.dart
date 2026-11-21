import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/local_library/logic/local_library_providers.dart';
import '../../features/local_library/logic/local_models.dart' show isLocalSongId;
import '../../models/song.dart';
import '../../providers/settings_provider.dart';
import '../../services/subsonic_service.dart';
import '../controllers/lyrics_sources_provider.dart';
import '../controllers/lyrics_translation_controller.dart' show lyricsServerApiProvider;
import '../models/lyric_line.dart';
import '../models/lyrics_result.dart';
import 'lrc_parser.dart';
import 'lrclib_service.dart';
import 'lyrics_server_api.dart';

/// Cache key prefix — bump the version suffix to invalidate all stored lyrics.
/// v2: entries carry their source, and word-timed lyrics are kept.
const _kCachePrefix = 'lyrics_v2_';

/// How long "nobody has these lyrics" is believed before asking again.
const _kMissTtl = Duration(hours: 12);

/// Orchestrates the lyrics waterfall, best source first:
///   0. a `.lrc` beside a file on this device
///   1. the local shared_preferences cache
///   2. Subsonic getLyricsBySongId (the file's own tags / sidecar); synced wins
///   3. the shuffle server's proxy (lrc.red → BetterLyrics → optional Spotify
///      wrapper, as switched on in Settings): word timing where a source has it
///   4. LRCLIB public API
///   5. plain text from step 2, when nothing synced turned up
///
/// Always returns a [LyricsResult]; never throws to the caller.
class LyricsRepository {
  final SubsonicService _subsonic;
  final LrcLibService _lrcLib;
  final LyricsServerApi? _server;
  final List<LyricsSource> Function() _sources;

  /// Lyrics kept beside a file on this device (sidecar `.lrc` or tags).
  final Future<String?> Function(String songId)? _deviceLyrics;

  LyricsRepository({
    required SubsonicService subsonic,
    LrcLibService? lrcLib,
    LyricsServerApi? server,
    List<LyricsSource> Function()? sources,
    Future<String?> Function(String songId)? deviceLyrics,
  }) : _subsonic = subsonic,
       _lrcLib = lrcLib ?? LrcLibService(),
       _server = server,
       _sources = sources ?? (() => const []),
       _deviceLyrics = deviceLyrics;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<LyricsResult> getLyrics(Song song) async {
    // Step 0 — a .lrc next to the local file beats every online source.
    final device = await _fromDevice(song.id);
    if (device != null) return device.withSource('device');

    // Step 1 — local cache
    final cached = await _fromCache(song.id);
    if (cached != null) {
      debugPrint('[LyricsRepository] Cache hit for "${song.title}"');
      return cached;
    }

    // Step 2 — OpenSubsonic getLyricsBySongId (reads FLAC tags + sidecar .lrc).
    // Device songs are unknown to the server.
    LyricsResult? plainFromServer;
    try {
      final entry = isLocalSongId(song.id) ? null : await _subsonic.getLyricsBySongId(song.id);
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
              source: 'server',
            );
            debugPrint(
              '[LyricsRepository] OpenSubsonic hit (${result.type.name}) for "${song.title}"',
            );
            if (isSynced) {
              await _cache(song.id, result);
              return result;
            }
            plainFromServer = result; // keep looking for a synced version
          }
        }
      }
    } catch (e) {
      debugPrint('[LyricsRepository] getLyricsBySongId error: $e');
    }

    // Step 3 — the proxy's sources. A word-timed answer is the best there is.
    final online = await _fromProxy(song);
    if (online != null && online.type == LyricsType.synced) {
      await _cache(song.id, online);
      return online;
    }

    // Step 4 — LRCLIB
    final lrcLibResult = (await _lrcLib.fetch(song)).withSource('lrclib');
    if (lrcLibResult.type == LyricsType.synced) {
      await _cache(song.id, lrcLibResult);
      return lrcLibResult;
    }

    // Step 5 — plain text, from the best place that had any.
    final plain = plainFromServer ?? online ?? (lrcLibResult.type == LyricsType.plain ? lrcLibResult : null);
    final result = plain ?? LyricsResult.none();
    await _cache(song.id, result);
    debugPrint('[LyricsRepository] final result (${result.type.name}) for "${song.title}"');
    return result;
  }

  /// The shuffle server's third-party sources; null when none is switched on,
  /// the song is only on this device, or the server has nothing / can't be
  /// reached (the next source in the waterfall then gets its turn).
  Future<LyricsResult?> _fromProxy(Song song) async {
    final server = _server;
    final sources = _sources();
    if (server == null || sources.isEmpty || isLocalSongId(song.id)) return null;
    try {
      final got = await server.fetchSynced(
        songId: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        durationSeconds: song.duration,
        sources: [for (final s in sources) s.wire],
      );
      if (got == null) return null;
      final synced = got.sync != 'plain' && LrcParser.isLrcFormat(got.lrc);
      final lyrics = synced ? LrcParser.parseLrc(got.lrc) : LrcParser.parsePlain(got.lrc);
      if (lyrics.isEmpty) return null;
      return LyricsResult(
        type: synced ? LyricsType.synced : LyricsType.plain,
        lyrics: lyrics,
        rawText: got.lrc,
        source: got.source,
      );
    } catch (e) {
      debugPrint('[LyricsRepository] proxy error: $e');
      return null;
    }
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

  Future<LyricsResult?> _fromDevice(String songId) async {
    try {
      final text = await _deviceLyrics?.call(songId);
      if (text == null || text.trim().isEmpty) return null;
      final synced = LrcParser.isLrcFormat(text);
      final lyrics = synced ? LrcParser.parseLrc(text) : LrcParser.parsePlain(text);
      if (lyrics.isEmpty) return null;
      return LyricsResult(
        type: synced ? LyricsType.synced : LyricsType.plain,
        lyrics: lyrics,
        rawText: text,
      );
    } catch (e) {
      debugPrint('[LyricsRepository] Device lyrics error: $e');
      return null;
    }
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────

  Future<void> _cache(String songId, LyricsResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode({...result.toJson(), 'at': DateTime.now().millisecondsSinceEpoch});
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
      final result = LyricsResult.fromJson(json, _parseCached);
      // Only synced lyrics are kept for good; a miss or plain text is asked
      // about again later (a source may have the song by then).
      if (result.type != LyricsType.synced) {
        final at = DateTime.fromMillisecondsSinceEpoch((json['at'] as num?)?.toInt() ?? 0);
        if (DateTime.now().difference(at) > _kMissTtl) return null;
      }
      return result;
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
  final local = ref.watch(localLibraryServiceProvider);
  return LyricsRepository(
    subsonic: subsonic,
    deviceLyrics: local.lyricsFor,
    server: ref.watch(lyricsServerApiProvider),
    // Read at fetch time: switching a source on applies to the next song.
    sources: () => ref.read(lyricsSourcesProvider.notifier).ordered,
  );
});
