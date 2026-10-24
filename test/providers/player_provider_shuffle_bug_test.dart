import 'package:audio_service/audio_service.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/player_provider.dart' hide PlayerState;
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/navi_audio_handler.dart';
import 'package:navivibe/services/listening_event_collector.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/services/playlist_cache_service.dart';

import '../helpers/reversing_shuffle_repository.dart';

Song _song({
  required String id,
  String title = 'Song',
  String artist = 'Artist',
  int duration = 200,
}) => Song(
  id: id,
  title: '$title $id',
  artist: artist,
  album: 'Album',
  genre: 'Rock',
  composer: 'Comp',
  coverArt: '',
  duration: duration,
  track: 1,
  year: 2024,
);

class MockPlaylistCacheService extends Fake implements PlaylistCacheService {}

class MockListeningEventCollector extends Mock
    implements ListeningEventCollector {}

class MockSubsonicService extends SubsonicService {
  MockSubsonicService(PlaylistCacheService cache)
    : super(
        serverUrl: 'https://test.example.com',
        username: 'test',
        password: 'test',
        cache: cache,
      );
}

class ControlledAudioPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast(sync: true);
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast(sync: true);
  final StreamController<LoopMode> _loopModeController =
      StreamController<LoopMode>.broadcast(sync: true);
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<PlaybackEvent> _playbackEventController =
      StreamController<PlaybackEvent>.broadcast(sync: true);
  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<ProcessingState> _processingStateController =
      StreamController<ProcessingState>.broadcast(sync: true);

  int? _currentIndex = 0;
  Duration _mockPosition = Duration.zero;
  bool _playing = false;

  @override
  Duration get position => _mockPosition;

  @override
  LoopMode get loopMode => LoopMode.off;

  @override
  bool get playing => _playing;

  @override
  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      _playbackEventController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _processingStateController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<LoopMode> get loopModeStream => _loopModeController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  int? get currentIndex => _currentIndex;

  @override
  AudioSource? get audioSource => null;

  @override
  Stream<SequenceState> get sequenceStateStream => const Stream.empty();

  void setMockPosition(Duration position) {
    _mockPosition = position;
    _positionController.add(position);
  }

  void setMockPlaying(bool playing) {
    _playing = playing;
    _playingController.add(playing);
  }

  Future<void> emitCurrentIndex(int? index) async {
    _currentIndex = index;
    _currentIndexController.add(index);
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    _currentIndex = initialIndex ?? 0;
    _mockPosition = initialPosition ?? Duration.zero;
    return null;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (index != null) {
      _currentIndex = index;
    }
  }

  @override
  Future<void> play() async {
    _playing = true;
  }

  @override
  Future<void> stop() async {
    _playing = false;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> dispose() async {}
}

class TestAudioHandler extends NaviAudioHandler {
  TestAudioHandler(super.subsonicService, {super.player}) {
    player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < currentQueue.length) {
        final song = currentQueue[index];
        mediaItem.add(MediaItem(
          id: song.id,
          album: song.album,
          title: song.title,
          artist: song.artist,
          duration: Duration(seconds: song.duration),
        ));
      }
    });
  }

  @override
  Future<void> setQueue(
    List<Song> songs,
    int startIndex, {
    List<Song>? unshuffledSongs,
  }) async {
    currentQueue = List<Song>.from(songs);
  }
}

