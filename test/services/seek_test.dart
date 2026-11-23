// Seek regression test.
//
// Bug: NaviAudioHandler had no seek(): audio_service's default does nothing, so the
// notification / lock screen seek bar, headset and car seek commands, and the app's own
// seek bar (PlayerNotifier.seek -> handler.seek) all did nothing on every phone.
import 'dart:io';

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

/// Minimal player: records every seek, reports a stable ready state at [at].
class _Player implements AudioPlayer {
  final seeks = <Duration?>[];
  Duration at = Duration.zero;

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks.add(position);
    if (position != null) at = position;
  }

  @override
  bool get playing => false;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  Duration get position => at;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  Duration? get duration => const Duration(minutes: 4);
  @override
  double get speed => 1.0;
  @override
  bool get shuffleModeEnabled => false;
  @override
  LoopMode get loopMode => LoopMode.off;

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
    final dir = Directory.systemTemp.createTempSync('seek_test');
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

  test('seek moves the player to the requested position', () async {
    await handler.seek(const Duration(seconds: 73));
    expect(player.seeks, [const Duration(seconds: 73)]);
  });

  test('the notification declares seeking and the handler acts on it', () async {
    handler.refreshControls();
    expect(handler.playbackState.value.systemActions.map((a) => a.name), contains('seek'));
    await handler.seek(const Duration(seconds: 5));
    expect(player.position, const Duration(seconds: 5));
  });
}
