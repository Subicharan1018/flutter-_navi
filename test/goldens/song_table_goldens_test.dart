// The Windows song table on the real Playlist and Songs pages, at the sizes the
// desktop app is used at.
//
//   flutter test test/goldens/song_table_goldens_test.dart --update-goldens

@Tags(['golden'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/artist.dart';
import 'package:navivibe/features/social/logic/social_providers.dart' show invitationCountProvider;
import 'package:navivibe/features/updates/logic/update_providers.dart' show updateCheckProvider;
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/artwork.dart';
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/library/artists_page.dart' show libraryArtistsProvider;
import 'package:navivibe/screens/home_screen.dart';
import 'package:navivibe/widgets/mascot/microduck_pose.dart' show microduckClock;
import 'package:navivibe/screens/library_screen.dart';
import 'package:navivibe/screens/settings_screen.dart';
import 'package:navivibe/widgets/shell/desktop/now_playing_panel.dart' show NowPlayingPanel, PanelKind;
import 'package:navivibe/widgets/shell/desktop/player_bar.dart';
import 'package:navivibe/screens/library/songs_page.dart';
import 'package:navivibe/screens/playlist_details_screen.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/app_tab.dart';
import 'package:navivibe/widgets/shell/desktop/desktop_layout.dart';
import 'package:navivibe/widgets/shell/desktop/library_rail.dart';
import 'package:navivibe/widgets/shell/desktop/top_bar.dart';
import 'package:navivibe/widgets/shell/desktop/window_ground.dart';

import 'golden_fonts.dart';

const _titles = [
  ('Aga Naga (From "Ponniyin Selvan Part-2")', 'A. R. Rahman, Shakthisree Gopalan', 'Ponniyin Selvan: Part 2'),
  ('Alone', 'Alan Walker', 'Different World'),
  ('Espresso', 'Sabrina Carpenter', 'Short n’ Sweet'),
  ('Thaniye (From "Vidaamuyarchi")', 'Anirudh Ravichander', 'Vidaamuyarchi'),
  ('Kannukulla', 'Sean Roldan', 'Kannukulla'),
  ('Oru Kal Oru Kannadi', 'Yuvan Shankar Raja', 'Oru Kal Oru Kannadi'),
  ('Hangova (From "DC")', 'Anirudh Ravichander', 'DC'),
  ('Katrukkulle', 'G. V. Prakash Kumar', 'Katrukkulle'),
  ('Vennilave', 'A. R. Rahman', 'Minsara Kanavu'),
  ('Ordinary', 'Alex Warren', 'You’ll Be Alright, Kid'),
  ('Starboy', 'The Weeknd', 'Starboy'),
  ('Nenjukkul Peidhidum', 'Harris Jayaraj', 'Vaaranam Aayiram'),
  ('Blinding Lights', 'The Weeknd', 'After Hours'),
  ('Munbe Vaa', 'A. R. Rahman', 'Sillunu Oru Kaadhal'),
];

final _albums = [
  for (final (i, t) in _titles.indexed) Album(id: 'g$i', name: t.$3, artist: t.$2, coverArt: 'g$i', songCount: 8 + i, duration: 2400, year: 2024),
];

final _songs = [
  for (final (i, t) in _titles.indexed)
    Song(
      id: 'g$i',
      title: t.$1,
      artist: t.$2,
      album: t.$3,
      coverArt: 'g$i',
      duration: 150 + (i * 37) % 160,
      track: i + 1,
      year: 2024,
      suffix: 'flac',
      bitRate: 900,
      created: DateTime(2025, 1 + i % 12, 3 + i),
    ),
];

Future<Map<String, Uint8List>> _covers() async {
  final out = <String, Uint8List>{};
  for (final s in _songs) {
    final h = s.id.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xffff);
    // Warm and teal fixtures only: the app never shows purple, so neither do its goldens.
    final hue = 10 + (h % 6) * 9;
    final c1 = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.38).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 160).toDouble(), 0.40, 0.50).toColor();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const r = Rect.fromLTWH(0, 0, 200, 200);
    canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [c1, c2]).createShader(r));
    final img = await rec.endRecording().toImage(200, 200);
    out[s.id] = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }
  return out;
}

