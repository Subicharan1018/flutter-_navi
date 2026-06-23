import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/listening_stats.dart';
import '../providers/settings_provider.dart';

// =============================================================================
// ListeningStatsNotifier
//
// Fetches playback stats from GET <loggingApiUrl>/listening-log/stats?period=...
// Exposes AsyncValue<ListeningStats> so the UI can handle loading/error/data.
// =============================================================================

class ListeningStatsNotifier extends Notifier<AsyncValue<ListeningStats>> {
  // In Riverpod 3.x, family args are passed via the constructor.
  ListeningStatsNotifier(this._period);
  final String _period;

  @override
  AsyncValue<ListeningStats> build() {
    // Kick off the initial fetch after build returns.
    Future.microtask(() => fetch());
    return const AsyncValue.loading();
  }

  /// Loads stats from the server. Sets state to loading → data or error.
  Future<void> fetch() async {
    state = const AsyncValue.loading();
    // Use the computed getter: apiBaseUrl:loggingPort
    final baseUrl = ref.read(settingsProvider).loggingApiUrl;
    final client = ref.read(subsonicServiceProvider).client;

    if (baseUrl.isEmpty) {
      state = AsyncValue.error(
        'No server URL configured. Set the API Base URL in Settings.',
        StackTrace.current,
      );
      return;
    }

    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/listening-log/stats',
      ).replace(queryParameters: {'period': _period});

      final response = await client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        state = AsyncValue.data(ListeningStats.fromJson(json));
      } else {
        state = AsyncValue.error(
          'Server returned ${response.statusCode}',
          StackTrace.current,
        );
      }
    } catch (e, st) {
      debugPrint('[ListeningStats] ❌ fetch failed: $e');
      state = AsyncValue.error(e, st);
    }
  }
}

/// Provider family — one notifier per period string ('weekly', 'monthly', 'all').
/// In Riverpod 3.x, family args are passed via the Notifier constructor.
final listeningStatsProvider =
    NotifierProvider.family<
      ListeningStatsNotifier,
      AsyncValue<ListeningStats>,
      String
    >((period) => ListeningStatsNotifier(period));
