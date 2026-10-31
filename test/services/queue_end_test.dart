import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;
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

Song _song(String id) => Song(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  album: 'Album',
  coverArt: '',
  duration: 260,
  track: 1,
  year: 2024,
);

class _Cache extends Fake implements PlaylistCacheService {}

class _Service extends SubsonicService {
  _Service()
    : super(
        serverUrl: 'https://test.example.com',
        username: 'test',
        password: 'test',
        cache: _Cache(),
      );
}

/// A player that can be told the current track finished, the way
/// just_audio/media_kit do: processingState completed, `playing` still true.
class _CompletingPlayer extends Fake implements AudioPlayer {
  final _state = StreamController<PlayerState>.broadcast(sync: true);
  final _index = StreamController<int?>.broadcast(sync: true);
  int? _currentIndex = 0;
  Duration _position = Duration.zero;
  bool _playing = true;
  final calls = <String>[];

  @override
  Duration get position => _position;
  @override
  bool get playing => _playing;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  bool get shuffleModeEnabled => false;
  @override
  double get speed => 1.0;
  @override
  Duration get bufferedPosition => _position;
  @override
  ProcessingState get processingState => ProcessingState.completed;
  @override
  int? get currentIndex => _currentIndex;
  @override
  Stream<PlayerState> get playerStateStream => _state.stream;
  @override
  Stream<int?> get currentIndexStream => _index.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<SequenceState> get sequenceStateStream => const Stream.empty();

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    _currentIndex = initialIndex ?? 0;
    _position = initialPosition ?? Duration.zero;
    return null;
  }

  @override
  Future<void> play() async {
    _playing = true;
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    _playing = false;
    calls.add('pause');
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    _position = position ?? Duration.zero;
    calls.add('seek:${_position.inSeconds}');
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> dispose() async {}

  void finishTrack(int index) {
    _currentIndex = index;
    _position = const Duration(minutes: 4, seconds: 20);
    _state.add(PlayerState(true, ProcessingState.completed));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('hive_queue_end');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  late _CompletingPlayer player;
  late NaviAudioHandler handler;

  setUp(() async {
    player = _CompletingPlayer();
    handler = NaviAudioHandler(_Service(), player: player);
    await handler.setQueue([_song('1'), _song('2'), _song('3')], 0);
  });

  const settle = Duration(milliseconds: 600);

  test('finishing the last song pauses and rewinds', () async {
    player.finishTrack(2);
    await Future<void>.delayed(settle);
    expect(player.playing, isFalse);
    expect(player.position, Duration.zero);
    expect(player.calls, containsAllInOrder(['pause', 'seek:0']));
  });

  test('finishing a middle song leaves playback to the queue', () async {
    player.finishTrack(0);
    await Future<void>.delayed(settle);
    expect(player.calls, isNot(contains('pause')));
    expect(player.playing, isTrue);
  });

  test('repeat all never stops at the end', () async {
    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    player.finishTrack(2);
    await Future<void>.delayed(settle);
    expect(player.calls, isNot(contains('pause')));
  });

  test('does not rewind if playback restarted in the meantime', () async {
    player.finishTrack(2);
    await player.play(); // e.g. autoplay appended songs and resumed
    await Future<void>.delayed(settle);
    expect(player.calls, isNot(contains('seek:0')));
  });
}
