import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';

void main() {
  test('opening the database creates indexes for the library sort columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'song_metadata'")
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    expect(names, containsAll(['idx_song_meta_created', 'idx_song_meta_play_count', 'idx_song_meta_duration']));
  });
}
