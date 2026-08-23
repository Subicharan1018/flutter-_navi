import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:rxdart/rxdart.dart';

import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/session_sync_provider.dart';
import 'package:navivibe/services/session_sync_service.dart';
import 'package:navivibe/services/navi_audio_handler.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/services/listening_event_collector.dart';

class MockNaviAudioHandler extends Mock implements NaviAudioHandler {}

class MockSubsonicService extends Mock implements SubsonicService {}

class MockListeningEventCollector extends Mock
    implements ListeningEventCollector {}

class ControlledAudioPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast(sync: true);
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast(sync: true);
  final StreamController<LoopMode> _loopModeController =
      StreamController<LoopMode>.broadcast(sync: true);
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<ProcessingState> _processingStateController =
      StreamController<ProcessingState>.broadcast(sync: true);

  int? _currentIndex = 0;
  bool _playing = false;
  Duration _position = Duration.zero;

  @override
  Duration get position => _position;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  bool get playing => _playing;

  @override
  Stream<int?> get currentIndexStream => _currentIndexController.stream;
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
  Future<void> pause() async {
    _playing = false;
    _playingController.add(false);
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _playingController.add(false);
  }

  @override
  Future<void> play() async {
    _playing = true;
    _playingController.add(true);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) {
      _position = position;
      _positionController.add(position);
    }
    if (index != null) {
      _currentIndex = index;
      _currentIndexController.add(index);
    }
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _loopModeController.add(mode);
  }

  @override
  Future<void> dispose() async {
    await _currentIndexController.close();
    await _playingController.close();
    await _loopModeController.close();
    await _positionController.close();
    await _processingStateController.close();
  }
}

class ControlledNaviAudioHandler extends Mock implements NaviAudioHandler {
  @override
  final ControlledAudioPlayer player = ControlledAudioPlayer();

  @override
  List<Song> currentQueue = [];

  final BehaviorSubject<audio_service.MediaItem?> _mediaItemSubject =
      BehaviorSubject<audio_service.MediaItem?>.seeded(null);
  @override
  BehaviorSubject<audio_service.MediaItem?> get mediaItem => _mediaItemSubject;

  final BehaviorSubject<audio_service.PlaybackState> _playbackStateSubject =
      BehaviorSubject<audio_service.PlaybackState>.seeded(
    audio_service.PlaybackState(),
  );
  @override
  BehaviorSubject<audio_service.PlaybackState> get playbackState =>
      _playbackStateSubject;

  @override
  int get currentIndex => player.currentIndex ?? 0;

  ControlledNaviAudioHandler() {
    player.playingStream.listen((playing) {
      _playbackStateSubject.add(
        _playbackStateSubject.value.copyWith(playing: playing),
      );
    });
    player.loopModeStream.listen((loop) {
      final rm = const {
            LoopMode.off: audio_service.AudioServiceRepeatMode.none,
            LoopMode.one: audio_service.AudioServiceRepeatMode.one,
            LoopMode.all: audio_service.AudioServiceRepeatMode.all,
          }[loop] ??
          audio_service.AudioServiceRepeatMode.none;
      _playbackStateSubject.add(
        _playbackStateSubject.value.copyWith(repeatMode: rm),
      );
    });
    player.processingStateStream.listen((state) {
      final ps = const {
            ProcessingState.idle: audio_service.AudioProcessingState.idle,
            ProcessingState.loading: audio_service.AudioProcessingState.loading,
            ProcessingState.buffering:
                audio_service.AudioProcessingState.buffering,
            ProcessingState.ready: audio_service.AudioProcessingState.ready,
            ProcessingState.completed:
                audio_service.AudioProcessingState.completed,
          }[state] ??
          audio_service.AudioProcessingState.idle;
      _playbackStateSubject.add(
        _playbackStateSubject.value.copyWith(processingState: ps),
      );
    });
    player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < currentQueue.length) {
        final song = currentQueue[index];
        _mediaItemSubject.add(
          audio_service.MediaItem(
            id: song.id,
            album: song.album,
            title: song.title,
            artist: song.artist,
            duration: Duration(seconds: song.duration),
          ),
        );
      }
    });
  }

  @override
  Future<void> play() async => player.play();

  @override
  Future<void> pause() async => player.pause();

  @override
  Future<void> seek(Duration position) async => player.seek(position);

  @override
  Future<void> setQueue(
    List<Song> songs,
    int startIndex, {
    List<Song>? unshuffledSongs,
  }) async {
    currentQueue = List.from(songs);
    await player.seek(Duration.zero, index: startIndex);
  }

  @override
  Future<void> dispose() async {
    player.dispose();
    await _mediaItemSubject.close();
    await _playbackStateSubject.close();
  }
}

