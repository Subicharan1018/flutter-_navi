import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/local_library/logic/local_index.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/widgets/cover_art.dart';
import 'package:navivibe/widgets/song_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _song = Song(
  id: 's1', title: 'Thaniye', artist: 'Anirudh', album: 'Al', coverArt: 's1', duration: 240, track: 1, year: 2024,
);

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer()
      : super(PlayerState(
          queue: const [],
          currentIndex: -1,
          isPlaying: false,
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

/// The server is unreachable; a cover is only available if the device holds
/// one, which the test switches on after the first frame.
class _Svc extends Fake implements SubsonicService {
  String? deviceCover;
  @override
  String getCoverArtUrl(String? id, {int? size}) => deviceCover == null ? '' : Uri.file(deviceCover!).toString();
}

void main() {
  late _Svc svc;
  late File cover;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc = _Svc();
    cover = File('${Directory.systemTemp.createTempSync('navi_tile_').path}/s1.jpg')..writeAsBytesSync([0xFF, 0xD8, 1, 2]);
  });

  Widget app() {
    final List<Override> overrides = [
      playerProvider.overrideWith((ref) => _FakePlayer()),
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      subsonicServiceProvider.overrideWithValue(svc),
      catalogSongProvider.overrideWith((ref, id) => null),
    ];
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.build(AppThemeTokens.fallback),
        builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
        home: Scaffold(body: SongTile(song: _song, onTap: () {})),
      ),
    );
  }

  testWidgets('a downloaded song shows its saved cover file with no network', (tester) async {
    svc.deviceCover = cover.path; // what the resolver returns once the download holds the jpg
    await tester.pumpWidget(app());
    final art = tester.widget<CoverArt>(find.byType(CoverArt));
    expect(art.url, startsWith('file:'));
    expect(find.descendant(of: find.byType(CoverArt), matching: find.byType(Image)), findsOneWidget);
  });

  testWidgets('a tile drawn before the local index finished loading repaints when it does', (tester) async {
    await tester.pumpWidget(app());
    expect(tester.widget<CoverArt>(find.byType(CoverArt)).url, isEmpty);

    svc.deviceCover = cover.path;
    LocalLibraryIndex.instance.replace(paths: const {}, covers: {'s1': cover.path}); // scan finished
    await tester.pump();
    await tester.pump();
    expect(tester.widget<CoverArt>(find.byType(CoverArt)).url, startsWith('file:'));
    LocalLibraryIndex.instance.clear();
  });
}
