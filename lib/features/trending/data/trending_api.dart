import 'package:dio/dio.dart';

import 'trending_models.dart';

/// A charts request failed. [message] is safe to show as is.
class TrendingException implements Exception {
  final String message;
  const TrendingException(this.message);

  @override
  String toString() => message;
}

/// Client for the shuffle server's read-only `/fetch/trending` route. Build it
/// with `createShuffleDio` so it shares the shuffle client's auth and retries.
class TrendingApi {
  final Dio _dio;
  const TrendingApi(this._dio);

  Future<TrendingCharts> charts() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/fetch/trending');
      return TrendingCharts.fromJson(r.data ?? const {});
    } on DioException catch (e) {
      throw TrendingException(switch (e.response?.statusCode) {
        null => 'Can’t reach the server. Check your connection.',
        401 => 'Sign in again to see the charts.',
        _ => 'The charts aren’t available right now.',
      });
    }
  }
}
