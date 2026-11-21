// Weekly Exploration: the page on a phone (a week in progress with a preview playing, and while the list is
// being made) and on Windows.
//
//   flutter test test/goldens/weekly_exploration_test.dart --update-goldens

@Tags(['golden'])
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/weekly_exploration/data/weekly_api.dart';
import 'package:navivibe/features/weekly_exploration/logic/preview_player.dart';
import 'package:navivibe/features/weekly_exploration/logic/weekly_providers.dart';
import 'package:navivibe/features/weekly_exploration/ui/weekly_exploration_screen.dart';
import 'package:navivibe/player/artwork.dart';
import 'package:navivibe/utils/platform_utils.dart';

import '../helpers/fake_http.dart';
import 'golden_fonts.dart';

Map<String, dynamic> _pick(int id, String title, String artist, String reason,
        {String state = 'pending', String dl = 'none', String? songId, String kind = 'near', String week = '2026-11-16', bool preview = true}) =>
    {
      'id': id, 'title': title, 'artist': artist, 'album': 'Album', 'year': 2025, 'duration_s': 214.0,
      'cover_url': 'cover://$id', 'preview_url': preview ? 'https://audio-ssl.itunes.apple.com/$id.m4a' : null,
      'reason': reason, 'kind': kind, 'state': state, 'week': week,
      'expires_at': DateTime(2026, 11, 30).millisecondsSinceEpoch / 1000.0,
      'download': {'state': dl, 'song_id': songId},
    };

// Made-up songs and artists.
final _picks = [
  _pick(1, 'Neon Monsoon', 'Aarav Kumar', 'Like Diya Ram'),
  _pick(2, 'Kaadhal Kaalam', 'Meena Rao', 'More from Meena Rao, one of your most played'),
  _pick(3, 'Slow Harbor', 'Zed Harbor', 'Two steps out from Odd Lark', kind: 'far'),
  _pick(4, 'Thendral Veedhi', 'Karthik Sen', 'Like Aarav Kumar'),
  _pick(5, 'Paper Lanterns', 'Mina Hart', 'Like Zed Harbor', preview: false),
  _pick(6, 'Veera Nadai', 'Karthik Sen', 'Like Aarav Kumar', state: 'kept', dl: 'queued'),
  _pick(7, 'Oru Pudhu Paadal', 'Sample Singer', 'Like Diya Ram', state: 'kept', dl: 'ready', songId: 'nd7'),
  _pick(8, 'Rue Banks', 'Odd Lark', 'Suggested by ListenBrainz'),
  _pick(9, 'Old Tide', 'Fenn Cole', 'Like Zed Harbor', week: '2026-11-09'),
];

Map<String, dynamic> _page(List<Map<String, dynamic>> picks, {bool building = false}) => {
      'enabled': true, 'cap': 10, 'max_cap': 25, 'week': '2026-11-16', 'kept_this_week': 2, 'building': building,
      'needs_build': false, 'build_note': null, 'download_note': null, 'night': {'from': 1, 'to': 7}, 'picks': picks,
    };

class _Engine implements PreviewEngine {
  final pos = StreamController<Duration>.broadcast();
  @override
  Stream<Duration> get position => pos.stream;
  @override
  Stream<void> get completed => const Stream.empty();
  @override
  Future<void> play(String url) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

Future<Map<String, Uint8List>> _covers() async {
  final out = <String, Uint8List>{};
  for (var i = 1; i <= 9; i++) {
    // Warm and teal fixtures only: the app never shows purple, so neither do its goldens.
    final hue = 10 + (i * 37 % 6) * 9;
    final c1 = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.38).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 160).toDouble(), 0.40, 0.50).toColor();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const r = Rect.fromLTWH(0, 0, 200, 200);
    canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [c1, c2]).createShader(r));
    final img = await rec.endRecording().toImage(200, 200);
    out['$i'] = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }
  return out;
}

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() {
    debugCoverImageOverride = null;
    PlatformUtils.debugDesktopOverride = null;
  });

  Future<void> shoot(WidgetTester tester, Map<String, dynamic> page, Size size, String name, {bool desktop = false, bool playing = false}) async {
    final covers = (await tester.runAsync(_covers))!;
    debugCoverImageOverride = (url, key) => MemoryImage(covers[url.replaceFirst('cover://', '')] ?? covers['1']!);
    PlatformUtils.debugDesktopOverride = desktop;
    tester.view.devicePixelRatio = desktop ? 1 : 3;
    tester.view.physicalSize = desktop ? size : size * 3;
    addTearDown(tester.view.reset);
    final engine = _Engine();
    const Widget home = WeeklyExplorationScreen();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        weeklyApiProvider.overrideWithValue(WeeklyApi(fakeDio(FakeAdapter((o) => jsonBody(200, page))))),
        previewEngineProvider.overrideWithValue(engine),
        previewPauseMainProvider.overrideWithValue(() async {}),
        previewNetworkOkProvider.overrideWithValue(() async => true),
        onlineFetchEnabledProvider.overrideWith((ref) => true),
      ],
      child: ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(AppThemeTokens.fallback),
          home: Scaffold(backgroundColor: AppThemeTokens.fallback.bgBase, body: home),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 120));
    }
    if (playing) {
      await tester.tap(find.bySemanticsLabel('Preview Neon Monsoon'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      engine.pos.add(const Duration(seconds: 12));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('weekly_exploration/$name.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('phone: a week in progress, a preview playing', (tester) async {
    await shoot(tester, _page(_picks), const Size(390, 844), 'phone_week', playing: true);
  });

  testWidgets('phone: the list is being made', (tester) async {
    await shoot(tester, _page(const [], building: true), const Size(390, 844), 'phone_building');
  });

  testWidgets('windows: a week in progress', (tester) async {
    await shoot(tester, _page(_picks), const Size(1366, 768), 'windows_week', desktop: true, playing: true);
  });
}
