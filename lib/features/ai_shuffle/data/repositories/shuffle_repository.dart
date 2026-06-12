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
import '../models/predict_response.dart';
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
    bool reshuffle = false,
    List<String> excludedTitles = const [],
    String seedTitle = '',
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
      reshuffle: reshuffle,
      excludedTitles: excludedTitles,
      seedTitle: seedTitle,
    );

    if (response.queue.isEmpty) throw const ShuffleEmptyResponse();
    return response;
  }

  // ---------------------------------------------------------------------------
  // Predictive Endpoints
  // ---------------------------------------------------------------------------

  /// Fetches predictions from /predict/always-hear.
  /// Throws [ShuffleEmptyResponse] if the server returns 0 songs.
  Future<PredictResponse> getPredictAlwaysHear({
    int limit = 20,
    int? weatherCode,
  }) async {
    final response = await _api.getPredictAlwaysHear(
      limit: limit,
      weatherCode: weatherCode,
    );

    if (response.isEmpty) {
      throw const ShuffleEmptyResponse(
        'always-hear returned 0 predictions. '
        'Listen to more music to build your profile.',
      );
    }

    return response;
  }

  /// Fetches discovery songs from /predict/discovery.
  /// Throws [ShuffleEmptyResponse] if the discovery pool is empty.
  Future<PredictResponse> getPredictDiscovery({
    int limit = 20,
    int maxPriorPlays = 2,
    int? weatherCode,
  }) async {
    final response = await _api.getPredictDiscovery(
      limit: limit,
      maxPriorPlays: maxPriorPlays,
      weatherCode: weatherCode,
    );

    if (response.isEmpty) {
      throw const ShuffleEmptyResponse(
        'discovery pool is empty. '
        'Try increasing max_prior_plays or adding more songs.',
      );
    }

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

  /// Reports impression feedback (shown vs. played). Best-effort telemetry.
  Future<void> postImpressions({
    required List<String> shown,
    required List<String> played,
  }) async {
    try {
      await _api.postImpressions(shown: shown, played: played);
    } catch (e) {
      debugPrint('[ShuffleRepo] impressions error (ignored): $e');
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
