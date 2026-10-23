import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/composer.dart';

import '../helpers/test_utils.dart';

void main() {
  group('nameKey', () {
    test('ignores dots, spaces and case', () {
      expect(nameKey('A. R. Rahman'), 'arrahman');
      expect(nameKey('A.R. Rahman'), 'arrahman');
      expect(nameKey('AR Rahman'), 'arrahman');
      expect(nameKey('  a.r.rahman '), 'arrahman');
    });

    test('keeps non-Latin letters', () {
      expect(nameKey('இளையராஜா'), isNotEmpty);
      expect(nameKey('இளையராஜா'), isNot(nameKey('ரஹ்மான்')));
    });
  });

  group('splitComposers', () {
    test('splits on commas, ampersands, slashes, semicolons and "and"', () {
      expect(splitComposers('Harris Jayaraj, Yuvan Shankar Raja'), ['Harris Jayaraj', 'Yuvan Shankar Raja']);
      expect(splitComposers('Vishal & Shekhar'), ['Vishal', 'Shekhar']);
      expect(splitComposers('A / B; C and D'), ['A', 'B', 'C', 'D']);
    });

    test('does not split inside a name', () {
      expect(splitComposers('Anirudh Ravichander'), ['Anirudh Ravichander']);
      expect(splitComposers('Sandeep'), ['Sandeep']);
    });

    test('drops blanks and spelling duplicates', () {
      expect(splitComposers(''), isEmpty);
      expect(splitComposers(' , '), isEmpty);
      expect(splitComposers('A. R. Rahman, AR Rahman'), ['A. R. Rahman']);
    });
  });

  group('songCreditLine', () {
    test('composer first, then the artist', () {
      expect(
        songCreditLine(composer: 'Anirudh Ravichander', artist: 'Dhanush'),
        'Anirudh Ravichander · Dhanush',
      );
    });

    test('artist only when there is no composer', () {
      expect(songCreditLine(composer: '', artist: 'Dhanush'), 'Dhanush');
      expect(songCreditLine(composer: '  ', artist: 'Dhanush'), 'Dhanush');
    });

    test('composer only when the artist is the composer', () {
      expect(songCreditLine(composer: 'A. R. Rahman', artist: 'AR Rahman'), 'A. R. Rahman');
      expect(songCreditLine(composer: 'Vishal, Shekhar', artist: 'Shekhar'), 'Vishal, Shekhar');
    });

    test('composer only when the artist is blank', () {
      expect(songCreditLine(composer: 'Ilaiyaraaja', artist: ''), 'Ilaiyaraaja');
    });

    test('a singer who is only one of two artists still shows', () {
      expect(
        songCreditLine(composer: 'Anirudh', artist: 'Anirudh, Dhanush'),
        'Anirudh · Anirudh, Dhanush',
      );
    });
  });

  group('composerLineFor', () {
    test('null without a composer or when the artist is the composer', () {
      expect(composerLineFor(makeSong(composer: '', artist: 'X')), isNull);
      expect(composerLineFor(makeSong(composer: 'A.R. Rahman', artist: 'AR Rahman')), isNull);
    });

    test('the credit otherwise', () {
      expect(composerLineFor(makeSong(composer: 'Anirudh', artist: 'Dhanush')), 'Anirudh');
    });
  });

  group('buildComposers', () {
    final songs = [
      makeSong(id: '1', composer: 'A. R. Rahman', album: 'Roja'),
      makeSong(id: '2', composer: 'A.R. Rahman', album: 'Roja'),
      makeSong(id: '3', composer: 'AR Rahman', album: 'Bombay'),
      makeSong(id: '4', composer: 'Harris Jayaraj, A. R. Rahman', album: 'Duet'),
      makeSong(id: '5', composer: 'Harris Jayaraj', album: 'Duet'),
      makeSong(id: '6', composer: '', album: 'None'),
    ];

    test('folds spelling variants and splits multi-composer credits', () {
      final composers = buildComposers(songs);
      expect(composers.map((c) => c.key), ['arrahman', 'harrisjayaraj']);
      expect(composers[0].songCount, 4);
      expect(composers[1].songCount, 2);
    });

    test('shows the most used spelling', () {
      expect(buildComposers(songs).first.name, anyOf('A. R. Rahman', 'A.R. Rahman'));
      final tie = buildComposers([makeSong(id: 'a', composer: 'AR Rahman'), makeSong(id: 'b', composer: 'A. R. Rahman')]);
      expect(tie.single.name, 'A. R. Rahman'); // tie → the longer
    });

    test('is sorted A–Z ignoring case', () {
      final composers = buildComposers([
        makeSong(id: 'a', composer: 'yuvan'),
        makeSong(id: 'b', composer: 'Anirudh'),
        makeSong(id: 'c', composer: 'devi sri prasad'),
      ]);
      expect(composers.map((c) => c.name), ['Anirudh', 'devi sri prasad', 'yuvan']);
    });
  });

  group('groupByAlbum', () {
    test('groups by film, newest first, tracks in order', () {
      final groups = groupByAlbum([
        makeSong(id: '1', album: 'Old', year: 1992, track: 2),
        makeSong(id: '2', album: 'New', year: 2022, track: 3),
        makeSong(id: '3', album: 'new', year: 2022, track: 1),
        makeSong(id: '4', album: 'Old', year: 1992, track: 1),
      ]);
      expect(groups.map((g) => g.name), ['New', 'Old']);
      expect(groups[0].songs.map((s) => s.id), ['3', '2']);
      expect(groups[1].songs.map((s) => s.id), ['4', '1']);
    });

    test('songs with no album go under Singles', () {
      expect(groupByAlbum([makeSong(album: ' ')]).single.name, 'Singles');
    });
  });

  group('matchComposers', () {
    final all = buildComposers([
      makeSong(id: '1', composer: 'A. R. Rahman'),
      makeSong(id: '2', composer: 'Harris Jayaraj'),
      makeSong(id: '3', composer: 'Rahul Raj'),
    ]);

    test('matches by prefix before containment, ignoring dots and spaces', () {
      expect(matchComposers(all, 'ar rah').map((c) => c.name), ['A. R. Rahman']);
      expect(matchComposers(all, 'ra').map((c) => c.name), ['Rahul Raj', 'A. R. Rahman', 'Harris Jayaraj']);
    });

    test('nothing for a blank query', () {
      expect(matchComposers(all, ' . '), isEmpty);
    });
  });
}
