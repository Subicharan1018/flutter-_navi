import 'package:dio/dio.dart';

import '../../online_fetch/data/online_fetch_api.dart' show guardFetchCall;
import 'preview_models.dart';

/// Client for the shuffle server's `/preview-feed` routes. Build it on the fetch Dio, so a slow answer is waited for and a
/// POST is never replayed. Server side: tool/server/preview-feed-v1/.
class PreviewFeedApi {
  final Dio _dio;
  const PreviewFeedApi(this._dio);

  Future<PreviewFeedPage> feed({int limit = 12}) => guardFetchCall(() async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/preview-feed',
      queryParameters: {'limit': limit},
    );
    return PreviewFeedPage.fromJson(r.data ?? const {});
  });

  /// A heart (`yes`) or a swipe past (`no`). [ratio] is how much of the 30 s clip was heard (0 to 1).
  /// A 429 means today's hearts are used up: that is an answer, not a failure.
  Future<PreviewSignalResult> signal(
    PreviewItem item, {
    required bool yes,
    required double ratio,
  }) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/preview-feed/signal',
        data: {
          'key': item.key,
          'title': item.title,
          'artist': item.artist,
          'album': item.album,
          'art_url': item.artUrl ?? '',
          'source': item.source.name,
          'verdict': yes ? 'yes' : 'no',
          'ratio': ratio.clamp(0.0, 1.0),
        },
      );
      return PreviewSignalResult(
        remaining: (r.data?['remaining'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        return const PreviewSignalResult(remaining: 0, capReached: true);
      }
      return guardFetchCall<PreviewSignalResult>(() async => throw e);
    }
  }
}
