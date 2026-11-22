// Renders the Windows mini player in both shapes with real fonts and a
// synthetic cover (no copyrighted art, no lyrics text), at 1x and 1.3x text.
//
//   flutter test test/goldens/mini_player_test.dart --update-goldens

@Tags(['golden'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/lyrics/controllers/lyrics_controller.dart';
import 'package:navivibe/lyrics/models/lyric_line.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/artwork.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/mini_player.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/mini_player_view.dart';

import 'golden_fonts.dart';

final _song = Song(
  id: 'mini1',
  title: 'Thaniye (From "Vidaamuyarchi")',
  artist: 'Anirudh Ravichander',
  album: 'Vidaamuyarchi',
  coverArt: 'mini1',
  duration: 238,
  track: 1,
  year: 2024,
  suffix: 'flac',
  bitRate: 900,
);

class _Audio extends Fake implements AudioPlayer {
  @override
  Duration get position => const Duration(seconds: 84);
  @override
  Stream<Duration> get positionStream =>
      Stream.value(const Duration(seconds: 84));
  @override
  Duration? get duration => const Duration(seconds: 238);
  @override
  Stream<Duration?> get durationStream =>
      Stream.value(const Duration(seconds: 238));
  @override
  bool get playing => true;
  @override
  double get volume => 0.7;
}

class _Player extends StateNotifier<PlayerState> implements PlayerNotifier {
  final _audio = _Audio();
  _Player()
    : super(
        PlayerState(
          queue: [_song],
          currentIndex: 0,
          isPlaying: true,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: const ['mini1'],
          history: const [],
          syncMode: SyncMode.activeHere,
        ),
      );
  @override
  AudioPlayer get player => _audio;
  @override
  dynamic noSuchMethod(Invocation i) =>
      i.isMethod ? Future<void>.value() : null;
}

class _Settings extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  _Settings()
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

class _Subsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => 'cover://$id';
}

class _Lyrics extends LyricsController {
  @override
  LyricsState build() => LyricsState(
    status: LyricsStatus.synced,
    lyrics: const SyncedLyrics(
      lines: [
        LyricLine(
          timestamp: Duration.zero,
          text: 'The words go here, one line at a time',
        ),
      ],
    ),
    activeLineIndex: 0,
  );
}

class _Window implements MiniWindow {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

Future<Uint8List> _cover() async {
  const size = 720;
  const r = Rect.fromLTWH(0, 0, 720, 720);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    r,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2F5D8A), Color(0xFFE8B16A)],
      ).createShader(r),
  );
  canvas.drawCircle(
    const Offset(430, 300),
    200,
    Paint()..color = Colors.white.withValues(alpha: 0.35),
  );
  canvas.drawCircle(
    const Offset(300, 460),
    90,
    Paint()..color = const Color(0x55000000),
  );
  final img = await rec.endRecording().toImage(size, size);
  return (await img.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
}

void main() {
  late Uint8List cover;

  setUpAll(() async {
    await loadGoldenFonts();
    cover = (await _cover());
  });
  setUp(() {
    PlatformUtils.debugDesktopOverride = true;
    debugCoverImageOverride = (url, key) => MemoryImage(cover);
  });
  tearDown(() {
    debugCoverImageOverride = null;
    PlatformUtils.debugDesktopOverride = null;
  });

  for (final mode in MiniMode.values) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('mini player ${mode.name} x$scale', (tester) async {
        final size = MiniPlayer.sizeFor(mode);
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final mini = MiniPlayer(window: _Window(), store: _Store(mode));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerProvider.overrideWith((ref) => _Player()),
              settingsProvider.overrideWith((ref) => _Settings()),
              subsonicServiceProvider.overrideWithValue(_Subsonic()),
              lyricsControllerProvider.overrideWith(_Lyrics.new),
              coverPaletteProvider('mini1').overrideWithValue(
                const AsyncData(
                  AlbumPalette(
                    deep: Color(0xFF14283D),
                    base: Color(0xFF2F5D8A),
                    vibrant: Color(0xFFE8B16A),
                    glow: Color(0xFF4A7FB0),
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(AppThemeTokens.fallback),
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
              ),
              home: Scaffold(
                body: MiniPlayerView(onReturn: () {}, controller: mini),
              ),
            ),
          ),
        );
        // The cover decodes off the test clock.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Over the window, so the square shows its window buttons too.
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(Offset(size.width / 2, size.height / 2));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('mini_player/${mode.name}_x$scale.png'),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 30));
      });
    }
  }
}

class _Store implements MiniStore {
  final MiniMode mode;
  _Store(this.mode);
  @override
  MiniPrefs load() => MiniPrefs(mode: mode);
  @override
  void save(MiniPrefs p) {}
}