class FakeSessionSyncService implements SessionSyncService {
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _reconnectController = StreamController<int>.broadcast();

  final List<Map<String, dynamic>> pushedUpdates = [];
  final List<String> transferredDevices = [];

  PlaybackState _current = const PlaybackState.initial();

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<int> get reconnectAttemptStream => _reconnectController.stream;

  @override
  PlaybackState get currentState => _current;

  void emitSyncState(PlaybackState state) {
    _current = state;
    _stateController.add(state);
  }

  @override
  void pushStateUpdate({
    String? trackId,
    int? positionMs,
    bool? isPlaying,
    List<String>? queue,
  }) {
    pushedUpdates.add({
      'track_id': trackId,
      'position_ms': positionMs,
      'is_playing': isPlaying,
      'queue': queue,
    });
  }

  @override
  void transferPlayback(String deviceId) {
    transferredDevices.add(deviceId);
  }

  @override
  Future<void> connect() async {}

  @override
  void disconnect() {}

  @override
  void dispose() {
    _stateController.close();
    _reconnectController.close();
  }

  @override
  String? get deviceId => 'mock-device-id';

  @override
  Future<PlaybackState> fetchCurrentState() async => _current;

  @override
  bool get isConnected => true;

  @override
  int get reconnectAttempt => 0;
}

