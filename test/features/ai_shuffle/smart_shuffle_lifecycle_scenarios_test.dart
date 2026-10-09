import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/features/ai_shuffle/data/models/feedback_request.dart';
import 'package:navivibe/features/ai_shuffle/data/models/next_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/recommended_song.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_exception.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_repository.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/player_provider.dart' hide PlayerState;
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/listening_event_collector.dart';
import 'package:navivibe/services/navi_audio_handler.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/services/scrobble_service.dart';
import 'package:navivibe/services/subsonic_service.dart';

// -----------------------------------------------------------------------------
// Helper: create Song
// -----------------------------------------------------------------------------
Song createTestSong({
  required String id,
  required String title,
  String artist = 'Test Artist',
  String album = 'Test Album',
  String genre = 'Rock',
  int duration = 200,
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    composer: artist,
    coverArt: '',
    duration: duration,
    track: 1,
    year: 2024,
  );
}

// -----------------------------------------------------------------------------
// Helper: create RecommendedSong
// -----------------------------------------------------------------------------
RecommendedSong createTestRecommendation({
  required int rank,
  required String title,
  required String artist,
}) {
  return RecommendedSong(
    rank: rank,
    title: title,
    filePath: 'path/$title.mp3',
    genreBucket: 'Rock',
    composer: artist,
    audio: const AudioFeatures(
      energy: 0.8,
      valence: 0.7,
      acousticness: 0.1,
      danceability: 0.6,
    ),
    scores: const SongScores(
      contextHistory: 0.9,
      audioFit: 0.85,
      composerLoyalty: 0.8,
      finalScore: 0.88,
    ),
    why: 'Smart transition',
    artist: artist,
    album: 'Test Album',
  );
}

// -----------------------------------------------------------------------------
// Controlled Mocks
// -----------------------------------------------------------------------------
class MockPlaylistCacheService extends Fake implements PlaylistCacheService {}

class MockSubsonicService extends SubsonicService {
  MockSubsonicService(PlaylistCacheService cache)
      : super(serverUrl: '', username: '', password: '', cache: cache);

  @override
  String getStreamUrl(String id, {int? maxBitRate, String? format}) =>
      'https://test.example.com/stream/$id';

  @override
  String getCoverArtUrl(String? id, {int? size}) =>
      'https://test.example.com/cover/$id';

  @override
  Future<List<Song>> getSimilarSongs(String songId, {int count = 10}) async {
    return List.generate(
      count,
      (i) => createTestSong(
        id: 'autoplay_$i',
        title: 'Autoplay Song $i',
        artist: 'Autoplay Artist',
      ),
    );
  }

  @override
  Future<void> star(String id) async {}

  @override
  Future<void> unstar(String id) async {}

  @override
  Future<void> setRating(String id, int rating) async {}
}

class MockScrobbleService extends Fake implements ScrobbleService {
  @override
  Future<void> nowPlaying(String id) async {}

  @override
  void submit(String songId, {Song? song}) async {}
}

class ControlledAudioPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast(sync: true);
  final StreamController<PlaybackEvent> _playbackEventController =
      StreamController<PlaybackEvent>.broadcast(sync: true);
  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<ProcessingState> _processingStateController =
      StreamController<ProcessingState>.broadcast(sync: true);
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);

  int? _currentIndex = 0;
  Duration _position = Duration.zero;
  bool _playing = false;
  LoopMode _loopMode = LoopMode.off;

  int setAudioSourceCallCount = 0;
  int seekCallCount = 0;

  @override
  Duration get position => _position;

  void setPosition(Duration p) {
    _position = p;
    _positionController.add(p);
  }

  @override
  LoopMode get loopMode => _loopMode;

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
  }

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
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<SequenceState> get sequenceStateStream => const Stream.empty();

  @override
  int? get currentIndex => _currentIndex;

  Future<void> emitCurrentIndex(int? index) async {
    _currentIndex = index;
    _currentIndexController.add(index);
  }

  Future<void> emitProcessingState(ProcessingState state) async {
    _processingStateController.add(state);
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    setAudioSourceCallCount++;
    _currentIndex = initialIndex ?? 0;
    _position = initialPosition ?? Duration.zero;
    return null;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seekCallCount++;
    if (position != null) _position = position;
    if (index != null) {
      _currentIndex = index;
      _currentIndexController.add(index);
    }
  }

  @override
  Future<void> play() async {
    _playing = true;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> stop() async {
    _playing = false;
  }

  @override
  Future<void> setVolume(double volume) async {}

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
    unshuffledQueue.clear();
    unshuffledQueue.addAll(unshuffledSongs ?? songs);
  }

  @override
  Future<void> commitSmartLocalOrder({
    required List<Song> pastAndPresent,
    required List<Song> orderedFuture,
    required int anchorIndex,
    bool preferMoveBasedReorder = false,
  }) async {
    currentQueue = [...pastAndPresent, ...orderedFuture];
  }

  @override
  Future<void> updateQueuePreservingCurrent(
    List<Song> newQueue,
    int newCurrentIndex,
  ) async {
    currentQueue = List.from(newQueue);
  }
}

