import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/ai_shuffle/ui/ai_shuffle_screen.dart';
import 'package:navivibe/features/social/ui/jam/jam_tab.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/screens/album_details_screen.dart';
import 'package:navivibe/screens/home_screen.dart';
import 'package:navivibe/screens/library/albums_page.dart';
import 'package:navivibe/screens/library/playlists_page.dart';
import 'package:navivibe/screens/library/songs_page.dart';
import 'package:navivibe/screens/library_screen.dart';
import 'package:navivibe/screens/replay/replay_screen.dart';
import 'package:navivibe/screens/search_screen.dart';
import 'package:navivibe/screens/settings_screen.dart';
import 'package:navivibe/screens/stats/stats_screen.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/tv_frame.dart';

/// Every main page at every size NaviVibe is meant to fit. The pages are built
/// with their real providers and no server, so what renders is the loading,
/// empty or error state: still the same layout containers, and the part that
/// must never overflow or clip.
const _sizes = <(String, Size)>[
  ('phone 360x640', Size(360, 640)),
  ('phone 393x852', Size(393, 852)),
  ('phone 430x932', Size(430, 932)),
  ('phone landscape 852x393', Size(852, 393)),
  ('tablet 800x1280', Size(800, 1280)),
  ('desktop 1280x720', Size(1280, 720)),
  ('desktop 1366x768', Size(1366, 768)),
  ('desktop 1920x1080', Size(1920, 1080)),
  ('desktop 2560x1440', Size(2560, 1440)),
];

final _pages = <(String, Widget Function())>[
  ('Home', () => const HomeScreen()),
  ('Search', () => const SearchScreen()),
  ('Library', () => const LibraryScreen()),
  ('Playlists', () => const PlaylistsPage()),
  ('Albums', () => const AlbumsPage()),
  ('Songs', () => const SongsPage()),
  ('Replay', () => const ReplayScreen()),
  ('Settings', () => const SettingsScreen()),
  ('Jam', () => const JamTabScreen()),
  ('Stats', () => const StatsScreen()),
  ('Smart Shuffle', () => const AiShuffleScreen()),
  (
    'Album',
    () => AlbumDetailsScreen(
          album: Album(id: 'a1', name: 'A very long album title that has to wrap or ellipsise somewhere', artist: 'An Artist With A Long Name', coverArt: 'a1', songCount: 12, duration: 2400, year: 2024),
        ),
  ),
];

void main() {
  tvSizes();
  artScale();
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_pages');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  for (final (pageName, build) in _pages) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('$pageName fits every size at text ×$scale', (tester) async {
        final failures = <String>[];
        for (final (label, size) in _sizes) {
          PlatformUtils.debugTvOverride = false;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          final errors = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = errors.add;
          await tester.pumpWidget(ProviderScope(
            child: MaterialApp(
              builder: (context, child) => ThemeTokens(
                tokens: AppThemeTokens.fallback,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
              home: build(),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpWidget(const SizedBox()); // dispose before the next size
          await tester.pump(const Duration(milliseconds: 50));
          FlutterError.onError = previous;
          for (final e in errors) {
            final text = e.exceptionAsString();
            if (text.contains('overflowed')) failures.add('$label: ${text.split('\n').take(1).join(' | ')}');
          }
        }
        await tester.pump(const Duration(seconds: 30)); // let retry back-off timers run out
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        PlatformUtils.debugTvOverride = null;
        expect(failures, isEmpty, reason: '$pageName overflowed');
      });
    }
  }
}

/// The TV is laid out on its own 1280-wide canvas (TvFrame); the key pages must
/// fit it at the densities TVs report.
void tvSizes() {
  for (final (pageName, build) in [
    ('Home', () => const HomeScreen() as Widget),
    ('Library', () => const LibraryScreen()),
    ('Search', () => const SearchScreen()),
  ]) {
    testWidgets('$pageName fits the TV canvas', (tester) async {
      final failures = <String>[];
      for (final s in const [(Size(960, 540), 2.0), (Size(1280, 720), 1.5), (Size(1920, 1080), 1.0)]) {
        PlatformUtils.debugTvOverride = true;
        tester.view.devicePixelRatio = s.$2;
        tester.view.physicalSize = s.$1 * s.$2;
        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            builder: (context, child) =>
                ThemeTokens(tokens: AppThemeTokens.fallback, child: TvFrame(child: child!)),
            home: build(),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 50));
        FlutterError.onError = previous;
        for (final e in errors) {
          if (e.exceptionAsString().contains('overflowed')) failures.add('${s.$1} @${s.$2}: ${e.exceptionAsString().split('\n').first}');
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      PlatformUtils.debugTvOverride = null;
      expect(failures, isEmpty);
    });
  }
}

void artScale() {
  test('one cover scale per platform: bigger for a sofa, richer on desktop, never inverted', () {
    for (final a in [ArtSize.phone, ArtSize.desktop, ArtSize.tv]) {
      expect(a.thumb, lessThan(a.tile));
      expect(a.player, lessThan(a.tile));
      expect(a.tile, lessThan(a.header + 60));
    }
    expect(ArtSize.tv.thumb, greaterThan(ArtSize.phone.thumb));
    expect(ArtSize.tv.tile, greaterThan(ArtSize.phone.tile));
    expect(ArtSize.desktop.panel, greaterThan(0));
    expect(ArtSize.phone.panel, 0);
  });
}
