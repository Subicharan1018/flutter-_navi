/// The whole artist page (header, Latest Release, Top Songs, With You, Albums
/// by year) with realistic data and textured stand-in covers.
/// Phone 390×844 @3x and Windows 1280×800.
///
///   flutter test test/goldens/artist_screen_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/artist_run/logic/artist_run.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/artwork.dart' show coverPaletteProvider, debugCoverImageOverride;
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/artist_screen.dart';
import 'package:navivibe/services/subsonic_service.dart';

import 'fake_covers.dart';
import 'golden_fonts.dart';

class _Subsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => 'c${(id ?? '0').hashCode.abs() % 9}';
}

class _Player extends StateNotifier<PlayerState> implements PlayerNotifier {
  _Player()
      : super(const PlayerState(
          queue: [],
          currentIndex: 0,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: [],
        ));
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

Album _a(int i, String name, int year, int songs) =>
    Album(id: 'al$i', name: name, artist: 'Anirudh Ravichander', coverArt: 'al$i', songCount: songs, duration: 0, year: year);

Song _s(int i, String title, String album) => Song(
  id: 's$i',
  title: title,
  artist: 'Anirudh Ravichander',
  album: album,
  coverArt: 'al$i',
  duration: 230,
  track: i,
  year: 2023,
);

final _albums = [
  _a(1, 'Jailer', 2023, 7),
  _a(2, 'Leo', 2023, 11),
  _a(3, 'Jawan', 2023, 9),
  _a(4, 'Master', 2021, 10),
  _a(5, 'Doctor', 2021, 6),
  _a(6, 'Vikram', 2022, 8),
  _a(7, 'Petta', 2019, 12),
  _a(8, 'Maari', 2015, 9),
  _a(9, 'Vedalam', 2015, 7),
  _a(10, '3', 2012, 10),
];

final _top = [
  _s(1, 'Hukum', 'Jailer'),
  _s(2, 'Badass', 'Leo'),
  _s(3, 'Chaleya', 'Jawan'),
  _s(4, 'Vaathi Coming', 'Master'),
  _s(5, 'Why This Kolaveri Di', '3'),
];

ArtistHistory _history() => ArtistHistory.from([
  for (var i = 0; i < 42; i++)
    ArtistPlay(song: 'Hukum', album: 'Jailer', at: DateTime(2023, 8, 1 + i % 25), seconds: 200),
  for (var i = 0; i < 25; i++)
    ArtistPlay(song: 'Vaathi Coming', album: 'Master', at: DateTime(2024, 2, 1 + i), seconds: 210),
  for (var i = 0; i < 13; i++)
    ArtistPlay(song: 'Why This Kolaveri Di', album: '3', at: DateTime(2025, 5, 1 + i), seconds: 220),
  ArtistPlay(song: 'Badass', album: 'Leo', at: DateTime(2026, 11, 18), seconds: 180),
]);

Widget _app() {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: [
      subsonicServiceProvider.overrideWithValue(_Subsonic()),
      playerProvider.overrideWith((ref) => _Player()),
      artistPageProvider.overrideWith((ref, key) async => (albums: _albums, top: _top)),
      artistHistoryProvider.overrideWith((ref, name) async => _history()),
      coverPaletteProvider.overrideWith((ref, id) async => AlbumPalette.fallback),
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(tokens),
        home: const ArtistScreen(artistId: 'ar1', name: 'Anirudh Ravichander'),
      ),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() => debugCoverImageOverride = null);

  Future<void> load(WidgetTester tester, Size logical, double dpr) async {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final sw = await tester.runAsync(() => texturedCovers());
    debugCoverImageOverride = (url, key) => sw![url] ?? sw['c0']!;
    await tester.pumpWidget(_app());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
  }

  testWidgets('artist page, phone', (tester) async {
    await load(tester, const Size(390, 1500), 2);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('artist_screen/artist_phone.png'));
  });

  testWidgets('artist page, windows', (tester) async {
    await load(tester, const Size(1280, 1100), 1);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('artist_screen/artist_windows.png'));
  });
}
