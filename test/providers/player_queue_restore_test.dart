// ignore_for_file: deprecated_member_use
import 'package:audio_service/audio_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:rxdart/rxdart.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/queue_snapshot.dart';
import 'package:navivibe/providers/player_provider.dart' hide PlayerState;
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/navi_audio_handler.dart';
import 'package:navivibe/services/listening_event_collector.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/services/playlist_cache_service.dart';

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

class MockSubsonicService extends Mock implements SubsonicService {
  MockSubsonicService(PlaylistCacheService cache);
  @override
  Future<void> scrobble(String songId, {required bool submission, int? timeMs, bool strict = false}) async {}
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
  Duration _pos = Duration.zero;
  bool _playing = false;

  @override
  Duration get position => _pos;
  @override
  Future<void> seek(Duration? position, {int? index}) async => _pos = position ?? Duration.zero;
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
  Stream<SequenceState> get sequenceStateStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<LoopMode> get loopModeStream => _loopModeController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  int? get currentIndex => _currentIndex;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    Duration? initialPosition,
    int? initialIndex,
    bool preload = true,
  }) async {
    _currentIndex = initialIndex ?? 0;
    return null;
  }

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

  void simulateIndexChange(int newIndex) {
    _currentIndex = newIndex;
    _currentIndexController.add(newIndex);
  }
}

class MockAudioHandler extends Mock implements NaviAudioHandler {
  @override
  final player = ControlledAudioPlayer();

  @override
  List<Song> currentQueue = [];

  final BehaviorSubject<MediaItem?> _mediaItemSubject = BehaviorSubject<MediaItem?>.seeded(null);
  @override
  BehaviorSubject<MediaItem?> get mediaItem => _mediaItemSubject;

  final BehaviorSubject<PlaybackState> _playbackStateSubject = BehaviorSubject<PlaybackState>.seeded(PlaybackState());
  @override
  BehaviorSubject<PlaybackState> get playbackState => _playbackStateSubject;

  @override
  int get currentIndex => player.currentIndex ?? 0;

