import 'package:dio/dio.dart';

import 'fetch_models.dart';

/// A "Search online" request failed. [message] is safe to show as is.
class OnlineFetchException implements Exception {
  final String message;
  final int? statusCode;
  const OnlineFetchException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Client for the shuffle server's /fetch routes. Build it with
/// `createShuffleDio` so it shares the shuffle client's auth and retry rules
/// (POSTs are never replayed after a timeout, so a search or download is
/// never created twice).
class OnlineFetchApi {
  final Dio _dio;
  const OnlineFetchApi(this._dio);

  /// Whether this account may use online search. Any failure means no — the
  /// button simply doesn't appear.
  Future<bool> enabled() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/fetch/enabled');
      return r.data?['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<int> startSearch(String query) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>('/fetch/searches', data: {'query': query});
        return (r.data!['search_id'] as num).toInt();
      });

  Future<FetchSearch> search(int id) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/fetch/searches/$id');
        return FetchSearch.fromJson(r.data!);
      });

  Future<int> startDownload(int candidateId) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>('/fetch/jobs', data: {'candidate_id': candidateId});
        return (r.data!['job_id'] as num).toInt();
      });

  Future<FetchJob> job(int id) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/fetch/jobs/$id');
        return FetchJob.fromJson(r.data!);
      });

  Future<T> _wrap<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final serverMessage = body is Map && body['error'] is String ? body['error'] as String : null;
      throw OnlineFetchException(
        switch (code) {
          null => 'Can’t reach the server. Check your connection.',
          401 => 'Sign in again to search online.',
          429 => serverMessage ?? 'Too many requests. Try again in a minute.',
          _ => serverMessage ?? 'Online search isn’t available right now.',
        },
        statusCode: code,
      );
    }
  }
}