/// Every shuffle (Smart Local or local) keeps the playing song playing and
/// moves it to the front, with the rest of the queue after it. This is the
/// index that song now has, which the guard must hold.
int _anchorIndex(ProviderContainer c, String songId) =>
    c.read(playerProvider).queue.indexWhere((s) => s.id == songId);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(
      Song(
        id: '',
        title: '',
        artist: '',
        album: '',
        coverArt: '',
        duration: 0,
        track: 0,
        year: 0,
      ),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (MethodCall methodCall) async {
            return ['wifi'];
          },
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return Directory.systemTemp.path;
          },
        );

    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('hive_test_shuffle_bug');
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  group('BUG-A — Stale currentIndex After Async Reshuffle', () {
    test(
      'applyShuffleAlgorithm maintains safeIndex despite transient stream emissions',
      () async {
        final mockCache = MockPlaylistCacheService();
        final mockService = MockSubsonicService(mockCache);
        final mockPlayer = ControlledAudioPlayer();
        final handler = TestAudioHandler(mockService, player: mockPlayer);

        final mockCollector = MockListeningEventCollector();
        final container = ProviderContainer(
          overrides: [
            audioHandlerProvider.overrideWithValue(handler),
            subsonicServiceProvider.overrideWithValue(mockService),
            listenerCollectorProvider.overrideWithValue(mockCollector),
            shuffleRepositoryProvider.overrideWithValue(ReversingShuffleRepository()),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(playerProvider.notifier);
        final songs = [
          _song(id: '1', title: 'First'),
          _song(id: '2', title: 'Second'),
          _song(id: '3', title: 'Third', artist: 'Target'),
          _song(id: '4', title: 'Fourth'),
          _song(id: '5', title: 'Fifth'),
        ];

        await notifier.setQueue(songs, 2);
        await mockPlayer.emitCurrentIndex(2);

        // Let any initial stream events settle
        await Future.delayed(const Duration(milliseconds: 50));

        final stateBefore = container.read(playerProvider);
        expect(stateBefore.currentIndex, 2);
        expect(stateBefore.currentSong?.id, '3');

        // Setup Smart Local Shuffle mode
        container
            .read(settingsProvider.notifier)
            .setShuffleAlgorithm(ShuffleAlgorithm.smartLocal);

        // Smart Reshuffle: the server call runs outside the queue lock, the
        // commit inside it. (The Shuffle toggle is local-only by design.)
        await notifier.smartReshuffle();

        // The playing song keeps playing, now at the front of the new order.
        final anchor = _anchorIndex(container, '3');
        final stateAfter = container.read(playerProvider);
        expect(stateAfter.currentSong?.id, '3');
        expect(stateAfter.currentIndex, anchor);
        // The Smart Shuffle order was applied (the fake reverses candidates).
        expect(stateAfter.queue.skip(anchor + 1).map((s) => s.id), ['5', '4', '2', '1']);

        // Realistic worst case from just_audio: stale emissions of indices
        // from before the reorder arrive after it.
        await mockPlayer.emitCurrentIndex(2);
        await Future.delayed(const Duration(milliseconds: 10));
        await mockPlayer.emitCurrentIndex(1);
        await Future.delayed(const Duration(milliseconds: 10));

        // The guard must hold the anchor through them.
        final stateDuringRace = container.read(playerProvider);
        expect(
          stateDuringRace.currentIndex,
          anchor,
          reason: 'Transient stream events must not move playback off the anchor',
        );
        expect(stateDuringRace.currentSong?.id, '3');

        // Finally the player reports the anchor itself.
        await mockPlayer.emitCurrentIndex(anchor);
        await Future.delayed(const Duration(milliseconds: 10));

        final finalState = container.read(playerProvider);
        expect(finalState.currentIndex, anchor);
        expect(finalState.currentSong?.id, '3');
      },
    );
  });

  // BUG-004 (Change 2): _lastKnownIndex must be synced on guard-timer expiry.
  // Without the fix, _lastKnownIndex stays at the pre-shuffle value even after
  // the 500ms window closes, so the very first stream event processed post-guard
  // is compared against a stale prevIndex — causing the handler to accept it
  // and overwrite state.currentIndex with the transient value.
  group('BUG-B — _lastKnownIndex Stale After Guard Timer Expiry', () {
    test(
      'guard timer expiry: _lastKnownIndex is synced so state stays on anchor',
      () async {
        final mockCache = MockPlaylistCacheService();
        final mockService = MockSubsonicService(mockCache);
        final mockPlayer = ControlledAudioPlayer();
        final handler = TestAudioHandler(mockService, player: mockPlayer);
        final mockCollector = MockListeningEventCollector();

        final container = ProviderContainer(
          overrides: [
            audioHandlerProvider.overrideWithValue(handler),
            subsonicServiceProvider.overrideWithValue(mockService),
            listenerCollectorProvider.overrideWithValue(mockCollector),
            shuffleRepositoryProvider.overrideWithValue(ReversingShuffleRepository()),
          ],
        );
        addTearDown(container.dispose);

        container
            .read(settingsProvider.notifier)
            .setShuffleAlgorithm(ShuffleAlgorithm.smartLocal);

        final notifier = container.read(playerProvider.notifier);
        final songs = [
          _song(id: '1', title: 'First'),
          _song(id: '2', title: 'Second'),
          _song(id: '3', title: 'TargetSong'),
          _song(id: '4', title: 'Fourth'),
          _song(id: '5', title: 'Fifth'),
        ];

        await notifier.setQueue(songs, 2);
        await mockPlayer.emitCurrentIndex(2);
        await Future.delayed(const Duration(milliseconds: 50));

        // Reshuffle.
        await notifier.applyShuffleAlgorithm();

        // Guard window is active; verify the anchor (the playing song, now at
        // the front of the new order) is held.
        final anchor = _anchorIndex(container, '3');
        expect(container.read(playerProvider).currentIndex, anchor);
        expect(container.read(playerProvider).currentSong?.id, '3');

        // Wait for the 500ms guard timer to expire.
        // This is the critical moment: _lastKnownIndex must be updated to the
        // anchor so subsequent stream events have the correct comparison base.
        await Future.delayed(const Duration(milliseconds: 600));

        // Guard has expired. State should still reflect the anchor.
        final stateAfterExpiry = container.read(playerProvider);
        expect(
          stateAfterExpiry.currentIndex,
          anchor,
          reason: 'State must remain on anchor after guard timer expires',
        );
        expect(
          stateAfterExpiry.currentSong?.id,
          '3',
          reason: 'currentSong must be TargetSong at guard expiry',
        );
      },
    );

    // Verify the standard (non-smartLocal) shuffle path is also fixed.
    test('standard shuffle: _lastKnownIndex synced after guard expiry', () async {
      final mockCache = MockPlaylistCacheService();
      final mockService = MockSubsonicService(mockCache);
      final mockPlayer = ControlledAudioPlayer();
      final handler = TestAudioHandler(mockService, player: mockPlayer);
      final mockCollector = MockListeningEventCollector();

      final container = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          subsonicServiceProvider.overrideWithValue(mockService),
          listenerCollectorProvider.overrideWithValue(mockCollector),
        ],
      );
      addTearDown(container.dispose);

      // Use standard shuffle (non-smartLocal) to exercise the other guard path.
      container
          .read(settingsProvider.notifier)
          .setShuffleAlgorithm(ShuffleAlgorithm.standard);

      final notifier = container.read(playerProvider.notifier);
      final songs = [
        _song(id: '1', title: 'First'),
        _song(id: '2', title: 'Second'),
        _song(id: '3', title: 'Anchor'),
        _song(id: '4', title: 'Fourth'),
        _song(id: '5', title: 'Fifth'),
      ];

      await notifier.setQueue(songs, 2);
      await mockPlayer.emitCurrentIndex(2);
      await Future.delayed(const Duration(milliseconds: 50));

      // Make the player appear to be shuffling already so applyShuffleAlgorithm
      // calls the standard path.
      await notifier.applyShuffleAlgorithm();

      // Immediately after, current song ID must still be '3'.
      final stateAfter = container.read(playerProvider);
      final anchorId = stateAfter.currentSong?.id;
      expect(anchorId, isNotNull);

      // Emit a transient 0 while the guard is active.
      await mockPlayer.emitCurrentIndex(0);
      await Future.delayed(const Duration(milliseconds: 10));

      // Still must be on anchor.
      expect(
        container.read(playerProvider).currentSong?.id,
        anchorId,
        reason: 'Standard shuffle path must also suppress transient index=0',
      );

      // Let the guard expire.
      await Future.delayed(const Duration(milliseconds: 600));

      // State must be consistent at expiry.
      expect(
        container.read(playerProvider).currentSong?.id,
        anchorId,
        reason: 'Song must remain on anchor after guard expiry (standard path)',
      );
    });
  });
}
