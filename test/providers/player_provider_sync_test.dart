import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:rxdart/rxdart.dart';

import 'package:drift/native.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/play_route.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/remote_queue_provider.dart';
import 'package:navivibe/providers/session_sync_provider.dart';
import 'package:navivibe/providers/settings_provider.dart' show appDatabaseProvider;
import 'package:navivibe/services/session_sync_service.dart';
import 'package:navivibe/utils/user_activity.dart';
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
  final List<bool> forcedClaims = [];

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
    String? trackTitle,
    String? artist,
    String? album,
    String? coverArtId,
    double? durationS,
    int? queueIndex,
    bool? queueLocked,
  }) {
    pushedUpdates.add({
      'track_id': trackId,
      'position_ms': positionMs,
      'is_playing': isPlaying,
      'queue': queue,
      'track_title': trackTitle,
      'queue_index': queueIndex,
      'queue_locked': queueLocked,
    });
  }

  final queueEdits = <(QueueEditType, Map<String, dynamic>)>[];

  @override
  String? sendQueueEdit(QueueEditType type, Map<String, dynamic> args) {
    queueEdits.add((type, args));
    return 'cmd-${queueEdits.length}';
  }

  @override
  void transferPlayback(String deviceId, {String? deviceName, bool force = false}) {
    transferredDevices.add(deviceId);
    forcedClaims.add(force);
  }

  final _commandController = StreamController<RemoteCommand>.broadcast();
  final sentCommands = <String>[];

  void emitCommand(RemoteCommand c) => _commandController.add(c);

  @override
  Stream<RemoteCommand> get commandStream => _commandController.stream;

  @override
  String? sendCommand(String action, {int? positionMs, double? volume, String? trackId, int? index, List<String>? queue, String? target}) {
    if (!linkUp) return null;
    sentCommands.add(action);
    if (action == 'set_queue') queuesSent.add((queue ?? const [], index));
    return 'cmd-${sentCommands.length}';
  }

  final playOns = <(String, List<String>, int)>[];
  final queuesSent = <(List<String>, int?)>[];

  /// False: the session link is down, nothing can be sent.
  bool linkUp = true;

  @override
  String? playOn(String deviceId, List<String> queue, int index, {Map<String, dynamic> meta = const {}}) {
    if (!linkUp) return null;
    playOns.add((deviceId, queue, index));
    return 'play-${playOns.length}';
  }

  final _prepareController = StreamController<PrepareTransfer>.broadcast();
  final readySent = <String>[];

  void emitPrepare(PrepareTransfer p) => _prepareController.add(p);

  @override
  Stream<PrepareTransfer> get prepareStream => _prepareController.stream;

  @override
  void sendReady(String transferId) => readySent.add(transferId);

  @override
  final ClockEstimator clock = ClockEstimator();

  @override
  int serverNowMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  bool get serverSpeaksV3 => true;

  @override
  void resetAccount() {}

  @override
  void releasePlayback() {}

  @override
  void requestDevices() {}

  @override
  String? get deviceName => 'Test phone';

  @override
  List<SyncDevice> get currentDevices => const [];

  @override
  Stream<List<SyncDevice>> get devicesStream => const Stream.empty();

  final _resultController = StreamController<CommandResult>.broadcast(sync: true);
  void emitResult(CommandResult r) => _resultController.add(r);

  @override
  Stream<CommandResult> get resultStream => _resultController.stream;

  @override
  SyncConnection get connection => SyncConnection.online;

  @override
  Stream<SyncConnection> get connectionStream => const Stream.empty();

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
        // The library copy the player looks songs up in before the server.
        appDatabaseProvider.overrideWithValue(AppDatabase.forTesting(NativeDatabase.memory())),
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

  group('PlayerNotifier remote control', () {
    Future<PlayerNotifier> make({String active = 'device-me'}) async {
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
      fakeSyncService.emitSyncState(PlaybackState(activeDevice: active, activeDeviceName: 'Somewhere', trackId: 't1', isPlaying: true));
      await Future.delayed(Duration.zero);
      return notifier;
    }

    test('the active device obeys a pause command', () async {
      final notifier = await make();
      expect(notifier.state.syncMode, SyncMode.activeHere);
      notifier.state = notifier.state.copyWith(isPlaying: true);
      fakeSyncService.emitCommand(const RemoteCommand(action: 'pause', fromName: 'iPad'));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(notifier.state.isPlaying, isFalse);
      notifier.dispose();
    });

    test('a passive device ignores commands meant for the active one', () async {
      final notifier = await make(active: 'device-other');
      expect(notifier.state.syncMode, SyncMode.passive);
      fakeSyncService.emitCommand(const RemoteCommand(action: 'play'));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(audioHandler.player.playing, isFalse);
      expect(notifier.state.syncMode, SyncMode.passive);
      notifier.dispose();
    });

    test('remoteControl() sends the command to the server instead of playing here', () async {
      final notifier = await make(active: 'device-other');
      notifier.remoteControl('next');
      notifier.remoteControl('seek', positionMs: 5000);
      expect(fakeSyncService.sentCommands, ['next', 'seek']);
      expect(audioHandler.player.playing, isFalse);
      notifier.dispose();
    });

    test('transferTo() this device claims playback with its own name', () async {
      final notifier = await make(active: 'device-other');
      await notifier.transferTo('device-me');
      expect(fakeSyncService.transferredDevices, ['device-me']);
      notifier.dispose();
    });

    test('transferTo() another device hands playback over', () async {
      final notifier = await make();
      await notifier.transferTo('device-tv');
      expect(fakeSyncService.transferredDevices, ['device-tv']);
      notifier.dispose();
    });

    test('a passive device never takes playback on its own (no touch behind it)', () async {
      UserActivity.debugSet(null);
      final notifier = await make(active: 'device-other');
      await notifier.play();
      await notifier.setQueue([
        Song(id: 's1', title: 'T', artist: 'A', album: 'B', coverArt: '', duration: 100, track: 1, year: 2020),
      ], 0);
      expect(fakeSyncService.transferredDevices, isEmpty);
      expect(audioHandler.player.playing, isFalse);
      expect(notifier.state.syncMode, SyncMode.passive);
      notifier.dispose();
    });

    test('a touch makes the claim legitimate, and it is forced so the server honours it', () async {
      final notifier = await make(active: 'device-other');
      UserActivity.debugSet(DateTime.now());
      await notifier.play();
      expect(fakeSyncService.transferredDevices, ['device-me']);
      expect(fakeSyncService.forcedClaims, [true]);
      UserActivity.debugSet(null);
      notifier.dispose();
    });

    test('code that runs by itself can take playback only inside a window it opens (Jam)', () async {
      UserActivity.debugSet(null);
      final notifier = await make(active: 'device-other');
      notifier.permitClaim();
      await notifier.play();
      expect(fakeSyncService.transferredDevices, ['device-me']);
      notifier.dispose();
    });

    test('with nobody playing anywhere a device may start, and the claim is not forced', () async {
      UserActivity.debugSet(null);
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));
      final notifier = PlayerNotifier(ref, audioHandler, mockSubsonicService, mockCollector, deviceIdProvider: () async => 'device-me');
      await Future.delayed(Duration.zero);
      expect(notifier.state.syncMode, SyncMode.idle);
      await notifier.play();
      expect(fakeSyncService.transferredDevices, ['device-me']);
      expect(fakeSyncService.forcedClaims, [false]);
      notifier.dispose();
    });

    test('becoming the host through a transfer does not claim a second time', () async {
      final notifier = await make(active: 'device-other');
      UserActivity.debugSet(DateTime.now());
      await notifier.claimActiveDevice();
      expect(fakeSyncService.transferredDevices, ['device-me']);
      fakeSyncService.emitSyncState(PlaybackState(activeDevice: 'device-me', trackId: 't1', isPlaying: true, queue: const ['t1', 't2']));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(notifier.state.syncMode, SyncMode.activeHere);
      expect(fakeSyncService.transferredDevices, ['device-me']);
      UserActivity.debugSet(null);
      notifier.dispose();
    });

    test('ECHO: applying the host state never makes this device say or claim anything', () async {
      UserActivity.debugSet(null);
      final notifier = await make(active: 'device-other');
      fakeSyncService.pushedUpdates.clear();
      for (var i = 0; i < 5; i++) {
        fakeSyncService.emitSyncState(PlaybackState(
          activeDevice: 'device-other',
          activeDeviceName: 'Windows PC',
          trackId: 't$i',
          positionMs: i * 1000,
          isPlaying: i.isEven,
          queue: const ['t0', 't1'],
          epoch: 3,
          version: i,
        ));
        await Future.delayed(Duration.zero);
      }
      expect(fakeSyncService.pushedUpdates, isEmpty);
      expect(fakeSyncService.transferredDevices, isEmpty);
      expect(fakeSyncService.sentCommands, isEmpty);
      expect(fakeSyncService.readySent, isEmpty);
      expect(audioHandler.player.playing, isFalse);
      notifier.dispose();
    });

    test('a handover order loads the song paused at the host position, then says ready (the host plays on)', () async {
      final songs = [
        Song(id: 't1', title: 'One', artist: 'A', album: 'B', coverArt: '', duration: 200, track: 1, year: 2020),
        Song(id: 't2', title: 'Two', artist: 'A', album: 'B', coverArt: '', duration: 200, track: 2, year: 2020),
      ];
      when(() => mockSubsonicService.getSongs(any())).thenAnswer((_) async => songs);
      final notifier = await make(active: 'device-other');
      fakeSyncService.emitPrepare(const PrepareTransfer(transferId: 'x1', epoch: 2, trackId: 't2', positionMs: 61000, queue: ['t1', 't2'], queueIndex: 1));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(fakeSyncService.readySent, ['x1']);
      // The song that is playing and what follows; songs before it are history.
      expect(notifier.state.queue.map((s) => s.id), ['t2']);
      expect(notifier.state.currentIndex, 0);
      expect(audioHandler.player.playing, isFalse);          // not yet the host: silent
      expect(notifier.state.syncMode, SyncMode.passive);
      expect(fakeSyncService.transferredDevices, isEmpty);
      notifier.dispose();
    });

    test('a handover says ready after the first few songs, then adds the rest of the queue', () async {
      final ids = [for (var i = 0; i < 25; i++) 'q$i'];
      final asked = <int>[];
      when(() => mockSubsonicService.getSongs(any())).thenAnswer((inv) async {
        final want = inv.positionalArguments.first as List<String>;
        asked.add(want.length);
        return [for (final id in want) Song(id: id, title: id, artist: 'A', album: 'B', coverArt: '', duration: 200, track: 1, year: 2020)];
      });
      final notifier = await make(active: 'device-other');
      fakeSyncService.emitPrepare(PrepareTransfer(transferId: 'x3', epoch: 2, trackId: 'q5', positionMs: 1000, queue: ids, queueIndex: 5));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(fakeSyncService.readySent, ['x3']);
      expect(asked.first, lessThanOrEqualTo(10), reason: 'only the first window is looked up before ready');
      await Future.delayed(const Duration(milliseconds: 150));
      expect(asked.every((n) => n <= 40), isTrue, reason: 'the rest comes in small batches, not all at once');
      notifier.dispose();
    });

    test('a handover that cannot be prepared stays silent, so the server rolls it back', () async {
      when(() => mockSubsonicService.getSongs(any())).thenAnswer((_) async => <Song>[]);
      final notifier = await make(active: 'device-other');
      fakeSyncService.emitPrepare(const PrepareTransfer(transferId: 'x2', epoch: 2, trackId: 'gone', queue: ['gone']));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(fakeSyncService.readySent, isEmpty);
      notifier.dispose();
    });

    test('after a restart the server still names this device host and playing: it picks up where it was', () async {
      UserActivity.debugSet(null);
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));
      final notifier = PlayerNotifier(ref, audioHandler, mockSubsonicService, mockCollector, deviceIdProvider: () async => 'device-me');
      await Future.delayed(Duration.zero);
      expect(notifier.state.syncMode, SyncMode.idle);
      fakeSyncService.emitSyncState(PlaybackState(
        activeDevice: 'device-me',
        trackId: 'tr',
        trackTitle: 'Song',
        positionMs: 10000,
        isPlaying: true,
        updatedAt: DateTime.now(),
        queue: const ['tr'],
      ));
      await Future.delayed(const Duration(milliseconds: 80));
      expect(notifier.state.syncMode, SyncMode.activeHere);
      expect(audioHandler.player.playing, isTrue);
      notifier.dispose();
    });

    test('a host whose link dropped while it kept playing takes its seat back on reconnect', () async {
      UserActivity.debugSet(null);
      final notifier = await make();
      notifier.state = notifier.state.copyWith(isPlaying: true);
      fakeSyncService.emitSyncState(const PlaybackState.initial().copyWith(syncUnknown: true)); // the socket dropped
      await Future.delayed(Duration.zero);
      expect(notifier.state.syncMode, SyncMode.standalone);
      fakeSyncService.transferredDevices.clear();
      fakeSyncService.emitSyncState(const PlaybackState.initial());              // the server let go of it meanwhile
      await Future.delayed(const Duration(milliseconds: 30));
      expect(fakeSyncService.transferredDevices, ['device-me']);
      expect(fakeSyncService.forcedClaims.last, isFalse);                        // nobody's seat was taken
      expect(fakeSyncService.pushedUpdates.last['is_playing'], isTrue);
      notifier.dispose();
    });

    test('a device that was NOT the host does not claim after an outage', () async {
      UserActivity.debugSet(null);
      final notifier = await make(active: 'device-other');
      fakeSyncService.emitSyncState(const PlaybackState.initial().copyWith(syncUnknown: true));
      await Future.delayed(Duration.zero);
      fakeSyncService.emitSyncState(const PlaybackState.initial());
      await Future.delayed(const Duration(milliseconds: 30));
      expect(fakeSyncService.transferredDevices, isEmpty);
      notifier.dispose();
    });

    test('updates carry the song details other devices show', () async {
      final notifier = await make();
      fakeSyncService.pushedUpdates.clear();
      await notifier.setQueue([
        Song(id: 's1', title: 'Hello', artist: 'Adele', album: '25', coverArt: 'c1', duration: 295, track: 1, year: 2015),
      ], 0);
      final withTitle = fakeSyncService.pushedUpdates.where((u) => u['track_title'] == 'Hello');
      expect(withTitle, isNotEmpty);
      notifier.dispose();
    });
  });

  // ── Protocol 4: the host applies queue edits other devices sent ────────────
  group('a play started by a person goes where music plays', () {
    List<Song> songs([int n = 3]) => [for (var i = 0; i < n; i++) _createSong('s$i', 'Song $i')];

    Future<(PlayerNotifier, ProviderContainer)> make({String? active = 'device-pc'}) async {
      UserActivity.debugSet(DateTime.now()); // a tap started it
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));
      final notifier = PlayerNotifier(ref, audioHandler, mockSubsonicService, mockCollector, deviceIdProvider: () async => 'device-me');
      await Future.delayed(Duration.zero);
      fakeSyncService.emitSyncState(PlaybackState(
          activeDevice: active, activeDeviceName: 'Windows PC', trackId: 't1', isPlaying: true, queue: const ['t1', 't2'], epoch: 1, version: 1));
      await Future.delayed(Duration.zero);
      addTearDown(() => UserActivity.debugSet(null));
      return (notifier, container);
    }

    test('a tap while another device plays sends the queue there and plays nothing here', () async {
      final (notifier, container) = await make();
      await notifier.setQueue(songs(), 1, playlistName: 'Mix');
      expect(fakeSyncService.queuesSent.single.$1, ['s0', 's1', 's2']);
      expect(fakeSyncService.queuesSent.single.$2, 1);
      expect(fakeSyncService.transferredDevices, isEmpty); // nobody was taken from
      expect(audioHandler.player.playing, isFalse);
      expect(notifier.state.queue, isEmpty); // this device's own queue is untouched
      expect(notifier.state.syncMode, SyncMode.passive);
      final notice = container.read(playNoticeProvider);
      expect(notice.message, 'Playing on Windows PC');
      expect(notice.canPlayHere, isTrue);
      // The remote queue view shows the new queue at once.
      expect([for (final s in container.read(remoteQueueProvider).songs) s.id], ['s0', 's1', 's2']);
      notifier.dispose();
    });

    test('Play on a list does the same, shuffled or not', () async {
      final (notifier, _) = await make();
      await notifier.playPlaylist(songs(), playlistName: 'Album');
      expect(fakeSyncService.queuesSent.last.$1, ['s0', 's1', 's2']);
      expect(fakeSyncService.queuesSent.last.$2, 0);
      await notifier.playPlaylist(songs(5), shuffle: true);
      expect(fakeSyncService.queuesSent.last.$1.toSet(), {'s0', 's1', 's2', 's3', 's4'});
      expect(fakeSyncService.queuesSent.length, 2);
      expect(audioHandler.player.playing, isFalse);
      notifier.dispose();
    });

    test('"Play here instead" starts the same songs on this device and takes playback', () async {
      final (notifier, container) = await make();
      await notifier.setQueue(songs(), 2);
      await notifier.playHereInstead();
      expect(fakeSyncService.transferredDevices, ['device-me']);
      expect(fakeSyncService.forcedClaims, [true]); // a person's choice: it wins
      expect(notifier.state.queue.map((s) => s.id), ['s0', 's1', 's2']);
      expect(notifier.state.currentIndex, 2);
      expect(audioHandler.player.playing, isTrue);
      expect(container.read(playTargetProvider), isNull);
      notifier.dispose();
    });

    test('a play with no touch behind it (restore, autoplay) is never routed', () async {
      final (notifier, _) = await make();
      UserActivity.debugSet(null);
      await notifier.setQueue(songs(), 0);
      expect(fakeSyncService.queuesSent, isEmpty);
      expect(fakeSyncService.transferredDevices, isEmpty); // and it does not steal either
      notifier.dispose();
    });

    test('a Jam (it opens a claim window) plays here even though another device plays', () async {
      final (notifier, _) = await make();
      notifier.permitClaim();
      await notifier.setQueue(songs(), 0);
      expect(fakeSyncService.queuesSent, isEmpty);
      expect(fakeSyncService.transferredDevices, ['device-me']);
      notifier.dispose();
    });

    test('a device picked in the sheet gets the queue, even when it is not the one playing', () async {
      final (notifier, container) = await make();
      container.read(playTargetProvider.notifier).choose('device-tv');
      await notifier.setQueue(songs(), 1);
      expect(fakeSyncService.playOns.single.$1, 'device-tv');
      expect(fakeSyncService.playOns.single.$2, ['s0', 's1', 's2']);
      expect(fakeSyncService.playOns.single.$3, 1);
      expect(fakeSyncService.queuesSent, isEmpty);
      expect(audioHandler.player.playing, isFalse);
      expect(container.read(playNoticeProvider).message, startsWith('Playing on'));
      notifier.dispose();
    });

    test('this device picked in the sheet plays here and takes playback', () async {
      final (notifier, container) = await make();
      container.read(playTargetProvider.notifier).choose('device-me');
      await notifier.setQueue(songs(), 0);
      expect(fakeSyncService.queuesSent, isEmpty);
      expect(fakeSyncService.transferredDevices, ['device-me']);
      expect(audioHandler.player.playing, isTrue);
      notifier.dispose();
    });

    test('a pick lasts only until playback changes hands', () async {
      final (notifier, container) = await make();
      container.read(playTargetProvider.notifier).choose('device-tv');
      fakeSyncService.emitSyncState(const PlaybackState(activeDevice: 'device-tv', activeDeviceName: 'TV', epoch: 2, version: 2));
      await Future.delayed(Duration.zero);
      expect(container.read(playTargetProvider), isNull);
      notifier.dispose();
    });

    test('with no link nothing is sent, nothing plays here, and the person is told', () async {
      final (notifier, container) = await make();
      fakeSyncService.linkUp = false;
      await notifier.setQueue(songs(), 0);
      expect(fakeSyncService.queuesSent, isEmpty);
      expect(audioHandler.player.playing, isFalse);
      expect(container.read(playNoticeProvider).message, contains('Can’t reach'));
      expect(container.read(playNoticeProvider).canPlayHere, isFalse);
      notifier.dispose();
    });

    test('when nobody plays anywhere a tap simply plays here', () async {
      final (notifier, _) = await make(active: null);
      await notifier.setQueue(songs(), 0);
      expect(fakeSyncService.queuesSent, isEmpty);
      expect(fakeSyncService.transferredDevices, ['device-me']);
      expect(audioHandler.player.playing, isTrue);
      notifier.dispose();
    });

    test('a refusal from the other device is said in words (offline, no answer)', () async {
      final (notifier, container) = await make();
      fakeSyncService.emitResult(const CommandResult(ok: false, action: 'playOn', reason: 'device_offline'));
      expect(container.read(playNoticeProvider).message, 'That device went offline.');
      fakeSyncService.emitResult(const CommandResult(ok: false, action: 'transfer', reason: 'timeout'));
      expect(container.read(playNoticeProvider).message, contains('didn’t answer'));
      // Queue edits are explained by the remote queue, not twice.
      final seq = container.read(playNoticeProvider).seq;
      fakeSyncService.emitResult(const CommandResult(ok: false, action: 'queue_remove', reason: 'queue_changed'));
      fakeSyncService.emitResult(const CommandResult(ok: true, action: 'playOn'));
      expect(container.read(playNoticeProvider).seq, seq);
      notifier.dispose();
    });
  });

  group('host applies remote queue edits', () {
    late QueueKeepingHandler handler;
    final songs = [for (final id in ['a', 'b', 'c', 'd', 'e']) _createSong(id, 'Song $id')];

    setUpAll(() => registerFallbackValue(<String>[]));

    Future<PlayerNotifier> host({int index = 1}) async {
      handler = QueueKeepingHandler();
      final container = createContainer();
      final ref = container.read(Provider((ref) => ref));
      final notifier = PlayerNotifier(ref, handler, mockSubsonicService, mockCollector,
          deviceIdProvider: () async => 'device-me');
      await Future.delayed(Duration.zero);
      fakeSyncService.emitSyncState(const PlaybackState(activeDevice: 'device-me', trackId: 'b', isPlaying: true));
      await Future.delayed(Duration.zero);
      handler.currentQueue = [...songs];
      notifier.state = notifier.state.copyWith(queue: [...songs], currentIndex: index);
      await Future.delayed(Duration.zero);
      fakeSyncService.pushedUpdates.clear();
      addTearDown(() async {
        notifier.dispose();
        await handler.dispose();
      });
      return notifier;
    }

    List<String> ids(List<Song> q) => [for (final s in q) s.id];

    Future<void> send(RemoteCommand c) async {
      fakeSyncService.emitCommand(c);
      await Future.delayed(const Duration(milliseconds: 20));
    }

    /// The player's queue, the audio handler's and what the other devices were told all agree.
    void expectInSync(PlayerNotifier n, List<String> want, int index) {
      expect(ids(n.state.queue), want);
      expect(ids(handler.currentQueue), want);
      expect(n.state.currentIndex, index);
      expect(fakeSyncService.pushedUpdates.last['queue'], want);
    }

    test('insert: songs land at the index the server resolved, fetched once', () async {
      when(() => mockSubsonicService.getSongs(any())).thenAnswer((i) async =>
          [for (final id in i.positionalArguments.first as List<String>) _createSong(id, 'New $id')]);
      final n = await host();
      await send(const RemoteCommand(action: 'queue_insert', trackIds: ['x', 'y'], index: 2));
      expectInSync(n, ['a', 'b', 'x', 'y', 'c', 'd', 'e'], 1);
      expect(n.state.queue[2].title, 'New x');
      // A song already in the queue needs no lookup.
      await send(const RemoteCommand(action: 'queue_insert', trackIds: ['e'], index: 0));
      expectInSync(n, ['e', 'a', 'b', 'x', 'y', 'c', 'd', 'e'], 2);
      verify(() => mockSubsonicService.getSongs(any())).called(1);
    });

    test('remove: by index, checked against the song id', () async {
      final n = await host();
      await send(const RemoteCommand(action: 'queue_remove', index: 3, trackId: 'd'));
      expectInSync(n, ['a', 'b', 'c', 'e'], 1);
      // The queue moved under the edit: the id finds the song.
      await send(const RemoteCommand(action: 'queue_remove', index: 0, trackId: 'e'));
      expectInSync(n, ['a', 'b', 'c'], 1);
      await send(const RemoteCommand(action: 'queue_remove', index: 0, trackId: 'a'));
      expectInSync(n, ['b', 'c'], 0);
    });

    test('remove of a song that is gone, or the one playing, changes nothing and reports the truth', () async {
      final n = await host();
      await send(const RemoteCommand(action: 'queue_remove', index: 2, trackId: 'zzz'));
      expectInSync(n, ['a', 'b', 'c', 'd', 'e'], 1);
      await send(const RemoteCommand(action: 'queue_remove', index: 1, trackId: 'b'));
      expectInSync(n, ['a', 'b', 'c', 'd', 'e'], 1);
    });

    test('move: reorders the player and the handler, the playing song keeps playing', () async {
      final n = await host();
      await send(const RemoteCommand(action: 'queue_move', from: 4, to: 2, trackId: 'e'));
      expectInSync(n, ['a', 'b', 'e', 'c', 'd'], 1);
      await send(const RemoteCommand(action: 'queue_move', from: 0, to: 3, trackId: 'a'));
      expectInSync(n, ['b', 'e', 'c', 'a', 'd'], 0);
      await send(const RemoteCommand(action: 'queue_move', from: 0, to: 2, trackId: 'b'));   // the playing song itself
      expectInSync(n, ['e', 'c', 'b', 'a', 'd'], 2);
    });

    test('clear upcoming: everything after the playing song goes, History stays', () async {
      final n = await host(index: 2);
      await send(const RemoteCommand(action: 'queue_clear_upcoming', index: 2, trackId: 'c'));
      expectInSync(n, ['a', 'b', 'c'], 2);
      expect(handler.removed, [4, 3]);                    // from the end: the playing song never moves
    });

    test('a queue that follows a Jam takes no edits from other devices, and says so', () async {
      final n = await host();
      n.setQueueFollowsJam(true);
      expect(fakeSyncService.pushedUpdates.last['queue_locked'], isTrue);
      await send(const RemoteCommand(action: 'queue_remove', index: 3, trackId: 'd'));
      expectInSync(n, ['a', 'b', 'c', 'd', 'e'], 1);
      n.setQueueFollowsJam(false);
      expect(fakeSyncService.pushedUpdates.last['queue_locked'], isFalse);
      await send(const RemoteCommand(action: 'queue_remove', index: 3, trackId: 'd'));
      expectInSync(n, ['a', 'b', 'c', 'e'], 1);
    });

    test("the host's own edits are mirrored to the other devices", () async {
      final n = await host();
      await n.removeFromQueue(4);
      await Future.delayed(Duration.zero);
      expectInSync(n, ['a', 'b', 'c', 'd'], 1);
      await n.clearUpcoming();
      await Future.delayed(Duration.zero);
      expectInSync(n, ['a', 'b'], 1);
    });

    test('a passive device ignores queue edits (only the host applies them)', () async {
      final n = await host();
      fakeSyncService.emitSyncState(const PlaybackState(activeDevice: 'device-other', trackId: 'b'));
      await Future.delayed(Duration.zero);
      await send(const RemoteCommand(action: 'queue_remove', index: 3, trackId: 'd'));
      expect(ids(n.state.queue), ['a', 'b', 'c', 'd', 'e']);
    });
  });
}

/// Keeps a real queue, so a test can check the player and its handler agree.
class QueueKeepingHandler extends ControlledNaviAudioHandler {
  final removed = <int>[];

  @override
  Future<void> insertAllNext(List<Song> songs, {int? atIndex}) async {
    currentQueue.insertAll((atIndex ?? currentIndex + 1).clamp(0, currentQueue.length), songs);
  }

  @override
  Future<void> addAllToQueue(List<Song> songs) async => currentQueue.addAll(songs);

  @override
  Future<void> removeFromQueue(int index) async {
    removed.add(index);
    currentQueue.removeAt(index);
  }

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex, {bool isShuffleMode = false}) async {
    currentQueue.insert(newIndex, currentQueue.removeAt(oldIndex));
  }
}
