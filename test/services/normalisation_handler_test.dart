import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/navi_audio_handler.dart';
import 'package:navivibe/services/playback_tuning.dart';
import 'package:navivibe/services/player_volume.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song(String id, {double? gain}) => Song(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      coverArt: '',
      duration: 260,
      track: 1,
      year: 2024,
      trackGain: gain,
    );

class _Cache extends Fake implements PlaylistCacheService {}

class _Service extends SubsonicService {
  _Service() : super(serverUrl: 'https://test.example.com', username: 'test', password: 'test', cache: _Cache());

  final asked = <String>[];

  @override
  Future<Song> getSong(String id) async {
    asked.add(id);
    return _song(id);
  }
}

class _Player extends Fake implements AudioPlayer {
  final volumes = <double>[];
  int? _index = 0;
  double _volume = 1;

  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  bool get shuffleModeEnabled => false;
  @override
  double get speed => 1.0;
  @override
  double get volume => _volume;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  int? get currentIndex => _index;
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<SequenceState> get sequenceStateStream => const Stream.empty();
  @override
  Future<Duration?> setAudioSource(AudioSource source, {bool preload = true, int? initialIndex, Duration? initialPosition}) async {
    _index = initialIndex ?? 0;
    return null;
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration? position, {int? index}) async {}
  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    volumes.add(volume);
  }

  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('hive_normalise');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  late _Player player;
  late _Service service;
  late NaviAudioHandler handler;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 100));

  /// Loads the queue and announces its first song, as the player's index
  /// stream would on a device.
  Future<void> play(List<Song> queue) async {
    await handler.setQueue(queue, 0);
    handler.mediaItem.add(MediaItem(id: queue.first.id, title: queue.first.title));
    await settle();
  }

  setUp(() {
    player = _Player();
    service = _Service();
    handler = NaviAudioHandler(service, player: player);
  });

  void tune(ReplayGainMode mode, [LoudnessLevel loudness = LoudnessLevel.quiet]) =>
      handler.configureTuning(replayGainMode: mode, crossfadeSeconds: 0, speed: 1, loudness: loudness);

  double amplitude(double db) => math.pow(10, db / 20).toDouble();

  test('with everything off the volume is never touched', () async {
    tune(ReplayGainMode.off, LoudnessLevel.loud);
    await play([_song('1', gain: -9), _song('2')]);
    await settle();
    expect(player.volumes, isEmpty);
    expect(service.asked, isEmpty);
  });

  test('applies the tag, and returns to full volume when switched off', () async {
    await play([_song('1', gain: -9)]);
    await settle();
    tune(ReplayGainMode.track, LoudnessLevel.normal);
    await settle();
    expect(player.volume, closeTo(amplitude(-5), 1e-6));
    tune(ReplayGainMode.off);
    await settle();
    expect(player.volume, 1.0);
  });

  test('a song queued without tags gets them from the library mirror', () async {
    handler.gainLookup = (id) async => _song(id, gain: -12);
    tune(ReplayGainMode.track);
    await play([_song('1')]);
    await settle();
    expect(player.volume, closeTo(amplitude(-12), 1e-6));
    expect(service.asked, isEmpty);
  });

  test('a song with no tags anywhere stays at the stand-in level', () async {
    tune(ReplayGainMode.track);
    await play([_song('1')]);
    await settle();
    expect(player.volume, closeTo(amplitude(kUntaggedGainDb), 1e-6));
    expect(service.asked, ['1']);
  });

  test('normalisation keeps the listener’s own volume', () async {
    await player.setUserVolume(0.5);
    tune(ReplayGainMode.track);
    await play([_song('1', gain: -6)]);
    await settle();
    expect(player.userVolume, 0.5);
    expect(player.volume, closeTo(0.5 * amplitude(-6), 1e-6));
  });
}
