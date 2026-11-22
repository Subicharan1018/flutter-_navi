import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/everyday/album_picks.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/song.dart';

Song s(String id, {int plays = 0, bool starred = false, int rating = 0, String albumId = '', String album = '', int track = 0, String artist = 'A'}) => Song(
  id: id, title: 'T$id', artist: artist, album: album, albumId: albumId, coverArt: id, duration: 100, track: track, year: 2000,
  playCount: plays, starred: starred, rating: rating,
);

Album alb(String id) => Album(id: id, name: 'Album $id', artist: 'A', coverArt: id, songCount: 0, duration: 0);

AlbumCandidate cand(String id, List<Song> songs) => AlbumCandidate(alb(id), songs);

void main() {
  group('albumsForYou', () {
    test('one loved song and the rest unheard qualifies', () {
      final picks = albumsForYou([
        cand('a', [s('1', starred: true, plays: 9), for (var i = 2; i <= 8; i++) s('$i')]),
      ]);
      expect(picks, hasLength(1));
      expect(picks.single.loved, 1);
      expect(picks.single.unheard, 7);
      expect(picks.single.lovedTitle, 'T1');
      expect(picks.single.reason, 'You love T1 · 7 more to discover');
    });

    test('rejects: too short, nothing loved, loved majority, mostly heard, dismissed', () {
      final short = cand('short', [s('1', starred: true), s('2'), s('3'), s('4')]);
      final none = cand('none', [for (var i = 0; i < 8; i++) s('n$i')]);
      final majority = cand('maj', [for (var i = 0; i < 8; i++) s('m$i', starred: i < 5)]);
      final heard = cand('heard', [s('h0', starred: true), for (var i = 1; i < 8; i++) s('h$i', plays: 1)]);
      final hiddenOne = cand('hid', [s('x0', starred: true), for (var i = 1; i < 8; i++) s('x$i')]);
      final picks = albumsForYou([short, none, majority, heard, hiddenOne], hidden: {'hid'});
      expect(picks, isEmpty);
    });

    test('songs played on this device count as heard', () {
      final c = cand('a', [s('1', starred: true), for (var i = 2; i <= 6; i++) s('$i')]);
      expect(albumsForYou([c]), hasLength(1));
      expect(albumsForYou([c], playedLocally: {'2', '3', '4'}), isEmpty);
    });

    test('rating 4 or five plays also mean loved', () {
      final c1 = cand('r', [s('1', rating: 4), for (var i = 2; i <= 7; i++) s('$i')]);
      final c2 = cand('p', [s('1', plays: lovedPlayCount), for (var i = 2; i <= 7; i++) s('$i')]);
      expect(albumsForYou([c1, c2]), hasLength(2));
    });

    test('ranks more to discover first and caps the list', () {
      final big = cand('big', [s('b1', starred: true), for (var i = 2; i <= 10; i++) s('b$i')]);
      final mixed = cand('mixed', [
        s('m1', starred: true),
        s('m2', plays: 3),
        s('m3', plays: 3),
        s('m4'),
        s('m5'),
        s('m6'),
        s('m7'),
      ]);
      final picks = albumsForYou([mixed, big]);
      expect([for (final p in picks) p.album.id], ['big', 'mixed']);
      expect(albumsForYou([mixed, big], max: 1), hasLength(1));
    });

    test('the favourite named is the most played loved song', () {
      final c = cand('a', [s('1', starred: true, plays: 2), s('2', starred: true, plays: 40), for (var i = 3; i <= 10; i++) s('$i')]);
      expect(albumsForYou([c]).single.lovedTitle, 'T2');
      expect(albumsForYou([c]).single.reason, startsWith('You love T2 and 1 more'));
    });
  });

  group('shuffleByAlbum', () {
    final songs = [
      s('a2', albumId: 'A', track: 2),
      s('b1', albumId: 'B', track: 1),
      s('a1', albumId: 'A', track: 1),
      s('b3', albumId: 'B', track: 3),
      s('a3', albumId: 'A', track: 3),
      s('b2', albumId: 'B', track: 2),
      s('c1', albumId: 'C', track: 1),
    ];

    test('every album stays whole and in track order, for any seed', () {
      for (var seed = 0; seed < 25; seed++) {
        final out = shuffleByAlbum(songs, Random(seed)).map((x) => x.id).toList();
        expect(out, hasLength(songs.length));
        expect(out.toSet(), songs.map((x) => x.id).toSet());
        for (final prefix in ['a', 'b']) {
          final idx = [for (var i = 0; i < out.length; i++) if (out[i].startsWith(prefix)) i];
          expect(idx.last - idx.first, 2, reason: 'album $prefix contiguous (seed $seed)');
          expect([for (final i in idx) out[i]], ['${prefix}1', '${prefix}2', '${prefix}3']);
        }
      }
    });

    test('the album order really varies', () {
      final firsts = {for (var seed = 0; seed < 30; seed++) shuffleByAlbum(songs, Random(seed)).first.albumId};
      expect(firsts, {'A', 'B', 'C'});
    });

    test('same seed, same order', () {
      expect(shuffleByAlbum(songs, Random(3)).map((x) => x.id), shuffleByAlbum(songs, Random(3)).map((x) => x.id));
    });

    test('no album id: grouped by name and artist; no album at all: songs stand alone', () {
      final loose = [
        s('x2', album: 'Film', track: 2),
        s('y1', album: 'Other', track: 1, artist: 'Z'),
        s('x1', album: 'Film', track: 1),
        s('n1'),
        s('n2'),
      ];
      for (var seed = 0; seed < 10; seed++) {
        final out = shuffleByAlbum(loose, Random(seed)).map((x) => x.id).toList();
        expect(out.indexOf('x1') + 1, out.indexOf('x2'));
        expect(out, hasLength(5));
      }
    });

    test('unnumbered tracks keep their incoming order after numbered ones', () {
      final out = shuffleByAlbum([
        s('u1', albumId: 'A'),
        s('n2', albumId: 'A', track: 2),
        s('u2', albumId: 'A'),
        s('n1', albumId: 'A', track: 1),
      ], Random(1));
      expect(out.map((x) => x.id), ['n1', 'n2', 'u1', 'u2']);
    });

    test('empty stays empty', () => expect(shuffleByAlbum(const [], Random()), isEmpty));
  });
}
