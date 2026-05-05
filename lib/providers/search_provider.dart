import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/hive_boxes.dart';
import 'settings_provider.dart';

final searchProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  query,
) async {
  if (query.isEmpty) return {'songs': [], 'albums': [], 'artists': []};
  final service = ref.watch(subsonicServiceProvider);
  return await service.search(query);
});

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super([]) {
    _loadHistory();
  }

  void _loadHistory() {
    final stored = HiveBoxes.prefs.get(HiveBoxes.kSearchHistory);
    if (stored != null) {
      state = List<String>.from(stored as List);
    }
  }

  Future<void> addQuery(String query) async {
    if (query.trim().isEmpty) return;

    final newHistory = [
      query,
      ...state.where((q) => q != query),
    ].take(10).toList();

    state = newHistory;
    await HiveBoxes.prefs.put(HiveBoxes.kSearchHistory, newHistory);
  }

  Future<void> removeQuery(String query) async {
    final newHistory = state.where((q) => q != query).toList();
    state = newHistory;
    await HiveBoxes.prefs.put(HiveBoxes.kSearchHistory, newHistory);
  }

  Future<void> clearHistory() async {
    state = [];
    await HiveBoxes.prefs.delete(HiveBoxes.kSearchHistory);
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
      return SearchHistoryNotifier();
    });
