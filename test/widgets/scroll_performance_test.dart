import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/smooth_wheel.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/desktop/window_ground.dart';
import 'package:navivibe/widgets/table/song_table.dart';

Song _s(int i) => Song(
      id: 's$i',
      title: 'Song $i',
      artist: 'Artist $i',
      album: 'Album ${i % 7}',
      coverArt: 's$i',
      duration: 200 + i,
      track: i,
      year: 2024,
      suffix: 'flac',
      bitRate: 900,
      created: DateTime(2024, 1 + i % 12, 5),
    );

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer(List<Song> queue, int index)
      : super(PlayerState(
          queue: queue,
          currentIndex: index,
          isPlaying: true,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: const [],
          history: const [],
          syncMode: SyncMode.activeHere,
        ));
  void setPlaying(bool v) => state = state.copyWith(isPlaying: v);
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

/// Counts how often each widget type builds, split into first builds and
/// rebuilds of an element that was already built.
class _Counter {
  final firstBuilds = <String, int>{};
  final rebuilds = <String, int>{};
  final _seen = HashSet<Element>.identity();

  /// Starts counting. Elements already in the tree count as built once.
  void install(WidgetTester tester) {
    _seen
      ..clear()
      ..addAll(tester.allElements);
    debugOnRebuildDirtyWidget = (element, _) {
      final name = element.widget.runtimeType.toString();
      final m = _seen.add(element) ? firstBuilds : rebuilds;
      m[name] = (m[name] ?? 0) + 1;
    };
  }

  void reset() {
    firstBuilds.clear();
    rebuilds.clear();
  }

  void uninstall() => debugOnRebuildDirtyWidget = null;
}

void main() {
  setUp(() => PlatformUtils.debugDesktopOverride = true);
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    PointerAnchor.reset();
  });

  group('song table while scrolling', () {
    late List<Song> songs;
    late _FakePlayer player;
    final counter = _Counter();

    Future<ScrollController> pumpTable(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1366, 768);
      addTearDown(tester.view.reset);
      songs = [for (var i = 0; i < 1000; i++) _s(i)];
      player = _FakePlayer(songs, 3);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        PointerAnchor(
          child: ProviderScope(
            overrides: [
              playerProvider.overrideWith((ref) => player),
              subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
              catalogSongProvider.overrideWith((ref, id) => null),
            ],
            child: MaterialApp(
              theme: AppTheme.build(AppThemeTokens.fallback),
              builder: (c, child) => ThemeTokens(tokens: AppThemeTokens.fallback, child: child!),
              home: Scaffold(
                body: CustomScrollView(
                  controller: controller,
                  // ignore: deprecated_member_use
                  cacheExtent: 900,
                  slivers: [SongTableSliver(songs: songs, onPlay: (_, _) {}, showDateAdded: true)],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return controller;
    }

    tearDown(counter.uninstall);

    testWidgets('scrolling never rebuilds a row that stays on screen', (tester) async {
      final controller = await pumpTable(tester);
      counter.install(tester);
      counter.reset();
      // 40 frames of a steady glide, 24 px a frame (~1400 px/s).
      for (var i = 0; i < 40; i++) {
        controller.jumpTo(controller.offset + 24);
        await tester.pump(const Duration(milliseconds: 16));
      }
      // A row is built when it first scrolls in, and not again while it stays.
      expect(counter.rebuilds['_Row'] ?? 0, 0, reason: 'rows that stay mounted must not rebuild on scroll');
      // ~960 px = 20 rows scrolled in; the build-ahead means a bounded handful, not a whole screen a frame.
      expect(counter.firstBuilds['_Row'] ?? 0, lessThanOrEqualTo(24));
      expect(counter.firstBuilds['_Row'] ?? 0, greaterThan(0));
    });

    testWidgets('hovering a row rebuilds that row only', (tester) async {
      await pumpTable(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1000, 5));
      addTearDown(mouse.removePointer);
      counter.install(tester);
      counter.reset();
      await mouse.moveTo(tester.getCenter(find.text('Song 6')));
      await tester.pump();
      expect(counter.rebuilds['_Row'] ?? 0, 1);
      await mouse.moveTo(tester.getCenter(find.text('Song 7')));
      await tester.pump();
      expect(counter.rebuilds['_Row'] ?? 0, 3, reason: 'leave one row, enter the next: one rebuild each');
    });

    testWidgets('play / pause rebuilds the playing row, not the table', (tester) async {
      await pumpTable(tester);
      counter.install(tester);
      counter.reset();
      player.setPlaying(false);
      await tester.pump();
      expect(counter.rebuilds['_Row'] ?? 0, lessThanOrEqualTo(1));
      expect(counter.rebuilds['SongTableSliver'] ?? 0, 0);
    });
  });

  group('eased wheel', () {
    Future<ScrollController> pumpList(WidgetTester tester, {Axis axis = Axis.vertical}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 600);
      addTearDown(tester.view.reset);
      final c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView.builder(
            controller: c,
            scrollDirection: axis,
            itemExtent: 50,
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(width: 50, height: 50, child: Text('$i')),
          ),
        ),
      );
      return c;
    }

    bool wheel(WidgetTester tester, double dy, {double dx = 0}) {
      final result = HitTestResult();
      tester.binding.hitTestInView(result, const Offset(300, 300), tester.view.viewId);
      return SmoothWheel.handle(
        PointerScrollEvent(position: const Offset(300, 300), scrollDelta: Offset(dx, dy)),
        result,
      );
    }

    testWidgets('a notch glides over several frames instead of jumping', (tester) async {
      final c = await pumpList(tester);
      expect(wheel(tester, 100), isTrue);
      expect(c.offset, 0, reason: 'nothing moves in the frame the notch arrives');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(c.offset, inExclusiveRange(1, 99), reason: 'part way after 60 ms');
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.offset, closeTo(100, 0.5));
    });

    testWidgets('notches in a row add up while gliding', (tester) async {
      final c = await pumpList(tester);
      wheel(tester, 100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      wheel(tester, 100);
      wheel(tester, 100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(c.offset, closeTo(300, 0.5));
    });

    testWidgets('at the end of a list the wheel is left for Flutter', (tester) async {
      final c = await pumpList(tester);
      c.jumpTo(c.position.maxScrollExtent);
      await tester.pump();
      expect(wheel(tester, 100), isFalse);
      expect(wheel(tester, -100), isTrue, reason: 'back up from the end still glides');
    });

    testWidgets('a horizontal shelf ignores the up/down wheel', (tester) async {
      final c = await pumpList(tester, axis: Axis.horizontal);
      expect(wheel(tester, 100), isFalse);
      expect(c.offset, 0);
    });
  });

  testWidgets('the window gradient is its own layer and does not hold the page', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => ThemeTokens(tokens: AppThemeTokens.fallback, child: child!),
        home: const WindowGround(tint: Color(0xFF204060), fallback: Color(0xFF000000), child: Text('page')),
      ),
    );
    final gradient = find.byWidgetPredicate(
      (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient != null,
    );
    expect(gradient, findsOneWidget);
    expect(find.ancestor(of: gradient, matching: find.byType(RepaintBoundary)), findsWidgets);
    expect(find.descendant(of: gradient, matching: find.text('page')), findsNothing);
  });
}
