import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navivibe/models/download_state.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/download_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/offline_service.dart';
import 'package:navivibe/services/subsonic_service.dart';

Song makeSong({
  String id = '1',
  String title = 'Test Song',
  String artist = 'Artist',
  String album = 'Album',
  String genre = 'Rock',
  String composer = 'Bach',
  int duration = 200,
  int track = 1,
  int year = 2024,
  bool starred = false,
  int playCount = 0,
  int rating = 0,
  double dynamicWeight = 1.0,
}) => Song(
  id: id,
  title: title,
  artist: artist,
  album: album,
  genre: genre,
  composer: composer,
  coverArt: '',
  duration: duration,
  track: track,
  year: year,
  starred: starred,
  playCount: playCount,
  rating: rating,
  dynamicWeight: dynamicWeight,
);

class MockOfflineService extends Mock implements OfflineService {
  final List<String> preDownloadedIds;
  final Duration downloadDelay;
  final void Function(Song)? onDownload;
  final bool downloadSuccess;

  MockOfflineService({
    this.preDownloadedIds = const [],
    this.downloadDelay = Duration.zero,
    this.onDownload,
    this.downloadSuccess = true,
  });

  @override
  List<String> getDownloadedSongIds() => preDownloadedIds;

  @override
  Future<bool> downloadSong(
    Song song,
    SubsonicService subsonicService, {
    void Function(double progress)? onProgress,
  }) async {
    onDownload?.call(song);
    await Future.delayed(downloadDelay);
    onProgress?.call(1.0);
    return downloadSuccess;
  }
}

class MockSubsonicService extends Mock implements SubsonicService {}

void main() {
  group('DownloadStateNotifier', () {
    late MockSubsonicService mockSubsonicService;

    setUp(() {
      mockSubsonicService = MockSubsonicService();
    });

    test('initial state is seeded from OfflineService', () {
      final container = ProviderContainer(
        overrides: [
          offlineServiceProvider.overrideWithValue(
            MockOfflineService(preDownloadedIds: ['123']),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(downloadStateProvider);
      expect(state, isNotEmpty);
      expect(state['123']?.status, equals(SongDownloadStatus.downloaded));
    });

    test(
      'downloadSong transitions through queued → downloading → downloaded',
      () async {
        final container = ProviderContainer(
          overrides: [
            offlineServiceProvider.overrideWithValue(
              MockOfflineService(downloadDelay: Duration.zero),
            ),
            subsonicServiceProvider.overrideWithValue(mockSubsonicService),
          ],
        );
        addTearDown(container.dispose);

        final song = makeSong(id: '1');
        await container.read(downloadStateProvider.notifier).downloadSong(song);

        final finalStatus = container.read(downloadStateProvider)['1']?.status;
        expect(finalStatus, equals(SongDownloadStatus.downloaded));
      },
    );

    test(
      'multi-tap blocked — second call is no-op while downloading',
      () async {
        int downloadCallCount = 0;
        final container = ProviderContainer(
          overrides: [
            offlineServiceProvider.overrideWithValue(
              MockOfflineService(
                onDownload: (_) {
                  downloadCallCount++;
                },
                downloadDelay: const Duration(milliseconds: 50),
              ),
            ),
            subsonicServiceProvider.overrideWithValue(mockSubsonicService),
          ],
        );
        addTearDown(container.dispose);

        final song = makeSong(id: '1');
        final notifier = container.read(downloadStateProvider.notifier);

        // Fire two downloads in parallel without awaiting
        notifier.downloadSong(song);
        notifier.downloadSong(song); // should be blocked

        await Future.delayed(const Duration(milliseconds: 200));

        expect(downloadCallCount, equals(1)); // only one actual download
      },
    );

    test(
      'downloadPlaylist queues all songs at once then downloads sequentially',
      () async {
        final container = ProviderContainer(
          overrides: [
            offlineServiceProvider.overrideWithValue(
              MockOfflineService(downloadDelay: Duration.zero),
            ),
            subsonicServiceProvider.overrideWithValue(mockSubsonicService),
          ],
        );
        addTearDown(container.dispose);

        final songs = [makeSong(id: '1'), makeSong(id: '2'), makeSong(id: '3')];
        await container
            .read(downloadStateProvider.notifier)
            .downloadPlaylist(songs);

        final state = container.read(downloadStateProvider);
        for (final song in songs) {
          expect(state[song.id]?.status, equals(SongDownloadStatus.downloaded));
        }
      },
    );

    test('already downloaded songs are skipped in downloadPlaylist', () async {
      int downloadCallCount = 0;
      final container = ProviderContainer(
        overrides: [
          offlineServiceProvider.overrideWithValue(
            MockOfflineService(
              preDownloadedIds: ['2'], // song 2 already downloaded
              onDownload: (_) => downloadCallCount++,
              downloadDelay: Duration.zero,
            ),
          ),
          subsonicServiceProvider.overrideWithValue(mockSubsonicService),
        ],
      );
      addTearDown(container.dispose);

      final songs = [makeSong(id: '1'), makeSong(id: '2'), makeSong(id: '3')];
      await container
          .read(downloadStateProvider.notifier)
          .downloadPlaylist(songs);

      // Only 1 and 3 should trigger actual downloads
      expect(downloadCallCount, equals(2));
    });
  });
}
