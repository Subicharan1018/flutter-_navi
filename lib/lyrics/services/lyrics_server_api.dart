import 'package:dio/dio.dart';

import '../models/lyric_translation.dart';

/// A lyrics-server request failed. [message] is safe to show as is.
class LyricsServerException implements Exception {
  final String message;
  final int? statusCode;
  const LyricsServerException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// What `GET /lyrics/fetch` answers: [lrc] is enhanced LRC (word tags
/// `<mm:ss.xx>` inside a timed line), [sync] is `word`, `line` or `plain`.
class ProxyLyrics {
  final String source;
  final String sync;
  final String lrc;
  const ProxyLyrics({required this.source, required this.sync, required this.lrc});

  /// Null-safe: an answer without text is not an answer.
  static ProxyLyrics? tryParse(Map<String, dynamic> json) {
    final lrc = json['lrc']?.toString() ?? '';
    if (lrc.trim().isEmpty) return null;
    return ProxyLyrics(
      source: json['source']?.toString() ?? '',
      sync: json['sync']?.toString() ?? 'line',
      lrc: lrc.trim(),
    );
  }

  static ProxyLyrics? fromJson(Map<String, dynamic> json) => tryParse(json);
}

/// Client for the shuffle server's lyrics routes: translation and
/// pronunciation (`POST /lyrics/translate`) and search by lyrics
/// (`GET /search/lyrics`). Build the Dio with `createShuffleDio`.
class LyricsServerApi {
  final Dio _dio;
  const LyricsServerApi(this._dio);

  /// Translates [lines] (the song's lyric lines in order, blanks included) to
  /// [target]. The result lines are index-aligned with [lines]. The server
  /// asks its LLM once per song and target, then serves it from its cache; the
  /// first call can take a while, hence the long receive timeout.
  Future<LyricsTranslation> translate({
    required String songId,
    required String title,
    required String artist,
    required List<String> lines,
    String target = 'en',
  }) => _wrap(() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/lyrics/translate',
      data: {
        'song_id': songId,
        'title': title,
        'artist': artist,
        'target': target,
        'lines': lines,
      },
      options: Options(receiveTimeout: const Duration(seconds: 90)),
    );
    return LyricsTranslation.fromJson(
      r.data ?? const {},
      expectedLines: lines.length,
    );
  });

  /// Songs whose lyrics contain [query], best match first.
  Future<List<LyricMatch>> searchLyrics(String query, {int limit = 20}) =>
      _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>(
          '/search/lyrics',
          queryParameters: {'q': query, 'limit': limit},
        );
        final raw = r.data?['results'];
        return [
          if (raw is List)
            for (final m in raw)
              if (m is Map) LyricMatch.fromJson(Map<String, dynamic>.from(m)),
        ];
      });

  /// Synced lyrics from the third-party [sources] (`LyricsSource.wire` names,
  /// in the order to try), fetched and cached per song by the server. Null when
  /// every source answered and none has the song (404, or 200 without text);
  /// throws [LyricsServerException] for anything else — including a 404 that
  /// says `retry: true` (a source did not answer) — so the caller can tell
  /// "nobody has it" from "could not find out" and fall back.
  ///
  /// [refresh] asks the server to ignore a remembered "nobody has it" and ask
  /// its sources again (the server limits it to a few times an hour).
  Future<ProxyLyrics?> fetchSynced({
    required String songId,
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
    required List<String> sources,
    String? spotifyId,
    bool refresh = false,
  }) => _wrap(() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/lyrics/fetch',
        queryParameters: {
          'song_id': songId,
          'title': title,
          'artist': artist,
          if (album.isNotEmpty) 'album': album,
          if (durationSeconds > 0) 'duration': durationSeconds,
          'sources': sources.join(','),
          if (spotifyId != null && spotifyId.isNotEmpty) 'spotify_id': spotifyId,
          if (refresh) 'refresh': 1,
        },
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      return ProxyLyrics.fromJson(r.data ?? const {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        final body = e.response?.data;
        if (body is Map && body['retry'] == true) {
          throw LyricsServerException(
            body['error'] is String ? body['error'] as String : 'The lyrics sources did not answer.',
            statusCode: 404,
          );
        }
        return null;
      }
      rethrow;
    }
  });

  Future<T> _wrap<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final serverMessage = body is Map && body['error'] is String
          ? body['error'] as String
          : null;
      throw LyricsServerException(switch (code) {
        null => 'Can’t reach the server. Check your connection.',
        401 => 'Sign in again to use lyrics tools.',
        429 => serverMessage ?? 'Too many requests. Try again in a minute.',
        _ => serverMessage ?? 'The lyrics service isn’t available right now.',
      }, statusCode: code);
    }
  }
}
