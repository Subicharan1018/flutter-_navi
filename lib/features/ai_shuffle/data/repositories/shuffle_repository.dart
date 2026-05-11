// =============================================================================
// ShuffleRepository — business logic layer wrapping ShuffleApiService.
//
// Responsibilities:
//   - Health polling stream (every 30s)
//   - Hive-backed stats cache with stale-while-revalidate strategy:
//     read Hive first → return cached value → fetch from network in background
//   - Thin pass-through for all other endpoints
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/hive_boxes.dart';

import '../models/health_response.dart';
import '../models/recommended_song.dart';
import '../models/profile_response.dart';
import '../models/stats_response.dart';
import '../models/session_status_response.dart';
import '../repositories/shuffle_exception.dart';
import '../services/shuffle_api_service.dart';

class ShuffleRepository {
  final ShuffleApiService _api;

  // Hive box key for the cached stats JSON string.
  static const _kStatsCache = 'shuffle_stats_cache';
  static const _kStatsCacheTime = 'shuffle_stats_cache_time';

  ShuffleRepository(this._api);

  // ---------------------------------------------------------------------------
  // Health stream — 30-second periodic poll
  // ---------------------------------------------------------------------------

  /// Emits a [HealthResponse] immediately on first subscription, then every
  /// 30 seconds. Network errors are silently swallowed and do not close the
  /// stream — the UI uses `serverHealthProvider` to show an error indicator.
  Stream<HealthResponse> healthStream() async* {
    while (true) {
      try {
        yield await _api.getHealth();
      } catch (e) {
        debugPrint('[ShuffleRepo] Health check failed: $e');
        // Yield a "down" placeholder so the UI can show a red indicator.
        yield HealthResponse(
          status: 'error',
          uptime: '',
          librarySize: 0,
          modelLoaded: false,
        );
      }
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  // ---------------------------------------------------------------------------
  // Recommendations
  // ---------------------------------------------------------------------------

  /// Fetches the next [count] recommended songs following [current].
  /// Throws [ShuffleNetworkError], [ShuffleServerError], or
  /// [ShuffleEmptyResponse] on failure.
  Future<List<RecommendedSong>> getNext({
    required String current,
    String? playlist,
    String? artist,
    int count = 5,
  }) async {
    final response = await _api.getNext(
      current: current,
      playlist: playlist,
      artist: artist,
      count: count,
    );
    if (response.songs.isEmpty) {
      throw const ShuffleEmptyResponse();
    }
    return response.songs;
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  /// Returns the full behavioural + acoustic profile for [song].
  Future<ProfileResponse> getProfile({required String song}) =>
      _api.getProfile(song: song);

  // ---------------------------------------------------------------------------
  // Stats — Hive-backed stale-while-revalidate cache
  // ---------------------------------------------------------------------------

  /// Returns stats. Tries Hive first; if no cached data (or stale),
  /// fetches from the network. The Riverpod provider adds a 15-min TTL on top.
  Future<ShuffleStatsResponse> getStats() async {
    final box = HiveBoxes.shuffleCache;

    // Serve cached data if present and < 15 minutes old.
    final cachedJson = box.get(_kStatsCache) as String?;
    final cachedTime = box.get(_kStatsCacheTime) as int?;
    if (cachedJson != null && cachedTime != null) {
        final age = DateTime.now().millisecondsSinceEpoch - cachedTime;
        if (age < const Duration(minutes: 15).inMilliseconds) {
          try {
            final map = jsonDecode(cachedJson) as Map<String, dynamic>;
            debugPrint('[ShuffleRepo] Returning cached stats (${age ~/ 1000}s old)');
            return ShuffleStatsResponse.fromJson(map);
          } catch (_) { /* malformed cache — fall through to network */ }
        }
    }

    // Fetch fresh data.
    final response = await _api.getStats();

    // Persist to Hive.
    try {
      await box.put(_kStatsCache, jsonEncode(_statsToJson(response)));
      await box.put(_kStatsCacheTime, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[ShuffleRepo] Failed to cache stats: $e');
    }

    return response;
  }

  // ---------------------------------------------------------------------------
  // Session management
  // ---------------------------------------------------------------------------

  /// Resets the server-side session exclusion list.
  Future<void> resetSession() => _api.resetSession();

  /// Returns the current session state.
  Future<SessionStatusResponse> getSessionStatus() =>
      _api.getSessionStatus();

  // ---------------------------------------------------------------------------
  // JSON serialisation helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _statsToJson(ShuffleStatsResponse r) => {
        'total_plays': r.totalPlays,
        'top_songs': r.topSongs,
        'top_artists': r.topArtists,
        'weekly': r.weekly,
        'monthly': r.monthly,
      };
}
