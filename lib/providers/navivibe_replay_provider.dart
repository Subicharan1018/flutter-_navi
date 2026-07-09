// =============================================================================
// navivibe_replay_provider.dart
//
// Riverpod providers for GET /replay and GET /replay/<year>/<month>.
// Data is sourced from the Navivibe server (not the local Drift DB).
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/ai_shuffle/logic/shuffle_providers.dart';
import '../features/ai_shuffle/data/models/replay_response.dart';

export '../features/ai_shuffle/data/models/replay_response.dart';

// ---------------------------------------------------------------------------
// Yearly Replay — GET /replay?year=<year>
// ---------------------------------------------------------------------------

/// Fetches the yearly Replay for [year]. Pass null to get the current year.
/// autoDispose so the cache is freed when the screen is popped.
final navivibeYearlyReplayProvider = FutureProvider.autoDispose
    .family<YearlyReplayResponse, int?>((ref, year) {
  final repo = ref.watch(shuffleRepositoryProvider);
  return repo.getYearlyReplay(year: year);
});

// ---------------------------------------------------------------------------
// Monthly Replay — GET /replay/<year>/<month>
// ---------------------------------------------------------------------------

/// Key type for the monthly replay family provider.
typedef MonthlyReplayKey = ({int year, int month});

/// Fetches the monthly Replay deep-dive for a specific year + month.
/// autoDispose so each month's data is freed when not watched.
final navivibeMonthlyReplayProvider = FutureProvider.autoDispose
    .family<MonthlyReplayResponse, MonthlyReplayKey>((ref, key) {
  final repo = ref.watch(shuffleRepositoryProvider);
  return repo.getMonthlyReplay(year: key.year, month: key.month);
});
