// Repeat mode regression tests.
//
// Bugs covered:
//  * Tapping repeat changed the engine but never re-broadcast playbackState,
//    and the UI reads repeat from playbackState — so the button looked dead.
//  * setRepeatMode (lock screen / notification / headset) ignored the mode it
//    was asked for and cycled instead (asking for "all" from "off" gave "one").
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/services/navi_audio_handler.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/services/subsonic_service.dart';

class _Cache extends Fake implements PlaylistCacheService {}

class _Subsonic extends SubsonicService {
  _Subsonic()
      : super(serverUrl: 'https://test.example.com', username: 'u', password: 'p', cache: _Cache());
}

/// Minimal player: records loop-mode writes, reports a stable idle state.
class _Player implements AudioPlayer {
  final loopWrites = <LoopMode>[];
  LoopMode _loop = LoopMode.off;

  @override
  LoopMode get loopMode => _loop;
  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopWrites.add(mode);
    _loop = mode;
  }

  @override
  bool get playing => false;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1.0;
  @override
  bool get shuffleModeEnabled => false;

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName.toString().contains('Stream')) return const Stream<Never>.empty();
    return null;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('repeat_mode_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  late _Player player;
  late NaviAudioHandler handler;

  setUp(() {
    player = _Player();
    handler = NaviAudioHandler(_Subsonic(), player: player);
  });

  test('changing repeat is broadcast immediately', () async {
    await handler.applyRepeatMode(LoopMode.one);
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.one);

    await handler.applyRepeatMode(LoopMode.all);
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.all);

    await handler.applyRepeatMode(LoopMode.off);
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.none);
  });

  test('setRepeatMode applies the requested mode instead of cycling', () async {
    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    expect(handler.repeatMode, LoopMode.all);
    expect(player.loopWrites.last, LoopMode.all);

    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    expect(handler.repeatMode, LoopMode.all, reason: 'same request twice stays put');

    await handler.setRepeatMode(AudioServiceRepeatMode.none);
    expect(handler.repeatMode, LoopMode.off);
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.none);
  });
}
