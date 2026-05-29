// =============================================================================
// shuffle_providers.dart — Riverpod providers for Smart Shuffle (v3.0.0).
// =============================================================================

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

// ---------------------------------------------------------------------------
// Core infrastructure providers
// ---------------------------------------------------------------------------

/// Creates the API service using Navidrome credentials from settings.
/// Recreated automatically whenever username or password changes.
final shuffleApiServiceProvider = Provider<ShuffleApiService>((ref) {
  final settings = ref.watch(
    settingsProvider.select(
      (s) => (username: s.username, password: s.password),
    ),
  );
  return ShuffleApiService(
    username: settings.username,
    password: settings.password,
  );
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
}

final shuffleQueueProvider =
    StateNotifierProvider<ShuffleQueueNotifier, ShuffleQueueState>((ref) {
      return ShuffleQueueNotifier(ref.watch(shuffleRepositoryProvider));
    });

// ---------------------------------------------------------------------------
// Feedback helper — fire-and-forget
// ---------------------------------------------------------------------------

/// Call this to send feedback without waiting for a result.
void sendShuffleFeedback(Ref ref, FeedbackRequest request) {
  ref.read(shuffleRepositoryProvider).postFeedback(request);
}
