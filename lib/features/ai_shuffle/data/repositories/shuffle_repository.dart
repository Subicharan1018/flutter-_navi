// =============================================================================
// ShuffleRepository — business logic layer for Smart Shuffle (v4.0.0).
// =============================================================================

import 'package:flutter/foundation.dart';

import '../services/shuffle_api_service.dart';
import '../models/health_response.dart';
import '../models/next_response.dart';
import '../models/feedback_request.dart';
import '../models/model_status_response.dart';
import '../models/listening_stats_response.dart';
import '../models/listening_history_response.dart';
import '../models/contribution_graph_response.dart';
import '../models/song_deep_dive_response.dart';
import 'shuffle_exception.dart';

class ShuffleRepository {
  final ShuffleApiService _api;

  ShuffleRepository(this._api);

  // ---------------------------------------------------------------------------
  // Health
  // ---------------------------------------------------------------------------

  /// Fetches server health. Returns null on any error.
  Future<HealthResponse?> getHealthOrNull() async {
    try {
      return await _api.getHealth();
    } catch (e) {
      debugPrint('[ShuffleRepo] health error: $e');
      return null;
    }
  }

  /// Health as a stream — polls on creation then once-on-call.
  /// Callers can use Riverpod FutureProvider.autoDispose instead.
  Future<HealthResponse> getHealth() async {
    return await _api.getHealth();
  }

  // ---------------------------------------------------------------------------
  // Weather
  // ---------------------------------------------------------------------------

  Future<WeatherInfo> getWeather() => _api.getWeather();

  // ---------------------------------------------------------------------------
  // Next recommendation queue
  // ---------------------------------------------------------------------------

  /// Fetches the next Smart Shuffle queue. Throws [ShuffleException] subtypes.
  Future<NextResponse> getNext({
    String source = 'smart',
    String? playlistId,
    int count = 15,
    int depth = 0,
    String? playlistName,
    String genreStreakType = '',
    int genreStreakCount = 0,
    List<String> playedTitles = const [],
    List<double> recentListenRatios = const [],
    String lastEndReason = '',
    List<String> candidates = const [],
  }) async {
    final response = await _api.getNext(
      source: source,
      playlistId: playlistId,
      count: count,
      depth: depth,
      playlistName: playlistName,
      genreStreakType: genreStreakType,
      genreStreakCount: genreStreakCount,
      playedTitles: playedTitles,
      recentListenRatios: recentListenRatios,
      lastEndReason: lastEndReason,
      candidates: candidates,
    );

    if (response.queue.isEmpty) throw const ShuffleEmptyResponse();
    return response;
  }

  // ---------------------------------------------------------------------------
  // Feedback
  // ---------------------------------------------------------------------------

  /// Posts listening feedback. Errors are swallowed — feedback is best-effort.
  Future<void> postFeedback(FeedbackRequest request) async {
    try {
      await _api.postFeedback(request);
    } catch (e) {
      debugPrint('[ShuffleRepo] feedback error (ignored): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Model status
  // ---------------------------------------------------------------------------

  Future<ModelStatusResponse> getModelStatus() => _api.getModelStatus();

  // ---------------------------------------------------------------------------
  // Listening log
  // ---------------------------------------------------------------------------

  Future<ListeningStatsResponse> getListeningStats({
    String period = 'weekly',
  }) => _api.getListeningStats(period: period);

  Future<ListeningHistoryResponse> getListeningHistory({
    int limit = 50,
    int offset = 0,
    String? artist,
    String? title,
    String period = 'all',
  }) => _api.getListeningHistory(
    limit: limit,
    offset: offset,
    artist: artist,
    title: title,
    period: period,
  );

  Future<ContributionGraphResponse> getContributionGraph() =>
      _api.getContributionGraph();

  Future<List<Map<String, dynamic>>> getComposers() => _api.getComposers();

  Future<SongDeepDiveResponse> getSongDeepDive({required String title}) =>
      _api.getSongDeepDive(title: title);
}
