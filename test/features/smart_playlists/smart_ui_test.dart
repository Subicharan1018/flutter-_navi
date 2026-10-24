import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/smart_playlists/data/smart_evaluator.dart';
import 'package:navivibe/features/smart_playlists/data/smart_rules.dart';
import 'package:navivibe/features/smart_playlists/logic/smart_playlist_providers.dart';
import 'package:navivibe/features/smart_playlists/ui/rule_editor_screen.dart';
import 'package:navivibe/features/smart_playlists/ui/smart_widgets.dart';
import 'package:navivibe/models/song.dart';

SongFacts fact(String id, {int year = 2021, List<String> languages = const ['ta']}) => SongFacts(
      song: Song(id: id, title: 'Song $id', artist: 'A', album: 'B', coverArt: id, duration: 200, track: 1, year: year),
      languages: languages,
    );

Widget host(Widget home, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        builder: (context, child) => ThemeTokens(tokens: AppThemeTokens.fallback, child: child!),
        home: home,
      ),
    );

void main() {
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hive_smart_ui');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  tearDown(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  testWidgets('SmartBadge reads "Smart" and fits a narrow row', (tester) async {
    await tester.pumpWidget(host(const Scaffold(body: SizedBox(width: 120, child: Row(children: [SmartBadge()])))));
    expect(find.text('Smart'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
