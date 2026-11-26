// The whole Now Playing screen: where the queue's mode buttons sit, the output
// name, and the move between the two layouts (and its reduced-motion path).
// No image comparisons, so this runs in CI too (see player_surfaces_test.dart
// for the pictures).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/artwork.dart';
import 'package:navivibe/player/player_controls.dart' show TransportControls;
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/now_playing_screen.dart';
import 'package:navivibe/services/output_route.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/mascot/microduck_strip.dart' show microduckTrackKey;

Song _s(String id) => Song(id: id, title: 'Title $id', artist: 'Artist', album: 'Album', coverArt: id, duration: 200, track: 1, year: 2024);

class _FakeAudioPlayer extends Fake implements AudioPlayer {
  @override
  Duration get position => const Duration(seconds: 20);
  @override
  Stream<Duration> get positionStream => Stream.value(position);
  @override
  Duration? get duration => null;
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  double get volume => 0.6;
  @override
  Stream<double> get volumeStream => Stream.value(volume);
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer()
      : super(PlayerState(
          queue: [_s('a'), _s('b'), _s('c')],
          currentIndex: 1,
          isPlaying: true,
          shuffleMode: true,
          autoplayMode: true,
          repeatMode: LoopMode.off,
          starredIds: const [],
          history: const [],
          syncMode: SyncMode.standalone,
        ));
  final _audio = _FakeAudioPlayer();
  @override
  AudioPlayer get player => _audio;
  @override
  String? get currentPlaylistName => null;
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://x', username: 'u', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => 'cover://$id';
}

class _NoArtwork extends NowPlayingArtworkNotifier {
  @override
  ArtworkData? build() => null;
}

class _FixedRoute extends OutputRouteNotifier {
  @override
  OutputRoute? build() => const OutputRoute(RouteKind.bluetooth, 'OnePlus Buds Pro');
}

const _phone = Size(390, 844);

Future<void> _pumpScreen(WidgetTester tester, {Size size = _phone, bool reduced = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tokens = AppThemeTokens.fallback;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      playerProvider.overrideWith((ref) => _FakePlayer()),
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      nowPlayingArtworkProvider.overrideWith(_NoArtwork.new),
      outputRouteProvider.overrideWith(_FixedRoute.new),
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        theme: AppTheme.build(tokens),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: const NowPlayingScreen(),
          ),
        ),
      ),
    ),
  ));
  await _wait(tester);
}