class MockListeningEventCollector extends Fake implements ListeningEventCollector {
  final List<String> startedSongTitles = [];
  final List<String> endedSongTitles = [];

  @override
  void onSongStarted({
    required Song song,
    required String sourceContext,
    required String transitionType,
    Song? prevSong,
    Duration positionAtSwitch = Duration.zero,
    int queuePosition = 0,
    bool shuffleActive = false,
  }) {
    startedSongTitles.add(song.title);
  }

  @override
  void onSongEnded(Song song, Duration position) {
    endedSongTitles.add(song.title);
  }

  @override
  void onSongRepeated() {}

  @override
  void recordSuggestFeedback(Song song, bool isMore) {}

  @override
  void persistWeight(String songId, double weight) {}
}

/// A configurable mock repository for Smart Shuffle
class MockShuffleRepository extends Fake implements ShuffleRepository {
  /// History of calls to getNext
  final List<Map<String, dynamic>> getNextCalls = [];
  /// History of feedback requests
  final List<FeedbackRequest> feedbackRequests = [];

  /// Configurable response generator or delay
  Duration? artificialDelay;
  bool shouldThrowError = false;

  /// Knowledge of all songs in the test library to support reshuffle
  List<Song> allLibrarySongs = [];

  /// Custom order callback for candidates
  List<String> Function(List<String> candidates)? customOrderStrategy;

  @override
  Future<NextResponse> getNext({
    String source = 'smart',
    String? playlistId,
    int count = 15,
    int depth = 0,
    String? playlistName,
    String genreStreakType = '',
    int genreStreakCount = 0,
    List<String> playedTitles = const [],
    List<double> recentListenRatios = const [],
    String lastEndReason = '',
    List<String> candidates = const [],
    bool reshuffle = false,
    List<String> excludedTitles = const [],
    String seedTitle = '',
  }) async {
    getNextCalls.add({
      'source': source,
      'count': count,
      'depth': depth,
      'candidates': List<String>.from(candidates),
      'seedTitle': seedTitle,
      'playedTitles': List<String>.from(playedTitles),
      'excludedTitles': List<String>.from(excludedTitles),
      'reshuffle': reshuffle,
    });

    if (artificialDelay != null) {
      await Future.delayed(artificialDelay!);
    }

    if (shouldThrowError) {
      throw ShuffleServerError(500);
    }

    final List<String> orderedTitles;
    if (customOrderStrategy != null) {
      orderedTitles = customOrderStrategy!(candidates);
    } else if (candidates.isNotEmpty) {
      orderedTitles = candidates.reversed.toList();
    } else {
      // Reshuffle case without candidates: pick up to 16 library songs not in excludedTitles
      final excludedSet = excludedTitles.toSet();
      orderedTitles = allLibrarySongs
          .where((s) => !excludedSet.contains(s.title))
          .take(16)
          .map((s) => s.title)
          .toList();
    }

    final recs = orderedTitles.mapIndexed((i, title) {
      return createTestRecommendation(
        rank: i + 1,
        title: title,
        artist: 'Test Artist',
      );
    }).toList();

    return NextResponse(
      mode: 'smart',
      source: source,
      queue: recs,
      reshuffle: reshuffle,
    );
  }

  @override
  Future<void> postFeedback(FeedbackRequest request) async {
    feedbackRequests.add(request);
  }

