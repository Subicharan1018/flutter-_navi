// Search results read top to bottom: Songs, Playlists, Albums (films, when
// they land, go between Songs and Playlists), then artists.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/local_library/logic/local_library_providers.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/lyrics/controllers/lyrics_search_provider.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/artist.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/search_results.dart';
import 'package:navivibe/providers/composer_provider.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/search_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/search_screen.dart';
import 'package:navivibe/utils/platform_utils.dart';

import '../helpers/test_utils.dart';
import 'mini_player_fakes.dart' show FakeSettings, FakeSubsonic;

Playlist _list(String id, String name) =>
    Playlist(id: id, name: name, comment: '', songCount: 3, duration: 600);

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_search_order');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.audio = await Hive.openBox('audio');
  });
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  Future<void> pump(WidgetTester tester, SearchResults results) async {
    PlatformUtils.debugDesktopOverride = true;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'monsoon'),
          searchProvider.overrideWith((ref, q) async => results),
          composerSearchProvider.overrideWith((ref, q) => const []),
          lyricsSearchProvider.overrideWith((ref, q) async => const []),
          localSearchProvider.overrideWith((ref, q) async => const []),
          onlineFetchEnabledProvider.overrideWith((ref) async => false),
          playlistsProvider.overrideWith(
            (ref) async => [_list('p1', 'Monsoon Drive'), _list('p2', 'Gym')],
          ),
          subsonicServiceProvider.overrideWithValue(FakeSubsonic()),
          settingsProvider.overrideWith((ref) => FakeSettings()),
        ],
        child: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(
            theme: AppTheme.build(AppThemeTokens.fallback),
            home: const SearchScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('Songs, then Playlists, then Albums, then Artists', (
    tester,
  ) async {
    await pump(
      tester,
      SearchResults(
        songs: [makeSong(id: 's1', title: 'Monsoon Song')],
        albums: [
          Album(
            id: 'a1',
            name: 'Monsoon Line',
            artist: 'X',
            coverArt: 'a1',
            songCount: 3,
            duration: 600,
            year: 2024,
          ),
        ],
        artists: [Artist(id: 'r1', name: 'Monsoon Band', albumCount: 1)],
      ),
    );
    double y(String heading) => tester.getTopLeft(find.text(heading)).dy;
    expect(y('Songs'), lessThan(y('Playlists')));
    expect(y('Playlists'), lessThan(y('Albums')));
    expect(y('Albums'), lessThan(y('Artists')));
    expect(find.text('Monsoon Drive'), findsOneWidget);
    expect(find.text('Gym'), findsNothing);
    // The song table keeps the page's margin on both sides.
    expect(
      tester.getTopLeft(find.text('#')).dx,
      greaterThanOrEqualTo(Space.xxl),
    );
    expect(
      tester.getTopRight(find.text('Time')).dx,
      lessThanOrEqualTo(900 - Space.xxl),
    );
    await close(tester);
  });

  testWidgets('a search that only matches a playlist still shows it', (
    tester,
  ) async {
    await pump(tester, SearchResults.empty);
    expect(find.text('Monsoon Drive'), findsOneWidget);
    await close(tester);
  });
}
