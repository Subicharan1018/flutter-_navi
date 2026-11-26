// The song heard must be the song shown. The fake player here behaves like
// ExoPlayer where it matters: it keeps playing the same source object while the
// playlist around it is edited, so "heard" is read from the audio, never from
// the app's own bookkeeping.
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' show MediaItem;
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

Song _song(int i) => Song(
  id: 's$i',
  title: 'Song $i',
  artist: 'Artist',
  album: 'Album',
  genre: 'Rock',
  composer: 'Comp',
  coverArt: '',
  duration: 200,
  track: 1,
  year: 2024,
);

List<Song> _songs(int n, [int from = 0]) => [for (var i = from; i < from + n; i++) _song(i)];

class _Cache extends Fake implements PlaylistCacheService {}

class _Subsonic extends SubsonicService {
  _Subsonic() : super(serverUrl: 'https://test.example.com', username: 'u', password: 'p', cache: _Cache());

  @override
  String getStreamUrl(String id, {int? maxBitRate, String? format}) => 'https://test.example.com/rest/stream?id=$id';

  @override
  String getCoverArtUrl(String? id, {int? size}) => 'https://test.example.com/rest/getCoverArt?id=$id';
}

class _Player extends Fake implements AudioPlayer {
  ConcatenatingAudioSource? _list;
  AudioSource? _heard;
  int _lastIndex = 0;
  bool isOn = false;

  /// just_audio's play() completes only when playback pauses or ends, and never
  /// when Android refuses audio focus (a phone call).
  bool playNeverReturns = false;
  bool failNextSeek = false;

  final _sequence = StreamController<SequenceState>.broadcast(sync: true);

  String? get heardId => (_heard?.sequence.first.tag as MediaItem?)?.id;

  List<String> get loadedIds => [for (final c in _list!.children) (c.sequence.first.tag as MediaItem).id];

  /// The track ends and the next loaded one starts (gapless). False at the end.
  bool advance() {
    final i = currentIndex! + 1;
    if (i >= _list!.children.length) return false;
    _heard = _list!.children[i];
    return true;
  }

  @override
  int? get currentIndex {
    final list = _list;
    if (list == null) return null;
    final i = list.children.indexWhere((c) => identical(c, _heard));
    if (i >= 0) return _lastIndex = i;
    // The playing source was removed: the engine moves on to what took its place.
    if (list.children.isEmpty) return null;
    _lastIndex = _lastIndex.clamp(0, list.children.length - 1);
    _heard = list.children[_lastIndex];
    return _lastIndex;
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source, {bool preload = true, int? initialIndex, Duration? initialPosition}) async {
    _list = source as ConcatenatingAudioSource;
    _lastIndex = initialIndex ?? 0;
    _heard = _list!.children[_lastIndex];
    return null;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (failNextSeek) {
      failNextSeek = false;
      throw PlatformException(code: 'seek', message: 'source failed');
    }
    if (index != null) _heard = _list!.children[index];
  }

  @override
  Future<void> play() {
    isOn = true;
    return playNeverReturns ? Completer<void>().future : Future<void>.value();
  }

  @override
  Future<void> pause() async => isOn = false;
  @override
  Future<void> stop() async => isOn = false;
  @override
  bool get playing => isOn;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  Duration? get duration => const Duration(seconds: 200);
  @override
  double get speed => 1;
  @override
  bool get shuffleModeEnabled => false;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  PlayerState get playerState => PlayerState(isOn, ProcessingState.ready);
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<SequenceState> get sequenceStateStream => _sequence.stream;
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
    final dir = Directory.systemTemp.createTempSync('hive_playback_identity');
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

  const settle = Duration(milliseconds: 40);
  late _Player player;
  late NaviAudioHandler handler;

  setUp(() {
    player = _Player();
    handler = NaviAudioHandler(_Subsonic(), player: player, skipSettle: settle);
  });

  Future<void> landed() => Future<void>.delayed(const Duration(milliseconds: 250));

