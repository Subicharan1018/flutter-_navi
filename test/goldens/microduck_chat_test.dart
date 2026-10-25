// Renders Microduck's chat sheet in several states to build/mascot_frames/
// (chat_*.png), so it can be looked at, and checks what each state says.
//
//   flutter test test/goldens/microduck_chat_test.dart

@Tags(['golden'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/artwork.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/widgets/mascot/chat/chat_controller.dart';
import 'package:navivibe/widgets/mascot/microduck_chat.dart';
import 'package:navivibe/widgets/mascot/microduck_texture.dart';

import 'golden_fonts.dart';

Song _song(String id, String title, String artist, {String composer = ''}) => Song(
      id: id,
      title: title,
      artist: artist,
      album: 'Album',
      coverArt: id,
      duration: 240,
      track: 1,
      year: 2022,
      composer: composer,
      playCount: 41,
    );

final _songs = [
  _song('a1', 'Aga Naga', 'A. R. Rahman, Shakthisree Gopalan', composer: 'A. R. Rahman'),
  _song('a2', 'Thaniye', 'Anirudh Ravichander', composer: 'Anirudh'),
  _song('a3', 'Kannukulla', 'Sean Roldan'),
  _song('a4', 'Oru Kal Oru Kannadi', 'Yuvan Shankar Raja'),
];

final Map<String, Uint8List> _covers = {};

Future<void> _prepareCovers() async {
  for (final s in _songs) {
    final h = s.id.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xffff);
    final c1 = HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.7, 0.4).toColor();
    final c2 = HSLColor.fromAHSL(1, ((h * 7) % 360).toDouble(), 0.8, 0.6).toColor();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const r = Rect.fromLTWH(0, 0, 200, 200);
    canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [c1, c2]).createShader(r));
    final img = await rec.endRecording().toImage(200, 200);
    _covers[s.id] = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }
}

class _FakeAudioPlayer extends Fake implements AudioPlayer {
  @override
  Duration get position => const Duration(seconds: 71);
  @override
  Stream<Duration> get positionStream => Stream.value(const Duration(seconds: 71));
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer(super.state);
  @override
  AudioPlayer get player => _FakeAudioPlayer();
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

/// A chat whose state is whatever the test says.
class _FixedChat extends MicroduckChatController {
  final ChatState fixed;
  _FixedChat(this.fixed);
  @override
  ChatState build() => fixed;
}

ChatMessage _duck(String text, {ChatSongs? songs, bool failed = false}) => ChatMessage(ChatRole.duck, text, songs: songs, failed: failed);

void main() {
  final key = GlobalKey();

  setUpAll(loadGoldenFonts);

  setUp(() {
    debugCoverImageOverride = (url, k) => MemoryImage(_covers[url.replaceFirst('cover://', '')]!);
  });
  tearDown(() => debugCoverImageOverride = null);

  Future<void> shot(
    WidgetTester tester,
    String name,
    ChatState chat, {
    List<String> expectText = const [],
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.runAsync(_prepareCovers);
    await tester.runAsync(MicroduckTexture.ensure);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final tokens = AppThemeTokens.fromPalette(AlbumPalette.fallback);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        playerProvider.overrideWith((ref) => _FakePlayer(PlayerState(
              queue: _songs,
              currentIndex: 0,
              isPlaying: true,
              shuffleMode: false,
              autoplayMode: false,
              repeatMode: LoopMode.off,
              starredIds: const [],
            ))),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
        microduckChatProvider.overrideWith(() => _FixedChat(chat)),
      ],
      child: ThemeTokens(
        tokens: tokens,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(tokens),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: tokens.bgBase,
              body: const Align(alignment: Alignment.bottomCenter, child: MicroduckChatSheet()),
            ),
          ),
        ),
      ),
    ));
    // Real time for image decoding; fake time for the robot's ticker.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    for (final text in expectText) {
      expect(find.textContaining(text), findsWidgets, reason: name);
    }
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    final dir = Directory('build/mascot_frames')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a fresh chat: greeting and suggestions for the playing song', (tester) async {
    await shot(
      tester,
      'chat_1_new',
      ChatState(messages: [_duck('Hi, I’m Microduck. Tell me a mood, or pick one below.')]),
      expectText: ['Hi, I’m Microduck', 'More like this', 'What is this song?', 'Who is the composer?'],
    );
  });

  testWidgets('a reply with song cards and because lines', (tester) async {
    await shot(
      tester,
      'chat_2_cards',
      ChatState(messages: [
        _duck('Hi, I’m Microduck. Tell me a mood, or pick one below.'),
        const ChatMessage(ChatRole.you, 'calm Tamil melodies'),
        _duck(
          'Tuned for Tamil · Melody · calm · 24 songs.',
          songs: ChatSongs(
            title: 'Tamil · Melody · calm',
            songs: _songs.take(3).toList(),
            because: const {'a1': 'You play a lot of A. R. Rahman', 'a2': 'Slow and warm, like your evening plays'},
            playAll: () async {},
            playLabel: 'Play this mix',
          ),
        ),
      ]),
      expectText: ['Tuned for Tamil', 'Aga Naga', 'You play a lot of A. R. Rahman', 'Play this mix'],
    );
  });

  testWidgets('while it thinks', (tester) async {
    await shot(
      tester,
      'chat_3_thinking',
      ChatState(messages: [
        _duck('Hi, I’m Microduck. Tell me a mood, or pick one below.'),
        const ChatMessage(ChatRole.you, 'something for a rainy night drive'),
      ], busy: true),
      expectText: ['Thinking', 'rainy night drive'],
    );
  });

  testWidgets('a failure, told in character', (tester) async {
    await shot(
      tester,
      'chat_4_offline',
      ChatState(messages: [
        const ChatMessage(ChatRole.you, 'surprise me'),
        _duck('My signal dropped. Check your connection and ask me again.', failed: true),
      ]),
      expectText: ['My signal dropped', 'Try again'],
    );
  });

  testWidgets('what is playing, with the song card', (tester) async {
    await shot(
      tester,
      'chat_5_nowplaying',
      ChatState(messages: [
        const ChatMessage(ChatRole.you, 'What is this song?'),
        _duck(
          '“Aga Naga” by A. R. Rahman, Shakthisree Gopalan. Composed by A. R. Rahman. Released in 2022. You have played it 41 times.',
          songs: ChatSongs(title: 'Playing now', songs: [_songs[0]]),
        ),
      ]),
      expectText: ['Composed by A. R. Rahman', 'PLAYING NOW'],
    );
  });

  // The chat on a small phone, a rotated phone and with large text: nothing
  // overflows (a failing overflow would throw).
  for (final (name, size, scale) in const [
    ('chat_small_x1.5', Size(360, 640), 1.5),
    ('chat_landscape', Size(800, 360), 1.0),
    ('chat_tv', Size(1920, 1080), 1.0),
  ]) {
    testWidgets('chat fits — $name', (tester) async {
      await shot(
        tester,
        name,
        ChatState(messages: [
          const ChatMessage(ChatRole.you, 'calm Tamil melodies for a long night drive with the windows down'),
          _duck(
            'Tuned for Tamil · Melody · calm · 24 songs.',
            songs: ChatSongs(
              title: 'Tamil · Melody · calm',
              songs: _songs.take(3).toList(),
              because: const {'a1': 'You play a lot of A. R. Rahman'},
              playAll: () async {},
              playLabel: 'Play this mix',
            ),
          ),
        ]),
        size: size,
        textScale: scale,
      );
    });
  }
}
