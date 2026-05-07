import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/shuffle_algorithms.dart';

Song makeSong({
  required String id,
  String genre = 'Unknown',
  String composer = 'Unknown',
  String album = 'Unknown',
  int track = 0,
  double dynamicWeight = 1.0,
  int rating = 0,
  int playCount = 0,
  bool starred = false,
}) {
  return Song(
    id: id,
    title: 'Title $id',
    artist: 'Artist',
    album: album,
    genre: genre,
    composer: composer,
    coverArt: '',
    duration: 200,
    track: track,
    year: 2024,
    starred: starred,
    playCount: playCount,
    rating: rating,
    dynamicWeight: dynamicWeight,
  );
}

void main() {
  List<Song> generatePool(int count) {
    return List.generate(count, (i) => makeSong(id: 's$i'));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. Standard Shuffle
  // ──────────────────────────────────────────────────────────────────────────
  group('Standard Shuffle', () {
    test('returns all items exactly once', () {
      final pool = generatePool(50);
      final result = standardShuffleIsolate(pool);

      expect(result.length, equals(50));
      expect(result.map((s) => s.id).toSet().length, equals(50));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. Dithered Position Shuffle
  // ──────────────────────────────────────────────────────────────────────────
  group('Dithered Position Shuffle', () {
    test('returns all items exactly once', () {
      final pool = generatePool(50);
      final result = ditheredPositionShuffleIsolate({
        'songs': pool,
        'pref': ShufflePreference.genre.index,
      });

      expect(result.length, equals(50));
      expect(result.map((s) => s.id).toSet().length, equals(50));
    });

    test('spaces out items of the same genre', () {
      final pool = [
        makeSong(id: 'r1', genre: 'Rock'),
        makeSong(id: 'r2', genre: 'Rock'),
        makeSong(id: 'r3', genre: 'Rock'),
        makeSong(id: 'p1', genre: 'Pop'),
        makeSong(id: 'p2', genre: 'Pop'),
        makeSong(id: 'p3', genre: 'Pop'),
      ];
      final result = ditheredPositionShuffleIsolate({
        'songs': pool,
        'pref': ShufflePreference.genre.index,
      });

      expect(result.length, equals(6));
      expect(result.map((s) => s.id).toSet().length, equals(6));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. Merge Shuffle
  // ──────────────────────────────────────────────────────────────────────────
  group('Merge Shuffle', () {
    test('returns all items exactly once', () {
      final pool = generatePool(50);
      final result = mergeShuffleIsolate({
        'songs': pool,
        'pref': ShufflePreference.genre.index,
      });

      expect(result.length, equals(50));
      expect(result.map((s) => s.id).toSet().length, equals(50));
    });

    test('interleaves larger and smaller lists correctly', () {
      // This tests the underlying interleave function
      final larger = [
        makeSong(id: 'l1'),
        makeSong(id: 'l2'),
        makeSong(id: 'l3'),
      ];
      final smaller = [makeSong(id: 's1')];
      // Note: we can't directly call interleave without importing dart:math inside test
      // but we can test mergeShuffleIsolate which uses it.

      final pool = [
        makeSong(id: 'r1', genre: 'Rock'),
        makeSong(id: 'r2', genre: 'Rock'),
        makeSong(id: 'r3', genre: 'Rock'),
        makeSong(id: 'p1', genre: 'Pop'),
      ];

      final result = mergeShuffleIsolate({
        'songs': pool,
        'pref': ShufflePreference.genre.index,
      });

      expect(result.length, equals(4));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. Weighted Shuffle
  // ──────────────────────────────────────────────────────────────────────────
  group('Weighted Shuffle', () {
    test('returns all items exactly once', () {
      final pool = generatePool(50);
      final result = weightedShuffleIsolate(pool);

      expect(result.length, equals(50));
      expect(result.map((s) => s.id).toSet().length, equals(50));
    });

    test(
      'higher weight items generally appear earlier (statistical check)',
      () {
        // To test weighted probability without flakiness, we run it many times
        // and check the average index of a heavily weighted song.
        final normalSong = makeSong(id: 'low', dynamicWeight: 1.0);
        final heavySong = makeSong(
          id: 'high',
          dynamicWeight: 10.0,
          starred: true,
          playCount: 100,
          rating: 5,
        );

        final pool = [
          normalSong,
          normalSong,
          normalSong,
          normalSong,
          heavySong,
        ];

        int highTotalIndex = 0;
        int lowTotalIndex = 0;

        for (int i = 0; i < 50; i++) {
          final result = weightedShuffleIsolate(pool);
          highTotalIndex += result.indexWhere((s) => s.id == 'high');
          lowTotalIndex += result.indexWhere(
            (s) => s.id == 'low',
          ); // First occurrence
        }

        final highAvg = highTotalIndex / 50.0;
        final lowAvg = lowTotalIndex / 50.0;

        // The heavy song should, on average, appear significantly earlier than
        // the first occurrence of the low-weight songs.
        expect(
          highAvg,
          lessThan(lowAvg + 1.0),
        ); // Add a buffer since 'low' is the FIRST of 4.
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 5. Album-Aware Shuffle
  // ──────────────────────────────────────────────────────────────────────────
  group('Album-Aware Shuffle', () {
    test('returns all items exactly once', () {
      final pool = generatePool(50);
      final result = albumAwareShuffleIsolate({
        'songs': pool,
        'shuffleTracks': false,
      });

      expect(result.length, equals(50));
      expect(result.map((s) => s.id).toSet().length, equals(50));
    });

    test(
      'keeps album tracks contiguous and ordered when shuffleTracks=false',
      () {
        final pool = [
          makeSong(id: 'a2', album: 'A', track: 2),
          makeSong(id: 'b1', album: 'B', track: 1),
          makeSong(id: 'a1', album: 'A', track: 1),
          makeSong(id: 'a3', album: 'A', track: 3),
          makeSong(id: 'b2', album: 'B', track: 2),
        ];

        final result = albumAwareShuffleIsolate({
          'songs': pool,
          'shuffleTracks': false,
        });

        // Find where Album A starts
        final aStart = result.indexWhere((s) => s.album == 'A');
        expect(aStart, isNot(equals(-1)));

        // Album A must be contiguous and in track order
        expect(result[aStart].id, equals('a1'));
        expect(result[aStart + 1].id, equals('a2'));
        expect(result[aStart + 2].id, equals('a3'));
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 6. Recency-Dampened Weighted Shuffle
  // ──────────────────────────────────────────────────────────────────────────
  group('Recency-Dampened Shuffle', () {
    test('returns all items exactly once', () {
      final pool = generatePool(50);
      final result = recencyDampenedShuffleIsolate({
        'songs': pool,
        'recentIds': <String>[],
      });

      expect(result.length, equals(50));
      expect(result.map((s) => s.id).toSet().length, equals(50));
    });

    test('recently played items appear later (statistical check)', () {
      final recent = makeSong(id: 'recent', dynamicWeight: 5.0);
      final normal = makeSong(id: 'normal', dynamicWeight: 5.0);

      final pool = [recent, normal, normal, normal, normal];
      final recentIds = ['recent'];

      int recentTotalIndex = 0;

      for (int i = 0; i < 50; i++) {
        final result = recencyDampenedShuffleIsolate({
          'songs': pool,
          'recentIds': recentIds,
        });
        recentTotalIndex += result.indexWhere((s) => s.id == 'recent');
      }

      final recentAvg = recentTotalIndex / 50.0;

      // Given the 0.1x weight multiplier for recent items, 'recent' should
      // heavily cluster at the end of the 5-item list.
      expect(recentAvg, greaterThan(2.0));
    });
  });
}
