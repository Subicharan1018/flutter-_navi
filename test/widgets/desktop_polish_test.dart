import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kSecondaryButton;
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
import 'package:navivibe/player/artwork.dart' show coverPaletteProvider;
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/desktop/desktop_layout.dart';
import 'package:navivibe/widgets/shell/desktop/now_playing_panel.dart';
import 'package:navivibe/widgets/shell/desktop/player_bar.dart';
import 'package:navivibe/widgets/table/song_table.dart';

Song _s(int i) => Song(
      id: 's$i',
      title: 'Song ${String.fromCharCode(64 + i)}',
      artist: 'Artist $i',
      album: 'Album $i',
      coverArt: 's$i',
      duration: 100 + i * 10,
      track: i,
      year: 2024,
      suffix: 'flac',
      bitRate: 900,
      created: DateTime(2024, i, 5),
    );

class _Audio extends Fake implements AudioPlayer {
  @override
  double get volume => 0.5;
  @override
  Stream<double> get volumeStream => const Stream.empty();
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
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  final _audio = _Audio();
  _FakePlayer(bool song)
      : super(PlayerState(
          queue: song ? [_s(1)] : const [],
          currentIndex: song ? 0 : -1,
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

Widget _app(Widget home, {bool song = false, List<Override> extra = const []}) {
  final List<Override> overrides = [
    playerProvider.overrideWith((ref) => _FakePlayer(song)),
    settingsProvider.overrideWith((ref) => _FakeSettings()),
    subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
    catalogSongProvider.overrideWith((ref, id) => null),
    ...extra,
  ];
  return PointerAnchor(
    child: ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.build(AppThemeTokens.fallback),
        builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
        home: Scaffold(body: home),
      ),
    ),
  );
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_polish');
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

  Future<void> click(WidgetTester tester, Finder f, {bool ctrl = false}) async {
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 350));
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }

  group('the soft white', () {
    test('on Windows the filled accent is about 89% of white; elsewhere it is the accent itself', () {
      final t = AppThemeTokens.fallback;
      PlatformUtils.debugDesktopOverride = true;
      final soft = t.accentFill;
      expect(soft, isNot(t.accent));
      expect(soft.r, closeTo(0.89, 0.01));
      PlatformUtils.debugDesktopOverride = false;
      expect(t.accentFill, t.accent, reason: 'the phone and the TV do not change');
    });

    test('the glyph on it keeps at least 4.5:1 contrast', () {
      final t = AppThemeTokens.fallback;
      PlatformUtils.debugDesktopOverride = true;
      double lum(Color c) {
        double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
      }

      final a = lum(t.accentFill), b = lum(t.onAccent);
      final ratio = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    testWidgets('the player bar Play disc is not pure white', (tester) async {
      await size(tester, 1366, 300);
      await tester.pumpWidget(_app(
        Align(alignment: Alignment.bottomCenter, child: DesktopPlayerBar(panel: null, onTogglePanel: (_) {})),
        song: true,
        extra: [coverPaletteProvider('s1').overrideWithValue(const AsyncData(AlbumPalette.fallback))],
      ));
      await tester.pump(const Duration(milliseconds: 600));
      final disc = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle && c.constraints?.maxWidth == 34;
      });
      expect(disc, hasLength(1));
      final color = (disc.single.decoration as BoxDecoration).color!;
      expect(color, isNot(Colors.white));
      expect(color.r, closeTo(0.89, 0.01));
    });
  });

  group('player bar', () {
    Future<void> bar(WidgetTester tester, double w, {List<Override> extra = const []}) async {
      await size(tester, w, 300);
      await tester.pumpWidget(_app(
        Align(alignment: Alignment.bottomCenter, child: DesktopPlayerBar(panel: null, onTogglePanel: (_) {})),
        song: true,
        extra: extra.isEmpty ? [coverPaletteProvider('s1').overrideWithValue(const AsyncData(AlbumPalette.fallback))] : extra,
      ));
      await tester.pump(const Duration(milliseconds: 600));
    }

    Color barColor(WidgetTester tester) {
      final box = find.descendant(of: find.byType(DesktopPlayerBar), matching: find.byType(Container)).first;
      return ((tester.widget<Container>(box).decoration) as BoxDecoration).color!;
    }

    testWidgets('takes the playing cover\'s colour', (tester) async {
      const palette = AlbumPalette(deep: Color(0xFF3B1010), base: Color(0xFF7A2A2A), vibrant: Color(0xFFC04040), glow: Color(0xFFE08080));
      await bar(tester, 1366, extra: [coverPaletteProvider('s1').overrideWithValue(const AsyncData(palette))]);
      final tinted = barColor(tester);
      expect(tinted, isNot(AppThemeTokens.fallback.bgSurface));
      expect(tinted.r, greaterThan(tinted.b), reason: 'a red cover gives a red-leaning bar');
    });

    testWidgets('is the plain surface until a palette arrives', (tester) async {
      await bar(tester, 1366, extra: [coverPaletteProvider.overrideWith((ref, id) => Completer<AlbumPalette>().future)]);
      expect(barColor(tester), AppThemeTokens.fallback.bgSurface);
    });

    testWidgets('the seek bar grows with the window, up to about 720', (tester) async {
      await bar(tester, 1100);
      final narrow = tester.getSize(find.byType(DesktopSeekBar)).width;
      await bar(tester, 1920);
      final wide = tester.getSize(find.byType(DesktopSeekBar)).width;
      expect(wide, greaterThan(narrow));
      expect(wide, lessThanOrEqualTo(720));
      expect(wide, greaterThan(640));
    });

    testWidgets('the right-hand icons are grouped by separators: panels | volume | window', (tester) async {
      await bar(tester, 1366);
      final seps = tester.widgetList<Container>(find.byType(Container)).where((c) => c.constraints?.maxWidth == 1 && c.constraints?.maxHeight == 18);
      expect(seps.length, 2);
    });

    testWidgets('the keyboard-help button does not look toggled (no dot, no fill)', (tester) async {
      await bar(tester, 1366);
      final help = find.byTooltip('Keyboard shortcuts (Ctrl+/)');
      expect(help, findsOneWidget);
      expect(find.descendant(of: help, matching: find.byType(DecoratedBox)).evaluate().where((e) {
        final d = (e.widget as DecoratedBox).decoration;
        return d is BoxDecoration && d.color != null;
      }), isEmpty);
    });
  });

  group('the overlay panel has no shadow and no scrim', () {
    testWidgets('only a hairline and its own ground', (tester) async {
      await size(tester, 1100, 700);
      await tester.pumpWidget(_app(
        PanelOverlay(panel: PanelKind.about, onChange: (_) {}, onClose: () {}, child: const Center(child: Text('content'))),
        song: true,
      ));
      await tester.pump(const Duration(milliseconds: 300));
      // The backdrop catches clicks but paints nothing.
      final backdrop = find.byKey(const Key('panel-backdrop'));
      expect(find.descendant(of: backdrop, matching: find.byType(ColoredBox)), findsNothing);
      // No box shadow anywhere in the panel's frame.
      final shadowed = tester.widgetList<DecoratedBox>(find.descendant(of: find.byType(PanelOverlay), matching: find.byType(DecoratedBox))).where((d) {
        final dec = d.decoration;
        return dec is BoxDecoration && (dec.boxShadow?.isNotEmpty ?? false);
      });
      expect(shadowed, isEmpty);
    });
  });

  group('several rows selected', () {
    late List<Song> removed;
    late List<Song> played;

    Widget table() {
      removed = [];
      played = [];
      return _app(CustomScrollView(slivers: [
        SongTableSliver(
          songs: [for (var i = 1; i <= 5; i++) _s(i)],
          playlistId: 'pl',
          showDateAdded: true,
          onPlay: (s, ordered) => played = ordered,
          onRemove: (l) => removed.addAll(l),
        ),
      ]));
    }

    testWidgets('the header becomes a bar with the count, Play, Add to, Remove and Clear', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      expect(find.textContaining('selected'), findsNothing);
      await click(tester, find.text('Song A'));
      expect(find.textContaining('selected'), findsNothing, reason: 'one row is not a group');
      await click(tester, find.text('Song C'), ctrl: true);
      expect(find.text('2 selected'), findsOneWidget);
      for (final a in ['Play', 'Add to…', 'Remove', 'Clear']) {
        expect(find.text(a), findsOneWidget, reason: a);
      }
      expect(find.text('Title'), findsNothing, reason: 'the bar replaces the column labels while rows are picked');
    });

    testWidgets('Play plays the picked rows, Remove removes them, Clear clears', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      await click(tester, find.text('Song A'));
      await click(tester, find.text('Song B'), ctrl: true);
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect([for (final s in played) s.title], ['Song A', 'Song B']);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect([for (final s in removed) s.title], ['Song A', 'Song B']);
      expect(find.textContaining('selected'), findsNothing);

      await click(tester, find.text('Song C'));
      await click(tester, find.text('Song D'), ctrl: true);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(find.textContaining('selected'), findsNothing);
      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('Add to… offers the queue and a playlist', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      await click(tester, find.text('Song A'));
      await click(tester, find.text('Song B'), ctrl: true);
      await tester.tap(find.text('Add to…'));
      await tester.pumpAndSettle();
      for (final a in ['Play Next', 'Add to Queue', 'A Playlist…']) {
        expect(find.text(a), findsOneWidget, reason: a);
      }
    });
  });

  group('choosing columns', () {
    Widget table() => _app(CustomScrollView(slivers: [
          SongTableSliver(songs: [for (var i = 1; i <= 3; i++) _s(i)], showDateAdded: true, onPlay: (a, b) {}),
        ]));

    testWidgets('the header\'s button lists the optional columns; turning one off hides it, and the choice is remembered', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      expect(find.text('Album'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      await tester.tap(find.byTooltip('Choose columns'));
      await tester.pumpAndSettle();
      expect(find.text('Date added'), findsOneWidget);
      await tester.tap(find.text('Album').last); // the menu row (the header label is the other one)
      await tester.pumpAndSettle();
      expect(find.text('Album'), findsNothing);
      expect(find.text('Added'), findsOneWidget);
      expect(DesktopLayout.hiddenColumns.value, {'album'});
      expect(HiveBoxes.prefs.get('desktop_table_hidden_columns'), ['album']);
      // And back.
      await tester.tap(find.byTooltip('Choose columns'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album'));
      await tester.pumpAndSettle();
      expect(find.text('Album'), findsOneWidget, reason: 'back as a header label');
    });

    testWidgets('a table with neither optional column has no chooser', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(CustomScrollView(slivers: [
        SongTableSliver(songs: [_s(1)], showAlbum: false, onPlay: (a, b) {}),
      ])));
      expect(find.byTooltip('Choose columns'), findsNothing);
    });
  });

  group('key hints in the right-click menu', () {
    testWidgets('a song in a playlist shows L for Favorite and Del for Remove', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(CustomScrollView(slivers: [
        SongTableSliver(songs: [for (var i = 1; i <= 3; i++) _s(i)], playlistId: 'pl', onRemove: (_) {}, onPlay: (a, b) {}),
      ])));
      await tester.tapAt(tester.getCenter(find.text('Song B')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('L'), findsOneWidget);
      expect(find.text('Del'), findsOneWidget);
    });

    testWidgets('the group menu shows Enter for Play and Del for Remove', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(CustomScrollView(slivers: [
        SongTableSliver(songs: [for (var i = 1; i <= 3; i++) _s(i)], playlistId: 'pl', onRemove: (_) {}, onPlay: (a, b) {}),
      ])));
      await click(tester, find.text('Song A'));
      await click(tester, find.text('Song B'), ctrl: true);
      await tester.tapAt(tester.getCenter(find.text('Song B')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Enter'), findsOneWidget);
      expect(find.text('Del'), findsOneWidget);
    });
  });
}