Song _createSong(String id, String title) => Song(
      id: id,
      title: title,
      artist: 'Artist $id',
      album: 'Album $id',
      genre: 'Pop',
      composer: 'Composer $id',
      coverArt: '',
      duration: 240,
      track: 1,
      year: 2024,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ControlledNaviAudioHandler audioHandler;
  late MockSubsonicService mockSubsonicService;
  late MockListeningEventCollector mockCollector;
  late FakeSessionSyncService fakeSyncService;

  setUp(() {
    audioHandler = ControlledNaviAudioHandler();
    mockSubsonicService = MockSubsonicService();
    mockCollector = MockListeningEventCollector();
    fakeSyncService = FakeSessionSyncService();
  });

  tearDown(() async {
    fakeSyncService.dispose();
    await audioHandler.dispose();
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        sessionSyncServiceProvider.overrideWithValue(fakeSyncService),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('PlayerNotifier SessionSync Integration', () {
    test('Initializes with SyncMode.idle and reacts to syncUnknown', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);
      expect(notifier.state.syncMode, SyncMode.idle);

      // Emit syncUnknown
      fakeSyncService.emitSyncState(
        const PlaybackState.initial().copyWith(syncUnknown: true),
      );
      await Future.delayed(Duration.zero);

      expect(notifier.state.syncMode, SyncMode.standalone);

      notifier.dispose();
    });

    test('Switches to activeHere when activeDevice == myDeviceId', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      fakeSyncService.emitSyncState(
        const PlaybackState(
          activeDevice: 'device-me',
          activeDeviceName: 'My Laptop',
          trackId: 'song-1',
          isPlaying: true,
          positionMs: 4000,
        ),
      );
      await Future.delayed(Duration.zero);

      expect(notifier.state.syncMode, SyncMode.activeHere);
      notifier.dispose();
    });

    test('Switches to passive and stops local engine when activeDevice != myDeviceId', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      // Start local playback
      await audioHandler.play();
      notifier.state = notifier.state.copyWith(isPlaying: true);
      expect(audioHandler.player.playing, isTrue);

      // Another device takes active playback
      final remoteUpdate = DateTime.parse('2026-08-22T08:00:00.000Z');
      fakeSyncService.emitSyncState(
        PlaybackState(
          activeDevice: 'device-other',
          activeDeviceName: 'Living Room TV',
          trackId: 'remote-song-42',
          trackTitle: 'Blinding Lights',
          artist: 'The Weeknd',
          positionMs: 65000,
          isPlaying: true,
          updatedAt: remoteUpdate,
        ),
      );
      await Future.delayed(Duration.zero);

      expect(notifier.state.syncMode, SyncMode.passive);
      expect(notifier.state.remoteTrackId, 'remote-song-42');
      expect(notifier.state.remoteTrackTitle, 'Blinding Lights');
      expect(notifier.state.remoteArtist, 'The Weeknd');
      expect(notifier.state.remotePositionMs, 65000);
      expect(notifier.state.remoteIsPlaying, isTrue);
      expect(notifier.state.remoteActiveDeviceName, 'Living Room TV');
      expect(notifier.state.remoteUpdatedAt, remoteUpdate);

      // Confirms local engine was paused
      expect(audioHandler.player.playing, isFalse);

      notifier.dispose();
    });

    test('play() performs implicit activation, starts engine, sets activeHere, and pushes state', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      final song = _createSong('song-10', 'Starboy');
      notifier.state = notifier.state.copyWith(
        queue: [song],
        currentIndex: 0,
        syncMode: SyncMode.idle,
      );

      await notifier.play();

      expect(fakeSyncService.transferredDevices, contains('device-me'));
      expect(notifier.state.syncMode, SyncMode.activeHere);
      expect(notifier.state.isPlaying, isTrue);
      expect(audioHandler.player.playing, isTrue);

      expect(fakeSyncService.pushedUpdates, isNotEmpty);
      final update = fakeSyncService.pushedUpdates.first;
      expect(update['track_id'], 'song-10');
      expect(update['is_playing'], isTrue);

      notifier.dispose();
    });

    test('pause() pushes isPlaying: false', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      notifier.state = notifier.state.copyWith(
        isPlaying: true,
        syncMode: SyncMode.activeHere,
      );

      await notifier.pause();

      expect(notifier.state.isPlaying, isFalse);
      expect(audioHandler.player.playing, isFalse);

      expect(fakeSyncService.pushedUpdates, isNotEmpty);
      final lastUpdate = fakeSyncService.pushedUpdates.last;
      expect(lastUpdate['is_playing'], isFalse);

      notifier.dispose();
    });

    test('seek() pushes position_ms', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);
      notifier.state = notifier.state.copyWith(syncMode: SyncMode.activeHere);

      await notifier.seek(const Duration(seconds: 45));

      expect(audioHandler.player.position, const Duration(seconds: 45));
      final lastUpdate = fakeSyncService.pushedUpdates.last;
      expect(lastUpdate['position_ms'], 45000);

      notifier.dispose();
    });

    test('passive device does not push state updates', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      notifier.state = notifier.state.copyWith(syncMode: SyncMode.passive);

      // Attempt to push update while passive
      await notifier.seek(const Duration(seconds: 10));

      expect(fakeSyncService.pushedUpdates, isEmpty);

      notifier.dispose();
    });

    test('togglePlay() delegates to play() when paused and pause() when playing', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      final song = _createSong('song-toggle', 'Save Your Tears');
      notifier.state = notifier.state.copyWith(
        queue: [song],
        currentIndex: 0,
        isPlaying: false,
        syncMode: SyncMode.idle,
      );

      // 1. togglePlay when paused -> plays
      await notifier.togglePlay();
      expect(notifier.state.isPlaying, isTrue);
      expect(fakeSyncService.transferredDevices, contains('device-me'));

      // 2. togglePlay when playing -> pauses
      await notifier.togglePlay();
      expect(notifier.state.isPlaying, isFalse);

      notifier.dispose();
    });

    test('setQueue() transfers playback, sets activeHere, and pushes queue update', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      final s1 = _createSong('s1', 'Track 1');
      final s2 = _createSong('s2', 'Track 2');

      await notifier.setQueue([s1, s2], 0);

      expect(fakeSyncService.transferredDevices, contains('device-me'));
      expect(notifier.state.syncMode, SyncMode.activeHere);
      expect(notifier.state.queue.length, 2);

      final push = fakeSyncService.pushedUpdates.firstWhere(
        (u) => u['track_id'] == 's1',
      );
      expect(push['queue'], ['s1', 's2']);
      expect(push['is_playing'], isTrue);

      notifier.dispose();
    });

    test('Switches to SyncMode.idle when activeDevice is null', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      // First set activeHere
      fakeSyncService.emitSyncState(
        const PlaybackState(
          activeDevice: 'device-me',
          isPlaying: true,
        ),
      );
      await Future.delayed(Duration.zero);
      expect(notifier.state.syncMode, SyncMode.activeHere);

      // Then activeDevice becomes null
      fakeSyncService.emitSyncState(
        const PlaybackState(
          activeDevice: null,
          isPlaying: false,
        ),
      );
      await Future.delayed(Duration.zero);
      expect(notifier.state.syncMode, SyncMode.idle);

      notifier.dispose();
    });

    test('claimActiveDevice() transfers playback without starting local engine immediately', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      // Start in passive mode
      fakeSyncService.emitSyncState(
        PlaybackState(
          activeDevice: 'device-other',
          activeDeviceName: 'iPad',
          trackId: 'remote-1',
          positionMs: 30000,
          isPlaying: true,
        ),
      );
      await Future.delayed(Duration.zero);
      expect(notifier.state.syncMode, SyncMode.passive);

      // Call claimActiveDevice
      await notifier.claimActiveDevice();

      // Confirms transfer request was sent
      expect(fakeSyncService.transferredDevices, contains('device-me'));
      // Confirms engine has NOT started playing yet (waiting for confirmation broadcast)
      expect(audioHandler.player.playing, isFalse);

      notifier.dispose();
    });

    test('Confirming broadcast resumes playback at interpolated remote position', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);

      // 1. Enter passive mode tracking remote song
      final s = _createSong('song-remote-99', 'Remote Hit');
      notifier.state = notifier.state.copyWith(queue: [s], currentIndex: 0);

      final remoteTimestamp = DateTime.now().subtract(const Duration(seconds: 2));
      fakeSyncService.emitSyncState(
        PlaybackState(
          activeDevice: 'device-other',
          activeDeviceName: 'MacBook',
          trackId: 'song-remote-99',
          positionMs: 50000,
          isPlaying: true,
          updatedAt: remoteTimestamp,
        ),
      );
      await Future.delayed(Duration.zero);
      expect(notifier.state.syncMode, SyncMode.passive);

      // 2. User tapped Play Here -> claimActiveDevice called
      await notifier.claimActiveDevice();

      // 3. Server sends confirming broadcast with activeDevice == 'device-me'
      fakeSyncService.emitSyncState(
        PlaybackState(
          activeDevice: 'device-me',
          activeDeviceName: 'My Laptop',
          trackId: 'song-remote-99',
          positionMs: 50000,
          isPlaying: true,
          updatedAt: remoteTimestamp,
        ),
      );
      await Future.delayed(Duration.zero);

      // 4. Verification: activeHere, playing, position interpolated (~52000 ms)
      expect(notifier.state.syncMode, SyncMode.activeHere);
      expect(audioHandler.player.playing, isTrue);
      expect(audioHandler.player.position.inMilliseconds, greaterThanOrEqualTo(51500));

      notifier.dispose();
    });

    test('claimActiveDevice() ignored when not in passive mode', () async {
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));

      final notifier = PlayerNotifier(
        ref,
        audioHandler,
        mockSubsonicService,
        mockCollector,
        deviceIdProvider: () async => 'device-me',
      );

      await Future.delayed(Duration.zero);
      expect(notifier.state.syncMode, SyncMode.idle);

      // Calling claimActiveDevice when idle should do nothing
      await notifier.claimActiveDevice();
      expect(fakeSyncService.transferredDevices, isEmpty);

      notifier.dispose();
    });
  });
}
