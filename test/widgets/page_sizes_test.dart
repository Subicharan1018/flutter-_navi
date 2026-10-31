import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/ai_shuffle/ui/ai_shuffle_screen.dart';
import 'package:navivibe/features/social/ui/jam/jam_tab.dart';
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
];

void main() {
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
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        PlatformUtils.debugTvOverride = null;
        expect(failures, isEmpty, reason: '$pageName overflowed');
      });
    }
  }
}
