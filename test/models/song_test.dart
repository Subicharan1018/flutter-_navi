// TEST-1: Unit tests for the Song model.
//
// Coverage:
//   • Song.fromJson — happy path with all fields present
//   • Song.fromJson — graceful defaults when fields are absent / null
//   • Song.fromJson — starred field (Subsonic sends a timestamp string
//     when starred, absent key when not starred)
//   • Song.toMap / fromJson round-trip (via SQLite column names)
//   • Song.copyWith — only the specified fields change
//   • Song equality — two Songs with the same data are == regardless of
//     dynamicWeight (which is a local shuffle weight, not part of identity)
//   • Song.hashCode — consistent with ==

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/song.dart';

void main() {
  // --------------------------------------------------------------------------
  // Fixture helpers
  // --------------------------------------------------------------------------

  const fullJson = <String, dynamic>{
    'id': 'abc123',
    'title': 'Test Song',
    'artist': 'Test Artist',
    'album': 'Test Album',
    'genre': 'Rock',
    'displayComposer': 'Test Composer',
    'coverArt': 'cover_1',
    'duration': 210,
    'track': 3,
    'year': 2023,
    'starred': '2024-01-01T00:00:00.000Z', // timestamp string = starred
    'playCount': 7,
    'userRating': 4,
    'created': '2023-06-15T12:30:00.000Z',
  };

  Song buildFromFull() => Song.fromJson(fullJson);

  // --------------------------------------------------------------------------
  // fromJson — happy path
  // --------------------------------------------------------------------------

  group('Song.fromJson — happy path', () {
    test('parses all basic string fields', () {
      final s = buildFromFull();
      expect(s.id, 'abc123');
      expect(s.title, 'Test Song');
      expect(s.artist, 'Test Artist');
      expect(s.album, 'Test Album');
      expect(s.genre, 'Rock');
      expect(s.composer, 'Test Composer');
      expect(s.coverArt, 'cover_1');
    });

    test('parses numeric fields', () {
      final s = buildFromFull();
      expect(s.duration, 210);
      expect(s.track, 3);
      expect(s.year, 2023);
      expect(s.playCount, 7);
      expect(s.rating, 4);
    });

    test('starred is true when JSON contains a starred timestamp', () {
      final s = buildFromFull();
      expect(s.starred, isTrue);
    });

    test('starred is false when JSON key is absent', () {
      final json = Map<String, dynamic>.from(fullJson)..remove('starred');
      expect(Song.fromJson(json).starred, isFalse);
    });

    test('starred is false when JSON value is null', () {
      final json = Map<String, dynamic>.from(fullJson)
        ..['starred'] = null;
      expect(Song.fromJson(json).starred, isFalse);
    });

    test('parses created date correctly', () {
      final s = buildFromFull();
      expect(s.created, DateTime.parse('2023-06-15T12:30:00.000Z'));
    });

    test('dynamicWeight defaults to 1.0', () {
      expect(buildFromFull().dynamicWeight, 1.0);
    });
  });

  // --------------------------------------------------------------------------
  // fromJson — missing / null fields fall back to defaults
  // --------------------------------------------------------------------------

  group('Song.fromJson — graceful defaults', () {
    late Song s;

    setUp(() => s = Song.fromJson(const {'id': 'x'}));

    test('title defaults to Unknown Title', () =>
        expect(s.title, 'Unknown Title'));
    test('artist defaults to Unknown Artist', () =>
        expect(s.artist, 'Unknown Artist'));
    test('album defaults to Unknown Album', () =>
        expect(s.album, 'Unknown Album'));
    test('genre defaults to empty string', () => expect(s.genre, ''));
    test('composer defaults to empty string', () => expect(s.composer, ''));
    test('coverArt defaults to empty string', () => expect(s.coverArt, ''));
    test('duration defaults to 0', () => expect(s.duration, 0));
    test('track defaults to 0', () => expect(s.track, 0));
    test('year defaults to 0', () => expect(s.year, 0));
    test('playCount defaults to 0', () => expect(s.playCount, 0));
    test('rating defaults to 0', () => expect(s.rating, 0));
    test('created defaults to null', () => expect(s.created, isNull));
  });

  // --------------------------------------------------------------------------
  // composer field priority: displayComposer beats composer
  // --------------------------------------------------------------------------

  group('Song.fromJson — composer field priority', () {
    test('prefers displayComposer over composer', () {
      final s = Song.fromJson({
        ...fullJson,
        'displayComposer': 'Display Composer',
        'composer': 'Raw Composer',
      });
      expect(s.composer, 'Display Composer');
    });

    test('falls back to composer when displayComposer is absent', () {
      final json = Map<String, dynamic>.from(fullJson)
        ..remove('displayComposer')
        ..['composer'] = 'Raw Composer';
      expect(Song.fromJson(json).composer, 'Raw Composer');
    });
  });

  // --------------------------------------------------------------------------
  // toMap / fromJson round-trip (SQLite column names)
  // --------------------------------------------------------------------------

  group('Song round-trip via toMap', () {
    test('all fields survive toMap → fromJson', () {
      final original = buildFromFull();
      final map = original.toMap();
      final restored = Song.fromJson(map);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.artist, original.artist);
      expect(restored.album, original.album);
      expect(restored.genre, original.genre);
      expect(restored.coverArt, original.coverArt);
      expect(restored.duration, original.duration);
      expect(restored.track, original.track);
      expect(restored.year, original.year);
      expect(restored.playCount, original.playCount);
      expect(restored.rating, original.rating);
      expect(restored.created, original.created);
    });

    test('starred survives round-trip (int 1 → bool true)', () {
      // SQLite stores starred as 1/0 (see toMap).  fromJson treats any
      // non-null value as starred=true.
      final original = buildFromFull();
      expect(original.starred, isTrue);
      final map = original.toMap();
      expect(map['starred'], 1);
      final restored = Song.fromJson(map);
      expect(restored.starred, isTrue);
    });
  });

  // --------------------------------------------------------------------------
  // copyWith
  // --------------------------------------------------------------------------

  group('Song.copyWith', () {
    test('unchanged fields are preserved', () {
      final original = buildFromFull();
      final copy = original.copyWith(starred: false);
      expect(copy.id, original.id);
      expect(copy.title, original.title);
      expect(copy.artist, original.artist);
    });

    test('changed field is updated', () {
      final original = buildFromFull();
      final copy = original.copyWith(starred: false);
      expect(copy.starred, isFalse);
    });

    test('dynamicWeight can be updated', () {
      final original = buildFromFull();
      final copy = original.copyWith(dynamicWeight: 2.5);
      expect(copy.dynamicWeight, 2.5);
    });

    test('copyWith does not mutate the original', () {
      final original = buildFromFull();
      original.copyWith(playCount: 99);
      expect(original.playCount, 7); // still from fullJson
    });
  });

  // --------------------------------------------------------------------------
  // Equality and hash code
  // --------------------------------------------------------------------------

  group('Song equality', () {
    test('two Songs built from the same JSON are equal', () {
      expect(buildFromFull(), equals(buildFromFull()));
    });

    test('dynamicWeight is excluded from equality', () {
      final a = buildFromFull().copyWith(dynamicWeight: 1.0);
      final b = buildFromFull().copyWith(dynamicWeight: 3.0);
      expect(a, equals(b));
    });

    test('Songs with different ids are not equal', () {
      final a = buildFromFull();
      final b = Song.fromJson({...fullJson, 'id': 'different'});
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with equality', () {
      final a = buildFromFull();
      final b = buildFromFull();
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('Songs with different dynamicWeight have the same hashCode', () {
      final a = buildFromFull().copyWith(dynamicWeight: 1.0);
      final b = buildFromFull().copyWith(dynamicWeight: 9.9);
      expect(a.hashCode, b.hashCode);
    });
  });
}
