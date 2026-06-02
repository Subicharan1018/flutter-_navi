// =============================================================================
// shuffle_providers.dart — Riverpod providers for Smart Shuffle (v3.0.0).
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../providers/settings_provider.dart';
import '../data/services/shuffle_api_service.dart';
import '../data/repositories/shuffle_repository.dart';
import '../data/models/health_response.dart';
import '../data/models/next_response.dart';
import '../data/models/model_status_response.dart';
import '../data/models/listening_stats_response.dart';
import '../data/models/contribution_graph_response.dart';
import '../data/models/feedback_request.dart';
import '../data/models/predict_response.dart';
import '../data/models/recommended_song.dart';
import '../data/repositories/shuffle_exception.dart';

// ---------------------------------------------------------------------------
// Core infrastructure providers
// ---------------------------------------------------------------------------

/// Creates the API service using Navidrome credentials from settings.
/// Uses [ShuffleApiService.withSupplier] so the Dio interceptor reads
/// credentials on every request — not at construction time. This ensures
/// credentials loaded from Hive after the first render are always used
/// correctly, preventing 401s during the app startup window.
final shuffleApiServiceProvider = Provider<ShuffleApiService>((ref) {
  return ShuffleApiService.withSupplier(() {
    final s = ref.read(settingsProvider);
    return (s.username, s.password);
  });
});

/// Repository built on top of the API service.
final shuffleRepositoryProvider = Provider<ShuffleRepository>((ref) {
  return ShuffleRepository(ref.watch(shuffleApiServiceProvider));
});

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------

/// Polls the /health endpoint once. Auto-refreshes on credentials change.
final serverHealthProvider = FutureProvider.autoDispose<HealthResponse>((ref) {
  final repo = ref.watch(shuffleRepositoryProvider);
  return repo.getHealth();
});

// ---------------------------------------------------------------------------
// Model status
// ---------------------------------------------------------------------------

/// Fetches the current user model state from /model/status.
final modelStatusProvider = FutureProvider.autoDispose<ModelStatusResponse>((
  ref,
) {
  final repo = ref.watch(shuffleRepositoryProvider);
  return repo.getModelStatus();
});

// ---------------------------------------------------------------------------
// Listening stats
// ---------------------------------------------------------------------------

/// Fetches aggregate listening stats for [period].
final listeningStatsProvider = FutureProvider.autoDispose
    .family<ListeningStatsResponse, String>((ref, period) {
      final repo = ref.watch(shuffleRepositoryProvider);
      return repo.getListeningStats(period: period);
    });

// ---------------------------------------------------------------------------
// Contribution Graph
// ---------------------------------------------------------------------------

/// Fetches the 1-year contribution graph.
final contributionGraphProvider =
    FutureProvider.autoDispose<ContributionGraphResponse>((ref) {
      final repo = ref.watch(shuffleRepositoryProvider);
      return repo.getContributionGraph();
    });

// ---------------------------------------------------------------------------
// Shuffle queue notifier
// ---------------------------------------------------------------------------

/// State for the current AI-recommended queue.
class ShuffleQueueState {
  final List<NextResponse> batches;
  final bool isLoading;
  final String? error;
  final int sessionDepth;
  final String? lastContext;
  final String? lastWeather;

  const ShuffleQueueState({
    this.batches = const [],
    this.isLoading = false,
    this.error,
    this.sessionDepth = 0,
    this.lastContext,
    this.lastWeather,
  });

  ShuffleQueueState copyWith({
    List<NextResponse>? batches,
    bool? isLoading,
    String? error,
    int? sessionDepth,
    String? lastContext,
    String? lastWeather,
  }) => ShuffleQueueState(
    batches: batches ?? this.batches,
    isLoading: isLoading ?? this.isLoading,
    error: error,
    sessionDepth: sessionDepth ?? this.sessionDepth,
    lastContext: lastContext ?? this.lastContext,
    lastWeather: lastWeather ?? this.lastWeather,
  );

  List<dynamic> get allSongs => batches.expand((b) => b.queue).toList();

  /// Typed version of allSongs — used by reshuffle and _applyAiShuffle.
  List<RecommendedSong> get allRecommendedSongs =>
      batches.expand((b) => b.queue).toList();
}

class ShuffleQueueNotifier extends StateNotifier<ShuffleQueueState> {
  final ShuffleRepository _repo;

  ShuffleQueueNotifier(this._repo) : super(const ShuffleQueueState());

  // Tracks played song titles for the session so they're excluded from /next.
  // Capped at 50 to prevent unbounded growth in long sessions.
  final List<String> _playedTitles = [];
  // Recent listen ratios — last 5 songs.
  final List<double> _recentListenRatios = [];
  String _lastEndReason = '';

