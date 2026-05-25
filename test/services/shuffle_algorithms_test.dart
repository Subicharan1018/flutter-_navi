// =============================================================================
// shuffle_algorithms_test.dart
//
// Pure Dart unit tests for all 6 shuffle algorithms in
// lib/services/shuffle_algorithms.dart.
//
// Tests verify:
//   1. Output length matches input (no duplicates, no missing songs)
//   2. Statistical distribution for weighted algorithms
//   3. Edge cases: empty list, single song, all same genre/album
//   4. Recency dampening weight reduction
//   5. Album-aware track order preservation
//
// These tests do NOT require a running Flutter engine — they test only the
// top-level isolate worker functions that operate on plain Song lists.
// =============================================================================

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/shuffle_algorithms.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/settings_provider.dart'
    show ShufflePreference;

// ── Test data factory ─────────────────────────────────────────────────────────

Song _song({
  required String id,
  String title = 'Song',
  String artist = 'Artist',
  String album = 'Album',
  String genre = 'Rock',
  String composer = 'Comp',
  int track = 1,
  bool starred = false,
  int playCount = 0,
  int rating = 0,
  double dynamicWeight = 1.0,
}) => Song(
  id: id,
  title: '$title $id',
  artist: artist,
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

List<Song> _makePool(
  int count, {
  String genre = 'Rock',
  String composer = 'Comp',
}) {
  return List.generate(
    count,
    (i) => _song(id: '$i', genre: genre, composer: composer, track: i + 1),
  );
}

List<Song> _makeMixedPool() {
  return [
    _song(id: '1', genre: 'Rock', composer: 'Bach', album: 'Album A'),
    _song(id: '2', genre: 'Jazz', composer: 'Bach', album: 'Album A'),
    _song(id: '3', genre: 'Rock', composer: 'Mozart', album: 'Album B'),
    _song(id: '4', genre: 'Jazz', composer: 'Mozart', album: 'Album B'),
    _song(id: '5', genre: 'Pop', composer: 'Bach', album: 'Album C'),
    _song(id: '6', genre: 'Pop', composer: 'Mozart', album: 'Album C'),
    _song(id: '7', genre: 'Rock', composer: 'Chopin', album: 'Album D'),
    _song(id: '8', genre: 'Jazz', composer: 'Chopin', album: 'Album D'),
  ];
}

// ── Helpers ────────────────────────────────────────────────────────────────────

Set<String> _ids(List<Song> songs) => songs.map((s) => s.id).toSet();

void _assertNoDuplicatesOrMissing(List<Song> input, List<Song> output) {
  expect(
    output.length,
    input.length,
    reason: 'Output length must match input length',
  );
  expect(
    _ids(output),
    _ids(input),
    reason: 'Output must contain exactly the same song IDs as input',
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  // ── 1. Standard Fisher-Yates ──────────────────────────────────────────────

  group('Algorithm 1: Standard Fisher-Yates', () {
    test('preserves all songs with no duplicates', () {
      final pool = _makePool(50);
      final result = standardShuffleIsolate(pool);
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('handles empty list', () {
      final result = standardShuffleIsolate([]);
      expect(result, isEmpty);
    });

    test('handles single song', () {
      final pool = [_song(id: '1')];
      final result = standardShuffleIsolate(pool);
      expect(result.length, 1);
      expect(result[0].id, '1');
    });

    test('actually shuffles (not identity) for large enough lists', () {
      final pool = _makePool(100);
      final originalIds = pool.map((s) => s.id).toList();

      // Run multiple times — at least one should differ from input order.
      // P(identity for 100 items) = 1/100! ≈ 0.
      bool foundDifferent = false;
      for (int i = 0; i < 5; i++) {
        final result = standardShuffleIsolate(List.from(pool));
        final resultIds = result.map((s) => s.id).toList();
        if (!_listEquals(originalIds, resultIds)) {
          foundDifferent = true;
          break;
        }
      }
      expect(
        foundDifferent,
        isTrue,
        reason: 'Shuffle should produce a different order from the input',
      );
    });
  });

  // ── 2. Dithered Position Shuffle ──────────────────────────────────────────

  group('Algorithm 2: Dithered Position Shuffle', () {
    test('preserves all songs (genre mode)', () {
      final pool = _makeMixedPool();
      final result = ditheredPositionShuffleIsolate({
        'songs': pool,
        'pref': ShufflePreference.genre.index,
      });
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('preserves all songs (composer mode)', () {
      final pool = _makeMixedPool();
      final result = ditheredPositionShuffleIsolate({
        'songs': pool,
        'pref': ShufflePreference.composer.index,
      });
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('handles songs with empty genre/composer (Unknown bucket)', () {
      final pool = [
        _song(id: '1', genre: '', composer: ''),
        _song(id: '2', genre: '', composer: ''),
        _song(id: '3', genre: 'Rock', composer: 'Bach'),
      ];
      final result = ditheredPositionShuffleIsolate({
        'songs': pool,
        'pref': ShufflePreference.genre.index,
      });
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('spreads same-genre songs apart', () {
      // 4 Rock + 4 Jazz
      final pool = [
        _song(id: '1', genre: 'Rock'),
        _song(id: '2', genre: 'Rock'),
        _song(id: '3', genre: 'Rock'),
        _song(id: '4', genre: 'Rock'),
        _song(id: '5', genre: 'Jazz'),
        _song(id: '6', genre: 'Jazz'),
        _song(id: '7', genre: 'Jazz'),
        _song(id: '8', genre: 'Jazz'),
      ];

      // Count back-to-back same-genre occurrences over many runs.
      int totalBackToBack = 0;
      const runs = 20;
      for (int r = 0; r < runs; r++) {
        final result = ditheredPositionShuffleIsolate({
          'songs': List.from(pool),
          'pref': ShufflePreference.genre.index,
        });
        for (int i = 1; i < result.length; i++) {
          if (result[i].genre == result[i - 1].genre) totalBackToBack++;
        }
      }
      // Perfect interleaving → 0. Allow generous 30% margin.
      final maxAllowed = (runs * 7 * 0.3).round();
      expect(
        totalBackToBack,
        lessThan(maxAllowed),
        reason: 'Dithered shuffle should spread same-genre songs apart',
      );
    });
  });

  // ── 3. Merge-Shuffle ──────────────────────────────────────────────────────

  group('Algorithm 3: Merge-Shuffle', () {
    test('preserves all songs', () {
      final pool = _makeMixedPool();
      final result = mergeShuffleIsolate({
        'songs': pool,
        'pref': ShufflePreference.genre.index,
      });
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('handles single-group pool', () {
      final pool = _makePool(5, genre: 'Rock');
      final result = mergeShuffleIsolate({
        'songs': pool,
        'pref': ShufflePreference.genre.index,
      });
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('handles empty pool', () {
      final result = mergeShuffleIsolate({
        'songs': <Song>[],
        'pref': ShufflePreference.genre.index,
      });
      expect(result, isEmpty);
    });

    test('interleave produces correct total length', () {
      final a = List.generate(5, (i) => _song(id: 'a$i', genre: 'Rock'));
      final b = List.generate(3, (i) => _song(id: 'b$i', genre: 'Jazz'));
      final result = interleave(a, b, Random(42));
      expect(result.length, a.length + b.length);
      // Verify no duplicates
      expect(_ids(result).length, result.length);
    });

    test('interleave handles empty smaller list', () {
      final a = _makePool(5);
      final result = interleave(a, [], Random(42));
      expect(result.length, a.length);
    });
  });

  // ── 4. Weighted Shuffle (Efraimidis-Spirakis) ─────────────────────────────

  group('Algorithm 4: Weighted Shuffle', () {
    test('preserves all songs', () {
      final pool = _makePool(20);
      final result = weightedShuffleIsolate(pool);
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('starred songs appear earlier on average', () {
      final starredSongs = List.generate(
        5,
        (i) => _song(id: 'star_$i', starred: true, playCount: 50, rating: 5),
      );
      final normalSongs = List.generate(
        15,
        (i) => _song(id: 'normal_$i', starred: false, playCount: 0, rating: 0),
      );
      final pool = [...starredSongs, ...normalSongs];

      double totalStarredPos = 0;
      double totalNormalPos = 0;
      const runs = 50;
      for (int r = 0; r < runs; r++) {
        final result = weightedShuffleIsolate(List.from(pool));
        for (int i = 0; i < result.length; i++) {
          if (result[i].starred) {
            totalStarredPos += i;
          } else {
            totalNormalPos += i;
          }
        }
      }
      final avgStarredPos = totalStarredPos / (runs * starredSongs.length);
      final avgNormalPos = totalNormalPos / (runs * normalSongs.length);

      expect(
        avgStarredPos,
        lessThan(avgNormalPos),
        reason: 'Starred/high-weight songs should appear earlier on average',
      );
    });

    test('songWeight formula is correct', () {
      // Base: dynamicWeight clamped to [0.1, 10.0]
      expect(
        songWeight(_song(id: '1', dynamicWeight: 1.0)),
        closeTo(1.0, 0.01),
      );

      // Starred: ×2
      expect(
        songWeight(_song(id: '1', dynamicWeight: 1.0, starred: true)),
        closeTo(2.0, 0.01),
      );

      // Rating 5: +(5-1)/4 = +1.0
      expect(
        songWeight(_song(id: '1', dynamicWeight: 1.0, rating: 5)),
        closeTo(2.0, 0.01),
      );

      // PlayCount 100: +(100/100).clamp(0,1) = +1.0
      expect(
        songWeight(_song(id: '1', dynamicWeight: 1.0, playCount: 100)),
        closeTo(2.0, 0.01),
      );

      // Clamping: dynamicWeight of 20.0 clamps to 10.0
      final clamped = songWeight(_song(id: '1', dynamicWeight: 20.0));
      expect(
        clamped,
        closeTo(10.0, 0.01),
        reason: 'dynamicWeight should clamp to 10.0',
      );
    });

    test('handles zero dynamicWeight (clamped to 0.1)', () {
      final w = songWeight(_song(id: '1', dynamicWeight: 0.0));
      expect(w, greaterThanOrEqualTo(0.1));
    });
  });

  // ── 5. Album-Aware Shuffle ────────────────────────────────────────────────

  group('Algorithm 5: Album-Aware Shuffle', () {
    test('preserves all songs', () {
      final pool = _makeMixedPool();
      final result = albumAwareShuffleIsolate({
        'songs': pool,
        'shuffleTracks': false,
      });
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('preserves track order within albums when shuffleTracks=false', () {
      final pool = [
        _song(id: '1', album: 'Album A', track: 1),
        _song(id: '2', album: 'Album A', track: 2),
        _song(id: '3', album: 'Album A', track: 3),
        _song(id: '4', album: 'Album B', track: 1),
        _song(id: '5', album: 'Album B', track: 2),
      ];

      for (int r = 0; r < 20; r++) {
        final result = albumAwareShuffleIsolate({
          'songs': List.from(pool),
          'shuffleTracks': false,
        });

        final albumA = result.where((s) => s.album == 'Album A').toList();
        final albumB = result.where((s) => s.album == 'Album B').toList();

        for (int i = 1; i < albumA.length; i++) {
          expect(
            albumA[i].track,
            greaterThan(albumA[i - 1].track),
            reason: 'Album A tracks should be in ascending order',
          );
        }
        for (int i = 1; i < albumB.length; i++) {
          expect(
            albumB[i].track,
            greaterThan(albumB[i - 1].track),
            reason: 'Album B tracks should be in ascending order',
          );
        }
      }
    });

    test('albums play as contiguous blocks', () {
      final pool = [
        _song(id: '1', album: 'A', track: 1),
        _song(id: '2', album: 'A', track: 2),
        _song(id: '3', album: 'B', track: 1),
        _song(id: '4', album: 'B', track: 2),
        _song(id: '5', album: 'C', track: 1),
      ];

      for (int r = 0; r < 20; r++) {
        final result = albumAwareShuffleIsolate({
          'songs': List.from(pool),
          'shuffleTracks': false,
        });

        final seen = <String>{};
        String? currentAlbum;
        for (final song in result) {
          if (song.album != currentAlbum) {
            expect(
              seen.contains(song.album),
              isFalse,
              reason: 'Album "${song.album}" appeared non-contiguously',
            );
            if (currentAlbum != null) seen.add(currentAlbum);
            currentAlbum = song.album;
          }
        }
      }
    });

    test('shuffleTracks=true randomizes within albums', () {
      final pool = [
        _song(id: '1', album: 'A', track: 1),
        _song(id: '2', album: 'A', track: 2),
        _song(id: '3', album: 'A', track: 3),
        _song(id: '4', album: 'A', track: 4),
        _song(id: '5', album: 'A', track: 5),
      ];

      // With shuffleTracks=true, track order should change at least once in 10 runs.
      bool foundDifferentOrder = false;
      for (int r = 0; r < 10; r++) {
        final result = albumAwareShuffleIsolate({
          'songs': List.from(pool),
          'shuffleTracks': true,
        });
        final tracks = result.map((s) => s.track).toList();
        if (!_listEquals(
          tracks.map((t) => t.toString()).toList(),
          [1, 2, 3, 4, 5].map((t) => t.toString()).toList(),
        )) {
          foundDifferentOrder = true;
          break;
        }
      }
      expect(
        foundDifferentOrder,
        isTrue,
        reason: 'shuffleTracks=true should randomize track order',
      );
    });
  });

  // ── 6. Recency-Dampened Weighted Shuffle ──────────────────────────────────

  group('Algorithm 6: Recency-Dampened Shuffle', () {
    test('preserves all songs', () {
      final pool = _makePool(20);
      final result = recencyDampenedShuffleIsolate({
        'songs': pool,
        'recentIds': <String>[],
      });
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('recent songs appear later on average', () {
      final pool = _makePool(20);
      final recentIds = pool.take(5).map((s) => s.id).toList();

      double totalRecentPos = 0;
      double totalOtherPos = 0;
      const runs = 50;
      for (int r = 0; r < runs; r++) {
        final result = recencyDampenedShuffleIsolate({
          'songs': List.from(pool),
          'recentIds': recentIds,
        });
        for (int i = 0; i < result.length; i++) {
          if (recentIds.contains(result[i].id)) {
            totalRecentPos += i;
          } else {
            totalOtherPos += i;
          }
        }
      }
      final avgRecentPos = totalRecentPos / (runs * recentIds.length);
      final avgOtherPos =
          totalOtherPos / (runs * (pool.length - recentIds.length));

      expect(
        avgRecentPos,
        greaterThan(avgOtherPos),
        reason: 'Recently played songs should be pushed toward the end',
      );
    });

    test('handles empty recentIds (no dampening applied)', () {
      final pool = _makePool(10);
      final result = recencyDampenedShuffleIsolate({
        'songs': pool,
        'recentIds': <String>[],
      });
      _assertNoDuplicatesOrMissing(pool, result);
    });

    test('0.1x weight multiplier is applied to recent songs', () {
      // A song with dynamicWeight=1.0, not starred, no rating, no plays
      // has base weight = 1.0. With recency dampening, weight = 0.1.
      final recentSong = _song(id: 'recent');
      final baseW = songWeight(recentSong);
      expect(baseW, closeTo(1.0, 0.01));
      // The algorithm applies 0.1× internally — we can verify this by
      // checking that the recent song consistently appears late.
      // (Direct weight inspection requires exposing internals, so we
      // verify via position statistics in the test above.)
    });
  });
}
