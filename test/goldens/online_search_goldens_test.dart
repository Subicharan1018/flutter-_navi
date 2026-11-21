// "Search online" as the phone sheet: the best match leading, then a result in
// every state (Get, owned, downloading, failed, blocked), and the Albums tab.
// The Windows page is in song_table_goldens_test.dart.
//
//   flutter test test/goldens/online_search_goldens_test.dart --update-goldens

@Tags(['golden'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/focus/navi_focus.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/data/fetch_models.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/online_fetch/ui/online_search_sheet.dart';
import 'package:navivibe/player/artwork.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

import 'golden_fonts.dart';

// A 1×1 grey PNG, stretched over every cover.
final _grey = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

class _FakeSearch extends OnlineSearchController {
  final OnlineSearchState fixed;
  _FakeSearch(this.fixed);
  @override
  OnlineSearchState build() => fixed;
  @override
  Future<void> start(String query, {FetchSearchType type = FetchSearchType.song, bool force = false}) async {}
}

class _FakeJobs extends FetchJobsController {
  final FetchDownloads fixed;
  _FakeJobs(this.fixed);
  @override
  FetchDownloads build() => fixed;
}

class _FakeSubsonic extends Fake implements SubsonicService {}

FetchCandidate _song(int id, String title, String artist, String album,
        {bool owned = false, bool blocked = false, FetchKind kind = FetchKind.original}) =>
    FetchCandidate(
        id: id, title: title, artist: artist, album: album, score: 1, kind: kind, inLibrary: owned, blocked: blocked, aiChecked: true, coverUrl: 'cover://$id');

void main() {
  setUpAll(loadGoldenFonts);

  Future<void> shoot(WidgetTester tester, OnlineSearchState state, String name, {FetchDownloads jobs = const FetchDownloads(), String? tab}) async {
    debugCoverImageOverride = (url, key) => MemoryImage(_grey);
    addTearDown(() => debugCoverImageOverride = null);
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        onlineSearchProvider.overrideWith(() => _FakeSearch(state)),
        fetchJobsProvider.overrideWith(() => _FakeJobs(jobs)),
        subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      ],
      child: ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(AppThemeTokens.fallback),
          home: Scaffold(
            backgroundColor: AppThemeTokens.fallback.bgBase,
            body: SafeArea(child: SingleChildScrollView(child: OnlineSearchSheet(query: state.query))),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 150));
    }
    if (tab != null) {
      await tester.tap(find.widgetWithText(NaviFocusable, tab));
      await tester.pumpAndSettle();
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('online_search/$name.png'));
  }

  testWidgets('songs: best match, owned, downloading, failed, blocked', (tester) async {
    final results = [
      _song(1, 'Naan Nee', 'Yuvan Shankar Raja', 'Paiyaa'),
      _song(2, 'Thuli Thuli', 'Yuvan Shankar Raja', 'Paiyaa', owned: true),
      _song(3, 'Adada Mazhaida', 'Yuvan Shankar Raja', 'Paiyaa'),
      _song(4, 'Naan Nee (Reprise)', 'Karthik', 'Paiyaa', kind: FetchKind.cover),
      _song(5, 'En Kadhal Solla', 'Yuvan Shankar Raja', 'Paiyaa', blocked: true),
    ];
    await shoot(
      tester,
      OnlineSearchState(
        query: 'naan nee',
        search: FetchSearch(id: 1, query: 'naan nee', status: FetchSearchStatus.done, candidates: results),
      ),
      'phone_songs',
      jobs: const FetchDownloads(jobs: {
        3: FetchJob(id: 3, candidateId: 3, phase: FetchJobPhase.downloading, progress: 0.42),
        4: FetchJob(id: 4, candidateId: 4, phase: FetchJobPhase.failed),
      }),
    );
  });

  testWidgets('albums tab', (tester) async {
    FetchCandidate album(int id, String title, String artist, int n) =>
        FetchCandidate(id: id, title: title, artist: artist, album: '', score: 1, kind: FetchKind.original, inLibrary: false, type: FetchSearchType.album, trackCount: n, aiChecked: true, coverUrl: 'cover://$id');
    await shoot(
      tester,
      OnlineSearchState(
        query: 'paiyaa',
        type: FetchSearchType.album,
        search: FetchSearch(id: 2, query: 'paiyaa', status: FetchSearchStatus.done, candidates: [
          album(11, 'Paiyaa', 'Yuvan Shankar Raja', 8),
          album(12, 'Paiyaa (Original Motion Picture Soundtrack)', 'Yuvan Shankar Raja', 9),
        ]),
      ),
      'phone_albums',
      tab: 'Albums',
    );
  });
}
