import 'package:drift/drift.dart';

@DataClassName('SearchHistoryEntity')
class SearchHistory extends Table {
  TextColumn get query => text()();
  IntColumn get lastSearchedAt => integer()();

  @override
  Set<Column> get primaryKey => {query};
}