class _Audio extends Fake implements AudioPlayer {
  @override
  double get volume => 0.7;
  @override
  Stream<double> get volumeStream => const Stream.empty();
  @override
  Duration get position => const Duration(seconds: 71);
  @override
  Stream<Duration> get positionStream => Stream.value(const Duration(seconds: 71));
  @override
  Duration? get duration => const Duration(seconds: 261);
  @override
  Stream<Duration?> get durationStream => Stream.value(const Duration(seconds: 261));
  @override
  bool get playing => true;
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  final _audio = _Audio();
  @override
  AudioPlayer get player => _audio;
  _FakePlayer()
      : super(PlayerState(
          queue: _songs,
          currentIndex: 3, // "Thaniye" is playing: its row is marked
          isPlaying: true,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: const [],
          history: const [],
          syncMode: SyncMode.activeHere,
        ));
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'u', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// What the fake server answers for a playlist: its songs, none, or an error.
enum _Server { ok, empty, fails }

class _FakeSubsonic extends Fake implements SubsonicService {
  final _Server mode;
  _FakeSubsonic([this.mode = _Server.ok]);
  @override
  String getCoverArtUrl(String? id, {int? size}) => 'cover://$id';
  @override
  Future<List<Song>> getPlaylistSongs(String id, {bool forceRefresh = false}) async => switch (mode) {
        _Server.ok => _songs,
        _Server.empty => const <Song>[],
        _Server.fails => throw Exception('offline'),
      };
}

class _FakePaged extends StateNotifier<PaginatedSongsState> implements PaginatedSongsNotifier {
  _FakePaged({List<Song>? songs}) : super(PaginatedSongsState(songs: songs ?? _songs, hasMore: false, isLoadingMore: false, offset: 14));
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

void main() {
  late Map<String, Uint8List> covers;

  setUpAll(() async {
    // Pin anything that depends on the date (Replay's year on Home, the mascot's sleep hours).
    homeClock = () => DateTime(2026, 11, 8, 14);
    microduckClock = () => DateTime(2026, 11, 8, 14);
    await loadGoldenFonts();
    Hive.init(Directory.systemTemp.createTempSync("hive_gold").path);
    HiveBoxes.prefs = await Hive.openBox("prefs");
    HiveBoxes.auth = await Hive.openBox("auth");
    HiveBoxes.session = await Hive.openBox("session");
    HiveBoxes.audio = await Hive.openBox("audio");
  });

  setUp(() => PlatformUtils.debugDesktopOverride = true);
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    debugCoverImageOverride = null;
  });