/// The screen never "settles" (the field drifts, titles scroll), so wait a while.
Future<void> _wait(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Finder _named(String type) => find.byWidgetPredicate((w) => w.runtimeType.toString() == type);

void main() {
  setUp(() {
    PlatformUtils.debugDesktopOverride = false;
    debugCoverImageOverride = (url, key) => const AssetImage('assets/none.png');
  });
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    debugCoverImageOverride = null;
  });

  double coverWidth(WidgetTester tester) => tester.getSize(_named('_Cover').first).width;

  testWidgets('queue mode buttons sit in thumb reach, above the scrubber and clear of the transport', (tester) async {
    await _pumpScreen(tester);
    await tester.tap(find.bySemanticsLabel('Queue').first);
    await _wait(tester);
    tester.takeException(); // the missing test cover

    final footer = tester.getRect(find.byKey(const ValueKey('queue_mode_footer')));
    final scrubber = tester.getRect(find.byKey(microduckTrackKey));
    final transport = tester.getRect(find.byType(TransportControls));
    final header = tester.getRect(find.text('Playing Next'));
    expect(footer.top, greaterThan(_phone.height * 0.5), reason: 'the lower half, where a thumb is');
    expect(footer.top, greaterThan(header.bottom + 100), reason: 'no longer under the header');
    expect(footer.bottom, lessThanOrEqualTo(scrubber.top + 1));
    expect(transport.top - footer.bottom, greaterThanOrEqualTo(24), reason: 'the scrubber keeps them apart');
    for (final label in ['Shuffle on', 'Repeat off', 'Autoplay on', 'Smart Reshuffle']) {
      final button = find.bySemanticsLabel(label);
      expect(button, findsOneWidget, reason: label);
      expect(footer.contains(tester.getCenter(button)), isTrue, reason: '$label is in the footer');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48), reason: '$label is easy to hit');
    }
    await _unmount(tester);
  });

  testWidgets('the output name sits under the devices button, and the host line is gone', (tester) async {
    await _pumpScreen(tester);
    tester.takeException();
    final name = tester.getRect(find.text('OnePlus Buds Pro'));
    final button = tester.getRect(find.bySemanticsLabel('Playing on OnePlus Buds Pro. Devices'));
    expect(name.top, greaterThanOrEqualTo(button.bottom - 1));
    expect(name.center.dx, closeTo(button.center.dx, 1));
    expect(find.text('This device is the host'), findsNothing);
    // The name never pushes Lyrics and Queue out of line with the middle button.
    expect(tester.getCenter(find.bySemanticsLabel('Lyrics')).dy, closeTo(button.center.dy, 1));
    expect(tester.getCenter(find.bySemanticsLabel('Queue')).dy, closeTo(button.center.dy, 1));
    await _unmount(tester);
  });

  testWidgets('opening the queue is one motion that a second tap turns around', (tester) async {
    await _pumpScreen(tester);
    tester.takeException();
    final big = coverWidth(tester);
    await tester.tap(find.bySemanticsLabel('Queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final mid = coverWidth(tester);
    expect(mid, inExclusiveRange(60, big), reason: 'between the two layouts');

    await tester.tap(find.bySemanticsLabel('Queue'));
    await tester.pump();
    expect(coverWidth(tester), closeTo(mid, 2), reason: 'turns around from where it was');
    await _wait(tester);
    expect(coverWidth(tester), closeTo(big, 0.5));
    expect(find.byKey(const ValueKey('queue_mode_footer')), findsNothing, reason: 'the pane is gone once closed');

    // Fully closed means closed: the cover takes the carousel swipe again.
    final swipe = await tester.startGesture(tester.getCenter(_named('_Cover').first));
    await swipe.moveBy(const Offset(-40, 0));
    await swipe.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(_named('_SideCover'), findsWidgets);
    await swipe.up();
    await _wait(tester);
    await _unmount(tester);
  });

  testWidgets('with animations removed the layout changes at once', (tester) async {
    await _pumpScreen(tester, reduced: true);
    tester.takeException();
    await tester.tap(find.bySemanticsLabel('Queue'));
    await tester.pump();
    expect(coverWidth(tester), 60, reason: 'no travel');
    await tester.pump(const Duration(milliseconds: 100));
    expect(coverWidth(tester), 60);
    await _wait(tester);
    await _unmount(tester);
  });

  for (final reduced in const [false, true]) {
    testWidgets('wide: closing the pane ${reduced ? 'with animations removed jumps' : 'slides'} to the centre', (tester) async {
      const window = Size(1440, 900);
      await _pumpScreen(tester, size: window, reduced: reduced);
      tester.takeException();
      double x() => tester.getCenter(_named('_Cover').first).dx;
      final beside = x();
      expect(beside, lessThan(window.width / 2));

      await tester.tap(find.bySemanticsLabel('Lyrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      if (reduced) {
        expect(x(), closeTo(window.width / 2, 1));
      } else {
        expect(x(), inExclusiveRange(beside, window.width / 2 - 1), reason: 'travelling, not snapped');
        expect(find.byKey(const ValueKey('np_wide_pane')), findsOneWidget, reason: 'the pane leaves with it');
      }
      await _wait(tester);
      expect(x(), closeTo(window.width / 2, 1));
      expect(find.byKey(const ValueKey('np_wide_pane')), findsNothing);
      await _unmount(tester);
    });
  }
}
