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

/// Revision of the lookup itself (matching, sources). A remembered "no lyrics"
/// written under an older revision is asked about again, once; found lyrics
/// are kept. Bump it whenever the lookup learns to find songs it used to miss.
/// 3: a failed request is no longer remembered as "no lyrics", and the server
/// matches multi-artist and renamed songs.
const kLookupRev = 3;

/// How long "every source said it has nothing" is believed before asking again.
const _kMissTtl = Duration(hours: 2);

/// Plain text may hide synced lyrics that a source gained since: a cached
/// plain result older than this is looked at again, once per app session.
const _kPlainRecheckAfter = Duration(minutes: 15);

/// Orchestrates the lyrics waterfall, best source first:
///   0. a `.lrc` beside a file on this device
///   1. the local shared_preferences cache
///   2. Subsonic getLyricsBySongId (the file's own tags / sidecar); synced wins
///   3. the shuffle server's proxy (lrc.red → BetterLyrics → YouTube Music →
///      optional Spotify wrapper, as switched on in Settings): word timing
///      where a source has it
///   4. LRCLIB public API
///   5. plain text from step 2, when nothing synced turned up
///
/// Every step ends found / nothing there / could not be reached. "No lyrics"
/// is remembered only when every step answered; if anything could not be
/// reached the result is [LyricsResult.unreachable] and nothing is cached, so
/// one flaky request never hides a song.
///
/// Always returns a [LyricsResult]; never throws to the caller.
class LyricsRepository {
  final SubsonicService _subsonic;
  final LrcLibService _lrcLib;
  final LyricsServerApi? _server;
  final List<LyricsSource> Function() _sources;
  final DateTime Function() _now;

  /// Lyrics kept beside a file on this device (sidecar `.lrc` or tags).
  final Future<String?> Function(String songId)? _deviceLyrics;

  /// Songs whose cached plain text was already looked at again this session.
  final Set<String> _plainRechecked = {};

  LyricsRepository({
    required SubsonicService subsonic,
    LrcLibService? lrcLib,
    LyricsServerApi? server,
    List<LyricsSource> Function()? sources,
    Future<String?> Function(String songId)? deviceLyrics,
    DateTime Function()? now,
  }) : _subsonic = subsonic,
       _lrcLib = lrcLib ?? LrcLibService(),
       _server = server,
       _sources = sources ?? (() => const []),
       _deviceLyrics = deviceLyrics,
       _now = now ?? DateTime.now;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// [refresh] is the "Search again" button: it skips a remembered "no lyrics"
  /// and plain text, and tells the server to ask its sources again.
  Future<LyricsResult> getLyrics(Song song, {bool refresh = false}) async {
    // Step 0 — a .lrc next to the local file beats every online source.
    final device = await _fromDevice(song.id);
    if (device != null) return device.withSource('device');

    // Step 1 — local cache
    LyricsResult? plainKept;
    final cached = await _readCache(song.id);
    if (cached != null) {
      final r = cached.result;
      if (r.type == LyricsType.synced) {
        debugPrint('[LyricsRepository] Cache hit for "${song.title}"');
        return r;
      }
      if (r.type == LyricsType.none && !refresh && cached.isFreshMiss(_now())) {
        return r;
      }
      if (r.type == LyricsType.plain) {
        if (!refresh && !_plainDue(song.id, cached)) return r;
        if (!refresh) return _recheckPlain(song, r);
        plainKept = r;
      }
    }

    var failed = false;

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
      failed = true;
    }

    // Step 3 — the proxy's sources. A word-timed answer is the best there is.
    final proxy = await _fromProxy(song, refresh: refresh);
    final online = proxy.result;
    failed = failed || proxy.failed;
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
    failed = failed || lrcLibResult.unreachable;

