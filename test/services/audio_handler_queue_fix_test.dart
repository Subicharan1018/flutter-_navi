import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/navi_audio_handler.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song({
  required String id,
  String title = 'Song',
  String artist = 'Artist',
}) => Song(
  id: id,
  title: '$title $id',
  artist: artist,
  album: 'Album',
  genre: 'Rock',
  composer: 'Comp',
  coverArt: '',
  duration: 200,
  track: 1,
  year: 2024,
);

class MockPlaylistCacheService extends Fake implements PlaylistCacheService {}

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
  final StreamController<PlaybackEvent> _playbackEventController =
      StreamController<PlaybackEvent>.broadcast(sync: true);
  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<ProcessingState> _processingStateController =
      StreamController<ProcessingState>.broadcast(sync: true);

  int? _currentIndex = 0;
  Duration _position = Duration.zero;
  bool _playing = false;
  AudioSource? _audioSource;

  int setAudioSourceCallCount = 0;

  @override
  Duration get position => _position;

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
  int? get currentIndex => _currentIndex;

  @override
  AudioSource? get audioSource => _audioSource;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    setAudioSourceCallCount++;
    _audioSource = source;
    _currentIndex = initialIndex ?? 0;
    _position = initialPosition ?? Duration.zero;
    return null;
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync(
      'hive_test_audio_handler_queue_fix',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return dir.path;
        }
        return null;
      },
    );
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  late MockPlaylistCacheService cache;
  late MockSubsonicService subsonicService;
  late ControlledAudioPlayer player;

  setUp(() {
    cache = MockPlaylistCacheService();
    subsonicService = MockSubsonicService(cache);
    player = ControlledAudioPlayer();
  });

  group('NaviAudioHandler Queue Bug Fix Tests', () {
    test('insertNext places song immediately after current playing track', () async {
      final handler = NaviAudioHandler(subsonicService, player: player);

      final songs = [_song(id: '1'), _song(id: '2'), _song(id: '3')];
      await handler.insertAllNext(songs, atIndex: 0);

      expect(handler.currentQueue.length, equals(3));
      expect(handler.currentQueue[0].id, equals('1'));

      // Insert '99' right after index 0
      final inserted = _song(id: '99');
      await handler.insertNext(inserted);

      expect(handler.currentQueue.length, equals(4));
      expect(handler.currentQueue[0].id, equals('1'));
      expect(handler.currentQueue[1].id, equals('99'));
      expect(handler.currentQueue[2].id, equals('2'));
      expect(handler.currentQueue[3].id, equals('3'));
    });

    test('reorderQueue syncs _unshuffledQueue during shuffle mode', () async {
      final handler = NaviAudioHandler(subsonicService, player: player);
      final songs = [_song(id: 'A'), _song(id: 'B'), _song(id: 'C'), _song(id: 'D')];
      await handler.insertAllNext(songs, atIndex: 0);

      // Reorder track 'D' (index 3) to index 1 while in shuffle mode
      await handler.reorderQueue(3, 1, isShuffleMode: true);

      expect(handler.currentQueue.map((s) => s.id).toList(), equals(['A', 'D', 'B', 'C']));
      expect(handler.unshuffledQueue.map((s) => s.id).toList(), equals(['A', 'D', 'B', 'C']));

      // Unshuffle should maintain the newly ordered songs
      await handler.unshuffle();
      expect(handler.currentQueue.map((s) => s.id).toList(), equals(['A', 'D', 'B', 'C']));
    });

    test('addToQueue on existing non-empty queue does not force source rebuild', () async {
      final handler = NaviAudioHandler(subsonicService, player: player);
      await handler.insertAllNext([_song(id: '1')], atIndex: 0);
      final initialCalls = player.setAudioSourceCallCount;

      // Add a song to non-empty queue
      await handler.addToQueue(_song(id: '2'));

      expect(handler.currentQueue.length, equals(2));
      // setAudioSource should NOT be called again on non-empty queue additions
      expect(player.setAudioSourceCallCount, equals(initialCalls));
    });
  });
}
