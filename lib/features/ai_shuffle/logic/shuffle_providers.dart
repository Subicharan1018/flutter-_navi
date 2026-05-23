// =============================================================================
// shuffle_providers.dart — Riverpod providers for Smart Shuffle (v3.0.0).
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../data/services/shuffle_api_service.dart';
import '../data/repositories/shuffle_repository.dart';
import '../data/models/health_response.dart';
import '../data/models/next_response.dart';
import '../data/models/model_status_response.dart';
import '../data/models/listening_stats_response.dart';
import '../data/models/feedback_request.dart';

// ---------------------------------------------------------------------------
// Core infrastructure providers
// ---------------------------------------------------------------------------

/// Creates the API service using Navidrome credentials from settings.
/// Recreated automatically whenever username or password changes.
final shuffleApiServiceProvider = Provider<ShuffleApiService>((ref) {
  final settings = ref.watch(
    settingsProvider.select((s) => (username: s.username, password: s.password)),
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
final modelStatusProvider =
    FutureProvider.autoDispose<ModelStatusResponse>((ref) {
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
  }) =>
      ShuffleQueueState(
        batches: batches ?? this.batches,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        sessionDepth: sessionDepth ?? this.sessionDepth,
        lastContext: lastContext ?? this.lastContext,
        lastWeather: lastWeather ?? this.lastWeather,
      );

  List<dynamic> get allSongs =>
      batches.expand((b) => b.queue).toList();
}

class ShuffleQueueNotifier extends StateNotifier<ShuffleQueueState> {
  final ShuffleRepository _repo;

  ShuffleQueueNotifier(this._repo) : super(const ShuffleQueueState());

  // Tracks played song titles for the session so they're excluded from /next.
  final List<String> _playedTitles = [];
  // Recent listen ratios — last 5 songs.
  final List<double> _recentListenRatios = [];
  String _lastEndReason = '';

  /// Fetches a new batch of recommendations.
  Future<void> fetchNext({
    String source = 'smart',
    String? playlistId,
    int count = 15,
    String? playlistName,
    String genreStreakType = '',
    int genreStreakCount = 0,
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
      );
      state = state.copyWith(
        batches: [...state.batches, response],
        isLoading: false,
        sessionDepth: state.sessionDepth + response.queue.length,
        lastContext: response.context?.bucketLabel,
        lastWeather: response.context?.weather,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
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
    }
    _recentListenRatios.add(listenRatio);
    if (_recentListenRatios.length > 5) {
      _recentListenRatios.removeAt(0);
    }
    _lastEndReason = endReason;
  }

  /// Clears the queue and resets session tracking.
  void clearQueue() {
    _playedTitles.clear();
    _recentListenRatios.clear();
    _lastEndReason = '';
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
