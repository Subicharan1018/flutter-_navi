import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/song.dart';
import '../models/lyrics_result.dart';
import 'lrc_parser.dart';
import '../../core/endpoints.dart';

/// Fetches lyrics from the LRCLIB public API.
/// https://lrclib.net — no API key required.
///
/// Response priority:
///   syncedLyrics field (LRC format) → [LyricsType.synced]
///   plainLyrics field only          → [LyricsType.plain]
///   404 or both empty               → [LyricsType.none]
///
/// This service never throws. A clean 404 (or a 200 without lyrics) is
/// [LyricsResult.none()]: LRCLIB answered and has nothing. Anything else
/// (timeout, no network, 429, 5xx, bad JSON) is [LyricsResult.unreachable()],
/// so the caller never remembers a failed request as "no lyrics".
class LrcLibService {
  static const String _baseUrl = Endpoints.lrclibGet;

  final http.Client _client;

  LrcLibService({http.Client? client}) : _client = client ?? http.Client();

  Future<LyricsResult> fetch(Song song) async {
    try {
      final uri = Uri.parse(_baseUrl).replace(
        queryParameters: {
          'artist_name': song.artist,
          'track_name': song.title,
          if (song.album.isNotEmpty) 'album_name': song.album,
          if (song.duration > 0) 'duration': song.duration.toString(),
        },
      );

      debugPrint('[LrcLibService] GET $uri');

      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 404) {
        debugPrint('[LrcLibService] 404 — no match for "${song.title}"');
        return LyricsResult.none();
      }

      if (response.statusCode != 200) {
        // 429, 5xx …: LRCLIB did not answer, which is not "no lyrics".
        debugPrint(
          '[LrcLibService] HTTP ${response.statusCode} for "${song.title}"',
        );
        return LyricsResult.unreachable();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        debugPrint('[LrcLibService] Decoded JSON is not a Map: $decoded');
        return LyricsResult.unreachable();
      }
      final json = Map<String, dynamic>.from(decoded);

      final synced = json['syncedLyrics']?.toString();
      if (synced != null && synced.trim().isNotEmpty) {
        debugPrint('[LrcLibService] Got synced lyrics for "${song.title}"');
        return LyricsResult(
          type: LyricsType.synced,
          lyrics: LrcParser.parseLrc(synced.trim()),
          rawText: synced.trim(),
        );
      }

      final plain = json['plainLyrics']?.toString();
      if (plain != null && plain.trim().isNotEmpty) {
        debugPrint('[LrcLibService] Got plain lyrics for "${song.title}"');
        return LyricsResult(
          type: LyricsType.plain,
          lyrics: LrcParser.parsePlain(plain.trim()),
          rawText: plain.trim(),
        );
      }

      debugPrint(
        '[LrcLibService] Response had no lyrics content for "${song.title}"',
      );
      return LyricsResult.none();
    } catch (e) {
      // A timeout, no network or bad JSON: unreachable, never "no lyrics".
      debugPrint('[LrcLibService] Error fetching lyrics: $e');
      return LyricsResult.unreachable();
    }
  }
}
