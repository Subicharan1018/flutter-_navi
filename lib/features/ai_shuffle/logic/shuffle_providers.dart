import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/health_response.dart';
import '../data/models/recommended_song.dart';
import '../data/models/profile_response.dart';
import '../data/models/stats_response.dart';
import '../data/models/session_status_response.dart';
import '../data/services/shuffle_api_service.dart';
import '../data/repositories/shuffle_repository.dart';
import '../data/repositories/shuffle_exception.dart';
import '../../../providers/settings_provider.dart';

// -----------------------------------------------------------------------------
// Provider 1: ShuffleApiService
// -----------------------------------------------------------------------------
final shuffleApiServiceProvider = Provider<ShuffleApiService>((ref) {
  // Use select so this rebuilt ONLY when the shuffle URL changes.
  final url = ref.watch(settingsProvider.select((s) => s.localShuffleUrl));
  return ShuffleApiService(baseUrl: url);
});

// -----------------------------------------------------------------------------
// Provider 2: ShuffleRepository
// -----------------------------------------------------------------------------
final shuffleRepositoryProvider = Provider<ShuffleRepository>((ref) {
  return ShuffleRepository(ref.watch(shuffleApiServiceProvider));
});

// -----------------------------------------------------------------------------
// Provider 3: ShuffleQueueNotifier
// -----------------------------------------------------------------------------
final shuffleQueueProvider =
    AsyncNotifierProvider<ShuffleQueueNotifier, List<RecommendedSong>>(
  ShuffleQueueNotifier.new,
);

class ShuffleQueueNotifier extends AsyncNotifier<List<RecommendedSong>> {
  @override
  Future<List<RecommendedSong>> build() async {
    // Start with an empty list. User must pick a song to trigger a fetch.
    return [];
  }

  /// Call this when the user selects a song.
  Future<void> fetchNext({
    required String current,
    String? playlist,
    String? artist,
    int count = 5,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await ref.read(shuffleRepositoryProvider).getNext(
            current: current,
            playlist: playlist,
            artist: artist,
            count: count,
          );
      if (response.isEmpty) {
        throw const ShuffleEmptyResponse('Server returned no recommendations.');
      }
      return response;
    });
  }

  /// Clear the queue (e.g. after session reset).
  void clearQueue() {
    state = const AsyncData([]);
  }
}

// -----------------------------------------------------------------------------
// Provider 4: SongProfileNotifier
// -----------------------------------------------------------------------------
final songProfileProvider =
    AsyncNotifierProvider.family<SongProfileNotifier, ProfileResponse, String>(
  SongProfileNotifier.new,
);

class SongProfileNotifier extends FamilyAsyncNotifier<ProfileResponse, String> {
  @override
  Future<ProfileResponse> build(String arg) async {
    return ref.read(shuffleRepositoryProvider).getProfile(song: arg);
  }
}

// -----------------------------------------------------------------------------
// Provider 5: ShuffleStatsProvider (15-min TTL)
// -----------------------------------------------------------------------------
final shuffleStatsProvider =
    FutureProvider.autoDispose<ShuffleStatsResponse>((ref) async {
  // Keep the provider alive even when no widget is watching it.
  final link = ref.keepAlive();

  // Auto-invalidate after 15 minutes so next watch triggers a fresh fetch.
  final timer = Timer(const Duration(minutes: 15), link.close);

  // Clean up timer if the provider is disposed before 15 minutes.
  ref.onDispose(timer.cancel);

  return ref.read(shuffleRepositoryProvider).getStats();
});

// -----------------------------------------------------------------------------
// Provider 6: ServerHealthProvider
// -----------------------------------------------------------------------------
final serverHealthProvider = StreamProvider<HealthResponse>((ref) {
  return ref.watch(shuffleRepositoryProvider).healthStream();
});

// -----------------------------------------------------------------------------
// Provider 7: SessionStatusProvider
// -----------------------------------------------------------------------------
final sessionStatusProvider =
    FutureProvider.autoDispose<SessionStatusResponse>((ref) async {
  return ref.read(shuffleRepositoryProvider).getSessionStatus();
});
