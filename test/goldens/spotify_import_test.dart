/// Settings › Import › Spotify History at phone size: nothing chosen yet, a file read and waiting to be sent,
/// and the finished import with its skips, listens, Wishlist and Remove rows.
///
///   flutter test test/goldens/spotify_import_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/spotify_import/data/spotify_import_api.dart';
import 'package:navivibe/features/spotify_import/logic/spotify_import_providers.dart';
import 'package:navivibe/features/spotify_import/logic/spotify_parser.dart';
import 'package:navivibe/features/spotify_import/ui/spotify_import_screen.dart';

import 'golden_fonts.dart';

class _Adapter implements HttpClientAdapter {
  final Object jobs;
  _Adapter(this.jobs);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async =>
      ResponseBody.fromString(jsonEncode(jobs), 200, headers: {
        'content-type': ['application/json'],
      });
  @override
  void close({bool force = false}) {}
}

const _done = {
  'id': 7,
  'source': 'spotify',
  'status': 'done',
  'total': 15930,
  'fetched': 15930,
  'imported': 7385,
  'wished': 5088,
  'already': 150,
  'near_dups': 0,
  'rejected_total': 0,
  'rejected': <String, int>{},
  'skips': 2081,
  'listens': 10392,
  'unclear': 539,
  'songs_matched': 802,
  'songs_unmatched': 1028,
  'wishlist_id': 3,
  'oldest_ts': 1698924536,
  'newest_ts': 1794153638,
};

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
  container: c,
  child: ThemeTokens(
    tokens: AppThemeTokens.fallback,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppThemeTokens.fallback),
      home: const SpotifyImportScreen(),
    ),
  ),
);

ProviderContainer _container(Object jobs, {SpotifyParseResult? file}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = _Adapter(jobs);
  return ProviderContainer(
    overrides: [
      spotifyImportApiProvider.overrideWithValue(SpotifyImportApi(dio)),
      spotifyFilePickerProvider.overrideWithValue(() async => ['export.zip']),
      if (file != null) spotifyParserProvider.overrideWithValue((_) async => file),
    ],
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1000) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('nothing chosen yet', (tester) async {
    phone(tester);
    final c = _container(<dynamic>[]);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('spotify_import/empty.png'));
  });

  testWidgets('a file read, waiting to be sent', (tester) async {
    phone(tester);
    final file = SpotifyParseResult(
      const [SpotifyPlay(t: 1700000000, ms: 200000, title: 'Neela Megam', artist: 'Aarav Kumar')],
      const SpotifyParseSummary(
        format: SpotifyFormat.extended,
        filesRead: 4,
        filesIgnored: 3,
        rows: 15950,
        kept: 15930,
        droppedEpisodes: 19,
        droppedPrivate: 1,
        firstTs: 1698924536,
        lastTs: 1794153638,
      ),
    );
    final c = _container(<dynamic>[], file: file);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    c.listen(spotifyImportProvider, (_, _) {});
    // `choose` is real: a stub picker and a stub parser, so the screen is in the state a person would see.
    await tester.runAsync(() => c.read(spotifyImportProvider.notifier).choose());
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('spotify_import/chosen.png'));
  });

  testWidgets('finished', (tester) async {
    phone(tester);
    final c = _container([_done]);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('spotify_import/done.png'));
  });
}
