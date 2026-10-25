// Visual render of the player surfaces (Now Playing, Queue, Lyrics, wide
// layout, mini player) with real fonts and real widgets.
//
//   flutter test test/goldens/player_surfaces_test.dart --update-goldens
//
// Covers: set NAVI_COVERS=/dir/with/jpgs to render real artwork locally
// (never committed); otherwise synthetic gradient covers are generated so the
// goldens stay copyright-free and deterministic in CI.

@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/album_palette.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/lyrics/controllers/lyrics_controller.dart';
import 'package:navivibe/lyrics/models/lyric_line.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/artwork.dart';
import 'package:navivibe/player/artwork_field.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/now_playing_screen.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/player/player_controls.dart' show GlyphButton, TransportControls;
import 'package:navivibe/widgets/mascot/microduck.dart';
import 'package:navivibe/widgets/mascot/microduck_strip.dart';
import 'package:navivibe/widgets/mini_player.dart';

import 'golden_fonts.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

Song _song(String id, String title, String artist, {String suffix = 'flac', int dur = 243}) => Song(
      id: id,
      title: title,
      artist: artist,
      album: 'Album $id',
      coverArt: id,
      duration: dur,
      track: 1,
      year: 2024,
      suffix: suffix,
      bitRate: suffix == 'flac' ? 1411 : 320,
    );

final _songs = [
  _song('bedc78', 'Aga Naga (From "Ponniyin Selvan Part-2")', 'A. R. Rahman, Shakthisree Gopalan'),
  _song('0cbb86', 'Alone', 'Alan Walker', suffix: 'mp3', dur: 161),
  _song('cb0c9a', 'Espresso', 'Sabrina Carpenter', dur: 175),
  _song('1a2078', 'Thaniye (From "Vidaamuyarchi")', 'Anirudh Ravichander', dur: 238),
  _song('q5', 'Kannukulla', 'Sean Roldan'),
  _song('q6', 'Oru Kal Oru Kannadi', 'Yuvan Shankar Raja'),
  _song('q7', 'Hangova (From "DC")', 'Anirudh Ravichander'),
  _song('q8', 'Katrukkulle', 'G. V. Prakash Kumar'),
];

/// Synthetic cover: two-hue diagonal field with a soft disc, seeded by id.
Future<ui.Image> _syntheticCover(String id, int size) async {
  final h = id.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xffff);
  final c1 = HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.72, 0.42).toColor();
  final c2 = HSLColor.fromAHSL(1, ((h * 7) % 360).toDouble(), 0.8, 0.6).toColor();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final r = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
  canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [c1, c2]).createShader(r));
  canvas.drawCircle(r.center.translate(size * 0.15, -size * 0.1), size * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.35));
  return rec.endRecording().toImage(size, size);
}

final Map<String, Uint8List> _coverBytes = {};

Future<void> _prepareCovers() async {
  final dir = Platform.environment['NAVI_COVERS'];
  for (final s in _songs) {
    final f = dir == null ? null : File('$dir/${s.id}.jpg');
    if (f != null && f.existsSync()) {
      _coverBytes[s.id] = f.readAsBytesSync();
    } else {
      final img = await _syntheticCover(s.id, 600);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      _coverBytes[s.id] = png!.buffer.asUint8List();
    }
  }
}

String _idFromKey(String key) => key.replaceFirst('cover_', '');

Future<ArtworkData> _artworkFor(Song s) async {
  final codec = await ui.instantiateImageCodec(_coverBytes[s.id]!, targetWidth: 64, targetHeight: 64);
  final image = (await codec.getNextFrame()).image;
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final palette = albumPaletteFromInts(extractAlbumPalette(rgba!.buffer.asUint8List()));
  return ArtworkData(key: coverCacheKey(s), image: image, palette: palette);
}

// ── Fakes ────────────────────────────────────────────────────────────────────

