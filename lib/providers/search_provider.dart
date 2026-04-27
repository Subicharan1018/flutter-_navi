import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_provider.dart';

final searchProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, query) async {
  if (query.isEmpty) return {'songs': [], 'albums': [], 'artists': []};
  final service = ref.watch(subsonicServiceProvider);
  return await service.search(query);
});

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super([]) {
    _loadHistory();
  }

  static const _key = 'search_history';

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_key) ?? [];
  }

  Future<void> addQuery(String query) async {
    if (query.trim().isEmpty) return;

    final newHistory = [
      query,
      ...state.where((q) => q != query),
    ].take(10).toList();

    state = newHistory;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, newHistory);
  }

  Future<void> removeQuery(String query) async {
    final newHistory = state.where((q) => q != query).toList();
    state = newHistory;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, newHistory);
  }

  Future<void> clearHistory() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final searchHistoryProvider = StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
  return SearchHistoryNotifier();
});
