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
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/player_provider.dart' hide PlayerState;
import 'package:rxdart/rxdart.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/navi_audio_handler.dart';
import 'package:navivibe/services/listening_event_collector.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_repository.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/features/ai_shuffle/data/models/feedback_request.dart';
import 'package:audio_service/audio_service.dart';

Song _song({
  required String id,
  String title = 'Song',
  int duration = 200,
}) => Song(
  id: id,
  title: '$title $id',
  artist: 'Artist',
  album: 'Album',
  genre: 'Rock',
  composer: 'Comp',
  coverArt: '',
  duration: duration,
  track: 1,
  year: 2024,
);

class MockPlaylistCacheService extends Fake implements PlaylistCacheService {}
class MockListeningEventCollector extends Mock implements ListeningEventCollector {}
class MockSubsonicService extends Mock implements SubsonicService {
  @override
  Future<void> scrobble(String songId, {required bool submission}) async {}
}
class MockShuffleRepository extends Mock implements ShuffleRepository {}

class ControlledAudioPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _currentIndexController = StreamController<int?>.broadcast(sync: true);
  final StreamController<bool> _playingController = StreamController<bool>.broadcast(sync: true);
  final StreamController<LoopMode> _loopModeController = StreamController<LoopMode>.broadcast(sync: true);
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast(sync: true);
  final StreamController<PlaybackEvent> _playbackEventController = StreamController<PlaybackEvent>.broadcast(sync: true);
  final StreamController<PlayerState> _playerStateController = StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<ProcessingState> _processingStateController = StreamController<ProcessingState>.broadcast(sync: true);

  int? _currentIndex = 0;
  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;

  @override Duration get position => Duration(seconds: 100);
  @override LoopMode get loopMode => LoopMode.off;
  @override bool get playing => _playing;
  @override ProcessingState get processingState => _processingState;

  @override Stream<int?> get currentIndexStream => _currentIndexController.stream;
  @override Stream<PlaybackEvent> get playbackEventStream => _playbackEventController.stream;
  @override Stream<PlayerState> get playerStateStream => _playerStateController.stream;
  @override Stream<ProcessingState> get processingStateStream => _processingStateController.stream;
  @override Stream<SequenceState> get sequenceStateStream => const Stream.empty();
  @override Stream<bool> get playingStream => _playingController.stream;
  @override Stream<LoopMode> get loopModeStream => _loopModeController.stream;
  @override Stream<Duration> get positionStream => _positionController.stream;

  @override int? get currentIndex => _currentIndex;

  @override Future<void> play() async {
    _playing = true;
    _playingController.add(true);
  }

  @override Future<void> pause() async {
    _playing = false;
    _playingController.add(false);
  }

  @override Future<void> stop() async {
    _playing = false;
    _playingController.add(false);
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source, {Duration? initialPosition, int? initialIndex, bool preload = true}) async {
    _currentIndex = initialIndex ?? 0;
    return null;
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
  final ControlledAudioPlayer _player = ControlledAudioPlayer();
  @override ControlledAudioPlayer get player => _player;

  @override
  List<Song> currentQueue = [];
  final BehaviorSubject<MediaItem?> _mediaItemSubject = BehaviorSubject<MediaItem?>.seeded(null);

  @override
  BehaviorSubject<MediaItem?> get mediaItem => _mediaItemSubject;

  final BehaviorSubject<PlaybackState> _playbackStateSubject = BehaviorSubject<PlaybackState>.seeded(PlaybackState());

  @override
  BehaviorSubject<PlaybackState> get playbackState => _playbackStateSubject;

  @override
  int get currentIndex => _player.currentIndex ?? 0;

  MockAudioHandler() {
    _player.playingStream.listen((playing) {
      _playbackStateSubject.add(_playbackStateSubject.value.copyWith(playing: playing));
    });
    _player.loopModeStream.listen((loop) {
      final rm = const {
        LoopMode.off: AudioServiceRepeatMode.none,
        LoopMode.one: AudioServiceRepeatMode.one,
        LoopMode.all: AudioServiceRepeatMode.all,
      }[loop] ?? AudioServiceRepeatMode.none;
      _playbackStateSubject.add(_playbackStateSubject.value.copyWith(repeatMode: rm));
    });
    _player.processingStateStream.listen((state) {
      final ps = const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[state] ?? AudioProcessingState.idle;
      _playbackStateSubject.add(_playbackStateSubject.value.copyWith(processingState: ps));
    });
    _player.currentIndexStream.listen((index) {
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
  Future<void> skipToNext() async {
    if (_player.currentIndex != null && _player.currentIndex! < currentQueue.length - 1) {
      final nextIdx = _player.currentIndex! + 1;
      _player.simulateIndexChange(nextIdx);
    }
  }

  @override
  Future<void> setQueue(List<Song> songs, int startIndex, {List<Song>? unshuffledSongs}) async {
    currentQueue = List<Song>.from(songs);
    _player.simulateIndexChange(startIndex);
  }

  @override
  Future<void> updateQueuePreservingCurrent(List<Song> newQueue, int newCurrentIndex) async {
    currentQueue = List<Song>.from(newQueue);
    _player.simulateIndexChange(newCurrentIndex);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('feedback_test');

  setUpAll(() async {
    registerFallbackValue(FeedbackRequest(title: 'fallback', listenRatio: 1.0, endReason: 'test', genreBucket: 'Pop', composer: 'Test'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tempDir.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (call) async => ['wifi']);
    SharedPreferences.setMockInitialValues({});
    await Hive.initFlutter('test_db_feedback');
    await HiveBoxes.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  late ProviderContainer container;
  late MockShuffleRepository mockShuffleRepo;
  late MockAudioHandler handler;

  setUp(() {
    mockShuffleRepo = MockShuffleRepository();
    when(() => mockShuffleRepo.postFeedback(any())).thenAnswer((_) async {});
    handler = MockAudioHandler();

    container = ProviderContainer(
      overrides: [
        subsonicServiceProvider.overrideWithValue(MockSubsonicService()),
        audioHandlerProvider.overrideWithValue(handler),
        shuffleRepositoryProvider.overrideWithValue(mockShuffleRepo),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('Primary path: processingState completed sends feedback exactly once', () async {
    final notifier = container.read(playerProvider.notifier);
    final shuffleNotifier = container.read(shuffleQueueProvider.notifier);
    
    // Initialize session so hasActiveSession is true
    shuffleNotifier.initSession();

    final s1 = _song(id: '1');
    final s2 = _song(id: '2');
    await notifier.setQueue([s1, s2], 0);
    
    // Simulate natural completion on track 1
    handler.player.simulateProcessingState(ProcessingState.completed);
    
    // Wait for the async gap inside player_provider
    await Future.delayed(const Duration(milliseconds: 100));

    // Verify feedback was sent
    verify(() => mockShuffleRepo.postFeedback(any(that: isA<FeedbackRequest>()
        .having((req) => req.title, 'title', contains('1'))
        .having((req) => req.endReason, 'endReason', 'natural')
    ))).called(1);
    
    // Simulate the fallback path (mediaItem.listen) firing due to skipToNext being called
    // because processingState completed advances to next track non-Linux
    handler._mediaItemSubject.add(MediaItem(id: s2.id, title: s2.title));
    await Future.delayed(const Duration(milliseconds: 100));

    // Verify it was NOT called again (due to _naturalFeedbackSent guard)
    verifyNever(() => mockShuffleRepo.postFeedback(any(that: isA<FeedbackRequest>()
        .having((req) => req.title, 'title', contains('1'))
    )));
  });

  test('Fallback path: mediaItem.listen on Android mid-queue sends feedback when completed missing', () async {
    final notifier = container.read(playerProvider.notifier);
    final shuffleNotifier = container.read(shuffleQueueProvider.notifier);
    shuffleNotifier.initSession();

    final s1 = _song(id: '1');
    final s2 = _song(id: '2');
    await notifier.setQueue([s1, s2], 0);

    // Emit the first song's mediaItem after setQueue completes so it isn't suppressed.
    handler._mediaItemSubject.add(MediaItem(id: s1.id, title: s1.title));
    await Future.delayed(const Duration(milliseconds: 10));

    // Simulate Android mid-queue behaviour: it never emits ProcessingState.completed
    // It just directly emits the next mediaItem
    handler.player.simulateIndexChange(1);
    handler._mediaItemSubject.add(MediaItem(id: s2.id, title: s2.title));
    
    await Future.delayed(const Duration(milliseconds: 100));

    // Verify fallback path sent feedback (since transCtx defaults to autoplay if nothing overrode it,
    // actually, in real code it relies on prevSong and newSong logic)
    // Wait, transCtx defaults to 'autoplay' internally when not explicit.
    verify(() => mockShuffleRepo.postFeedback(any(that: isA<FeedbackRequest>()
        .having((req) => req.title, 'title', contains('1'))
        .having((req) => req.endReason, 'endReason', 'natural')
    ))).called(1);
  });
}
