import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/download_state.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/download_provider.dart';
import 'package:navivibe/widgets/ui/collection_hero.dart';

void main() {
  group('DownloadProgressThrottle', () {
    test('drops chunks inside the interval that moved under 1%', () {
      var t = DateTime(2026);
      final th = DownloadProgressThrottle(now: () => t);
      expect(th.shouldEmit(0.0), isTrue); // first always passes
      t = t.add(const Duration(milliseconds: 10));
      expect(th.shouldEmit(0.004), isFalse);
      t = t.add(const Duration(milliseconds: 10));
      expect(th.shouldEmit(0.008), isFalse);
    });

    test('passes a >=1% step immediately', () {
      var t = DateTime(2026);
      final th = DownloadProgressThrottle(now: () => t);
      th.shouldEmit(0.0);
      t = t.add(const Duration(milliseconds: 5));
      expect(th.shouldEmit(0.02), isTrue);
    });

    test('passes after 250 ms even for a tiny move', () {
      var t = DateTime(2026);
      final th = DownloadProgressThrottle(now: () => t);
      th.shouldEmit(0.5);
      t = t.add(const Duration(milliseconds: 260));
      expect(th.shouldEmit(0.501), isTrue);
    });
  });

  test('CollectionDownloadProgress compares by content', () {
    final songs = <Song>[Song(id: 'a', title: 'a', artist: 'x', album: 'y', coverArt: '', duration: 1, track: 1, year: 2020)];
    final one = CollectionDownloadProgress.of(songs, {
      'a': const SongDownloadState(
          songId: 'a', status: SongDownloadStatus.downloading, progress: 0.1),
    });
    final two = CollectionDownloadProgress.of(songs, {
      'a': const SongDownloadState(
          songId: 'a', status: SongDownloadStatus.downloading, progress: 0.9),
    });
    expect(one, two);
  });
}
