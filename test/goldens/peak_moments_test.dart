/// Highlights and Best Moments, phone 390×844 @3x and Windows 1280×800.
///
///   flutter test test/goldens/peak_moments_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
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
import 'package:navivibe/features/peak_moments/ui/moments_sheet.dart' show MomentsSheet;
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

/// The scrubber's saved-moment bands: 350 px for a 240 s song, 20 px gutters.
void bandTests() {
  const dur = 240000;
  const gutter = 20.0;
  const trackW = 350.0;
  double xOf(int ms) => gutter + trackW * ms / dur;
  // The handles sit in the lower half of the 32 px band.
  const y = gutter + 24;

  Future<ProviderContainer> pump(WidgetTester tester, {List<int> taps = const [60000]}) async {
    tester.view.physicalSize = const Size(390, 140) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [peakBackendProvider.overrideWithValue(_Mem())]);
    addTearDown(c.dispose);
    for (final tap in taps) {
      await c.read(peakMarksProvider.notifier).toggleAt('s0', tap, durationMs: dur);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(AppThemeTokens.fallback),
            home: Builder(
              builder: (context) => Scaffold(
                backgroundColor: ThemeTokens.of(context).bgBase,
                body: Consumer(
                  builder: (context, ref, _) => Padding(
                    padding: const EdgeInsets.all(gutter),
                    child: SizedBox(
                      height: 32,
                      child: Stack(
                        children: [
                          // Stand-in for the 6 px scrubber bar.
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 13,
                            height: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: ThemeTokens.of(context).textMuted,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          PeakBands(songId: 's0', marks: ref.watch(songMarksProvider('s0')), totalMs: dur),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return c;
  }

  List<PeakMark> marks(ProviderContainer c) => c.read(songMarksProvider('s0'));

  testWidgets('both ends have a handle (golden)', (tester) async {
    await pump(tester, taps: [30000, 150000]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('peak_moments/bands_phone.png'));
  });

  testWidgets('dragging the end handle changes the saved length', (tester) async {
    final c = await pump(tester); // saved 57..77 s
    await tester.dragFrom(Offset(xOf(77000), y), const Offset(35, 0)); // +35 px = about +24 s
    await tester.pumpAndSettle();
    final m = marks(c).single;
    expect(m.startMs, 57000);
    expect(m.endMs, inInclusiveRange(98000, 104000));
  });

  testWidgets('dragging the start handle moves the start and keeps the end', (tester) async {
    final c = await pump(tester);
    await tester.dragFrom(Offset(xOf(57000), y), const Offset(-35, 0));
    await tester.pumpAndSettle();
    final m = marks(c).single;
    expect(m.endMs, 77000);
    expect(m.startMs, inInclusiveRange(29000, 35000));
  });

  testWidgets('the start handle stops at the previous moment and at 0', (tester) async {
    final c = await pump(tester, taps: [30000, 100000]); // 27..47 and 97..117
    await tester.dragFrom(Offset(xOf(97000), y), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(marks(c).last.startMs, 47000);
    await tester.dragFrom(Offset(xOf(27000), y), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(marks(c).first.startMs, 0);
  });

  testWidgets('the end handle cannot make a moment longer than 90 s', (tester) async {
    final c = await pump(tester);
    await tester.dragFrom(Offset(xOf(77000), y), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(marks(c).single.lengthMs, PeakMark.maxLengthMs);
  });

  testWidgets('arrow keys nudge a focused handle by a second', (tester) async {
    final c = await pump(tester); // 57..77 s
    final end = find.descendant(of: find.byKey(const ValueKey('end')), matching: find.byType(GestureDetector));
    Focus.of(tester.element(end.last)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(marks(c).single.endMs, 79000);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(marks(c).single.endMs, 78000);
    expect(marks(c).single.startMs, 57000);

    final start = find.descendant(of: find.byKey(const ValueKey('start')), matching: find.byType(GestureDetector));
    Focus.of(tester.element(start.last)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(marks(c).single.startMs, 56000);
  });

  testWidgets('the moments sheet nudges start and end by a second', (tester) async {
    tester.view.physicalSize = const Size(390, 700) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [peakBackendProvider.overrideWithValue(_Mem())]);
    addTearDown(c.dispose);
    await c.read(peakMarksProvider.notifier).toggleAt('s0', 62000, durationMs: dur); // 59..79 s
    await c.read(peakMarksProvider.notifier).toggleAt('s0', 150000, durationMs: dur); // 147..167 s
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(AppThemeTokens.fallback),
            home: Builder(
              builder: (context) => Scaffold(
                backgroundColor: ThemeTokens.of(context).bgBase,
                body: SingleChildScrollView(child: MomentsSheet(song: _library().first)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Moment 1 · 0:59–1:19 · 20 s'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('peak_moments/moments_sheet_phone.png'));
    await tester.tap(find.text('−1 s').at(0));
    await tester.tap(find.text('+1 s').at(1));
    await tester.pumpAndSettle();
    expect([marks(c).first.startMs, marks(c).first.endMs], [58000, 80000]);
  });
}