  /// What the screen and notification show, what the app thinks is current and
  /// what the speaker plays are one song.
  void expectHeardIsShown([String? id]) {
    final current = handler.currentQueue[handler.currentIndex].id;
    expect(player.heardId, current, reason: 'heard vs the current song');
    if (id != null) expect(player.heardId, id);
    final published = handler.mediaItem.valueOrNull?.id;
    if (published != null) expect(published, player.heardId, reason: 'notification vs heard');
  }

  /// The loaded sources are exactly the queue, from the window's start on.
  void expectSourcesMatchQueue() {
    final loaded = player.loadedIds;
    final queue = [for (final s in handler.currentQueue) s.id];
    final from = queue.indexOf(loaded.first);
    expect(from, isNonNegative);
    expect(loaded, queue.sublist(from, from + loaded.length), reason: 'source i must be queue item offset + i');
  }

  group('queues longer than the 100 loaded sources', () {
    test('adding songs never puts their audio in another song\'s place', () async {
      await handler.setQueue(_songs(150), 0);
      await handler.addAllToQueue(_songs(2, 900));
      expectSourcesMatchQueue();
      await player.seek(Duration.zero, index: 99);
      if (player.advance()) expectHeardIsShown();
    });

    test('edits beyond the loaded window leave the loaded sources alone', () async {
      await handler.setQueue(_songs(150), 0);
      await handler.removeFromQueue(120);
      await handler.insertAllNext(_songs(1, 900), atIndex: 130);
      await handler.reorderQueue(140, 110);
      await handler.pruneRange(105, 108);
      expectSourcesMatchQueue();
    });

    test('moving a song across the window edge keeps sources and queue aligned', () async {
      await handler.setQueue(_songs(150), 0);
      await handler.reorderQueue(120, 5);
      expectSourcesMatchQueue();
      expectHeardIsShown('s0');
      await handler.reorderQueue(3, 130);
      expectSourcesMatchQueue();
      expectHeardIsShown('s0');
    });

    test('adding to a short window that already ends the queue still appends audio', () async {
      await handler.setQueue(_songs(150), 100);
      await handler.addAllToQueue(_songs(1, 900));
      expectSourcesMatchQueue();
      expect(player.loadedIds.last, 's900');
    });
  });

  group('the queue changes while a skip is still settling', () {
    test('reorder: the song the skip showed is the one that plays', () async {
      await handler.setQueue(_songs(5), 0);
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, 's1');
      await handler.reorderQueue(3, 1);
      await landed();
      expectHeardIsShown('s1');
    });

    test('a song removed above it', () async {
      await handler.setQueue(_songs(5), 1);
      await handler.skipToNext();
      await handler.removeFromQueue(0);
      await landed();
      expectHeardIsShown('s2');
    });

    test('played songs pruned above it', () async {
      await handler.setQueue(_songs(8), 3);
      await handler.skipToNext();
      await handler.pruneRange(0, 2);
      await landed();
      expectHeardIsShown('s4');
    });

    test('shuffle', () async {
      await handler.setQueue(_songs(30), 0);
      await handler.skipToNext();
      await handler.standardShuffle();
      await landed();
      expectHeardIsShown('s1');
    });

    test('a second skip counts from the song shown, not from a stale index', () async {
      await handler.setQueue(_songs(6), 1);
      await handler.skipToNext(); // shows s2
      await handler.removeFromQueue(0);
      await handler.skipToNext(); // must show s3
      await landed();
      expectHeardIsShown('s3');
    });
  });

  test('a skip that fails to load shows what is still playing again', () async {
    await handler.setQueue(_songs(4), 0);
    player.failNextSeek = true;
    await handler.skipToNext();
    await landed();
    expectHeardIsShown('s0');
  });

  test('a play() that never returns cannot hold a jump or later queue edits', () async {
    await handler.setQueue(_songs(150), 0);
    await player.play();
    player.playNeverReturns = true;
    player.isOn = true;
    // Outside the loaded window: the source is rebuilt and playback restarted.
    await handler.jumpToIndex(140).timeout(const Duration(seconds: 2));
    await handler.addAllToQueue(_songs(1, 900)).timeout(const Duration(seconds: 2));
    expectHeardIsShown('s140');
  });
}
