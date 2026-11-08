import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/library/playlists_page.dart';
import 'package:navivibe/services/subsonic_service.dart';

/// The phone Library: Your playlists, Collab playlists and Shared with you as
/// separate, headed sections (signed in as "admin", as on Navidrome).

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'admin', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _On extends SocialSettingsNotifier {
  @override
  Future<SocialSettings> build() async => const SocialSettings(enabled: true);
}

Playlist pl(String id, String name, String? owner) =>
    Playlist(id: id, name: name, comment: '', songCount: 12, duration: 600, owner: owner);

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_phone_sections');
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

  Future<void> pump(WidgetTester tester, List<Playlist> server, {List<CollabPlaylist> collabs = const []}) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
        socialSettingsProvider.overrideWith(_On.new),
        collabListProvider.overrideWith((ref) async => collabs),
        sortedPlaylistsProvider.overrideWithValue(AsyncData(server)),
      ],
      child: MaterialApp(
        builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
        home: const PlaylistsPage(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  double y(WidgetTester t, String s) => t.getTopLeft(find.text(s)).dy;

  testWidgets('yours, collab and shared are separate sections in that order', (tester) async {
    await pump(
      tester,
      [pl('1', 'Gym', 'admin'), pl('2', 'Focus', 'Admin'), pl('3', 'Road Trip', 'maya'), pl('4', 'Chill', null)],
      collabs: const [CollabPlaylist(id: 'c1', name: 'Friday Night', owner: 'admin', isOwner: true, status: 'active', songCount: 5)],
    );
    expect(y(tester, 'Your playlists'), lessThan(y(tester, 'Gym')));
    expect(y(tester, 'Gym'), lessThan(y(tester, 'Collab playlists')));
    expect(y(tester, 'Collab playlists'), lessThan(y(tester, 'Friday Night')));
    expect(y(tester, 'Friday Night'), lessThan(y(tester, 'Shared with you')));
    expect(y(tester, 'Shared with you'), lessThan(y(tester, 'Road Trip')));
    // Same person in another case, and a playlist with no owner, are both yours.
    expect(y(tester, 'Focus'), lessThan(y(tester, 'Collab playlists')));
    expect(y(tester, 'Chill'), lessThan(y(tester, 'Collab playlists')));
    expect(find.text('12 songs · maya'), findsOneWidget); // the owner is named
  });

  testWidgets('Shared with you folds away and opens again', (tester) async {
    await pump(tester, [pl('1', 'Gym', 'admin'), pl('3', 'Road Trip', 'maya')]);
    expect(find.text('Road Trip'), findsOneWidget);
    await tester.tap(find.text('Shared with you'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Road Trip'), findsNothing);
    expect(find.text('Gym'), findsOneWidget);
    await tester.tap(find.text('Shared with you'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Road Trip'), findsOneWidget);
  });

  testWidgets('someone else’s playlist offers no Edit or Delete, only Make a Copy', (tester) async {
    await pump(tester, [pl('1', 'Gym', 'admin'), pl('3', 'Road Trip', 'maya')]);
    await tester.longPress(find.text('Road Trip'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Make a Copy'), findsOneWidget);
    expect(find.text('Edit Playlist'), findsNothing);
    expect(find.text('Delete Playlist'), findsNothing);
  });

  testWidgets('with only your own playlists there is no Shared section', (tester) async {
    await pump(tester, [pl('1', 'Gym', 'admin')]);
    expect(find.text('Shared with you'), findsNothing);
    expect(find.text('Gym'), findsOneWidget);
  });
}
