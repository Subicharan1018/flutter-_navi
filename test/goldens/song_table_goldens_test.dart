// The Windows song table on the real Playlist and Songs pages, at the sizes the
// desktop app is used at.
//
//   flutter test test/goldens/song_table_goldens_test.dart --update-goldens

@Tags(['golden'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/artwork.dart';
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/library/songs_page.dart';
import 'package:navivibe/screens/playlist_details_screen.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';

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
    final c1 = HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.7, 0.4).toColor();
    final c2 = HSLColor.fromAHSL(1, ((h * 7) % 360).toDouble(), 0.8, 0.6).toColor();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const r = Rect.fromLTWH(0, 0, 200, 200);
    canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [c1, c2]).createShader(r));
    final img = await rec.endRecording().toImage(200, 200);
    out[s.id] = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }
  return out;
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
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

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => 'cover://$id';
  @override
  Future<List<Song>> getPlaylistSongs(String id, {bool forceRefresh = false}) async => _songs;
}

class _FakePaged extends StateNotifier<PaginatedSongsState> implements PaginatedSongsNotifier {
  _FakePaged() : super(PaginatedSongsState(songs: _songs, hasMore: false, isLoadingMore: false, offset: 14));
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

void main() {
  late Map<String, Uint8List> covers;

  setUpAll(() async {
    await loadGoldenFonts();
  });

  setUp(() => PlatformUtils.debugDesktopOverride = true);
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    debugCoverImageOverride = null;
  });

  Future<void> shot(WidgetTester tester, Widget page, Size size, String name) async {
    covers = (await tester.runAsync(_covers))!;
    debugCoverImageOverride = (url, key) => MemoryImage(covers[url.replaceFirst('cover://', '')] ?? covers['g0']!);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        playerProvider.overrideWith((ref) => _FakePlayer()),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
        catalogSongProvider.overrideWith((ref, id) => null),
        isOfflineProvider.overrideWithValue(true), // no suggestions shelf, no network in a golden
        paginatedSongsProvider.overrideWith((ref, arg) => _FakePaged()),
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
}
