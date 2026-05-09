import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:just_audio/just_audio.dart';

import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/player_provider.dart' hide PlayerState;
import 'package:navivibe/services/audio_handler.dart';
import 'package:navivibe/services/scrobble_service.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/services/listening_log_service.dart';
import 'package:navivibe/services/playlist_cache_service.dart';

class MockSubsonicService extends Mock implements SubsonicService {}
class MockConnectivity extends Mock implements Connectivity {}
class MockScrobbleService extends Mock implements ScrobbleService {}
class MockListeningLogService extends Mock implements ListeningLogService {}
class MockPlaylistCacheService extends Fake implements PlaylistCacheService {}

class ControlledAudioPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _currentIndexController = StreamController<int?>.broadcast(sync: true);
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast(sync: true);
  final StreamController<bool> _playingController = StreamController<bool>.broadcast(sync: true);
  final StreamController<LoopMode> _loopModeController = StreamController<LoopMode>.broadcast(sync: true);
  final StreamController<PlaybackEvent> _playbackEventController = StreamController<PlaybackEvent>.broadcast(sync: true);
  final StreamController<PlayerState> _playerStateController = StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<ProcessingState> _processingStateController = StreamController<ProcessingState>.broadcast(sync: true);

  int? _currentIndex = -1;
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
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<LoopMode> get loopModeStream => _loopModeController.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _playbackEventController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<ProcessingState> get processingStateStream => _processingStateController.stream;

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

class TestAudioHandler extends AudioHandler {
  TestAudioHandler(super.subsonicService, {super.player});
  @override
  Future<void> setQueue(List<Song> songs, int startIndex, {List<Song>? unshuffledSongs}) async {
    currentQueue = List<Song>.from(songs);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('hive_test_scrobble');
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.audio = await Hive.openBox('audio');
    
    registerFallbackValue(Uri());
    registerFallbackValue(Duration.zero);
    registerFallbackValue(
      Song(id: '', title: '', artist: '', album: '', coverArt: '', duration: 0, track: 0, year: 0),
    );
  });

  group('ScrobbleService - Offline Guards & Submissions', () {
    late MockSubsonicService mockApi;
    late MockConnectivity mockConnectivity;
    late ScrobbleService scrobbleService;

    setUp(() {
      mockApi = MockSubsonicService();
      mockConnectivity = MockConnectivity();
      scrobbleService = ScrobbleService(
        mockApi,
        mockConnectivity,
        MockListeningLogService(),
      );
    });

    test('nowPlaying submits with submission=false when online', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => mockApi.scrobble(any(), submission: any(named: 'submission')))
          .thenAnswer((_) async => {});

      scrobbleService.nowPlaying('song123');
      await Future.delayed(Duration.zero); // allow unawaited futures

      verify(() => mockConnectivity.checkConnectivity()).called(1);
      verify(() => mockApi.scrobble('song123', submission: false)).called(1);
    });

    test('submit submits with submission=true when online', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.mobile]);
      when(() => mockApi.scrobble(any(), submission: any(named: 'submission')))
          .thenAnswer((_) async => {});

      scrobbleService.submit('song456');
      await Future.delayed(Duration.zero);

      verify(() => mockConnectivity.checkConnectivity()).called(1);
      verify(() => mockApi.scrobble('song456', submission: true)).called(1);
    });

    test('does NOT submit if offline', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);
          
      scrobbleService.submit('song789');
      scrobbleService.nowPlaying('song789');
      await Future.delayed(Duration.zero);

      verify(() => mockConnectivity.checkConnectivity()).called(2);
      verifyNever(() => mockApi.scrobble(any(), submission: any(named: 'submission')));
    });
  });

  group('PlayerNotifier - Scrobble Threshold Logic', () {
    late ControlledAudioPlayer mockPlayer;
    late TestAudioHandler handler;
    late MockScrobbleService mockScrobble;
    late ProviderContainer container;

    setUp(() {
      mockPlayer = ControlledAudioPlayer();
      final mockCache = MockPlaylistCacheService();
      final mockService = MockSubsonicService();
      handler = TestAudioHandler(mockService, player: mockPlayer);
      mockScrobble = MockScrobbleService();

      container = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          scrobbleServiceProvider.overrideWithValue(mockScrobble),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Threshold triggers at 50% for short songs', () async {
      final notifier = container.read(playerProvider.notifier);
      final song = Song(id: 's1', title: 'A', artist: 'B', album: 'C', coverArt: '', duration: 120, track: 1, year: 2024);
      
      await notifier.setQueue([song], 0);
      
      // new song start triggers nowPlaying
      await mockPlayer.emitCurrentIndex(0);
      await Future.delayed(Duration.zero);
      verify(() => mockScrobble.nowPlaying('s1')).called(1);

      // Not at threshold yet (threshold is 60s)
      mockPlayer.setMockPosition(const Duration(seconds: 30));
      await Future.delayed(Duration.zero);
      verifyNever(() => mockScrobble.submit(any()));

      // Cross threshold
      mockPlayer.setMockPosition(const Duration(seconds: 61));
      await Future.delayed(Duration.zero);
      verify(() => mockScrobble.submit(
        's1',
        song: any(named: 'song'),
      )).called(1);

      // Ensure it doesn't submit twice
      mockPlayer.setMockPosition(const Duration(seconds: 70));
      await Future.delayed(Duration.zero);
      verifyNever(() => mockScrobble.submit(any()));
    });

    test('Threshold capped at 4 minutes for long songs', () async {
      final notifier = container.read(playerProvider.notifier);
      final song = Song(id: 'long', title: 'A', artist: 'B', album: 'C', coverArt: '', duration: 600, track: 1, year: 2024); // 10 minutes
      
      await notifier.setQueue([song], 0);
      await mockPlayer.emitCurrentIndex(0);
      
      // 50% would be 5 minutes, but threshold is 4 mins (240s)
      mockPlayer.setMockPosition(const Duration(seconds: 230));
      await Future.delayed(Duration.zero);
      verifyNever(() => mockScrobble.submit(any()));

      mockPlayer.setMockPosition(const Duration(seconds: 241));
      await Future.delayed(Duration.zero);
      verify(() => mockScrobble.submit(
        'long',
        song: any(named: 'song'),
      )).called(1);
    });
    
    test('Skips before threshold do not trigger submission', () async {
      final notifier = container.read(playerProvider.notifier);
      final song1 = Song(id: 's1', title: 'A', artist: 'B', album: 'C', coverArt: '', duration: 100, track: 1, year: 2024);
      final song2 = Song(id: 's2', title: 'D', artist: 'B', album: 'C', coverArt: '', duration: 100, track: 2, year: 2024);
      
      await notifier.setQueue([song1, song2], 0);
      await mockPlayer.emitCurrentIndex(0);
      verify(() => mockScrobble.nowPlaying('s1')).called(1);
      
      mockPlayer.setMockPosition(const Duration(seconds: 10)); // Before 50s threshold
      await Future.delayed(Duration.zero);
      
      // User skips
      await mockPlayer.emitCurrentIndex(1);
      await Future.delayed(Duration.zero);
      verifyNever(() => mockScrobble.submit('s1'));
      verify(() => mockScrobble.nowPlaying('s2')).called(1);
    });
  });
}
