// test/replay_screen_test.dart
//
// Widget tests for the ReplayScreen and ReplayProvider data model.
// Follows the flutter-add-widget-test skill workflow.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/providers/replay_provider.dart';
import 'package:navivibe/screens/replay_screen.dart';
import 'package:navivibe/core/theme.dart';

// ---------------------------------------------------------------------------
// Helpers — stub providers with known data so tests are deterministic.
// ---------------------------------------------------------------------------

final _fakeSongs = [
  ReplaySong(
    songId: '1',
    title: 'Test Song One',
    artist: 'Artist A',
    albumName: 'Album X',
    playCount: 12,
    totalMinutesSec: 3600, // 1h
  ),
  ReplaySong(
    songId: '2',
    title: 'Test Song Two',
    artist: 'Artist B',
    albumName: 'Album Y',
    playCount: 8,
    totalMinutesSec: 900, // 15m
  ),
];

final _fakeStats = ReplayStats(
  totalSec: 4500,
  uniqueArtists: 2,
  uniqueSongs: 2,
  topGenre: 'Pop',
);

final _fakeData = ReplayData(songs: _fakeSongs, stats: _fakeStats);
final _emptyData = const ReplayData(
  songs: [],
  stats: ReplayStats(totalSec: 0, uniqueArtists: 0, uniqueSongs: 0),
);

// Override providers to return stub data synchronously.
final _monthlyOverride = monthlyReplayProvider.overrideWith(
  (ref) => Future.value(_fakeData),
);
final _weeklyOverride = weeklyReplayProvider.overrideWith(
  (ref) => Future.value(_emptyData),
);

Widget _buildTestApp({List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? [_monthlyOverride, _weeklyOverride],
    child: ThemeTokens(
      tokens: ThemeVariants.spotify(),
      child: MaterialApp(theme: AppTheme.darkTheme, home: const ReplayScreen()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('hive_test_replay');
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  // ── Step 1: ReplaySong.listeningLabel ─────────────────────────────────────
  group('ReplaySong.listeningLabel', () {
    test('formats hours and minutes correctly', () {
      final song = ReplaySong(
        songId: 'x',
        title: '',
        artist: '',
        albumName: '',
        playCount: 1,
        totalMinutesSec: 3660,
      );
      expect(song.listeningLabel, '1h 1m');
    });

    test('shows only minutes when under 1 hour', () {
      final song = ReplaySong(
        songId: 'x',
        title: '',
        artist: '',
        albumName: '',
        playCount: 1,
        totalMinutesSec: 720,
      );
      expect(song.listeningLabel, '12m');
    });
  });

  // ── Step 2: ReplayStats.totalTimeLabel ────────────────────────────────────
  group('ReplayStats.totalTimeLabel', () {
    test('formats total time with hours', () {
      const stats = ReplayStats(
        totalSec: 7200,
        uniqueArtists: 1,
        uniqueSongs: 1,
      );
      expect(stats.totalTimeLabel, '2h 0m');
    });
  });

  // ── Step 3: Screen renders top songs ──────────────────────────────────────
  group('ReplayScreen', () {
    testWidgets('renders Monthly tab with song titles', (tester) async {
      // Step 1: Build the widget
      await tester.pumpWidget(_buildTestApp());

      // Step 2: Wait for async FutureProvider to settle
      await tester.pumpAndSettle();

      // Step 3: Verify tab bar rendered
      expect(find.byType(TabBar), findsOneWidget);

      // Step 4: Verify at least one song title from fake data is visible
      expect(find.text('Test Song One'), findsOneWidget);
      expect(find.text('Artist A'), findsOneWidget);
    });

    testWidgets('shows listening time badge', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      // The 3600-second song should display "1h 0m"
      expect(find.text('1h 0m'), findsWidgets);
    });

    testWidgets('shows empty state on Weekly tab when no data', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      // Step 5: Tap the "This Week" tab
      await tester.tap(find.text('This Week'));
      await tester.pumpAndSettle();

      // Step 6: Empty hint should appear
      expect(find.textContaining('Listen more this week'), findsOneWidget);
    });

    testWidgets('Play All button is present on Monthly tab', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ElevatedButton, 'Play All'), findsOneWidget);
    });

    testWidgets('stats card shows unique artists count', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      // Unique artists = 2
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('rank numbers 1 and 2 are visible', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('#1'), findsNothing); // ReplaySongRow shows "1" not "#1"
      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('replay header contains Replay title', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Replay'), findsOneWidget);
    });
  });

  // ── Step 4: MiniPlayer progress painter semantics ─────────────────────────
  group('ReplaySong data model', () {
    test('empty ReplayData.isEmpty is true', () {
      expect(_emptyData.isEmpty, isTrue);
    });

    test('non-empty ReplayData.isEmpty is false', () {
      expect(_fakeData.isEmpty, isFalse);
    });
  });
}
