import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:navivibe/models/download_state.dart';
import 'package:navivibe/providers/download_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/library/composers_page.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/widgets/song_tile.dart';
import 'package:navivibe/models/catalog.dart';
import 'package:navivibe/widgets/ui/action_sheet.dart';

import '../helpers/test_utils.dart';

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _EmptyCatalog extends CatalogNotifier {
  @override
  Future<CatalogDocument> build() async => CatalogDocument.empty;
}

Widget _app(Widget home, {List<Override> overrides = const []}) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: [
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      catalogProvider.overrideWith(_EmptyCatalog.new),
      playerProvider.overrideWith((ref) => _FakePlayer()),
      downloadStateProvider.overrideWith(_NoDownloads.new),
      ...overrides,
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(theme: AppTheme.build(tokens), home: home),
    ),
  );
}

void main() {
  final songs = [
    makeSong(id: '1', title: 'Why This Kolaveri', artist: 'Dhanush', composer: 'Anirudh Ravichander', album: '3'),
    makeSong(id: '2', title: 'Roja Janeman', artist: 'A.R. Rahman', composer: 'A. R. Rahman', album: 'Roja'),
    makeSong(id: '3', title: 'Chinna Chinna Aasai', artist: 'Minmini', composer: 'AR Rahman', album: 'Roja'),
    makeSong(id: '4', title: 'No credit', artist: 'Someone', composer: '', album: 'X'),
  ];

  testWidgets('Composers page lists composers A–Z with song counts', (tester) async {
    await tester.pumpWidget(_app(const ComposersPage(), overrides: [allSongsProvider.overrideWith((ref) async => songs)]));
    await tester.pumpAndSettle();

    expect(find.text('Composers'), findsWidgets);
    expect(find.text('A. R. Rahman'), findsOneWidget);
    expect(find.text('2 songs'), findsOneWidget);
    expect(find.text('Anirudh Ravichander'), findsOneWidget);
    expect(find.text('1 song'), findsOneWidget);
    // A–Z: A. R. Rahman comes before Anirudh.
    expect(tester.getTopLeft(find.text('A. R. Rahman')).dy, lessThan(tester.getTopLeft(find.text('Anirudh Ravichander')).dy));
  });

  testWidgets('Composers page invites when no song has a composer', (tester) async {
    await tester.pumpWidget(_app(const ComposersPage(),
        overrides: [allSongsProvider.overrideWith((ref) async => [songs.last])]));
    await tester.pumpAndSettle();
    expect(find.text('No composers yet'), findsOneWidget);
  });

  testWidgets('Composers page says what failed and offers retry', (tester) async {
    await tester.pumpWidget(_app(const ComposersPage(),
        overrides: [allSongsProvider.overrideWith((ref) async => throw Exception('offline'))]));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load composers'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('SheetInfoRow shows label over value and links when tappable', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_app(Scaffold(
      body: Builder(
        builder: (context) => SheetGroup(children: [
          SheetInfoRow(label: 'Composer', value: 'Anirudh Ravichander', onTap: () => tapped = true),
          const SheetInfoRow(label: 'Lyricist', value: 'Vivek'),
        ]),
      ),
    )));
    expect(find.text('Composer'), findsOneWidget);
    expect(find.text('Anirudh Ravichander'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget); // only the tappable one
    await tester.tap(find.text('Anirudh Ravichander'));
    expect(tapped, isTrue);
  });

  testWidgets('SongTile puts the composer first and drops it when absent', (tester) async {
    await tester.pumpWidget(_app(Scaffold(
      body: Column(children: [
        for (final s in [songs[0], songs[1], songs[3]]) SongTile(song: s, onTap: () {}),
      ]),
    )));
    await tester.pump();
    expect(find.text('Anirudh Ravichander · Dhanush'), findsOneWidget);
    expect(find.text('A. R. Rahman'), findsOneWidget); // artist is the composer
    expect(find.text('Someone'), findsOneWidget); // no composer → artist as before
  });
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

class _NoDownloads extends DownloadStateNotifier {
  @override
  Map<String, SongDownloadState> build() => {};
}