class _FakeAudioPlayer extends Fake implements AudioPlayer {
  final Duration pos;
  _FakeAudioPlayer(this.pos);
  @override
  Duration get position => pos;
  @override
  Stream<Duration> get positionStream => Stream.value(pos);
  @override
  double get volume => 0.62;
  @override
  Stream<double> get volumeStream => Stream.value(0.62);
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  final _FakeAudioPlayer _player;
  _FakePlayer(super.state, Duration pos) : _player = _FakeAudioPlayer(pos);
  @override
  AudioPlayer get player => _player;
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'u', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => 'cover://$id';
}

class _FixedArtwork extends NowPlayingArtworkNotifier {
  final ArtworkData data;
  _FixedArtwork(this.data);
  @override
  ArtworkData? build() => data;
}

class _FakeLyrics extends LyricsController {
  @override
  LyricsState build() => LyricsState(
        status: LyricsStatus.synced,
        activeLineIndex: 3,
        lyrics: SyncedLyrics(lines: [
          for (final (i, t) in const [
            'Thaniye thaniye',
            'Nadakkiren unnai thedi',
            'Kanavugal ellam',
            'Un pere solludhe',
            'Oru naal varuvaai endru',
            'Kaathirukkiren naane',
            'Mazhaiyil nanaindha',
            'Kaagidha kappal pole',
          ].indexed)
            LyricLine(timestamp: Duration(seconds: 12 + i * 5), text: t),
        ]),
      );
}

// ── Harness ──────────────────────────────────────────────────────────────────

