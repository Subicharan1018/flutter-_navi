import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/hive_boxes.dart';
import '../models/search_results.dart';
import 'settings_provider.dart';

/// The active search text. The Search screen's field and the desktop
/// sidebar's field both write here, so either can start a search.
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchProvider = FutureProvider.autoDispose.family<SearchResults, String>((ref, query) {
  if (query.trim().isEmpty) return SearchResults.empty;
  return ref.watch(subsonicServiceProvider).search(query.trim());
});

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  static const _max = 10;

  SearchHistoryNotifier() : super(const []) {
    final stored = HiveBoxes.prefs.get(HiveBoxes.kSearchHistory);
    if (stored is List) state = List<String>.from(stored);
  }

  Future<void> addQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    state = [q, ...state.where((e) => e.toLowerCase() != q.toLowerCase())].take(_max).toList();
    await HiveBoxes.prefs.put(HiveBoxes.kSearchHistory, state);
  }

  Future<void> removeQuery(String query) async {
    state = state.where((q) => q != query).toList();
    await HiveBoxes.prefs.put(HiveBoxes.kSearchHistory, state);
  }

  Future<void> clearHistory() async {
    state = const [];
    await HiveBoxes.prefs.delete(HiveBoxes.kSearchHistory);
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) => SearchHistoryNotifier());