    // Step 5 — plain text, from the best place that had any.
    final plain =
        plainFromServer ??
        plainKept ??
        online ??
        (lrcLibResult.type == LyricsType.plain ? lrcLibResult : null);
    if (plain != null) {
      await _cache(song.id, plain);
      debugPrint('[LyricsRepository] final result (plain) for "${song.title}"');
      return plain;
    }
    if (failed) {
      // Something could not be reached: nobody said "no". Remember nothing,
      // so the next open (or "Try again") asks again.
      debugPrint('[LyricsRepository] unreachable for "${song.title}"');
      return LyricsResult.unreachable();
    }
    final none = LyricsResult.none();
    await _cache(song.id, none);
    debugPrint('[LyricsRepository] final result (none) for "${song.title}"');
    return none;
  }

  /// Plain text found earlier may be hiding synced lyrics that a source has
  /// since gained: ask the proxy once per session, keep the plain on any miss.
  bool _plainDue(String songId, _Cached cached) =>
      !_plainRechecked.contains(songId) &&
      _now().difference(cached.at) > _kPlainRecheckAfter;

  Future<LyricsResult> _recheckPlain(Song song, LyricsResult plain) async {
    _plainRechecked.add(song.id);
    final proxy = await _fromProxy(song);
    final online = proxy.result;
    if (online != null && online.type == LyricsType.synced) {
      await _cache(song.id, online);
      return online;
    }
    return plain;
  }

  /// The shuffle server's third-party sources. `result` is null when none is
  /// switched on, the song is only on this device, or the server has nothing;
  /// `failed` is true when it could not find out (no network, timeout, 401,
  /// 429, 5xx, a 404 with `retry`, or an answer that does not parse), so the
  /// caller never remembers that as "no lyrics".
  Future<({LyricsResult? result, bool failed})> _fromProxy(
    Song song, {
    bool refresh = false,
  }) async {
    final server = _server;
    final sources = _sources();
    if (server == null || sources.isEmpty || isLocalSongId(song.id)) {
      return (result: null, failed: false);
    }
    try {
      final got = await server.fetchSynced(
        songId: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        durationSeconds: song.duration,
        sources: [for (final s in sources) s.wire],
        refresh: refresh,
      );
      if (got == null) return (result: null, failed: false);
      final synced = got.sync != 'plain' && LrcParser.isLrcFormat(got.lrc);
      final lyrics = synced ? LrcParser.parseLrc(got.lrc) : LrcParser.parsePlain(got.lrc);
      if (lyrics.isEmpty) return (result: null, failed: true);
      return (
        result: LyricsResult(
          type: synced ? LyricsType.synced : LyricsType.plain,
          lyrics: lyrics,
          rawText: got.lrc,
          source: got.source,
        ),
        failed: false,
      );
    } catch (e) {
      debugPrint('[LyricsRepository] proxy error: $e');
      return (result: null, failed: true);
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
      final json = jsonEncode({
        ...result.toJson(),
        'at': _now().millisecondsSinceEpoch,
        'rev': kLookupRev,
      });
      await prefs.setString('$_kCachePrefix$songId', json);
    } catch (e) {
      debugPrint('[LyricsRepository] Cache write error: $e');
    }
  }

  Future<_Cached?> _readCache(String songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_kCachePrefix$songId');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      return _Cached(
        LyricsResult.fromJson(json, _parseCached),
        DateTime.fromMillisecondsSinceEpoch((json['at'] as num?)?.toInt() ?? 0),
        (json['rev'] as num?)?.toInt() ?? 0,
      );
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

/// A cache entry with the time and lookup revision it was written under.
class _Cached {
  final LyricsResult result;
  final DateTime at;
  final int rev;
  const _Cached(this.result, this.at, this.rev);

  /// A remembered "no lyrics" counts only when this build's lookup wrote it
  /// and it is recent; an older one (before the lookup learned more) is asked
  /// about again.
  bool isFreshMiss(DateTime now) => rev >= kLookupRev && now.difference(at) < _kMissTtl;
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
