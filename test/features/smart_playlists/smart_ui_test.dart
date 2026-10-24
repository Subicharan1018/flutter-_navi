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
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/screens/library/playlists_page.dart';

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

  // Opened once, outside the widget tests' fake-async zone: file IO started
  // inside it never completes.
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_smart_ui');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  setUp(() => HiveBoxes.prefs.clear().ignore());

  tearDownAll(() async {
    // Not closed: puts started inside the widget tests never finish there.
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('SmartBadge reads "Smart" and fits a narrow row', (tester) async {
    await tester.pumpWidget(host(const Scaffold(body: SizedBox(width: 120, child: Row(children: [SmartBadge()])))));
    expect(find.text('Smart'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule editor shows a live match count and saves the playlist', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final library = [fact('1'), fact('2', languages: ['en']), fact('3', year: 2010)];
    await tester.pumpWidget(host(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showSmartPlaylistEditor(context),
          child: const Text('open'),
        ),
      ),
      overrides: [smartFactsProvider.overrideWith((ref) async => library)],
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // A new playlist starts with one blank rule, which matches everything.
    expect(find.text('3 songs'), findsOneWidget);

    // Add a second rule, switch it to Year, and type 2021 (year = 2021).
    await tester.tap(find.text('Add Rule'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Language').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Year').last);
    await tester.pump(const Duration(milliseconds: 500));
    final fields = find.byType(CupertinoTextField);
    await tester.enterText(fields.at(1), '2021');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 songs'), findsOneWidget);

    await tester.enterText(fields.first, 'Fresh Tamil');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 500));

    final container = ProviderScope.containerOf(tester.element(find.text('open')));
    final saved = container.read(smartPlaylistsProvider).single;
    expect(saved.name, 'Fresh Tamil');
    expect(SmartPlaylist.isSmartId(saved.id), isTrue);
    expect(saved.rules.ruleCount, 2);
  });

  testWidgets('Playlists page marks smart playlists and expands folders', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final server = Playlist(id: 'p1', name: 'Gym', comment: '', songCount: 12, duration: 600);
    await tester.pumpWidget(host(
      const PlaylistsPage(),
      overrides: [sortedPlaylistsProvider.overrideWithValue(AsyncData([server]))],
    ));
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(PlaylistsPage)));

    container.read(smartPlaylistsProvider.notifier).upsert(
          SmartPlaylist(id: 'smart:7', name: 'Sad Tamil', createdAt: 0, rules: SmartGroup(children: [SmartRule.blank(SmartField.mood)])),
        );
    final folders = container.read(playlistFoldersProvider.notifier);
    final folderId = folders.create('Workout');
    folders.move('p1', folderId);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Sad Tamil'), findsOneWidget);
    expect(find.byType(SmartBadge), findsOneWidget);
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('1 playlist'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);

    await tester.tap(find.text('Workout'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Gym'), findsNothing);
    expect(find.text('Workout'), findsOneWidget);
  });
}
