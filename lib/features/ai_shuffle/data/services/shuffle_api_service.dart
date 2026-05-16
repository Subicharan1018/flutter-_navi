// =============================================================================
// ShuffleApiService — Dio-based HTTP client for the AI shuffle server.
//
// Typed methods for all 6 endpoints:
//   GET  /health
//   GET  /next?current=...&count=...
//   GET  /profile?song=...
//   GET  /stats
//   POST /session/reset
//   GET  /session/status
// =============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/health_response.dart';
import '../models/next_response.dart';
import '../models/profile_response.dart';
import '../models/stats_response.dart';
import '../models/session_status_response.dart';
import '../repositories/shuffle_exception.dart';

class ShuffleApiService {
  final Dio _dio;

  /// True when no valid base URL has been configured yet.
  /// All methods short-circuit with [ShuffleNetworkError] when this is true.
  final bool _unconfigured;

  /// [baseUrl] is the full URL including scheme and port,
  /// e.g. `http://192.168.1.10:5000`. Constructed from SettingsState.localShuffleUrl.
  ShuffleApiService({required String baseUrl})
      : _unconfigured = baseUrl.isEmpty || !(Uri.tryParse(baseUrl)?.hasAuthority ?? false),
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl.isEmpty ? 'http://localhost' : baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            headers: {'Accept': 'application/json'},
          ),
        ) {
    if (kDebugMode && !_unconfigured) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (obj) => debugPrint('[ShuffleApi] $obj'),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // GET /health
  // ---------------------------------------------------------------------------

  /// Returns the server health status. Throws [ShuffleNetworkError] or
  /// [ShuffleServerError] on failure.
  Future<HealthResponse> getHealth() async {
    if (_unconfigured) throw const ShuffleNetworkError('Server not configured');
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>('/health');
      return HealthResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // GET /next
  // ---------------------------------------------------------------------------

  /// Returns a list of recommended songs following [current].
  /// [count] controls how many recommendations to return (default 5).
  /// [playlist] and [artist] are optional context hints.
  Future<NextResponse> getNext({
    required String current,
    String? playlist,
    String? artist,
    int count = 5,
  }) async {
    if (_unconfigured) throw const ShuffleNetworkError('Server not configured');
    return _wrap(() async {
      final queryParams = <String, dynamic>{
        'current': current,
        'count': count.toString(),
        if (playlist != null && playlist.isNotEmpty) 'playlist': playlist,
        if (artist != null && artist.isNotEmpty) 'artist': artist,
      };

      final response = await _dio.get<dynamic>('/next',
          queryParameters: queryParams);

      final data = response.data;
      if (data is List) {
        return NextResponse.fromList(data);
      } else if (data is Map<String, dynamic>) {
        return NextResponse.fromJson(data);
      }
      return NextResponse(songs: [], source: 'unknown', sessionId: '');
    });
  }

  // ---------------------------------------------------------------------------
  // GET /profile
  // ---------------------------------------------------------------------------

  /// Returns the behavioural + acoustic profile for [song].
  Future<ProfileResponse> getProfile({required String song}) async {
    if (_unconfigured) throw const ShuffleNetworkError('Server not configured');
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/profile',
        queryParameters: {'song': song},
      );
      return ProfileResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // GET /stats
  // ---------------------------------------------------------------------------

  /// Returns aggregate server-side playback statistics.
  Future<ShuffleStatsResponse> getStats() async {
    if (_unconfigured) throw const ShuffleNetworkError('Server not configured');
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>('/stats');
      return ShuffleStatsResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // POST /session/reset
  // ---------------------------------------------------------------------------

  /// Resets the server-side session so previously excluded songs become
  /// eligible again for recommendation.
  Future<void> resetSession() async {
    if (_unconfigured) throw const ShuffleNetworkError('Server not configured');
    await _wrap(() async {
      await _dio.post<void>('/session/reset');
    });
  }

  // ---------------------------------------------------------------------------
  // GET /session/status
  // ---------------------------------------------------------------------------

  /// Returns the current session state (session_id, song_count, started_at).
  Future<SessionStatusResponse> getSessionStatus() async {
    if (_unconfigured) throw const ShuffleNetworkError('Server not configured');
    return _wrap(() async {
      final response =
          await _dio.get<Map<String, dynamic>>('/session/status');
      return SessionStatusResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // Error mapping helper
  // ---------------------------------------------------------------------------

  Future<T> _wrap<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      debugPrint('[ShuffleApi] ❌ ${e.type}: ${e.message}');
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          throw const ShuffleNetworkError();
        case DioExceptionType.badResponse:
          throw ShuffleServerError(e.response?.statusCode ?? 0);
        default:
          throw ShuffleNetworkError(e.message ?? 'Unknown network error');
      }
    } catch (e) {
      debugPrint('[ShuffleApi] ❌ unexpected: $e');
      throw ShuffleNetworkError(e.toString());
    }
  }
}

