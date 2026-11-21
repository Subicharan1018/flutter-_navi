/// The Smart Shuffle page on a phone (390 wide @3x) and on Windows (1280 wide):
/// a loaded mix, an empty one and the unreachable-server error.
///
///   flutter test test/goldens/smart_shuffle_screen_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/features/ai_shuffle/data/models/health_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/predict_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/recommended_song.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_repository.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/features/ai_shuffle/ui/ai_shuffle_screen.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/utils/platform_utils.dart';

import 'golden_fonts.dart';

class _FakeRepo extends Fake implements ShuffleRepository {}

class _FakePredict extends PredictQueueNotifier {
  _FakePredict(PredictQueueState initial) : super(_FakeRepo()) {
    state = initial;
  }

  @override
  Future<void> fetchPredict({required PredictMode mode}) async {}
}

const _titles = [
  ('Vaa Vaa En Devathaiye', 'A. R. Rahman'),
  ('Kadhal Rojave', 'Ilaiyaraaja'),
  ('Nenjukkul Peidhidum', 'Harris Jayaraj'),
  ('Munbe Vaa', 'A. R. Rahman'),
  ('Ennavale', 'Yuvan Shankar Raja'),
];

Song _song(int i) => Song(
      id: 's$i',
      title: _titles[i].$1,
      artist: _titles[i].$2,
      album: 'Album $i',
      genre: 'Film',
      composer: _titles[i].$2,
      coverArt: '',
      duration: 200 + i * 13,
      track: i + 1,
      year: 2008,
    );

RecommendedSong _rec(int i) => RecommendedSong(
      rank: i + 1,
      title: _titles[i].$1,
      filePath: 'p/$i.mp3',
      genreBucket: 'Film',
      composer: _titles[i].$2,
      audio: AudioFeatures(energy: .15 + i * .2, valence: .2 + (i * .37) % .7, acousticness: .3, danceability: .3 + i * .12),
      scores: SongScores(contextHistory: .9, audioFit: .8, composerLoyalty: .7, finalScore: .92 - i * .13),
      why: 'fits',
      artist: _titles[i].$2,
      album: 'Album $i',
    );

const _context = PredictContext(
  bucket: 'late_morning__summer__cloudy',
  fallbackLevel: 0,
  nInProfile: 412,
  weatherMood: 'cloudy',
  temperatureC: 28.4,
  timestampIst: '2026-11-21T10:40:00+05:30',
);

void main() {
  late Directory dir;
  setUpAll(() async {
    await loadGoldenFonts();
    dir = Directory.systemTemp.createTempSync('hive_ss_golden');
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.audio = await Hive.openBox('audio');
  });
  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  Future<void> shoot(WidgetTester tester, PredictQueueState predict, String file,
      {required bool desktop, double phoneHeight = 844}) async {
    PlatformUtils.debugDesktopOverride = desktop;
    tester.view.physicalSize = desktop ? const Size(1280, 900) : Size(390 * 3, phoneHeight * 3);
    tester.view.devicePixelRatio = desktop ? 1 : 3;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tokens = AppThemeTokens.fallback;
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        serverHealthProvider.overrideWith((ref) => Completer<HealthResponse>().future),
        predictQueueProvider.overrideWith((ref) => _FakePredict(predict)),
        allSongsProvider.overrideWith((ref) async => [for (var i = 0; i < _titles.length; i++) _song(i)]),
      ],
      child: ThemeTokens(
        tokens: tokens,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(tokens),
          home: Scaffold(backgroundColor: tokens.bgBase, body: const AiShuffleScreen()),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    // The field blooms and glides frame by frame (a ticker clamps big jumps).
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('smart_shuffle/$file.png'));
  }

  final loaded = PredictQueueState(
    status: PredictStatus.loaded,
    songs: [for (var i = 0; i < _titles.length; i++) _rec(i)],
    context: _context,
  );
  const empty = PredictQueueState(status: PredictStatus.loaded, context: _context);
  const failed = PredictQueueState(status: PredictStatus.error, errorMessage: 'offline');

  // The whole page, to see the taste field, the energy dial and the list.
  testWidgets('phone loaded, full page',
      (tester) => shoot(tester, loaded, 'screen_phone_loaded_full', desktop: false, phoneHeight: 1500));

  for (final (name, state) in [('loaded', loaded), ('empty', empty), ('error', failed)]) {
    testWidgets('phone $name', (tester) => shoot(tester, state, 'screen_phone_$name', desktop: false));
    testWidgets('windows $name', (tester) => shoot(tester, state, 'screen_windows_$name', desktop: true));
  }
}
