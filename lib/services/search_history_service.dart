import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';

class SearchHistoryService {
  final AppDatabase _db;

  SearchHistoryService(this._db);

  Future<List<String>> getRecentSearches({int limit = 10}) async {
    try {
      final query = _db.select(_db.searchHistory)
        ..orderBy([(t) => OrderingTerm(expression: t.lastSearched, mode: OrderingMode.desc)])
        ..limit(limit);

      final rows = await query.get();
      return rows.map((r) => r.query).toList();
    } catch (e) {
      debugPrint('[SearchHistory] getRecentSearches error: $e');
      return [];
    }
  }

  Future<void> addSearch(String query) async {
    if (query.trim().isEmpty) return;

    try {
      await _db.into(_db.searchHistory).insertOnConflictUpdate(SearchHistoryCompanion.insert(
        query: query.trim(),
        lastSearched: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (e) {
      debugPrint('[SearchHistory] addSearch error: $e');
    }
  }

  Future<void> removeSearch(String query) async {
    try {
      await (_db.delete(_db.searchHistory)..where((t) => t.query.equals(query))).go();
    } catch (e) {
      debugPrint('[SearchHistory] removeSearch error: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      await _db.delete(_db.searchHistory).go();
    } catch (e) {
      debugPrint('[SearchHistory] clearAll error: $e');
    }
  }
}
