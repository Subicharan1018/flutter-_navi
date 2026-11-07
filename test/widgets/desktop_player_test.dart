import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/desktop/desktop_layout.dart';
import 'package:navivibe/widgets/shell/desktop/now_playing_panel.dart';
import 'package:navivibe/widgets/shell/desktop/player_bar.dart';
import 'package:navivibe/widgets/shell/desktop/resize_handle.dart';
import 'package:navivibe/widgets/shell/shortcuts_help.dart';

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
  double vol = 0.5;
  final volumes = <double>[];
  final seeks = <Duration>[];
  final _volCtl = StreamController<double>.broadcast();

  @override
  double get volume => vol;
  @override
  Stream<double> get volumeStream => _volCtl.stream;
  @override
  Future<void> setVolume(double v) async {
    vol = v;
    volumes.add(v);
  }

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
  Future<void> seek(Duration? position, {int? index}) async => seeks.add(position ?? Duration.zero);
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  final _FakeAudio audio;
  int toggles = 0;
  _FakePlayer(this.audio)
      : super(PlayerState(
          queue: [_song],
          currentIndex: 0,
          isPlaying: true,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: const [],
          history: const [],
          syncMode: SyncMode.activeHere,
        ));
  @override
  AudioPlayer get player => audio;
  @override
  Future<void> togglePlay() async => toggles++;
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

// ignore: library_private_types_in_public_api
late _FakeAudio audio;