  // Session ID — nullable; null means initSession() has not been called yet.
  String? _sessionId;

  /// Starts a new playback session, generating a fresh UUID.
  /// Must be called AFTER clearQueue() in playPlaylist / _applyAiShuffle.
  void initSession() {
    _sessionId = const Uuid().v4();
  }

  /// The current session ID. Asserts in debug builds if initSession() was
  /// never called, so forgotten call sites are caught during development.
  String get sessionId {
    assert(
      _sessionId != null,
      'shuffleNotifier.sessionId read before initSession() was called',
    );
    return _sessionId ?? '';
  }

  /// True when a session UUID has been assigned via [initSession].
  /// Use this to guard [sendShuffleFeedback] calls so they are only sent
  /// during an active AI-shuffle session (not for ad-hoc setQueue playback).
  bool get hasActiveSession => _sessionId != null && _sessionId!.isNotEmpty;

  /// Fetches a new batch of recommendations.
  Future<NextResponse> fetchNext({
    String source = 'smart',
    String? playlistId,
    int count = 15,
    String? playlistName,
    String genreStreakType = '',
    int genreStreakCount = 0,
    List<String> candidates = const [],
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _repo.getNext(
        source: source,
        playlistId: playlistId,
        count: count,
        depth: state.sessionDepth,
        playlistName: playlistName,
        genreStreakType: genreStreakType,
        genreStreakCount: genreStreakCount,
        playedTitles: _playedTitles,
        recentListenRatios: _recentListenRatios,
        lastEndReason: _lastEndReason,
        candidates: candidates,
      );
      state = state.copyWith(
        batches: [...state.batches, response],
        isLoading: false,
        lastContext: response.context?.bucketLabel,
        lastWeather: response.context?.weather,
      );
      return response;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// Records a song as played and tracks the listen ratio for future requests.
  void recordPlay({
    required String title,
    required double listenRatio,
    required String endReason,
  }) {
    if (!_playedTitles.contains(title)) {
      _playedTitles.add(title);
      // Cap at 50 to prevent unbounded growth in long sessions.
      if (_playedTitles.length > 50) _playedTitles.removeAt(0);
    }
    _recentListenRatios.add(listenRatio);
    if (_recentListenRatios.length > 5) {
      _recentListenRatios.removeAt(0);
    }
    _lastEndReason = endReason;
    state = state.copyWith(sessionDepth: state.sessionDepth + 1);
  }

  /// Clears the queue and resets all session tracking.
  /// Call initSession() after this to begin a new session.
  void clearQueue() {
    _playedTitles.clear();
    _recentListenRatios.clear();
    _lastEndReason = '';
    _sessionId = null;
    state = const ShuffleQueueState();
  }

  /// Fetches a fresh 16-song batch from POST /next (reshuffle: true),
  /// excluding all currently visible queue titles so the server won't repeat them.
  ///
  /// Session state is preserved:
  ///   - [_playedTitles]         kept — session is ongoing
  ///   - [state.sessionDepth]    kept — not incremented on reshuffle
  ///   - [_recentListenRatios]   kept
  ///
  /// The resulting batch REPLACES state.batches (not appended).
  /// Fetches a fresh batch with reshuffle:true.
  ///
  /// [excludedTitlesOverride] — when provided (by [PlayerNotifier.reshuffleActiveQueue]),
  /// these titles are sent as the ban list instead of the preview batch in
  /// state.batches.  The state update (batches replacement) is skipped when
  /// called this way so the preview UI is left unchanged.
  Future<List<RecommendedSong>> reshuffle({
    String source = 'smart',
    String? playlistId,
    String? playlistName,
    String genreStreakType = '',
    int genreStreakCount = 0,
    List<String> candidates = const [],
    List<String>? excludedTitlesOverride,
  }) async {
    // When called from the preview UI, ban titles the user can currently see.
    // When called from PlayerNotifier, ban the active playback queue instead.
    final excludedTitles = excludedTitlesOverride ??
        state.batches.expand((b) => b.queue).map((s) => s.title).toList();

    final isPreviewCall = excludedTitlesOverride == null;

    if (isPreviewCall) {
      state = state.copyWith(isLoading: true, error: null);
    }
    try {
      final response = await _repo.getNext(
        source: source,
        playlistId: playlistId,
        count: 16,
        depth: state.sessionDepth, // preserved — session is still ongoing
        playlistName: playlistName,
        genreStreakType: genreStreakType,
        genreStreakCount: genreStreakCount,
        playedTitles: _playedTitles, // internal — no UI leakage
        recentListenRatios: _recentListenRatios,
        lastEndReason: _lastEndReason,
        candidates: candidates,
        reshuffle: true,
        excludedTitles: excludedTitles,
      );
      if (isPreviewCall) {
        // REPLACE — reshuffle is not an append for the preview UI.
        state = state.copyWith(
          batches: [response],
          isLoading: false,
          lastContext: response.context?.bucketLabel,
          lastWeather: response.context?.weather,
        );
      }
      return response.queue;
    } catch (e) {
      if (isPreviewCall) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
      rethrow;
    }
  }
}

final shuffleQueueProvider =
    StateNotifierProvider<ShuffleQueueNotifier, ShuffleQueueState>((ref) {
      return ShuffleQueueNotifier(ref.watch(shuffleRepositoryProvider));
    });

// ---------------------------------------------------------------------------
// Feedback helper — fire-and-forget
// ---------------------------------------------------------------------------

/// Call this to send feedback without waiting for a result.
/// No-ops when no active session exists (i.e. initSession() was never
/// called for the current playback context), preventing unauthenticated
/// 401 requests for ad-hoc / non-AI-shuffle playback.
void sendShuffleFeedback(Ref ref, FeedbackRequest request) {
  final notifier = ref.read(shuffleQueueProvider.notifier);
  if (!notifier.hasActiveSession) {
    debugPrint(
      '[ShuffleFeedback] Skipped — no active session '
      '(title: ${request.title})',
    );
    return;
  }
  ref.read(shuffleRepositoryProvider).postFeedback(request);
}

// ---------------------------------------------------------------------------
// Predictive Endpoints (v4.0.0) — Used by AI Shuffle Screen
// ---------------------------------------------------------------------------

enum PredictStatus { initial, loading, loaded, error }

class PredictQueueState {
  const PredictQueueState({
    this.status = PredictStatus.initial,
    this.songs = const [],
    this.context,
    this.mode = PredictMode.alwaysHear,
    this.errorMessage,
  });

  final PredictStatus status;
  final List<RecommendedSong> songs;
  final PredictContext? context;       // null until first successful load
  final PredictMode mode;
  final String? errorMessage;

  bool get isLoading  => status == PredictStatus.loading;
  bool get isLoaded   => status == PredictStatus.loaded;
  bool get hasError   => status == PredictStatus.error;
  bool get isEmpty    => isLoaded && songs.isEmpty;

  PredictQueueState copyWith({
    PredictStatus? status,
    List<RecommendedSong>? songs,
    PredictContext? context,
    PredictMode? mode,
    String? errorMessage,
  }) {
    return PredictQueueState(
      status:       status       ?? this.status,
      songs:        songs        ?? this.songs,
      context:      context      ?? this.context,
      mode:         mode         ?? this.mode,
      errorMessage: errorMessage,
    );
  }
}

class PredictQueueNotifier extends StateNotifier<PredictQueueState> {
  PredictQueueNotifier(this._repository)
      : super(const PredictQueueState());

  final ShuffleRepository _repository;

  /// Call this when the user taps "Shuffle Now" or switches the mode chip.
  Future<void> fetchPredict({required PredictMode mode}) async {
    // Show loading, preserving the selected mode immediately so the chip
    // stays highlighted before results arrive.
    state = state.copyWith(
      status: PredictStatus.loading,
      mode: mode,
      errorMessage: null,
    );

    try {
      final PredictResponse response;

      switch (mode) {
        case PredictMode.alwaysHear:
          response = await _repository.getPredictAlwaysHear(limit: 20);
        case PredictMode.discovery:
          response = await _repository.getPredictDiscovery(
            limit: 20,
            maxPriorPlays: 2,
          );
      }

      state = state.copyWith(
        status:  PredictStatus.loaded,
        songs:   response.songs,
        context: response.requestContext,
        mode:    response.mode,
      );
    } on ShuffleEmptyResponse catch (e) {
      state = state.copyWith(
        status:       PredictStatus.error,
        songs:        [],
        errorMessage: e.message,
      );
    } on ShuffleAuthError {
      state = state.copyWith(
        status:       PredictStatus.error,
        errorMessage: 'Session expired. Please log in again.',
      );
    } catch (e) {
      state = state.copyWith(
        status:       PredictStatus.error,
        errorMessage: 'Could not load recommendations: $e',
      );
    }
  }

  /// Convenience: switch mode without a full reload until the user
  /// taps "Shuffle Now". Just updates the chip highlight.
  void setMode(PredictMode mode) {
    state = state.copyWith(mode: mode);
  }
}

final predictQueueProvider =
    StateNotifierProvider<PredictQueueNotifier, PredictQueueState>((ref) {
  return PredictQueueNotifier(ref.watch(shuffleRepositoryProvider));
});