  Future<void> shot(WidgetTester tester, Widget page, Size size, String name, {List<Override> extra = const [], bool signedOut = false, _Server server = _Server.ok, List<Song>? pagedSongs, Future<void> Function(WidgetTester)? before}) async {
    covers = (await tester.runAsync(_covers))!;
    debugCoverImageOverride = (url, key) => MemoryImage(covers[url.replaceFirst('cover://', '')] ?? covers['g0']!);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...extra,
        playerProvider.overrideWith((ref) => _FakePlayer()),
        settingsProvider.overrideWith((ref) => signedOut ? _SignedOut() : _FakeSettings()),
        subsonicServiceProvider.overrideWithValue(_FakeSubsonic(server)),
        catalogSongProvider.overrideWith((ref, id) => null),
        isOfflineProvider.overrideWithValue(true), // no suggestions shelf, no network in a golden
        updateCheckProvider.overrideWith((ref) async => null),
        invitationCountProvider.overrideWithValue(0),
        sortedPlaylistsProvider.overrideWithValue(AsyncData([for (final n in ["Late Night Drive", "Gym", "Focus", "Tamil Classics", "Road Trip", "Rainy Day"]) Playlist(id: n, name: n, comment: "", songCount: 14, duration: 3000)])),
        sortedAlbumsProvider.overrideWithValue(AsyncData(_albums)),
        libraryArtistsProvider.overrideWith((ref) async => const <Artist>[]),
        paginatedSongsProvider.overrideWith((ref, arg) => _FakePaged(songs: pagedSongs)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(AppThemeTokens.fallback),
        builder: (c, child) => ThemeTokens(tokens: AppThemeTokens.fallback, child: child!),
        home: page,
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60))); // let images decode
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (before != null) {
      await before(tester);
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('desktop/$name.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  for (final size in const [Size(1366, 768), Size(1920, 1080)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('playlist table $tag', (tester) async {
      await shot(
        tester,
        PlaylistDetailsScreen(playlist: Playlist(id: 'p1', name: 'Late Night Drive', comment: '', songCount: 14, duration: 3100)),
        size,
        'playlist_$tag',
      );
    });
    testWidgets('songs table $tag', (tester) async {
      await shot(tester, const SongsPage(), size, 'songs_$tag');
    });
  }

  // The shell as one picture: top bar, library rail, a page, the right panel.
  // (Composed from the real pieces; the shell widget itself needs the whole app.)
  Widget shellPage(Size size, {Widget? page}) {
    final collapsed = size.width < 1200;
    return Builder(builder: (context) {
      // The same ground the real shell uses: one tint behind everything, every pane transparent.
      return DesktopWindowGround(child: Scaffold(backgroundColor: Colors.transparent, body: Column(children: [
        const DesktopTopBar(),
        Expanded(
          child: Row(children: [
            LibraryRail(tab: AppTab.home, onSelect: (_) {}, forceCollapsed: collapsed),
            Expanded(
              child: page ?? PlaylistDetailsScreen(
                playlist: Playlist(id: 'p1', name: 'Late Night Drive', comment: '', songCount: 14, duration: 3100),
              ),
            ),
            // The real panel (About), as the shell shows it while a song plays.
            if (!collapsed) NowPlayingPanel(panel: PanelKind.about, onChange: (_) {}, onClose: () {}),
          ]),
        ),
        DesktopPlayerBar(panel: PanelKind.queue, onTogglePanel: (_) {}),
      ])));
    });
  }

  for (final size in const [Size(1100, 700), Size(1366, 768), Size(1920, 1080)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('shell $tag', (tester) async {
      DesktopLayout.debugReset();
      await shot(tester, shellPage(size), size, 'shell_$tag');
    });
  }

  // Settings in the same window: the same ground as every other page, no black centre.
  testWidgets('shell with settings', (tester) async {
    DesktopLayout.debugReset();
    await shot(tester, shellPage(const Size(1366, 768), page: const SettingsScreen()), const Size(1366, 768), 'shell_settings_1366x768');
  });
  // A song table page (the page's own cover is different from the playing song's): still one tint.
  testWidgets('shell with songs', (tester) async {
    DesktopLayout.debugReset();
    await shot(tester, shellPage(const Size(1366, 768), page: const SongsPage()), const Size(1366, 768), 'shell_songs_1366x768');
  });

  // Home on a desktop: full width, shelves of 170 tiles, no Jam or update banner.
  for (final size in const [Size(1366, 768), Size(1920, 1080)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('home $tag', (tester) async {
      final albums = _albums;
      await shot(
        tester,
        const HomeScreen(),
        size,
        'home_$tag',
        signedOut: true,
        extra: [
          // Signed out of the smart features (they ask the network), with the library's own shelves filled.
          recentlyPlayedAlbumsProvider.overrideWith((ref) async => albums.take(9).toList()),
          recentlyPlayedSongsProvider.overrideWith((ref) async => _songs),
          recentlyAddedAlbumsProvider.overrideWith((ref) async => albums.reversed.take(9).toList()),
          favoritesProvider.overrideWith((ref) async => (songs: _songs.take(6).toList(), albums: <Album>[])),
          playlistsProvider.overrideWith((ref) async => [for (final n in ['Late Night Drive', 'Gym', 'Focus', 'Tamil Classics', 'Road Trip', 'Rainy Day', 'Study']) Playlist(id: n, name: n, comment: '', songCount: 14, duration: 3000)]),
        ],
      );
    });
  }

  // Library on a desktop: tiles and the list, and Settings with its categories.
  for (final size in const [Size(1366, 768), Size(1920, 1080)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('library tiles $tag', (tester) async {
      DesktopLayout.setLibraryGrid(true);
      await shot(tester, const LibraryScreen(), size, 'library_tiles_$tag', signedOut: true);
    });
    testWidgets('library list $tag', (tester) async {
      DesktopLayout.setLibraryGrid(false);
      await shot(tester, const LibraryScreen(), size, 'library_list_$tag', signedOut: true);
      DesktopLayout.setLibraryGrid(true);
    });
    testWidgets('settings $tag', (tester) async {
      await shot(tester, const SettingsScreen(), size, 'settings_$tag');
    });
    testWidgets('settings playback $tag', (tester) async {
      await shot(tester, const SettingsScreen(), size, 'settings_playback_$tag', before: (t) async {
        await t.tap(find.text('Playback').first);
        await t.pump();
      });
    });
    testWidgets('player bar $tag', (tester) async {
      await shot(
        tester,
        Scaffold(body: Align(alignment: Alignment.bottomCenter, child: DesktopPlayerBar(panel: PanelKind.queue, onTogglePanel: (_) {}))),
        size,
        'player_bar_$tag',
      );
    });
  }

  // The states that are not the happy path, on the table pages and Home: each says
  // what is going on in a few plain words and offers one way out.
  const stateSize = Size(1366, 768);
  testWidgets('state: songs empty', (tester) async {
    await shot(tester, const SongsPage(), stateSize, 'state_songs_empty', pagedSongs: const <Song>[]);
  });
  testWidgets('state: songs could not load', (tester) async {
    await shot(
      tester,
      const SongsPage(),
      stateSize,
      'state_songs_error',
      pagedSongs: const <Song>[],
      extra: [librarySyncProvider.overrideWith(_FailedSync.new)],
    );
  });
  testWidgets('state: playlist empty', (tester) async {
    await shot(
      tester,
      PlaylistDetailsScreen(playlist: Playlist(id: 'p1', name: 'Late Night Drive', comment: '', songCount: 0, duration: 0)),
      stateSize,
      'state_playlist_empty',
      server: _Server.empty,
    );
  });
  testWidgets('state: playlist could not load', (tester) async {
    await shot(
      tester,
      PlaylistDetailsScreen(playlist: Playlist(id: 'p1', name: 'Late Night Drive', comment: '', songCount: 14, duration: 3100)),
      stateSize,
      'state_playlist_error',
      server: _Server.fails,
    );
  });
  testWidgets('state: table find has no match', (tester) async {
    await shot(
      tester,
      const SongsPage(),
      stateSize,
      'state_table_no_results',
      before: (t) async {
        await t.tap(find.text('Alone'));
        await t.pump();
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.keyF);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await t.pump(const Duration(milliseconds: 100));
        await t.enterText(find.byType(EditableText).first, 'zzzz');
        await t.pump();
      },
    );
  });
  testWidgets('state: home first run', (tester) async {
    await shot(
      tester,
      const HomeScreen(),
      stateSize,
      'state_home_empty',
      signedOut: true,
      extra: [
        recentlyPlayedAlbumsProvider.overrideWith((ref) async => <Album>[]),
        recentlyPlayedSongsProvider.overrideWith((ref) async => <Song>[]),
        recentlyAddedAlbumsProvider.overrideWith((ref) async => <Album>[]),
        favoritesProvider.overrideWith((ref) async => (songs: <Song>[], albums: <Album>[])),
        playlistsProvider.overrideWith((ref) async => <Playlist>[]),
      ],
    );
  });
  testWidgets('state: home offline', (tester) async {
    await shot(
      tester,
      const HomeScreen(),
      stateSize,
      'state_home_error',
      signedOut: true,
      extra: [
        recentlyPlayedAlbumsProvider.overrideWith((ref) async => throw Exception('offline')),
        recentlyPlayedSongsProvider.overrideWith((ref) async => throw Exception('offline')),
        recentlyAddedAlbumsProvider.overrideWith((ref) async => throw Exception('offline')),
        favoritesProvider.overrideWith((ref) async => (songs: <Song>[], albums: <Album>[])),
        playlistsProvider.overrideWith((ref) async => throw Exception('offline')),
      ],
    );
  });
}

class _FailedSync extends LibrarySyncNotifier {
  @override
  LibrarySyncState build() => LibrarySyncState(error: Exception('offline'));
}

class _SignedOut extends StateNotifier<SettingsState> implements SettingsNotifier {
  _SignedOut() : super(const SettingsState(serverUrl: '', username: '', password: ''));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}