Widget _app(Widget child) {
  audio = _FakeAudio();
  final List<Override> overrides = [
    playerProvider.overrideWith((ref) => _FakePlayer(audio)),
    settingsProvider.overrideWith((ref) => _FakeSettings()),
    subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
    catalogSongProvider.overrideWith((ref, id) => null),
  ];
  return PointerAnchor(
    child: ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.build(AppThemeTokens.fallback),
        builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_player5');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
  });
  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  setUp(() {
    PlatformUtils.debugDesktopOverride = true;
    DesktopLayout.debugReset();
  });
  tearDown(() => PointerAnchor.reset());

  Future<void> size(WidgetTester tester, double w, double h) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(w, h);
    addTearDown(tester.view.reset);
  }

  Future<void> bar(WidgetTester tester, {double w = 1366, void Function(PanelKind)? onToggle, PanelKind? panel}) async {
    await size(tester, w, 300);
    await tester.pumpWidget(_app(Align(
      alignment: Alignment.bottomCenter,
      child: DesktopPlayerBar(panel: panel, onTogglePanel: onToggle ?? (_) {}),
    )));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('player bar', () {
    testWidgets('three zones: the song, the transport with time either side, the panels and volume', (tester) async {
      await bar(tester);
      expect(find.text('Thaniye'), findsOneWidget);
      expect(find.text('Anirudh'), findsOneWidget);
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget, reason: 'elapsed beside the bar');
      expect(find.text('4:00'), findsOneWidget, reason: 'total beside the bar');
      for (final tip in ['Lyrics', 'Queue', 'About this song', 'Mute (M)']) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      expect(tester.getSize(find.byType(DesktopPlayerBar)).height, DesktopPlayerBar.height);
    });

    testWidgets('the panel buttons report which panel was asked for', (tester) async {
      final asked = <PanelKind>[];
      await bar(tester, onToggle: asked.add);
      await tester.tap(find.byTooltip('Lyrics'));
      await tester.tap(find.byTooltip('Queue'));
      await tester.tap(find.byTooltip('About this song'));
      expect(asked, [PanelKind.lyrics, PanelKind.queue, PanelKind.about]);
    });

    testWidgets('play toggles; the button is a small round control', (tester) async {
      await bar(tester);
      await tester.tap(find.bySemanticsLabel('Pause'));
      final container = tester.container();
      expect((container.read(playerProvider.notifier) as _FakePlayer).toggles, 1);
      expect(tester.getSize(find.bySemanticsLabel('Pause')).width, lessThanOrEqualTo(40));
    });

    testWidgets('fits from 700 to 1920 wide', (tester) async {
      for (final w in [700.0, 900.0, 1100.0, 1366.0, 1920.0]) {
        await bar(tester, w: w);
        expect(tester.takeException(), isNull, reason: 'width $w');
      }
    });
  });

  group('seek bar', () {
    testWidgets('hovering names the time under the pointer; leaving hides it', (tester) async {
      await bar(tester);
      final seek = find.byType(DesktopSeekBar);
      final box = tester.getRect(find.descendant(of: seek, matching: find.byType(GestureDetector)).first);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      expect(find.byKey(const Key('seek-preview')), findsNothing);
      await mouse.moveTo(Offset(box.left + box.width * 0.5, box.center.dy));
      await tester.pump();
      expect(find.byKey(const Key('seek-preview')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('seek-preview')), matching: find.text('2:00')), findsOneWidget);
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(find.byKey(const Key('seek-preview')), findsNothing);
    });

    testWidgets('a click seeks to that point', (tester) async {
      await bar(tester);
      final box = tester.getRect(find.descendant(of: find.byType(DesktopSeekBar), matching: find.byType(GestureDetector)).first);
      await tester.tapAt(Offset(box.left + box.width * 0.75, box.center.dy));
      await tester.pump();
      expect(audio.seeks.single.inSeconds, closeTo(180, 2));
    });

    testWidgets('dragging seeks once, where it ends', (tester) async {
      await bar(tester);
      final box = tester.getRect(find.descendant(of: find.byType(DesktopSeekBar), matching: find.byType(GestureDetector)).first);
      final g = await tester.startGesture(Offset(box.left + box.width * 0.2, box.center.dy));
      await g.moveTo(Offset(box.left + box.width * 0.4, box.center.dy));
      await g.moveTo(Offset(box.left + box.width * 0.6, box.center.dy));
      await g.up();
      await tester.pump();
      expect(audio.seeks, hasLength(1));
      expect(audio.seeks.single.inSeconds, closeTo(144, 3));
    });
  });

  group('volume', () {
    testWidgets('the wheel changes it 5% a notch; down is quieter', (tester) async {
      await bar(tester);
      final vol = find.byType(DesktopVolume);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(vol));
      addTearDown(mouse.removePointer);
      await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(vol), scrollDelta: const Offset(0, -100)));
      await tester.pump();
      expect(audio.vol, closeTo(0.55, 0.001));
      await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(vol), scrollDelta: const Offset(0, 100)));
      await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(vol), scrollDelta: const Offset(0, 100)));
      await tester.pump();
      expect(audio.vol, closeTo(0.45, 0.001));
    });

    testWidgets('the wheel stops at 0 and 100%', (tester) async {
      await bar(tester);
      final vol = find.byType(DesktopVolume);
      for (var i = 0; i < 30; i++) {
        await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(vol), scrollDelta: const Offset(0, 100)));
      }
      expect(audio.vol, 0);
      for (var i = 0; i < 30; i++) {
        await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(vol), scrollDelta: const Offset(0, -100)));
      }
      expect(audio.vol, 1);
    });

    testWidgets('the mute button mutes, shows the muted glyph, and restores the level', (tester) async {
      await bar(tester);
      await tester.tap(find.byTooltip('Mute (M)'));
      await tester.pump();
      expect(audio.vol, 0);
      expect(find.byTooltip('Unmute (M)'), findsOneWidget);
      await tester.tap(find.byTooltip('Unmute (M)'));
      await tester.pump();
      expect(audio.vol, closeTo(0.5, 0.001));
    });

    testWidgets('a click on the slider sets the level there', (tester) async {
      await bar(tester);
      final slider = find.descendant(of: find.byType(DesktopVolume), matching: find.byType(GestureDetector)).last;
      final r = tester.getRect(slider);
      await tester.tapAt(Offset(r.left + r.width * 0.8, r.center.dy));
      await tester.pump();
      expect(audio.vol, closeTo(0.8, 0.03));
    });
  });

  group('keyboard shortcuts overlay', () {
    testWidgets('the bar button opens the list, Esc closes it', (tester) async {
      await bar(tester);
      await tester.tap(find.byType(KeyboardHelpButton));
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.text('Play or pause'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsNothing);
    });

    test('every group has rows, and the keys it names exist in the list once', () {
      final all = [for (final (_, rows) in kShortcutGroups) ...rows.map((r) => r.$1)];
      expect(all.toSet().length, all.length, reason: 'no key listed twice');
      expect(all, contains('Ctrl + /'));
      expect(all, contains('Ctrl + K'));
    });
  });

  group('Now Playing panel as an overlay', () {
    Future<void> host(WidgetTester tester, PanelKind? panel, {required List<String> log, double w = 1100, double h = 700}) async {
      await size(tester, w, h);
      await tester.pumpWidget(_app(PanelOverlay(
        panel: panel,
        onChange: (p) => log.add('change ${p.name}'),
        onClose: () => log.add('close'),
        child: const Center(child: Text('content')),
      )));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('closed: just the content, no backdrop', (tester) async {
      await host(tester, null, log: []);
      expect(find.text('content'), findsOneWidget);
      expect(find.byKey(const Key('panel-backdrop')), findsNothing);
      expect(find.byType(NowPlayingPanel), findsNothing);
    });

    testWidgets('open: the panel sits at the right edge over the content, as wide as the saved width', (tester) async {
      DesktopLayout.dragPanel(400);
      await host(tester, PanelKind.about, log: []);
      expect(find.text('content'), findsOneWidget);
      expect(find.byType(NowPlayingPanel), findsOneWidget);
      final r = tester.getRect(find.byType(NowPlayingPanel));
      expect(r.right, 1100);
      expect(r.width, 400);
      expect(r.height, 700);
    });

    testWidgets('Esc closes it', (tester) async {
      final log = <String>[];
      await host(tester, PanelKind.about, log: log);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(log, ['close']);
    });

    testWidgets('a click outside closes it; a click inside does not', (tester) async {
      final log = <String>[];
      await host(tester, PanelKind.about, log: log);
      await tester.tapAt(const Offset(100, 300));
      expect(log, ['close']);
      log.clear();
      await tester.tapAt(tester.getCenter(find.byType(NowPlayingPanel)));
      expect(log, isEmpty);
    });

    testWidgets('the close button closes it', (tester) async {
      final log = <String>[];
      await host(tester, PanelKind.about, log: log);
      await tester.tap(find.byTooltip('Close'));
      expect(log, ['close']);
    });

    testWidgets('dragging its edge resizes it, within limits, and the width is remembered', (tester) async {
      await host(tester, PanelKind.about, log: []);
      final before = tester.getSize(find.byType(NowPlayingPanel)).width;
      final handle = tester.getCenter(find.byType(ResizeHandle));
      final g = await tester.startGesture(handle, kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(-30, 0));
      }
      await tester.pump();
      expect(tester.getSize(find.byType(NowPlayingPanel)).width, greaterThan(before + 60));
      await g.moveBy(const Offset(-2000, 0));
      await tester.pump();
      expect(tester.getSize(find.byType(NowPlayingPanel)).width, DesktopLayout.panelMax);
      await g.up();
      await tester.pump(const Duration(seconds: 1));
      expect(HiveBoxes.prefs.get('desktop_panel_width'), DesktopLayout.panelMax);
    });

    testWidgets('the panel switcher reports the other panels', (tester) async {
      final log = <String>[];
      await host(tester, PanelKind.about, log: log);
      await tester.tap(find.text('Queue').first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, contains('change queue'));
    });
  });
}
