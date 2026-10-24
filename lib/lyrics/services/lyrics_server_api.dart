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
