/// Song rows with the composer first, and the Composers page, at phone size.
///
///   flutter test test/goldens/composers_test.dart --update-goldens
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/catalog.dart';
import 'package:navivibe/models/download_state.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/download_provider.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/library/composers_page.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/widgets/song_tile.dart';

import 'golden_fonts.dart';

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _EmptyCatalog extends CatalogNotifier {
  @override
  Future<CatalogDocument> build() async => CatalogDocument.empty;
}

class _NoDownloads extends DownloadStateNotifier {
  @override
  Map<String, SongDownloadState> build() => {};
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer()
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

Song _s(String id, String title, String artist, String composer, String album) => Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      composer: composer,
      coverArt: id,
      duration: 240,
      track: 1,
      year: 2022,
    );

final _songs = [
  _s('1', 'Why This Kolaveri Di', 'Dhanush', 'Anirudh Ravichander', '3'),
  _s('2', 'Chaiyya Chaiyya', 'Sukhwinder Singh, Sapna Awasthi', 'A. R. Rahman', 'Dil Se'),
  _s('3', 'Kadhal Rojave', 'S. P. Balasubrahmanyam', 'AR Rahman', 'Roja'),
  _s('4', 'Rowdy Baby', 'Dhanush, Dhee', 'Yuvan Shankar Raja', 'Maari 2'),
  _s('5', 'Vaseegara', 'Bombay Jayashri', 'Harris Jayaraj', 'Minnale'),
  _s('6', 'Anbe Anbe', 'Harris Jayaraj', 'Harris Jayaraj', 'Dhaam Dhoom'),
  _s('7', 'No composer tag', 'Some Singer', '', 'Singles'),
];

Widget _app(Widget home) {
  final tokens = AppThemeTokens.fallback;
  final overrides = <Override>[
    subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
    catalogProvider.overrideWith(_EmptyCatalog.new),
    playerProvider.overrideWith((ref) => _FakePlayer()),
    downloadStateProvider.overrideWith(_NoDownloads.new),
    allSongsProvider.overrideWith((ref) async => _songs),
  ];
  return ProviderScope(
    overrides: overrides,
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.build(tokens), home: home),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('song rows: composer first', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        backgroundColor: ThemeTokens.of(context).bgBase,
        body: SafeArea(
          child: Column(children: [for (final s in _songs) SongTile(song: s, onTap: () {})]),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('composers/song_rows.png'));
  });

  testWidgets('composers page', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app(const ComposersPage()));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('composers/page.png'));
  });
}
