import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/features/everyday/play_stats.dart';
import 'package:navivibe/features/everyday/play_stats_providers.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/settings_provider.dart' show appDatabaseProvider;

Song song(String id, {int plays = 0, DateTime? last}) => Song(
  id: id, title: id, artist: 'a', album: 'b', coverArt: id, duration: 100, track: 1, year: 2000,
  playCount: plays, lastPlayed: last,
);

void main() {
  final now = DateTime(2026, 11, 22, 10);

  group('Song parses played', () {
    test('reads the Subsonic played timestamp and round-trips it', () {
      final s = Song.fromJson({'id': '1', 'playCount': 3, 'played': '2026-11-20T08:00:00Z'});
      expect(s.lastPlayed, DateTime.utc(2026, 11, 20, 8));
      expect(Song.fromJson(s.toMap()).lastPlayed, s.lastPlayed);
    });
    test('absent played stays null', () => expect(Song.fromJson({'id': '1'}).lastPlayed, isNull));
  });

  group('PlayStats.merge', () {
    test('larger count and later date win', () {
      final s = song('1', plays: 5, last: DateTime(2026, 11, 1));
      final m = PlayStats.merge(s, localCount: 8, localLast: DateTime(2026, 11, 20));
      expect(m.count, 8);
      expect(m.lastPlayed, DateTime(2026, 11, 20));
      final m2 = PlayStats.merge(s, localCount: 2, localLast: DateTime(2026, 10, 1));
      expect(m2.count, 5);
      expect(m2.lastPlayed, DateTime(2026, 11, 1));
    });
    test('a date with no count is one play', () {
      expect(PlayStats.merge(song('1', last: DateTime(2026, 1, 1))).count, 1);
    });
    test('never played is empty', () => expect(PlayStats.merge(song('1')).isEmpty, isTrue));
  });

  group('labels', () {
    test('relativeDay counts calendar days', () {
      expect(relativeDay(DateTime(2026, 11, 22, 1), now), 'Today');
      expect(relativeDay(DateTime(2026, 11, 21, 23, 59), DateTime(2026, 11, 22, 0, 5)), 'Yesterday');
      expect(relativeDay(DateTime(2026, 11, 19), now), '3 days ago');
      expect(relativeDay(DateTime(2026, 11, 8), now), '2 weeks ago');
      expect(relativeDay(DateTime(2026, 8, 20), now), '3 months ago');
      expect(relativeDay(DateTime(2024, 3, 4), now), 'Mar 2024');
    });
    test('line', () {
      expect(const PlayStats().line(now), '');
      expect(PlayStats(count: 1, lastPlayed: DateTime(2026, 11, 21)).line(now), '1 play · last played yesterday');
      expect(PlayStats(count: 12, lastPlayed: DateTime(2026, 11, 19)).line(now), '12 plays · last played 3 days ago');
      expect(const PlayStats(count: 4).line(now), '4 plays');
    });
  });

  group('sortByPlayStats', () {
    final a = song('a', plays: 3, last: DateTime(2026, 11, 1));
    final b = song('b', plays: 9, last: DateTime(2026, 11, 10));
    final c = song('c');
    final d = song('d', plays: 3, last: DateTime(2026, 10, 1));
    final all = [a, b, c, d];
    List<String> ids(List<Song> l) => [for (final s in l) s.id];
    test('most played, stable on ties', () {
      expect(ids(sortByPlayStats(all, {}, PlayStatSort.mostPlayed)), ['b', 'a', 'd', 'c']);
    });
    test('recently played puts never-played last', () {
      expect(ids(sortByPlayStats(all, {}, PlayStatSort.recentlyPlayed)), ['b', 'a', 'd', 'c']);
    });
    test('longest unplayed puts never-played first', () {
      expect(ids(sortByPlayStats(all, {}, PlayStatSort.longestUnplayed)), ['c', 'd', 'a', 'b']);
    });
    test('local stats override via the map', () {
      final m = {'c': const PlayStats(count: 50)};
      expect(ids(sortByPlayStats(all, m, PlayStatSort.mostPlayed)).first, 'c');
    });
  });

  group('local play log', () {
    test('counts lasting plays and finds the latest start', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      Future<void> add(String id, int ts, int dur, bool skipped) => db.customStatement(
        'INSERT INTO play_events (play_id, song_id, session_id, ts_start, play_dur_sec, skip_before50, '
        'repeat_count, queue_position, shuffle_active, source_context, hour_of_day, day_of_week) '
        "VALUES ('$id$ts', '$id', 's', $ts, $dur, ${skipped ? 1 : 0}, 0, 0, 0, 'x', 1, 1)",
      );
      await add('s1', 1000, 200, false);
      await add('s1', 5000, 180, false);
      await add('s1', 9000, 1, false); // too short
      await add('s1', 9500, 40, true); // skipped
      await add('s2', 7000, 100, false);
      final c = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(c.dispose);
      final s = await c.read(localPlayStatsProvider('s1').future);
      expect(s.count, 2);
      expect(s.lastPlayed, DateTime.fromMillisecondsSinceEpoch(5000));
      expect((await c.read(localPlayStatsProvider('none').future)).isEmpty, isTrue);
    });
  });
}
