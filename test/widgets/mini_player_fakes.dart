// Fakes shared by the mini player tests.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/lyrics/controllers/lyrics_controller.dart';
import 'package:navivibe/lyrics/models/lyric_line.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/mini_player.dart';
import 'package:navivibe/services/subsonic_service.dart';

final miniSong = Song(
  id: 's1',
  title: 'Thaniye',
  artist: 'Anirudh',
  album: 'Vidaamuyarchi',
  coverArt: 's1',
  duration: 240,
  track: 1,
  year: 2024,
  suffix: 'flac',
  bitRate: 900,
);

class FakeAudio extends Fake implements AudioPlayer {
  double vol = 0.5;
  final seeks = <Duration?>[];
  @override
  Duration get position => const Duration(seconds: 60);
  @override
  Stream<Duration> get positionStream =>
      Stream.value(const Duration(seconds: 60));
  @override
  Duration? get duration => const Duration(seconds: 240);
  @override
  Stream<Duration?> get durationStream =>
      Stream.value(const Duration(seconds: 240));
  @override
  bool get playing => true;
  @override
  double get volume => vol;
  @override
  Future<void> setVolume(double v) async => vol = v;
  @override
  Future<void> seek(Duration? position, {int? index}) async =>
      seeks.add(position);
}

class FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  int toggles = 0, nexts = 0, prevs = 0;
  final stars = <String>[];
  final _audio = FakeAudio();
  FakePlayer(bool withSong)
    : super(
        PlayerState(
          queue: withSong ? [miniSong] : const [],
          currentIndex: withSong ? 0 : -1,
          isPlaying: true,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: const [],
          history: const [],
          syncMode: SyncMode.activeHere,
        ),
      );
  @override
  AudioPlayer get player => _audio;
  @override
  Future<void> togglePlay() async => toggles++;
  @override
  Future<void> playNext() async => nexts++;
  @override
  Future<void> playPrev() async => prevs++;
  @override
  Future<void> toggleStar(String id) async => stars.add(id);
  @override
  dynamic noSuchMethod(Invocation i) =>
      i.isMethod ? Future<void>.value() : null;
}

class FakeSettings extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  FakeSettings()
    : super(
        const SettingsState(
          serverUrl: 'https://music.example',
          username: 'u',
          password: 'p',
        ),
      );
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class MemWindow implements MiniWindow {
  Rect rect = const Rect.fromLTWH(100, 80, 1280, 800);
  bool onTop = false;
  @override
  Future<Rect> bounds() async => rect;
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<void> setBounds(Rect b) async => rect = b;
  @override
  Future<void> setAlwaysOnTop(bool t) async => onTop = t;
  @override
  Future<void> setMaximized(bool m) async {}
  @override
  Future<void> setMinimumSize(Size s) async {}
  @override
  Future<void> setResizable(bool r) async {}
  @override
  Future<void> show() async {}
}

class MemStore implements MiniStore {
  MiniPrefs prefs;
  MemStore([this.prefs = const MiniPrefs()]);
  @override
  MiniPrefs load() => prefs;
  @override
  void save(MiniPrefs p) => prefs = p;
}

class FakeLyrics extends LyricsController {
  final String? line;
  FakeLyrics(this.line);
  @override
  LyricsState build() => line == null
      ? const LyricsState(status: LyricsStatus.empty)
      : LyricsState(
          status: LyricsStatus.synced,
          lyrics: SyncedLyrics(
            lines: [LyricLine(timestamp: Duration.zero, text: line!)],
          ),
          activeLineIndex: 0,
        );
}
