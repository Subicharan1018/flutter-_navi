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

class ListeningStatsNotifier extends StateNotifier<AsyncValue<ListeningStats>> {
  final http.Client _client;
  final String _baseUrl;
  final String _period;

  ListeningStatsNotifier({
    required http.Client client,
    required String baseUrl,
    required String period,
  }) : _client = client,
       _baseUrl = baseUrl,
       _period = period,
       super(const AsyncValue.loading()) {
    fetch();
  }

  /// Loads stats from the server. Sets state to loading → data or error.
  Future<void> fetch() async {
    state = const AsyncValue.loading();
    if (_baseUrl.isEmpty) {
      state = AsyncValue.error(
        'No server URL configured. Set the API Base URL in Settings.',
        StackTrace.current,
      );
      return;
    }

    try {
      final uri = Uri.parse(
        '${_baseUrl.replaceAll(RegExp(r'/+$'), '')}/listening-log/stats',
      ).replace(queryParameters: {'period': _period});

      final response = await _client
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
final listeningStatsProvider =
    StateNotifierProvider.family<
      ListeningStatsNotifier,
      AsyncValue<ListeningStats>,
      String
    >((ref, period) {
      // Use the computed getter: apiBaseUrl:loggingPort
      final baseUrl = ref.watch(settingsProvider).loggingApiUrl;
      final client = ref.watch(subsonicServiceProvider).client;
      return ListeningStatsNotifier(
        client: client,
        baseUrl: baseUrl,
        period: period,
      );
    });
