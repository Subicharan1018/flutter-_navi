import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/artwork.dart' show coverPaletteProvider;
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/mini_player.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/mini_player_view.dart';

final _song = Song(
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

class _FakeAudio extends Fake implements AudioPlayer {
  @override
  Duration get position => const Duration(seconds: 60);
  @override
  Stream<Duration> get positionStream => Stream.value(const Duration(seconds: 60));
  @override
  Duration? get duration => const Duration(seconds: 240);
  @override
  Stream<Duration?> get durationStream => Stream.value(const Duration(seconds: 240));
  @override
  bool get playing => true;
  @override
  Future<void> seek(Duration? position, {int? index}) async {}
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  int toggles = 0, nexts = 0, prevs = 0;
  final _audio = _FakeAudio();
  _FakePlayer(bool withSong)
      : super(PlayerState(
          queue: withSong ? [_song] : const [],
          currentIndex: withSong ? 0 : -1,
          isPlaying: true,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: const [],
          history: const [],
          syncMode: SyncMode.activeHere,
        ));
  @override
  AudioPlayer get player => _audio;
  @override
  Future<void> togglePlay() async => toggles++;
  @override
  Future<void> playNext() async => nexts++;
  @override
  Future<void> playPrev() async => prevs++;
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
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _NoWindow implements MiniWindow {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

Widget _app(Widget child, {bool withSong = true}) {
  final List<Override> overrides = [
    playerProvider.overrideWith((ref) => _FakePlayer(withSong)),
    settingsProvider.overrideWith((ref) => _FakeSettings()),
    subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
    catalogSongProvider.overrideWith((ref, id) => null),
    coverPaletteProvider('s1').overrideWithValue(const AsyncData(AlbumPalette.fallback)),
  ];
  return PointerAnchor(
    child: ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.build(AppThemeTokens.fallback),
        builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
        home: child,
      ),
    ),
  );
}

void main() {
  setUp(() => PlatformUtils.debugDesktopOverride = true);
  tearDown(() => PointerAnchor.reset());

  Future<void> size(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = MiniPlayer.size;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the song, its seek bar and transport, and fits the mini window', (tester) async {
    await size(tester);
    var returned = 0;
    await tester.pumpWidget(_app(Scaffold(body: MiniPlayerView(onReturn: () => returned++))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Thaniye'), findsOneWidget);
    expect(find.text('Anirudh'), findsOneWidget);
    expect(find.text('1:00'), findsOneWidget);
    expect(find.text('4:00'), findsOneWidget);
    for (final tip in ['Previous', 'Next', 'Back to full player']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    await tester.tap(find.byTooltip('Back to full player'));
    expect(returned, 1);
  });

  testWidgets('transport buttons drive the player', (tester) async {
    await size(tester);
    await tester.pumpWidget(_app(Scaffold(body: MiniPlayerView(onReturn: () {}))));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.tap(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Previous'));
    final p = tester.element(find.byType(MiniPlayerView));
    final fake = ProviderScope.containerOf(p).read(playerProvider.notifier) as _FakePlayer;
    expect([fake.toggles, fake.nexts, fake.prevs], [1, 1, 1]);
  });

  testWidgets('with nothing playing it says so and still offers the way back', (tester) async {
    await size(tester);
    await tester.pumpWidget(_app(Scaffold(body: MiniPlayerView(onReturn: () {})), withSong: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.byTooltip('Back to full player'), findsOneWidget);
  });

  testWidgets('the host keeps the app mounted underneath and swaps the view in and out', (tester) async {
    await size(tester);
    final mini = MiniPlayer(window: _NoWindow());
    await tester.pumpWidget(_app(Scaffold(body: MiniPlayerHost(controller: mini, child: const Text('the app')))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('the app'), findsOneWidget);
    expect(find.text('Thaniye'), findsNothing);
    mini.active.value = true;
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('the app'), findsNothing, reason: 'offstage');
    expect(find.text('the app', skipOffstage: false), findsOneWidget, reason: 'state is kept');
    expect(find.text('Thaniye'), findsOneWidget);
    mini.active.value = false;
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('the app'), findsOneWidget);
  });
}
