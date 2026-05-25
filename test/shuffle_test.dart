import 'dart:async';
import 'dart:io';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navivibe/services/audio_handler.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/providers/player_provider.dart' hide PlayerState;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestAudioHandler extends AudioHandler {
  TestAudioHandler(super.subsonicService, {super.player});

  @override
  Future<void> setQueue(
    List<Song> songs,
    int startIndex, {
    List<Song>? unshuffledSongs,
  }) async {
    currentQueue = List<Song>.from(songs);
  }
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

  @override
  Duration get position => _mockPosition;

  void setMockPosition(Duration position) {
    _mockPosition = position;
    _positionController.add(position);
  }

  @override
  LoopMode get loopMode => LoopMode.off;

  @override
  bool get playing => false;

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

  Future<void> emitCurrentIndex(int? index) async {
    _currentIndex = index;
    _currentIndexController.add(index);
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}

class MockSubsonicService extends SubsonicService {
  MockSubsonicService(PlaylistCacheService cache)
    : super(serverUrl: '', username: '', password: '', cache: cache);
}

class MockPlaylistCacheService extends Fake implements PlaylistCacheService {}

class MockAudioPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast(sync: true);
  final StreamController<PlaybackEvent> _playbackEventController =
      StreamController<PlaybackEvent>.broadcast(sync: true);
  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<ProcessingState> _processingStateController =
      StreamController<ProcessingState>.broadcast(sync: true);

  @override
  Duration get position => Duration.zero;

  @override
  LoopMode get loopMode => LoopMode.off;

  @override
  bool get playing => false;

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
  int? get currentIndex => 0;

  @override
  AudioSource? get audioSource => null;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    return null;
  }

  @override
  Future<void> setVolume(double volume) async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (MethodCall methodCall) async {
            return ['wifi'];
          },
        );

    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('hive_test_shuffle');
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  group('Balanced Shuffle Logic', () {
    late TestAudioHandler handler;
    late Song s1, s2, s3, s4;

    setUp(() {
      final mockCache = MockPlaylistCacheService();
      final mockService = MockSubsonicService(mockCache);
      final mockPlayer = MockAudioPlayer();
      handler = TestAudioHandler(mockService, player: mockPlayer);

      s1 = Song(
        id: '1',
        title: 'S1',
        artist: 'A1',
        album: 'B1',
        composer: 'Comp1',
        genre: 'G1',
        coverArt: '',
        duration: 100,
        track: 1,
        year: 2020,
      );
      s2 = Song(
        id: '2',
        title: 'S2',
        artist: 'A2',
        album: 'B2',
        composer: 'Comp1',
        genre: 'G2',
        coverArt: '',
        duration: 100,
        track: 2,
        year: 2020,
      );
      s3 = Song(
        id: '3',
        title: 'S3',
        artist: 'A3',
        album: 'B3',
        composer: 'Comp2',
        genre: 'G1',
        coverArt: '',
        duration: 100,
        track: 3,
        year: 2020,
      );
      s4 = Song(
        id: '4',
        title: 'S4',
        artist: 'A4',
        album: 'B4',
        composer: 'Comp2',
        genre: 'G2',
        coverArt: '',
        duration: 100,
        track: 4,
        year: 2020,
      );

      handler.currentQueue = [s1, s2, s3, s4];
    });

    test('Groups correctly by Composer when preference is composer', () async {
      await handler.mergeShuffle(ShufflePreference.composer);

      final result = handler.currentQueue;
      expect(result[0].id, '1');
      // S1 is Comp1. result[1] MUST be Comp2 (S3 or S4)
      expect(result[1].composer, 'Comp2');
    });

    test('Groups correctly by Genre when preference is genre', () async {
      await handler.mergeShuffle(ShufflePreference.genre);

      final result = handler.currentQueue;
      expect(result[0].id, '1');
      // S1 is G1. result[1] MUST be G2 (S2 or S4)
      expect(result[1].genre, 'G2');
    });

    test('Handles missing metadata gracefully with "Unknown" bucket', () async {
      final s5 = Song(
        id: '5',
        title: 'S5',
        artist: 'A5',
        album: 'B5',
        composer: '',
        genre: '',
        coverArt: '',
        duration: 100,
        track: 5,
        year: 2020,
      );
      handler.currentQueue = [s1, s5];

      await handler.spotifyDitherShuffle(ShufflePreference.composer);
      expect(handler.currentQueue.length, 2);
      expect(handler.currentQueue[1].id, '5');
    });
  });

  test('Song.fromJson parses displayComposer', () {
    final json = {
      'id': '1',
      'title': 'Test Title',
      'displayComposer': 'Beethoven',
      'genre': 'Classical',
    };
    final song = Song.fromJson(json);
    expect(song.composer, 'Beethoven');
  });

  test(
    'history does not duplicate the same song on repeated index events',
    () async {
      final mockCache = MockPlaylistCacheService();
      final mockService = MockSubsonicService(mockCache);
      final mockPlayer = ControlledAudioPlayer();
      final handler = TestAudioHandler(mockService, player: mockPlayer);

      final container = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          subsonicServiceProvider.overrideWithValue(mockService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playerProvider.notifier);
      final songs = [
        Song(
          id: '1',
          title: 'First',
          artist: 'Artist 1',
          album: 'A',
          composer: 'C',
          genre: 'G',
          coverArt: '',
          duration: 120,
          track: 1,
          year: 2024,
        ),
        Song(
          id: '2',
          title: 'Second',
          artist: 'Artist 2',
          album: 'A',
          composer: 'C',
          genre: 'G',
          coverArt: '',
          duration: 120,
          track: 2,
          year: 2024,
        ),
      ];

      await notifier.setQueue(songs, 0);
      mockPlayer.setMockPosition(const Duration(seconds: 5));
      await Future.delayed(const Duration(milliseconds: 50)); // let stream emit
      await mockPlayer.emitCurrentIndex(1);
      await mockPlayer.emitCurrentIndex(1);

      expect(
        container.read(playerProvider).historySongs.map((song) => song.id),
        ['1'],
      );
    },
  );
}