  MockAudioHandler() {
    player.playingStream.listen((playing) {
      _playbackStateSubject.add(_playbackStateSubject.value.copyWith(playing: playing));
    });
    player.loopModeStream.listen((loop) {
      final rm = const {
        LoopMode.off: AudioServiceRepeatMode.none,
        LoopMode.one: AudioServiceRepeatMode.one,
        LoopMode.all: AudioServiceRepeatMode.all,
      }[loop] ?? AudioServiceRepeatMode.none;
      _playbackStateSubject.add(_playbackStateSubject.value.copyWith(repeatMode: rm));
    });
    player.processingStateStream.listen((state) {
      final ps = const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[state] ?? AudioProcessingState.idle;
      _playbackStateSubject.add(_playbackStateSubject.value.copyWith(processingState: ps));
    });
    player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < currentQueue.length) {
        final song = currentQueue[index];
        _mediaItemSubject.add(MediaItem(
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
    if (startIndex >= 0 && startIndex < songs.length) {
      await player.setAudioSource(
        ConcatenatingAudioSource(children: []),
        initialIndex: startIndex,
      );
      _mediaItemSubject.add(MediaItem(
        id: songs[startIndex].id,
        title: songs[startIndex].title,
      ));
    }
  }

  @override
  Future<void> updateQueuePreservingCurrent(List<Song> newQueue, int newCurrentIndex) async {
    currentQueue = List<Song>.from(newQueue);
    (player as ControlledAudioPlayer).simulateIndexChange(newCurrentIndex);
  }

  @override
  Future<void> standardShuffle() async {
    currentQueue.shuffle();
  }

  @override
  Future<void> dispose() async {}
}

class _RestoreHandler extends MockAudioHandler {
  bool paused = false;
  List<Song> unshuffledGiven = [];

  @override
  List<Song> get unshuffledQueue => unshuffledGiven;

  @override
  Future<void> setQueue(List<Song> songs, int startIndex, {List<Song>? unshuffledSongs}) async {
    unshuffledGiven = unshuffledSongs ?? songs;
    await super.setQueue(songs, startIndex, unshuffledSongs: unshuffledSongs);
  }

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> play() async => paused = false;

  @override
  Future<void> applyRepeatMode(LoopMode mode) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('queue_restore_test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tempDir.path);
  messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
  messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (call) async => ['wifi']);

  late MockSubsonicService subsonic;
  late _RestoreHandler handler;
  late ProviderContainer container;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.initFlutter('test_db_queue_restore');
    await HiveBoxes.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  const server = 'https://music.example';
  const user = 'me';
  final songs = [for (var i = 1; i <= 4; i++) _song(id: '$i')];

  Future<void> saved({String account = 'https://music.example|me', int index = 2, int posMs = 61000}) async {
    final snap = SavedQueue.capture(
      account: account,
      queue: songs,
      currentIndex: index,
      unshuffled: songs.reversed.toList(),
      shuffle: true,
      repeat: 0,
      source: 'Evening',
    )!;
    await HiveBoxes.session.put(HiveBoxes.kQueueSnapshot, snap.encode());
    await HiveBoxes.session.put(HiveBoxes.kCurrentTrackId, songs[index].id);
    await HiveBoxes.session.put(HiveBoxes.kLastPositionMs, posMs);
  }

  Future<PlayerNotifier> launch({bool expectRestore = false}) async {
    handler = _RestoreHandler();
    subsonic = MockSubsonicService(MockPlaylistCacheService());
    container = ProviderContainer(overrides: [
      subsonicServiceProvider.overrideWithValue(subsonic),
      audioHandlerProvider.overrideWithValue(handler),
    ]);
    final n = container.read(playerProvider.notifier);
    // The restore reads the library database first; poll until it has landed
    // (or, when nothing should come back, give it time to prove that).
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (expectRestore && container.read(playerProvider).queue.isNotEmpty) break;
      if (!expectRestore && i >= 5) break;
    }
    return n;
  }

  setUp(() async {
    await HiveBoxes.auth.put(HiveBoxes.kServerUrl, server);
    await HiveBoxes.auth.put(HiveBoxes.kUsername, user);
    await HiveBoxes.session.clear();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300)); // let async bookkeeping finish
    container.dispose();
  });

  test('last session comes back paused: queue, index, modes, source', () async {
    await saved();
    final n = await launch(expectRestore: true);
    final s = container.read(playerProvider);
    expect(s.queue.map((e) => e.id), ['1', '2', '3', '4']);
    expect(s.currentIndex, 2);
    expect(s.isPlaying, isFalse);
    expect(s.shuffleMode, isTrue);
    expect(n.currentPlaylistName, 'Evening');
    expect(handler.paused, isTrue);
    expect(handler.unshuffledGiven.map((e) => e.id), ['4', '3', '2', '1']);
  });

  test('another account does not restore', () async {
    await saved(account: 'https://music.example|someone-else');
    await launch();
    expect(container.read(playerProvider).queue, isEmpty);
  });

  test('a damaged snapshot starts clean and is dropped', () async {
    await HiveBoxes.session.put(HiveBoxes.kQueueSnapshot, '{"v":1,"broken');
    await launch();
    expect(container.read(playerProvider).queue, isEmpty);
    expect(HiveBoxes.session.get(HiveBoxes.kQueueSnapshot), isNull);
  });

  test('a queue the listener started first is not replaced', () async {
    await saved();
    final n = await launch();
    await n.setQueue([_song(id: '9')], 0);
    expect(container.read(playerProvider).queue.map((e) => e.id), ['9']);
  });

  test('exit saves the queue so the next launch restores it', () async {
    final n = await launch();
    await n.setQueue(songs, 1, playlistName: 'Mix');
    n.flushPersist();
    final firstRun = container; // the app process ends here; the next launch is a new one
    await launch(expectRestore: true);
    final s = container.read(playerProvider);
    expect(s.queue.map((e) => e.id), ['1', '2', '3', '4']);
    expect(s.currentIndex, 1);
    firstRun.dispose();
  });
}
