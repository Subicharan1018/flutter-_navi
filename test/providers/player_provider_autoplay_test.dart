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
  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;

  @override
  Duration get position => Duration.zero;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  bool get playing => _playing;
  @override
  ProcessingState get processingState => _processingState;

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

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (index != null) {
      _currentIndex = index;
      _currentIndexController.add(index);
    }
  }

  @override
  Future<void> seekToNext() async {
    if (_currentIndex != null) {
      _currentIndex = _currentIndex! + 1;
      _currentIndexController.add(_currentIndex);
    }
  }

  void simulateProcessingState(ProcessingState state) {
    _processingState = state;
    _processingStateController.add(state);
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
  Future<void> addAllToQueue(List<Song> songs) async {
    currentQueue.addAll(songs);
  }

  @override
  Future<void> jumpToIndex(int index) async {
    await player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> skipToNext() async {
    await player.seekToNext();
    if (player.currentIndex != null && player.currentIndex! < currentQueue.length) {
      _mediaItemSubject.add(MediaItem(
        id: currentQueue[player.currentIndex!].id,
        title: currentQueue[player.currentIndex!].title,
      ));
    }
  }

  @override
  Future<void> setQueue(
    List<Song> songs,
    int startIndex, {
    List<Song>? unshuffledSongs,
  }) async {
    currentQueue = List<Song>.from(songs);
    if (startIndex >= 0 && startIndex < songs.length) {
      await player.seek(Duration.zero, index: startIndex);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('autoplay_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          return null;
        },
      );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async {
          return ['wifi'];
        },
      );

  late ProviderContainer container;
  late MockSubsonicService subsonic;
  late MockAudioHandler handler;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.initFlutter('test_db_autoplay');
    await HiveBoxes.init();
  });

  tearDownAll(() async {
    await Hive.close();
    // Windows can keep a handle on a file it just closed for a moment; a leftover
    // temp folder must not fail the run.
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Left behind in the system temp folder; harmless.
    }
  });

  setUp(() {
    subsonic = MockSubsonicService(MockPlaylistCacheService());
    handler = MockAudioHandler();

    container = ProviderContainer(
      overrides: [
        subsonicServiceProvider.overrideWithValue(subsonic),
        audioHandlerProvider.overrideWithValue(handler),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test(
    'Autoplay fetches similar songs and advances when completed on last track',
    () async {
      final notifier = container.read(playerProvider.notifier);
      final s1 = _song(id: '1');
      final s2 = _song(id: '2');

      when(
        () => subsonic.getSimilarSongs(any(), count: any(named: 'count')),
      ).thenAnswer((_) async => [s2]);

      await notifier.setQueue([s1], 0);

      // Enable autoplay
      HiveBoxes.prefs.put(HiveBoxes.kAutoplayPreference, true);
      var state = container.read(playerProvider);
      if (!state.autoplayMode) {
        await notifier.toggleAutoplay();
      }

      // Simulate player completing
      (handler.player as ControlledAudioPlayer).simulateProcessingState(
        ProcessingState.completed,
      );

      // Wait for async fetch to finish
      await Future.delayed(const Duration(milliseconds: 300));

      state = container.read(playerProvider);
      expect(state.queue.length, 2);
      expect(state.queue[1].id, '2');
      expect(state.currentIndex, 1);
    },
  );

  ProviderContainer freshContainer() => ProviderContainer(
    overrides: [
      subsonicServiceProvider.overrideWithValue(subsonic),
      audioHandlerProvider.overrideWithValue(MockAudioHandler()),
    ],
  );

  test('Autoplay defaults to on when the preference was never set', () async {
    await HiveBoxes.prefs.delete(HiveBoxes.kAutoplayPreference);
    final c = freshContainer();
    addTearDown(c.dispose);
    c.read(playerProvider.notifier);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(c.read(playerProvider).autoplayMode, isTrue);
  });

  test('Autoplay restores the saved preference on startup', () async {
    await HiveBoxes.prefs.put(HiveBoxes.kAutoplayPreference, false);
    final off = freshContainer();
    addTearDown(off.dispose);
    off.read(playerProvider.notifier);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(off.read(playerProvider).autoplayMode, isFalse);

    await HiveBoxes.prefs.put(HiveBoxes.kAutoplayPreference, true);
    final on = freshContainer();
    addTearDown(on.dispose);
    on.read(playerProvider.notifier);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(on.read(playerProvider).autoplayMode, isTrue);
  });

  test('Empty similar list falls back to the artist top songs', () async {
    await HiveBoxes.prefs.put(HiveBoxes.kAutoplayPreference, true);
    final notifier = container.read(playerProvider.notifier);
    final s1 = _song(id: '1');
    final s2 = _song(id: '2');
    when(
      () => subsonic.getSimilarSongs(any(), count: any(named: 'count')),
    ).thenAnswer((_) async => []);
    when(
      () => subsonic.getTopSongs(any(), count: any(named: 'count')),
    ).thenAnswer((_) async => [s1, s2]); // s1 is already queued

    await notifier.setQueue([s1], 0);
    (handler.player as ControlledAudioPlayer).simulateProcessingState(
      ProcessingState.completed,
    );
    await Future.delayed(const Duration(milliseconds: 300));

    final state = container.read(playerProvider);
    expect(state.queue.map((s) => s.id), ['1', '2']);
    expect(state.currentIndex, 1);
  });

  test(
    'A single song started from search keeps going: falls through to random',
    () async {
      await HiveBoxes.prefs.put(HiveBoxes.kAutoplayPreference, true);
      final notifier = container.read(playerProvider.notifier);
      final s1 = _song(id: '1');
      final r1 = _song(id: '7');
      when(
        () => subsonic.getSimilarSongs(any(), count: any(named: 'count')),
      ).thenAnswer((_) async => []);
      when(
        () => subsonic.getTopSongs(any(), count: any(named: 'count')),
      ).thenAnswer((_) async => []);
      when(() => subsonic.getAlbum(any())).thenAnswer((_) async => [s1]);
      when(
        () => subsonic.getRandomSongs(size: any(named: 'size')),
      ).thenAnswer((_) async => [r1]);

      await notifier.setQueue([s1], 0);
      (handler.player as ControlledAudioPlayer).simulateProcessingState(
        ProcessingState.completed,
      );
      await Future.delayed(const Duration(milliseconds: 300));

      final state = container.read(playerProvider);
      expect(state.queue.length, 2);
      expect(state.queue[1].id, '7');
      expect(state.currentIndex, 1);
      expect(handler.player.playing, isTrue);
    },
  );

  test(
    'Autoplay completed on mid-queue track explicitly skips to next',
    () async {
      final notifier = container.read(playerProvider.notifier);
      final s1 = _song(id: '1');
      final s2 = _song(id: '2');

      await notifier.setQueue([s1, s2], 0);

      // Simulate player completing on index 0
      (handler.player as ControlledAudioPlayer).simulateProcessingState(
        ProcessingState.completed,
      );

      // The skip runs through async hops; wait for it rather than a fixed 50 ms,
      // which a busy machine (a parallel test run, CI) can overrun.
      for (var i = 0; i < 100 && handler.player.currentIndex != 1; i++) {
        await Future.delayed(const Duration(milliseconds: 30));
      }

      // We expect handler.skipToNext() to be called.
      // Our mock skips to next index on the mock player.
      expect(handler.player.currentIndex, 1);
    },
  );
}
