import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/library_extras/data/duplicates.dart';
import 'package:navivibe/features/library_extras/data/shared_inbox.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/song.dart';

Song song(String id, String title, String artist,
        {int duration = 200, String album = 'A', String albumId = '', String artistId = '', String suffix = '', int bitRate = 0, bool starred = false}) =>
    Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      albumId: albumId,
      artistId: artistId,
      coverArt: id,
      duration: duration,
      track: 1,
      year: 2000,
      suffix: suffix,
      bitRate: bitRate,
      starred: starred,
    );

Playlist pl(String id, String name, String owner) =>
    Playlist(id: id, name: name, comment: '', songCount: 3, duration: 600, owner: owner);

void main() {
  group('normalizeName', () {
    test('folds case, accents, punctuation and ampersands', () {
      expect(normalizeName('Don’t Stop (Believin\')'), 'dont stop believin');
      expect(normalizeName('Beyoncé'), 'beyonce');
      expect(normalizeName('Simon & Garfunkel'), 'simon and garfunkel');
      expect(normalizeName('  AC/DC '), 'acdc');
    });
    test('artist drops a leading The', () {
      expect(normalizeArtist('The Beatles'), 'beatles');
      expect(normalizeArtist('Theory of a Deadman'), 'theory of a deadman');
    });
  });

  group('findDuplicateSongs', () {
    test('groups same title+artist within the duration tolerance', () {
      final g = findDuplicateSongs([
        song('1', 'Hello', 'Adele', duration: 295),
        song('2', 'hello!', 'ADELE', duration: 296),
        song('3', 'Hello', 'Adele', duration: 330), // live cut: left alone
        song('4', 'Other', 'Adele'),
      ]);
      expect(g, hasLength(1));
      expect({for (final i in g.single.items) i.id}, {'1', '2'});
    });

    test('same title by different artists is not a duplicate', () {
      expect(findDuplicateSongs([song('1', 'Hello', 'Adele'), song('2', 'Hello', 'Lionel Richie')]), isEmpty);
    });

    test('chained durations form one group; a gap splits it', () {
      final g = findDuplicateSongs([
        song('1', 'X', 'Y', duration: 100),
        song('2', 'X', 'Y', duration: 102),
        song('3', 'X', 'Y', duration: 104),
        song('4', 'X', 'Y', duration: 200),
        song('5', 'X', 'Y', duration: 201),
      ]);
      expect(g, hasLength(2));
      expect(g.map((e) => e.items.length).toList()..sort(), [2, 3]);
    });

    test('keeper prefers lossless, then bitrate, then starred', () {
      final g = findDuplicateSongs([
        song('mp3', 'S', 'A', suffix: 'mp3', bitRate: 320),
        song('flac', 'S', 'A', suffix: 'flac', bitRate: 900),
        song('low', 'S', 'A', suffix: 'mp3', bitRate: 128, starred: true),
      ]).single;
      expect(g.suggestedKeeperId, 'flac');
      expect(extrasOf(g, 'flac').toSet(), {'mp3', 'low'});
    });

    test('empty library and empty titles are safe', () {
      expect(findDuplicateSongs(const []), isEmpty);
      expect(findDuplicateSongs([song('1', '', 'A'), song('2', '!!', 'A')]), isEmpty);
    });
  });

  group('albums and artists', () {
    test('album name variants by one artist are grouped; keeper has most songs', () {
      final songs = [
        song('1', 'a', 'Beatles', album: 'Abbey Road'),
        song('2', 'b', 'Beatles', album: 'Abbey Road'),
        song('3', 'c', 'The Beatles', album: 'ABBEY  ROAD.'),
        song('4', 'd', 'Beatles', album: 'Revolver'),
      ];
      final g = findDuplicateAlbums(songs);
      expect(g, hasLength(1));
      expect(g.single.items, hasLength(2));
      expect(g.single.items.firstWhere((i) => i.id == g.single.suggestedKeeperId).title, 'Abbey Road');
    });

    test('distinct album ids with the same name collapse; same id does not', () {
      final same = findDuplicateAlbums([
        song('1', 'a', 'X', album: 'Hits', albumId: 'al1'),
        song('2', 'b', 'X', album: 'Hits', albumId: 'al1'),
      ]);
      expect(same, isEmpty);
      final two = findDuplicateAlbums([
        song('1', 'a', 'X', album: 'Hits', albumId: 'al1'),
        song('2', 'b', 'X', album: 'hits', albumId: 'al2'),
      ]);
      expect(two, hasLength(1));
    });

    test('artist variants group; unrelated ones do not', () {
      final g = findDuplicateArtists([
        song('1', 'a', 'Beyoncé'),
        song('2', 'b', 'Beyonce'),
        song('3', 'c', 'beyonce'),
        song('4', 'd', 'Adele'),
      ]);
      expect(g, hasLength(1));
      expect(g.single.items, hasLength(3));
    });
  });

  group('buildCleanupExport', () {
    test('lists keeper and extras, honours the chosen keeper, deletes nothing', () {
      final g = findDuplicateSongs([song('a', 'S', 'A', duration: 100), song('b', 'S', 'A', duration: 100)]);
      final text = buildCleanupExport(g, {g.single.suggestedKeeperId: 'b'}, now: DateTime.utc(2026));
      expect(text, contains('KEEP   b'));
      expect(text, contains('EXTRA  a'));
      expect(text, contains('nothing has been deleted'));
    });
  });

  group('shared inbox', () {
    final all = [pl('1', 'Mine', 'admin'), pl('2', 'Zed', 'bob'), pl('3', 'Alpha', 'Carol'), pl('4', 'Gone', 'bob')];

    test('lists others only, new first then by name, minus dismissed', () {
      final inbox = buildSharedInbox(all, 'ADMIN', seen: {'3'}, dismissed: {'4'});
      expect(inbox.entries.map((e) => e.playlist.id), ['2', '3']);
      expect(inbox.newCount, 1);
      expect(inbox.entries.first.isNew, isTrue);
    });

    test('everything seen: no badge; no one shared: empty', () {
      expect(buildSharedInbox(all, 'admin', seen: {'2', '3', '4'}, dismissed: {}).newCount, 0);
      expect(buildSharedInbox([pl('1', 'Mine', 'admin')], 'admin', seen: {}, dismissed: {}).isEmpty, isTrue);
    });

    test('prefs keys are per user', () {
      expect(inboxPrefsKey('seen', ' Admin '), inboxPrefsKey('seen', 'admin'));
      expect(inboxPrefsKey('seen', 'bob'), isNot(inboxPrefsKey('seen', 'admin')));
    });
  });
}
