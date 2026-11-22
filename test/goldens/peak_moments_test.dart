/// Highlights and Best Moments, phone 390×844 @3x and Windows 1280×800.
///
///   flutter test test/goldens/peak_moments_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/peak_moments/data/peak_mark.dart';
import 'package:navivibe/features/peak_moments/data/peak_store.dart';
import 'package:navivibe/features/peak_moments/data/seek_log.dart';
import 'package:navivibe/features/peak_moments/logic/best_moments.dart';
import 'package:navivibe/features/peak_moments/logic/hotspots.dart';
import 'package:navivibe/features/peak_moments/ui/best_moments_screen.dart';
import 'package:navivibe/features/peak_moments/ui/highlights_screen.dart';
import 'package:navivibe/features/peak_moments/ui/peak_scrubber.dart' show PeakBands;
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

import 'golden_fonts.dart';

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _Mem implements PeakBackend {
  _Mem([Map<String, String>? seed]) : values = seed ?? {};
  final Map<String, String> values;
  @override
  String? read(String key) => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _titles = [
  ('Kaathalae Kaathalae', 'Govind Vasantha'),
  ('Ordinary Person', 'Anirudh Ravichander'),
  ('Vaathi Coming', 'Anirudh Ravichander'),
  ('Munbe Vaa', 'A. R. Rahman'),
  ('Hukum', 'Anirudh Ravichander'),
];

List<Song> _library() => [
  for (final (i, (t, a)) in _titles.indexed)
    Song(id: 's$i', title: t, artist: a, album: 'Album', coverArt: '', duration: 240, track: i + 1, year: 2024),
];

_Mem _marks() {
  final marks = const PeakMarks()
      .withSong('s0', [PeakMark(id: 'a', startMs: 62000, createdAt: 50, updatedAt: 50)])
      .withSong('s1', [
        PeakMark(id: 'b', startMs: 40000, createdAt: 40, updatedAt: 40),
        PeakMark(id: 'c', startMs: 150000, createdAt: 41, updatedAt: 41),
      ])
      .withSong('s3', [PeakMark(id: 'd', startMs: 95000, createdAt: 60, updatedAt: 60)]);
  final log = [
    for (final to in [100000, 104000, 110000]) SeekEntry(songId: 's2', fromMs: 200000, toMs: to, atMs: 9),
  ];
  return _Mem({HivePeakBackend.marksKey: marks.encode(), HivePeakBackend.seekKey: encodeSeekLog(log)});
}

BestMoments _best() => BestMoments(
  hotspots: [
    Hotspot(songId: 's2', startMs: 100000, count: 3, lastAtMs: 9),
    Hotspot(songId: 's0', startMs: 62000, count: 2, lastAtMs: 8),
  ],
  days: [
    PeakDay(day: DateTime(2026, 11, 8), plays: 41, seconds: 9400),
    PeakDay(day: DateTime(2026, 10, 25), plays: 33, seconds: 7300),
    PeakDay(day: DateTime(2026, 11, 14), plays: 22, seconds: 4800),
  ],
  sessions: [
    PeakSession(start: DateTime(2026, 11, 8, 21), songs: 28, seconds: 6900),
    PeakSession(start: DateTime(2026, 9, 30, 14), songs: 19, seconds: 4100),
  ],
);

Widget _app(Widget home, {List<Override> overrides = const [], _Mem? store, Future<List<Song>> Function()? songs}) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: [
      peakBackendProvider.overrideWithValue(store ?? _Mem()),
      allSongsProvider.overrideWith((ref) => (songs ?? () async => _library())()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      ...overrides,
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(tokens),
        home: Builder(builder: (c) => Scaffold(backgroundColor: ThemeTokens.of(c).bgBase, body: home)),
      ),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  void view(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  final now = DateTime(2026, 11, 22);

  bandTests();

  group('Highlights', () {
    testWidgets('data, phone', (tester) async {
      view(tester, const Size(390, 844), 3);
      await tester.pumpWidget(_app(const HighlightsScreen(), store: _marks()));
      await tester.pumpAndSettle();
      expect(find.text('Highlights'), findsWidgets);
      expect(find.text('Kaathalae Kaathalae'), findsOneWidget);
      expect(find.text('2 moments'), findsOneWidget); // s1 has two
      expect(find.text('Add most-replayed parts'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('peak_moments/highlights_phone.png'));
    });

    testWidgets('data, windows', (tester) async {
      view(tester, const Size(1280, 800), 1);
      await tester.pumpWidget(_app(const HighlightsScreen(), store: _marks()));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('peak_moments/highlights_windows.png'));
    });

    testWidgets('empty invites you to save a moment', (tester) async {
      view(tester, const Size(390, 844), 3);
      await tester.pumpWidget(_app(const HighlightsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Save the best parts of songs'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('peak_moments/highlights_empty_phone.png'));
    });

    testWidgets('error says what failed and retries', (tester) async {
      view(tester, const Size(390, 844), 3);
      await tester.pumpWidget(_app(const HighlightsScreen(), songs: () async => throw StateError('x')));
      await tester.pumpAndSettle();
      expect(find.text('Highlights aren’t available'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('loading shows a spinner, not an empty page', (tester) async {
      view(tester, const Size(390, 844), 3);
      await tester.pumpWidget(_app(const HighlightsScreen(), songs: () => Completer<List<Song>>().future));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('Save the best parts of songs'), findsNothing);
    });
  });

  group('Best moments', () {
    testWidgets('data, phone', (tester) async {
      view(tester, const Size(390, 844), 3);
      await tester.pumpWidget(_app(BestMomentsScreen(now: now), overrides: [bestMomentsProvider.overrideWith((ref) async => _best())]));
      await tester.pumpAndSettle();
      expect(find.text('Replayed Most'), findsOneWidget);
      expect(find.text('Vaathi Coming'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('peak_moments/best_phone.png'));
    });

    testWidgets('data, windows', (tester) async {
      view(tester, const Size(1280, 800), 1);
      await tester.pumpWidget(_app(BestMomentsScreen(now: now), overrides: [bestMomentsProvider.overrideWith((ref) async => _best())]));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('peak_moments/best_windows.png'));
    });

    testWidgets('empty explains what fills it', (tester) async {
      view(tester, const Size(390, 844), 3);
      await tester.pumpWidget(_app(BestMomentsScreen(now: now), overrides: [bestMomentsProvider.overrideWith((ref) async => const BestMoments())]));
      await tester.pumpAndSettle();
      expect(find.text('Your peaks start with your listening'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('peak_moments/best_empty_phone.png'));
    });

    testWidgets('history but no replays yet says when replays will appear', (tester) async {
      view(tester, const Size(390, 844), 3);
      final onlyDays = BestMoments(days: _best().days);
      await tester.pumpWidget(_app(BestMomentsScreen(now: now), overrides: [bestMomentsProvider.overrideWith((ref) async => onlyDays)]));
      await tester.pumpAndSettle();
      expect(find.textContaining('from now on'), findsOneWidget);
    });

    testWidgets('error offers a retry', (tester) async {
      view(tester, const Size(390, 844), 3);
      await tester.pumpWidget(_app(BestMomentsScreen(now: now), overrides: [bestMomentsProvider.overrideWith((ref) async => throw StateError('x'))]));
      await tester.pumpAndSettle();
      expect(find.text('Best moments aren’t available'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}

void bandTests() {
  testWidgets('dragging a band handle changes the saved length', (tester) async {
    tester.view.physicalSize = const Size(390, 200) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = _Mem();
    final c = ProviderContainer(overrides: [peakBackendProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    await c.read(peakMarksProvider.notifier).toggleAt('s0', 60000, durationMs: 240000);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    height: 32,
                    child: PeakBands(songId: 's0', marks: ref.watch(songMarksProvider('s0')), totalMs: 240000),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Track is 350 px for 240 s; the mark ends at 80 s = 116.7 px in.
    final handle = Offset(20 + 350 * 80 / 240, 20 + 24);
    await tester.dragFrom(handle, const Offset(35, 0)); // +10% of the width ≈ +24 s
    await tester.pumpAndSettle();
    final len = c.read(songMarksProvider('s0')).single.lengthMs;
    expect(len, inInclusiveRange(40000, 48000));
    expect(store.values[HivePeakBackend.marksKey], isNotNull);
  });
}
