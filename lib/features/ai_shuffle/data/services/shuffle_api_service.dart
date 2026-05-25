// =============================================================================
// ShuffleApiService — Dio-based HTTP client for the Smart Shuffle server.
//
// Base URL: https://shuffle.subimusic.me (hardcoded — no user config needed)
// Auth:     HTTP Basic Auth with Navidrome username:password
//
// Endpoints (v3.0.0):
//   GET  /health
//   POST /next
//   POST /feedback
//   GET  /model/status
//   GET  /listening-log/stats
//   GET  /listening-log/history
//   GET  /listening-log/composers
//   GET  /listening-log/song
// =============================================================================

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/health_response.dart';
import '../models/next_response.dart';
import '../models/feedback_request.dart';
import '../models/model_status_response.dart';
import '../models/listening_stats_response.dart';
import '../models/listening_history_response.dart';
import '../models/contribution_graph_response.dart';
import '../repositories/shuffle_exception.dart';

/// The canonical base URL for the Smart Shuffle hosted service.
const _kShuffleBaseUrl = 'https://shuffle.subimusic.me';

class ShuffleApiService {
  final Dio _dio;

  /// True when no credentials have been configured.
  /// All methods short-circuit with [ShuffleNetworkError] when this is true.
  final bool _unconfigured;

  ShuffleApiService({required String username, required String password})
    : _unconfigured = username.isEmpty || password.isEmpty,
      _dio = Dio(
        BaseOptions(
          baseUrl: _kShuffleBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Accept': 'application/json'},
        ),
      ) {
    if (!_unconfigured) {
      _dio.interceptors.add(_BasicAuthInterceptor(username, password));
    }
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          logPrint: (obj) => debugPrint('[ShuffleApi] $obj'),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // GET /health
  // ---------------------------------------------------------------------------

  /// Returns server health + current weather. No auth required by the server,
  /// but we still send credentials so the connection is validated.
  Future<HealthResponse> getHealth() async {
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>('/health');
      return HealthResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // POST /next
  // ---------------------------------------------------------------------------

  /// Fetches the next shuffle queue.
  ///
  /// [source] — 'smart' | 'playlist' | 'all_songs'
  /// [playlistId] — Navidrome playlist ID (triggers playlist mode)
  /// [count] — number of songs to return
  /// [depth] — session depth (affects exploration)
  /// [playlistName] — name of current playlist (sets genre streak)
  /// [genreStreakType] — genre of current streak
  /// [genreStreakCount] — consecutive songs in current streak
  /// [playedTitles] — titles played this session (excluded from results)
  /// [recentListenRatios] — last N listen ratios (0.0–1.0)
  /// [lastEndReason] — why the last song ended
  Future<NextResponse> getNext({
    String source = 'smart',
    String? playlistId,
    int count = 16,
    int depth = 0,
    String? playlistName,
    String genreStreakType = '',
    int genreStreakCount = 0,
    List<String> playedTitles = const [],
    List<double> recentListenRatios = const [],
    String lastEndReason = '',
  }) async {
    return _wrap(() async {
      final body = <String, dynamic>{
        'source': source,
        'count': count,
        'depth': depth,
        if (playlistId != null && playlistId.isNotEmpty)
          'playlist_id': playlistId,
        if (playlistName != null && playlistName.isNotEmpty)
          'playlist_name': playlistName,
        if (genreStreakType.isNotEmpty) 'genre_streak_type': genreStreakType,
        if (genreStreakCount > 0) 'genre_streak_count': genreStreakCount,
        if (playedTitles.isNotEmpty) 'played_titles': playedTitles.join(','),
        if (recentListenRatios.isNotEmpty)
          'recent_listen_ratios': recentListenRatios,
        if (lastEndReason.isNotEmpty) 'last_end_reason': lastEndReason,
      };

      final response = await _dio.post<Map<String, dynamic>>(
        '/next',
        data: body,
        options: Options(contentType: 'application/json'),
      );

      return NextResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // POST /feedback
  // ---------------------------------------------------------------------------

  /// Records a played track so the model learns the user's taste.
  Future<void> postFeedback(FeedbackRequest request) async {
    await _wrap(() async {
      await _dio.post<void>(
        '/feedback',
        data: request.toJson(),
        options: Options(contentType: 'application/json'),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // GET /model/status
  // ---------------------------------------------------------------------------

  /// Returns the current state of the user's personal model.
  Future<ModelStatusResponse> getModelStatus() async {
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>('/model/status');
      return ModelStatusResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // GET /listening-log/stats
  // ---------------------------------------------------------------------------

  /// Returns aggregate listening statistics for the given [period].
  /// [period] must be one of: daily | weekly | monthly | all
  Future<ListeningStatsResponse> getListeningStats({
    String period = 'weekly',
  }) async {
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/listening-log/stats',
        queryParameters: {'period': period},
      );
      return ListeningStatsResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // GET /listening-log/history
  // ---------------------------------------------------------------------------

  /// Returns paginated play history with optional filters.
  Future<ListeningHistoryResponse> getListeningHistory({
    int limit = 50,
    int offset = 0,
    String? artist,
    String? title,
    String period = 'all',
  }) async {
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/listening-log/history',
        queryParameters: {
          'limit': limit,
          'offset': offset,
          'period': period,
          if (artist != null && artist.isNotEmpty) 'artist': artist,
          if (title != null && title.isNotEmpty) 'title': title,
        },
      );
      return ListeningHistoryResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // GET /listening-log/contribution-graph
  // ---------------------------------------------------------------------------

  Future<ContributionGraphResponse> getContributionGraph() async {
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/listening-log/contribution-graph',
      );
      return ContributionGraphResponse.fromJson(response.data!);
    });
  }

  // ---------------------------------------------------------------------------
  // GET /listening-log/composers
  // ---------------------------------------------------------------------------

  /// Returns the composer loyalty table.
  Future<List<Map<String, dynamic>>> getComposers() async {
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/listening-log/composers',
      );
      final data = response.data!;
      return (data['composers'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
    });
  }

  // ---------------------------------------------------------------------------
  // GET /listening-log/song
  // ---------------------------------------------------------------------------

  /// Returns the full history for a single song across all context buckets.
  Future<Map<String, dynamic>> getSongDeepDive({required String title}) async {
    return _wrap(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/listening-log/song',
        queryParameters: {'title': title},
      );
      return response.data!;
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
          final code = e.response?.statusCode ?? 0;
          if (code == 401) throw const ShuffleAuthError();
          throw ShuffleServerError(code);
        default:
          throw ShuffleNetworkError(e.message ?? 'Unknown network error');
      }
    } catch (e) {
      debugPrint('[ShuffleApi] ❌ unexpected: $e');
      if (e is ShuffleException) rethrow;
      throw ShuffleNetworkError(e.toString());
    }
  }
}

// ---------------------------------------------------------------------------
// Basic Auth interceptor
// ---------------------------------------------------------------------------

class _BasicAuthInterceptor extends Interceptor {
  final String _credentials;

  _BasicAuthInterceptor(String username, String password)
    : _credentials = base64Encode(utf8.encode('$username:$password'));

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = 'Basic $_credentials';
    super.onRequest(options, handler);
  }
}
