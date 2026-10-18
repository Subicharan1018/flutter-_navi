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

  Future<TrendingCharts> charts() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/fetch/trending');
        return TrendingCharts.fromJson(r.data ?? const {});
      });

  /// Songs the charts brought into the library, newest first.
  Future<List<ChartArrival>> recentlyAdded({int limit = 30}) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/fetch/trending/new', queryParameters: {'limit': limit});
        return [
          for (final s in (r.data?['songs'] as List? ?? const []))
            if (s is Map) ChartArrival.fromJson(Map<String, dynamic>.from(s)),
        ]..removeWhere((a) => a.songId.isEmpty);
      });

  Future<T> _wrap<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw TrendingException(switch (e.response?.statusCode) {
        null => 'Can’t reach the server. Check your connection.',
        401 => 'Sign in again to see the charts.',
        _ => 'The charts aren’t available right now.',
      });
    }
  }
}