  @override
  Future<void> postImpressions({
    required List<String> shown,
    required List<String> played,
  }) async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => ['wifi'],
    );

    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('hive_smart_shuffle_scenarios');
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.audio = await Hive.openBox('audio');

    // Persist default Smart Shuffle setting in Hive so SettingsNotifier initializes with it
    await HiveBoxes.prefs.put(
      HiveBoxes.kShuffleAlgorithm,
      ShuffleAlgorithm.smartLocal.name,
    );
    await HiveBoxes.prefs.put(HiveBoxes.kDataCollectionEnabled, false);
  });

  late MockPlaylistCacheService cache;
  late MockSubsonicService subsonicService;
  late ControlledAudioPlayer player;
  late TestAudioHandler handler;
  late MockListeningEventCollector collector;
  late MockShuffleRepository mockRepo;
  late ProviderContainer container;

  void setupContainer({List<Song>? librarySongs}) {
    cache = MockPlaylistCacheService();
    subsonicService = MockSubsonicService(cache);
    player = ControlledAudioPlayer();
    handler = TestAudioHandler(subsonicService, player: player);
    collector = MockListeningEventCollector();
    mockRepo = MockShuffleRepository();
    if (librarySongs != null) {
      mockRepo.allLibrarySongs = librarySongs;
    }

    container = ProviderContainer(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        subsonicServiceProvider.overrideWithValue(subsonicService),
        listenerCollectorProvider.overrideWithValue(collector),
        shuffleRepositoryProvider.overrideWithValue(mockRepo),
        scrobbleServiceProvider.overrideWithValue(MockScrobbleService()),
      ],
    );
  }

  tearDown(() {
    container.dispose();
  });

  // Helper to generate a playlist of N songs
  List<Song> generatePlaylist(int count, {String prefix = 'Song'}) {
    return List.generate(
      count,
      (i) => createTestSong(
        id: 'id_$i',
        title: '$prefix ${i.toString().padLeft(2, '0')}',
        artist: 'Test Artist',
        album: 'Album 1',
      ),
    );
  }

  // Simulates a track completing naturally and advancing to nextIndex
  Future<void> simulateNaturalTrackCompletion(
    PlayerNotifier notifier, {
    required int nextIndex,
    required Song finishingSong,
  }) async {
    // Set position to song duration (100% listen ratio)
    player.setPosition(Duration(seconds: finishingSong.duration));
    await Future.delayed(const Duration(milliseconds: 15));

    // Emit completed state and new index
    await player.emitProcessingState(ProcessingState.completed);
    await player.emitCurrentIndex(nextIndex);
    await Future.delayed(const Duration(milliseconds: 25));
  }

  group('Smart Shuffle Lifecycle & Queue Scenarios', () {
    test('Scenario 1: Initial Playback with 16-song batch from large playlist', () async {
      final playlist = generatePlaylist(50);
      setupContainer(librarySongs: playlist);
      final notifier = container.read(playerProvider.notifier);

      // User starts playlist with Smart Shuffle
      await notifier.playPlaylist(
        playlist,
        shuffle: true,
        playlistName: 'Melody Hits',
      );

      final state = container.read(playerProvider);

      // Queue should have: 1 seed song + 16 smart-ordered songs = 17 songs total
      expect(state.queue.length, equals(17));
      expect(state.currentIndex, equals(0));
      expect(state.shuffleMode, isTrue);

      // Verify repo received candidates count of 16
      expect(mockRepo.getNextCalls.length, equals(1));
      final firstCall = mockRepo.getNextCalls.first;
      expect(firstCall['count'], equals(16));
      expect(firstCall['candidates'].length, equals(16));

      // Audio handler should match Riverpod state
      expect(handler.currentQueue.length, equals(17));
      expect(handler.currentQueue[0].id, equals(state.currentSong!.id));
    });

    test('Scenario 2: "Play Next" (insertNext) during active Smart Shuffle and subsequent completion', () async {
      final playlist = generatePlaylist(30);
      setupContainer(librarySongs: playlist);
      final notifier = container.read(playerProvider.notifier);

      await notifier.playPlaylist(playlist, shuffle: true);
      expect(container.read(playerProvider).queue.length, equals(17));

      final activeSong = container.read(playerProvider).currentSong!;
      final userSong = createTestSong(id: 'user_next_1', title: 'User Favorite Track');

      // User taps "Play Next"
      await notifier.insertNext(userSong);

      final stateAfterInsert = container.read(playerProvider);
      expect(stateAfterInsert.queue.length, equals(18));
      // Inserted song must be immediately after current playing song (index 1)
      expect(stateAfterInsert.queue[1].id, equals('user_next_1'));
      expect(stateAfterInsert.queue[0].id, equals(activeSong.id));

      // Natural track completion of active song
      await simulateNaturalTrackCompletion(
        notifier,
        nextIndex: 1,
        finishingSong: activeSong,
      );

      // Now Playing should be the user-inserted song
      final stateAtUserSong = container.read(playerProvider);
      expect(stateAtUserSong.currentIndex, equals(1));
      expect(stateAtUserSong.currentSong!.id, equals('user_next_1'));

      // User song finishes naturally
      await simulateNaturalTrackCompletion(
        notifier,
        nextIndex: 2,
        finishingSong: userSong,
      );

      // Smart shuffle resumes seamlessly with original smart song
      final stateAfterUserSong = container.read(playerProvider);
      expect(stateAfterUserSong.currentIndex, equals(2));
      expect(stateAfterUserSong.currentSong!.id, isNot('user_next_1'));
    });

    test('Scenario 3: Consecutive "Play Next" calls stack in proper reverse order', () async {
      final playlist = generatePlaylist(30);
      setupContainer(librarySongs: playlist);
      final notifier = container.read(playerProvider.notifier);

      await notifier.playPlaylist(playlist, shuffle: true);

      final songA = createTestSong(id: 'next_A', title: 'Song A');
      final songB = createTestSong(id: 'next_B', title: 'Song B');

      // Tap Play Next on A, then Play Next on B
      await notifier.insertNext(songA);
      await notifier.insertNext(songB);

      final state = container.read(playerProvider);
      // Expected: [Current, Song B, Song A, ...]
      expect(state.queue[1].id, equals('next_B'));
      expect(state.queue[2].id, equals('next_A'));
    });

    test('Scenario 4: "Add to Queue" (addToQueue) appends to tail and preserves order', () async {
      final playlist = generatePlaylist(40);
      setupContainer(librarySongs: playlist);
      final notifier = container.read(playerProvider.notifier);

      await notifier.playPlaylist(playlist, shuffle: true);
      expect(container.read(playerProvider).queue.length, equals(17));

      final tailSong = createTestSong(id: 'tail_song', title: 'User Tail Song');
      await notifier.addToQueue(tailSong);

      final state = container.read(playerProvider);
      expect(state.queue.length, equals(18));
      expect(state.queue.last.id, equals('tail_song'));
    });

    test('Scenario 5: Multi-Session Marathon (Hearing through 4 batches of 16 songs)', () async {
      // 70 songs playlist = Batch 1 (17) + Refill 1 (16) + Refill 2 (16) + Refill 3 (16) + Refill 4 (5)
      final playlist = generatePlaylist(70);
      setupContainer(librarySongs: playlist);
      final notifier = container.read(playerProvider.notifier);

      await notifier.playPlaylist(playlist, shuffle: true);
      expect(container.read(playerProvider).queue.length, equals(17));
      expect(mockRepo.getNextCalls.length, equals(1));

      // Advance through songs 0 to 13
      for (int i = 0; i < 13; i++) {
        final current = container.read(playerProvider).queue[i];
        await simulateNaturalTrackCompletion(
          notifier,
          nextIndex: i + 1,
          finishingSong: current,
        );
      }

      // At index 13: remainingAhead = 17 - 1 - 13 = 3 <= 3 -> REFILL 1 triggers
      await Future.delayed(const Duration(milliseconds: 50));

      expect(mockRepo.getNextCalls.length, equals(2),
          reason: 'Refill 1 should have fetched next 16 songs');
      // Queue expands: 17 + 16 = 33 songs
      expect(container.read(playerProvider).queue.length, equals(33));

      // Advance to index 29 (remainingAhead = 33 - 1 - 29 = 3 <= 3) -> REFILL 2 triggers
      for (int i = 13; i < 29; i++) {
        final current = container.read(playerProvider).queue[i];
        await simulateNaturalTrackCompletion(
          notifier,
          nextIndex: i + 1,
          finishingSong: current,
        );
      }

      await Future.delayed(const Duration(milliseconds: 50));
      expect(mockRepo.getNextCalls.length, equals(3),
          reason: 'Refill 2 should have fetched next 16 songs');
      // Queue expands: 33 + 16 = 49 songs
      expect(container.read(playerProvider).queue.length, equals(49));

      // Advance to index 45 (remainingAhead = 49 - 1 - 45 = 3 <= 3) -> REFILL 3 triggers
      for (int i = 29; i < 45; i++) {
        final current = container.read(playerProvider).queue[i];
        await simulateNaturalTrackCompletion(
          notifier,
          nextIndex: i + 1,
          finishingSong: current,
        );
      }

      await Future.delayed(const Duration(milliseconds: 50));
      expect(mockRepo.getNextCalls.length, equals(4),
          reason: 'Refill 3 should have fetched next 16 songs');

      // Total queue songs should now be grown cleanly without dropping active tracks
      final queue4 = container.read(playerProvider).queue;
      expect(queue4.isNotEmpty, isTrue);
      expect(container.read(playerProvider).currentSong, isNotNull);
    });

    test('Scenario 6: User jump near the end (user_selected) does NOT trigger premature refill', () async {
      final playlist = generatePlaylist(40);
      setupContainer(librarySongs: playlist);
      final notifier = container.read(playerProvider.notifier);

      await notifier.playPlaylist(playlist, shuffle: true);
      expect(mockRepo.getNextCalls.length, equals(1));

      // User jumps directly to song at index 15 (near the end of the 17-song queue)
      await notifier.jumpTo(15);
      await Future.delayed(const Duration(milliseconds: 50));

      // Should NOT fire refill immediately because transition was 'user_selected'
      expect(mockRepo.getNextCalls.length, equals(1),
          reason: 'Direct user jump should not fire instant premature refill');

      // Now let track 15 finish naturally
      final song15 = container.read(playerProvider).queue[15];
      await simulateNaturalTrackCompletion(
        notifier,
        nextIndex: 16,
        finishingSong: song15,
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Now that it finished naturally, refill should proceed
      expect(mockRepo.getNextCalls.length, equals(2));
    });

    test('Scenario 7: Server 500 error during refill falls back to raw pool order', () async {
      final playlist = generatePlaylist(35);
      setupContainer(librarySongs: playlist);
      final notifier = container.read(playerProvider.notifier);

      await notifier.playPlaylist(playlist, shuffle: true);
      expect(container.read(playerProvider).queue.length, equals(17));

      // Set server to fail on refill
      mockRepo.shouldThrowError = true;

      // Advance to trigger refill
      for (int i = 0; i < 14; i++) {
        final current = container.read(playerProvider).queue[i];
        await simulateNaturalTrackCompletion(
          notifier,
          nextIndex: i + 1,
          finishingSong: current,
        );
      }
      await Future.delayed(const Duration(milliseconds: 50));

      // Queue should STILL expand with the pool batch even though server failed
      final state = container.read(playerProvider);
      expect(state.queue.length, equals(33),
          reason: 'Fallback should append pool batch unordered on server failure');
      expect(state.currentSong, isNotNull);
    });

    test('Scenario 8: Reshuffle Active Queue preserves current song and replaces upcoming queue', () async {
      final playlist = generatePlaylist(40);
      setupContainer(librarySongs: playlist);
      final notifier = container.read(playerProvider.notifier);

      await notifier.playPlaylist(playlist, shuffle: true);
      final playingBeforeReshuffle = container.read(playerProvider).currentSong!;

      // Call reshuffleActiveQueue
      await notifier.reshuffleActiveQueue(playlist);

      final stateAfter = container.read(playerProvider);

      // Currently playing song is kept at index 0
      expect(stateAfter.currentIndex, equals(0));
      expect(stateAfter.currentSong!.id, equals(playingBeforeReshuffle.id));

      // Check excluded titles sent to server included original queue titles
      final lastCall = mockRepo.getNextCalls.last;
      expect(lastCall['reshuffle'], isTrue);
      expect(lastCall['excludedTitles'].contains(playingBeforeReshuffle.title), isTrue);
    });

    test('Scenario 9: Reordering and Removal in Up Next during Smart Shuffle', () async {
      final playlist = generatePlaylist(25);
      setupContainer(librarySongs: playlist);
      final notifier = container.read(playerProvider.notifier);

      await notifier.playPlaylist(playlist, shuffle: true);

      final queueBefore = container.read(playerProvider).queue;
      final songAt2 = queueBefore[2];

      // Reorder track from index 2 to index 5
      await notifier.reorderQueue(2, 5);
      final queueAfterReorder = container.read(playerProvider).queue;
      expect(queueAfterReorder[5].id, equals(songAt2.id));

      // Remove track at index 3
      final songAt3 = queueAfterReorder[3];
      await notifier.removeFromQueue(3);
      final queueAfterRemove = container.read(playerProvider).queue;
      expect(queueAfterRemove.any((s) => s.id == songAt3.id), isFalse);
      expect(queueAfterRemove.length, equals(queueBefore.length - 1));
    });
  });
}
