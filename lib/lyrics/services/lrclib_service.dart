import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/song.dart';
import '../models/lyrics_result.dart';
import 'lrc_parser.dart';

/// Fetches lyrics from the LRCLIB public API.
/// https://lrclib.net — no API key required.
///
/// Response priority:
///   syncedLyrics field (LRC format) → [LyricsType.synced]
///   plainLyrics field only          → [LyricsType.plain]
///   404 or both empty               → [LyricsType.none]
///
/// This service never throws — all errors are swallowed and return
/// [LyricsResult.none()] so the caller always gets a usable value.
class LrcLibService {
  static const String _baseUrl = 'https://lrclib.net/api/get';

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
        debugPrint(
          '[LrcLibService] HTTP ${response.statusCode} for "${song.title}"',
        );
        return LyricsResult.none();
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      final synced = json['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        debugPrint('[LrcLibService] Got synced lyrics for "${song.title}"');
        return LyricsResult(
          type: LyricsType.synced,
          lyrics: LrcParser.parseLrc(synced.trim()),
          rawText: synced.trim(),
        );
      }

      final plain = json['plainLyrics'] as String?;
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
      debugPrint('[LrcLibService] Error fetching lyrics: $e');
      return LyricsResult.none();
    }
  }
}
