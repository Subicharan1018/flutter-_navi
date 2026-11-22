import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/features/artist_run/logic/artist_run.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/providers/settings_provider.dart';

Album _album(String id, String name, int year, {int songs = 8}) =>
    Album(id: id, name: name, artist: 'Rahman', coverArt: id, songCount: songs, duration: 0, year: year);

void main() {
  group('groupByYear', () {
    test('newest year first, undated last, server order kept inside a year', () {
      final g = groupByYear([
        _album('a', 'A', 1992),
        _album('b', 'B', 0),
        _album('c', 'C', 2005),
        _album('d', 'D', 1992),
      ]);
      expect([for (final y in g) y.year], [2005, 1992, 0]);
      expect([for (final a in g[1].albums) a.id], ['a', 'd']);
      expect(g[1].songs, 16);
    });
    test('nothing in, nothing out', () => expect(groupByYear(const []), isEmpty));
  });

  group('ArtistHistory.from', () {
    ArtistPlay p(String song, String album, DateTime at, [int s = 200]) =>
        ArtistPlay(song: song, album: album, at: at, seconds: s);

    test('counts plays, minutes, first and last, top song and albums', () {
      final h = ArtistHistory.from([
        p('Roja', 'Roja', DateTime(2022, 3, 5), 300),
        p('Roja', 'Roja', DateTime(2024, 1, 2), 300),
        p('Bombay', ' Bombay ', DateTime(2023, 6, 1), 120),
      ]);
      expect(h.plays, 3);
      expect(h.minutes, 12);
      expect(h.first, DateTime(2022, 3, 5));
      expect(h.last, DateTime(2024, 1, 2));
      expect(h.topSong, 'Roja');
      expect(h.topSongPlays, 2);
      expect(h.playsOf(_album('x', 'bombay', 1995)), 1);
      expect(h.playsOf(_album('y', 'Unplayed', 2000)), 0);
    });

    test('a tie for top song goes to the alphabetically first, so it is stable', () {
      final h = ArtistHistory.from([p('Zed', 'A', DateTime(2024)), p('Alpha', 'A', DateTime(2024))]);
      expect(h.topSong, 'Alpha');
    });

    test('no plays is empty', () {
      final h = ArtistHistory.from(const []);
      expect(h.isEmpty, isTrue);
      expect(h.topSong, isNull);
    });
  });

  group('artistHistoryProvider', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> song(String id, String artist, String album) => db
        .into(db.songMetadata)
        .insert(
          SongMetadataCompanion.insert(
            songId: id,
            trackName: 'T$id',
            artistName: artist,
            albumName: album,
            durationSec: 200,
            updatedAt: 0,
          ),
        );

    Future<void> play(String id, String songId, DateTime at, {bool skipped = false, int secs = 180}) => db
        .into(db.playEvents)
        .insert(
          PlayEventsCompanion.insert(
            playId: id,
            songId: songId,
            sessionId: 's',
            tsStart: at.millisecondsSinceEpoch,
            sourceContext: 'playlist',
            hourOfDay: at.hour,
            dayOfWeek: at.weekday,
            playDurSec: Value(secs),
            skipBefore50: Value(skipped),
          ),
        );

    test('reads only this artist, only finished plays, ignoring case', () async {
      await song('1', 'A. R. Rahman', 'Roja');
      await song('2', 'Anirudh', 'Maari');
      await play('p1', '1', DateTime(2023, 2, 1));
      await play('p2', '1', DateTime(2024, 2, 1));
      await play('p3', '1', DateTime(2024, 3, 1), skipped: true);
      await play('p4', '2', DateTime(2024, 3, 1));
      final c = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(c.dispose);
      final h = await c.read(artistHistoryProvider('  a. r. rahman ').future);
      expect(h.plays, 2);
      expect(h.minutes, 6);
      expect(h.first, DateTime(2023, 2, 1));
      expect(h.topSong, 'T1');
      expect(h.playsOf(_album('x', 'roja', 1992)), 2);
      expect((await c.read(artistHistoryProvider('Nobody').future)).isEmpty, isTrue);
    });
  });
}
