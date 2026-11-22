import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/features/everyday/history_logic.dart';
import 'package:navivibe/features/everyday/history_providers.dart';
import 'package:navivibe/models/song.dart';

Song song(String id, {String title = '', String artist = 'Artist', String album = 'Album'}) => Song(
  id: id, title: title.isEmpty ? id : title, artist: artist, album: album, coverArt: id, duration: 100, track: 1, year: 2000,
);

HistoryEntry e(String id, DateTime at, {String title = '', String artist = 'Artist'}) =>
    HistoryEntry(song: song(id, title: title, artist: artist), at: at, playedSec: 100);

void main() {
  // Sunday 22 Nov 2026, 10:00.
  final now = DateTime(2026, 11, 22, 10);

  test('dayLabel', () {
    expect(dayLabel(DateTime(2026, 11, 22), now), 'Today');
    expect(dayLabel(DateTime(2026, 11, 21), now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 11, 17), now), 'Tuesday');
    expect(dayLabel(DateTime(2026, 11, 3), now), 'Nov 3');
    expect(dayLabel(DateTime(2025, 12, 31), now), 'Dec 31, 2025');
  });

  test('dayPart boundaries', () {
    expect([for (final h in [4, 5, 11, 12, 16, 17, 20, 21, 0]) dayPart(h)],
        ['night', 'morning', 'morning', 'afternoon', 'afternoon', 'evening', 'evening', 'night', 'night']);
  });

  group('groupByDay', () {
    test('newest day first, newest play first inside, any input order', () {
      final days = groupByDay([
        e('a', DateTime(2026, 11, 21, 9)),
        e('b', DateTime(2026, 11, 22, 8)),
        e('c', DateTime(2026, 11, 21, 20)),
        e('d', DateTime(2026, 11, 22, 9)),
      ], now);
      expect([for (final d in days) d.label], ['Today', 'Yesterday']);
      expect([for (final x in days[0].entries) x.song.id], ['d', 'b']);
      expect([for (final x in days[1].entries) x.song.id], ['c', 'a']);
    });
    test('empty', () => expect(groupByDay(const [], now), isEmpty));
  });

  test('splitByPart cuts where the day-part changes', () {
    final day = groupByDay([
      e('a', DateTime(2026, 11, 21, 9)),
      e('b', DateTime(2026, 11, 21, 19)),
      e('c', DateTime(2026, 11, 21, 20)),
      e('d', DateTime(2026, 11, 21, 22)),
    ], now).single;
    final parts = splitByPart(day);
    expect([for (final p in parts) p.part], ['night', 'evening', 'morning']);
    expect([for (final x in parts[1].entries) x.song.id], ['c', 'b']);
  });

  group('searchHistory', () {
    final entries = [
      e('1', DateTime(2026, 11, 17, 22), title: 'Kannazhaga', artist: 'Dhanush'), // Tuesday night
      e('2', DateTime(2026, 11, 17, 8), title: 'Vaseegara', artist: 'Bombay Jayashree'), // Tuesday morning
      e('3', DateTime(2026, 11, 21, 19), title: 'Munbe Vaa', artist: 'Shreya'), // yesterday evening
    ];
    List<String> ids(String q) => [for (final x in searchHistory(entries, q, now)) x.song.id];
    test('empty keeps all', () => expect(ids('  '), ['1', '2', '3']));
    test('song words', () => expect(ids('dhanush'), ['1']));
    test('time words', () {
      expect(ids('tuesday'), ['1', '2']);
      expect(ids('tue night'), ['1']);
      expect(ids('yesterday'), ['3']);
      expect(ids('evening'), ['3']);
    });
    test('mixed words all must match', () {
      expect(ids('tuesday morning vaseegara'), ['2']);
      expect(ids('tuesday shreya'), isEmpty);
    });
    test('two letters are not a weekday prefix', () => expect(ids('tu'), isEmpty));
  });

  test('songsInHeardOrder is oldest first and distinct', () {
    final out = songsInHeardOrder([
      e('b', DateTime(2026, 11, 21, 20)),
      e('a', DateTime(2026, 11, 21, 19)),
      e('a', DateTime(2026, 11, 21, 21)),
    ]);
    expect([for (final s in out) s.id], ['a', 'b']);
  });

  test('playFromHere runs forward in time from the tapped song', () {
    final list = [for (final h in [22, 21, 20]) e('s$h', DateTime(2026, 11, 21, h))]; // newest first
    expect([for (final s in playFromHere(list, 1)) s.id], ['s21', 's22']);
    expect(playFromHere(list, 9), isEmpty);
  });

  test('suggestedPlaylistName', () {
    expect(suggestedPlaylistName([e('a', DateTime(2026, 11, 21, 19))], now), 'Yesterday evening');
    expect(suggestedPlaylistName(const [], now), 'From my history');
  });

  group('readHistory', () {
    test('joins the mirror, pages by cursor, drops noise and unknown songs', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      Future<void> meta(String id) => db.customStatement(
        "INSERT INTO song_metadata (song_id, track_name, artist_name, album_name, duration_sec, updated_at) "
        "VALUES ('$id', 'T$id', 'A', 'B', 100, 1)",
      );
      Future<void> play(String id, int ts, int dur) => db.customStatement(
        'INSERT INTO play_events (play_id, song_id, session_id, ts_start, play_dur_sec, skip_before50, '
        'repeat_count, queue_position, shuffle_active, source_context, hour_of_day, day_of_week) '
        "VALUES ('p$ts', '$id', 's', $ts, $dur, 0, 0, 0, 0, 'x', 1, 1)",
      );
      await meta('a');
      await meta('b');
      await play('a', 1000, 60);
      await play('b', 2000, 60);
      await play('a', 3000, 1); // noise
      await play('gone', 4000, 60); // not in the mirror
      await play('a', 5000, 60);
      final all = await readHistory(db);
      expect([for (final x in all) x.at.millisecondsSinceEpoch], [5000, 2000, 1000]);
      expect(all.first.song.title, 'Ta');
      final older = await readHistory(db, beforeMs: 2000, limit: 5);
      expect([for (final x in older) x.at.millisecondsSinceEpoch], [1000]);
      final one = await readHistory(db, limit: 1);
      expect(one, hasLength(1));
    });
  });
}
