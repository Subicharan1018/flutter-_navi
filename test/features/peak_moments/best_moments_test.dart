import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/features/peak_moments/logic/best_moments.dart';
import 'package:navivibe/features/peak_moments/ui/best_moments_screen.dart' show dayLabel, sessionLength;

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> play(String id, DateTime at, int dur, {String session = 's', bool skip = false}) => db.customStatement(
    'INSERT INTO play_events (play_id, song_id, session_id, ts_start, play_dur_sec, skip_before50, '
    'repeat_count, queue_position, shuffle_active, source_context, hour_of_day, day_of_week) '
    "VALUES ('p${at.millisecondsSinceEpoch}$id', '$id', '$session', ${at.millisecondsSinceEpoch}, $dur, ${skip ? 1 : 0}, 0, 0, 0, 'x', 1, 1)",
  );

  test('busiest days: by audio time, skipped and accidental plays left out', () async {
    await play('a', DateTime(2026, 11, 1, 10), 200);
    await play('b', DateTime(2026, 11, 1, 11), 200);
    await play('c', DateTime(2026, 11, 2, 10), 300);
    await play('d', DateTime(2026, 11, 3, 10), 900, skip: true); // skipped: not listening
    await play('e', DateTime(2026, 11, 3, 11), 1); // accidental tap
    final days = await loadPeakDays(db);
    expect([for (final d in days) d.day.day], [1, 2]);
    expect(days.first.plays, 2);
    expect(days.first.seconds, 400);
  });

  test('longest sessions: grouped by session, longest first', () async {
    await play('a', DateTime(2026, 11, 1, 10), 200, session: 'x');
    await play('b', DateTime(2026, 11, 1, 10, 5), 250, session: 'x');
    await play('c', DateTime(2026, 11, 2, 10), 300, session: 'y');
    final s = await loadPeakSessions(db);
    expect(s.map((e) => e.seconds), [450, 300]);
    expect(s.first.songs, 2);
    expect(s.first.start, DateTime(2026, 11, 1, 10));
  });

  test('an empty log gives empty lists, not an error', () async {
    expect(await loadPeakDays(db), isEmpty);
    expect(await loadPeakSessions(db), isEmpty);
  });

  test('labels', () {
    final now = DateTime(2026, 11, 22);
    expect(dayLabel(DateTime(2026, 11, 8), now), 'Sun 8 Nov');
    expect(dayLabel(DateTime(2025, 12, 31), now), 'Wed 31 Dec 2025');
    expect(sessionLength(8100), '2h 15m');
    expect(sessionLength(2400), '40m');
  });
}
