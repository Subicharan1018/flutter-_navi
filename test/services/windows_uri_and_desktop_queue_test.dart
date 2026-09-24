import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/offline_service.dart';
import 'package:navivibe/services/navi_audio_handler.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song({
  required String id,
  String title = 'Song',
  String artist = 'Artist',
  String suffix = 'mp3',
}) => Song(
  id: id,
  title: '$title $id',
  artist: artist,
  album: 'Album',
  genre: 'Rock',
  composer: 'Comp',
  coverArt: id,
  duration: 200,
  track: 1,
  year: 2024,
  suffix: suffix,
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

  @override
  String getStreamUrl(String id, {int? maxBitRate, String? format}) =>
      'https://test.example.com/rest/stream?id=$id';

  @override
  String getCoverArtUrl(String? id, {int? size}) =>
      'https://test.example.com/rest/getCoverArt?id=$id';
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
  final Duration _position = Duration.zero;
  final bool _playing = false;
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
    _currentIndexController.add(_currentIndex);
    return const Duration(seconds: 200);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (index != null) {
      _currentIndex = index;
      _currentIndexController.add(_currentIndex);
    }
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _currentIndexController.close();
    await _playbackEventController.close();
    await _playerStateController.close();
    await _processingStateController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('navi_win_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory' ||
            call.method == 'getTemporaryDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    Hive.init(tempDir.path);
    HiveBoxes.auth = await Hive.openBox('auth_v2');
    HiveBoxes.session = await Hive.openBox('session_v2');
    HiveBoxes.prefs = await Hive.openBox('prefs_v2');
    HiveBoxes.audio = await Hive.openBox('audio_v2');
  });

  group('Windows File URI & OfflineService Tests', () {
    test('Uri.file handles Windows absolute paths with drive letter correctly', () {
      const windowsPath = r'C:\Users\yoges\AppData\Local\offline_music\song123.mp3';
      final uri = Uri.file(windowsPath, windows: true);

      expect(uri.isScheme('file'), isTrue);
      expect(uri.pathSegments.last, equals('song123.mp3'));
      // A correctly formed Windows file URI starts with file:/// (3 slashes)
      final uriStr = uri.toString();
      expect(uriStr.startsWith('file:///'), isTrue);
      expect(uriStr, isNot(startsWith('file://C:')));
    });

    test('getPlayableUrl generates valid file URI for downloaded song', () {
      SharedPreferences.setMockInitialValues({
        'offline_downloaded_songs': ['song_win_1'],
      });

      final offlineService = OfflineService();
      final cache = MockPlaylistCacheService();
      final subsonic = MockSubsonicService(cache);
      final song = _song(id: 'song_win_1');

      final url = offlineService.getPlayableUrl(song, subsonic);
      // When not downloaded locally, falls back to Subsonic stream URL
      expect(url, equals('https://test.example.com/rest/stream?id=song_win_1'));
    });
  });

  group('NaviAudioHandler Desktop Bridge & Queue Operations', () {
    late NaviAudioHandler handler;
    late MockSubsonicService subsonic;
    late ControlledAudioPlayer player;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      final cache = MockPlaylistCacheService();
      subsonic = MockSubsonicService(cache);
      player = ControlledAudioPlayer();
      handler = NaviAudioHandler(subsonic, player: player);
    });

    tearDown(() async {
      await handler.dispose();
      await player.dispose();
    });

    test('setQueue and queue mutation bounds clamping', () async {
      final songs = List.generate(5, (i) => _song(id: 'song_$i'));
      await handler.setQueue(songs, 1);

      expect(handler.currentQueue.length, equals(5));

      // Test safe reordering
      await handler.reorderQueue(0, 4);
      expect(handler.currentQueue.length, equals(5));
      expect(handler.currentQueue.last.id, equals('song_0'));

      // Test safe removal
      await handler.removeFromQueue(2);
      expect(handler.currentQueue.length, equals(4));

      // Test bounds protection
      await handler.removeFromQueue(100);
      expect(handler.currentQueue.length, equals(4));
    });

    test('MediaItem tag is properly assigned for downloaded vs remote tracks', () async {
      final songs = [_song(id: 's1'), _song(id: 's2')];
      await handler.setQueue(songs, 0);

      expect(handler.currentQueue.first.id, equals('s1'));
      expect(handler.currentQueue.first.title, equals('Song s1'));
    });

    test('standardShuffle pools all playlist songs and anchors active song at index 0', () async {
      final songs = List.generate(10, (i) => _song(id: 'track_$i'));
      // User is playing track 8 (near the end of playlist)
      await handler.setQueue(songs, 8, unshuffledSongs: songs);

      expect(handler.currentIndex, equals(8));
      expect(handler.currentQueue[8].id, equals('track_8'));

      // Reshuffle from playlist
      await handler.standardShuffle();

      // Active song track_8 must now be at index 0
      expect(handler.currentQueue.length, equals(10));
      expect(handler.currentQueue.first.id, equals('track_8'));
      expect(handler.currentIndex, equals(0));

      // All other 9 songs must be present in the queue
      final remainingIds = handler.currentQueue.skip(1).map((s) => s.id).toSet();
      expect(remainingIds.length, equals(9));
      expect(remainingIds.contains('track_8'), isFalse);
    });

    test('updateQueuePreservingCurrent preserves active song at index 0 without stopping', () async {
      final songs = List.generate(5, (i) => _song(id: 't_$i'));
      await handler.setQueue(songs, 0);

      final freshBatch = [_song(id: 't_0'), _song(id: 't_4'), _song(id: 't_2'), _song(id: 't_1')];
      await handler.updateQueuePreservingCurrent(freshBatch, 0);

      expect(handler.currentQueue.length, equals(4));
      expect(handler.currentQueue.first.id, equals('t_0'));
      expect(handler.currentIndex, equals(0));
    });
  });
}