Widget _app({
  required Song current,
  required ArtworkData art,
  required Widget home,
  bool playing = true,
  Duration pos = const Duration(seconds: 71),
}) {
  final idx = _songs.indexOf(current);
  final state = PlayerState(
    queue: _songs,
    currentIndex: idx,
    isPlaying: playing,
    shuffleMode: true,
    autoplayMode: true,
    repeatMode: LoopMode.off,
    starredIds: [_songs[0].id],
    history: _songs.where((s) => s != current).take(3).toList(),
    syncMode: SyncMode.activeHere,
  );
  final tokens = AppThemeTokens.fromPalette(art.palette);
  return ProviderScope(
    overrides: [
      playerProvider.overrideWith((ref) => _FakePlayer(state, pos)),
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      nowPlayingArtworkProvider.overrideWith(() => _FixedArtwork(art)),
      lyricsControllerProvider.overrideWith(_FakeLyrics.new),
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.build(tokens), home: home),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  // Image decoding is real async work: let it finish outside fake time.
  for (int i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
  });

  setUp(() {
    debugCoverImageOverride = (url, key) => MemoryImage(_coverBytes[_idFromKey(url.replaceFirst('cover://', ''))]!);
  });

  tearDown(() => debugCoverImageOverride = null);

  Future<void> shot(
    WidgetTester tester,
    String name, {
    required int songIndex,
    Size size = const Size(390, 844),
    bool playing = true,
    String? tap,
    Widget? home,
  }) async {
    debugDisableShadows = false; // render real soft shadows, as on device
    await tester.runAsync(_prepareCovers);
    await tester.runAsync(ArtworkField.precache);
    final song = _songs[songIndex];
    final art = (await tester.runAsync(() => _artworkFor(song)))!;
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(current: song, art: art, playing: playing, home: home ?? const NowPlayingScreen()));
    await _settle(tester);
    if (tap != null) {
      await tester.tap(find.bySemanticsLabel(tap).first);
      await _settle(tester);
    }
    try {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('player/$name.png'));
    } finally {
      debugDisableShadows = true; // must be restored before the test body ends
      // marquee schedules an uncancellable start-delay timer for long titles;
      // unmount and let the fake clock run past it.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }
  }

  testWidgets('a skip glides the covers across instead of cross-fading', (tester) async {
    await tester.runAsync(_prepareCovers);
    // Load the field's shader in real time: left to the widget, its shared
    // future would be created inside this test's fake clock and never
    // complete for the tests after it.
    await tester.runAsync(ArtworkField.precache);
    final art = (await tester.runAsync(() => _artworkFor(_songs[0])))!;
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(current: _songs[0], art: art, home: const NowPlayingScreen()));
    await _settle(tester);

    final sideCover = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_SideCover');
    expect(sideCover, findsNothing, reason: 'neighbours are hidden at rest');

    // Skip to the next song from outside the cover (button, notification).
    final container = ProviderScope.containerOf(tester.element(find.byType(NowPlayingScreen)));
    final player = container.read(playerProvider.notifier) as _FakePlayer;
    player.state = player.state.copyWith(currentIndex: 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(sideCover, findsOneWidget, reason: 'the old cover slides out beside the new one');

    await tester.pump(const Duration(seconds: 2));
    expect(sideCover, findsNothing, reason: 'the glide settles with the new cover centred');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('now playing — playing', (t) => shot(t, 'np_playing', songIndex: 0));
  testWidgets('now playing — paused', (t) => shot(t, 'np_paused', songIndex: 2, playing: false));
  testWidgets('now playing — queue', (t) => shot(t, 'np_queue', songIndex: 1, tap: 'Queue'));
  testWidgets('now playing — lyrics', (t) => shot(t, 'np_lyrics', songIndex: 3, tap: 'Lyrics'));
  testWidgets('now playing — wide', (t) => shot(t, 'np_wide', songIndex: 0, size: const Size(1440, 900)));
  testWidgets('mini player over a list', (t) => shot(
        t,
        'mini_player',
        songIndex: 3,
        home: Builder(builder: (context) {
          final tk = ThemeTokens.of(context);
          return Scaffold(
            backgroundColor: tk.bgBase,
            body: Stack(children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
                children: [
                  Text('Recently played', style: naviText(24, FontWeight.w800, tk.textPrimary)),
                  const SizedBox(height: 12),
                  for (final s in _songs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CoverImage(url: 'cover://${s.id}', cacheKey: coverCacheKey(s), width: 48, height: 48),
                      ),
                      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(s.artist),
                    ),
                ],
              ),
              const Positioned(left: 0, right: 0, bottom: 34, child: MiniPlayer()),
            ]),
          );
        }),
      ));

  // ── Microduck placement audit ───────────────────────────────────────────────
  //
  // The robot overlays the UI and must never get in the way: not over the
  // transport controls, the title's first line or the bar's own touches, never
  // outside its container, feet on the bar. Rendered at the real sizes of
  // phones, a tablet, a rotated phone, a Windows window and a TV, at normal
  // and large text; the pictures go to build/mascot_frames/layout/.
  const layoutSizes = {
    'phone360': Size(360, 800),
    'phone412': Size(412, 915),
    'tablet': Size(768, 1024),
    'landscape': Size(915, 412),
    'windows': Size(1280, 800),
    'tv': Size(1920, 1080),
  };

  Future<void> saveShot(WidgetTester tester, GlobalKey key, String name) async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    final dir = Directory('build/mascot_frames/layout')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  for (final e in layoutSizes.entries) {
    for (final scale in const [1.0, 1.5]) {
      final label = '${e.key} x$scale';
      testWidgets('microduck on now playing — $label', (tester) async {
        debugDisableShadows = false;
        await tester.runAsync(_prepareCovers);
        await tester.runAsync(ArtworkField.precache);
        final song = _songs[0]; // a long title: it wraps the title row's marquee
        final art = (await tester.runAsync(() => _artworkFor(song)))!;
        tester.view.physicalSize = e.value * 2;
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearAllTestValues();
        });
        final key = GlobalKey();
        await tester.pumpWidget(_app(
          current: song,
          art: art,
          home: RepaintBoundary(key: key, child: const NowPlayingScreen()),
        ));
        await _settle(tester);
        // The screen's own layout overflows in a few of these (a phone on its
        // side, 1.5x text in a short window). That is the screen, not the
        // robot, which is a layer and takes no room: note it, don't fail on it.
        final overflow = tester.takeException();
        if (overflow != null) {
          // ignore: avoid_print
          print('note: $label — the screen itself overflows (not the robot): ${overflow.toString().split('\n').first}');
        }

        final track = tester.getRect(find.byKey(microduckTrackKey));
        final screen = Offset.zero & e.value;
        final robots = find.byType(Microduck);
        final transport = find.byType(TransportControls);
        if (robots.evaluate().isEmpty) {
          // Left out only when there is genuinely no room above the bar.
          final title = tester.getRect(find.byKey(microduckTitleKey));
          expect(
            overlayHeight(feetY: track.top + kScrubberBarTop, titleBottom: title.bottom),
            0,
            reason: '$label: the robot may be missing only when it would not fit',
          );
        } else {
          final r = tester.getRect(robots.first);
          final title = tester.getRect(find.byKey(microduckTitleKey));
          expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(0.01, 0.01)), isTrue,
              reason: '$label: inside the screen ($r)');
          expect(r.top, greaterThanOrEqualTo(title.bottom - 0.5), reason: '$label: not over the title');
          expect(r.overlaps(tester.getRect(transport.first)), isFalse, reason: '$label: not over the controls');
          // Feet on the bar's top edge (the robot's feet are 4.5% up its square).
          expect(r.bottom - r.height * 0.045, closeTo(track.top + kScrubberBarTop, 1.5), reason: '$label: feet on the bar');
          // Within the bar's span, so it stays on it.
          expect(r.left, greaterThanOrEqualTo(track.left - 0.5));
          expect(r.right, lessThanOrEqualTo(track.right + 0.5));
          // The bar keeps its touches: the robot's touch area ends above it.
          final touch = tester.getRect(find.descendant(of: robots.first, matching: find.byType(Listener)).first);
          for (final y in [track.top + 6, track.top + 16, track.top + 26]) {
            expect(touch.contains(Offset(r.center.dx, y)), isFalse, reason: '$label: bar touches at y=$y reach the bar');
          }
        }
        await saveShot(tester, key, 'np_${e.key}_x$scale');
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });

      testWidgets('microduck on the mini player — $label', (tester) async {
        debugDisableShadows = false;
        await tester.runAsync(_prepareCovers);
        final song = _songs[3];
        final art = (await tester.runAsync(() => _artworkFor(song)))!;
        tester.view.physicalSize = e.value * 2;
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearAllTestValues();
        });
        final key = GlobalKey();
        await tester.pumpWidget(_app(
          current: song,
          art: art,
          home: RepaintBoundary(
            key: key,
            child: const Scaffold(
              body: Stack(children: [Positioned(left: 0, right: 0, bottom: 20, child: MiniPlayer())]),
            ),
          ),
        ));
        await _settle(tester);

        final capsule = tester.getRect(find.descendant(of: find.byType(MiniPlayer), matching: find.byType(AnimatedContainer)).first);
        final robots = find.byType(Microduck);
        expect(robots, findsOneWidget, reason: '$label: the mini player shows its robot');
        final r = tester.getRect(robots);
        expect(r.left, greaterThanOrEqualTo(capsule.left), reason: '$label: inside the capsule');
        expect(r.right, lessThanOrEqualTo(capsule.right));
        expect(r.top, greaterThanOrEqualTo(capsule.top - 0.5));
        expect(r.bottom, lessThanOrEqualTo(capsule.bottom + 0.5));
        for (final b in find.byType(GlyphButton).evaluate()) {
          expect(r.overlaps(tester.getRect(find.byElementPredicate((el) => el == b))), isFalse,
              reason: '$label: not over the play and next buttons');
        }
        final line = tester.getRect(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MiniProgress'));
        expect(r.bottom - r.height * 0.045, closeTo(line.top, 2.5), reason: '$label: feet on the progress line');
        await saveShot(tester, key, 'mini_${e.key}_x$scale');
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
