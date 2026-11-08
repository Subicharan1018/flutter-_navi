/// The library's playlist sections: Your playlists, Collab playlists and Shared
/// with you, as real separated groups with quiet headers on the Windows rail and
/// the Windows Library page, and the rules that decide which playlist goes where.
///
///   flutter test test/goldens/library_sections_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/social/data/social_models.dart' show CollabMember, CollabPlaylist;
import 'package:navivibe/features/social/logic/social_providers.dart' show collabListProvider, invitationCountProvider;
import 'package:navivibe/features/updates/logic/update_providers.dart' show updateCheckProvider;
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/artist.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/playlist_access.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/library/artists_page.dart';
import 'package:navivibe/screens/library/desktop_library_page.dart';
import 'package:navivibe/screens/library/library_entries.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/shell/app_tab.dart';
import 'package:navivibe/widgets/shell/nav_stack.dart' show activeTab;
import 'package:navivibe/widgets/shell/desktop/desktop_layout.dart';
import 'package:navivibe/widgets/shell/desktop/library_rail.dart';

import 'golden_fonts.dart';

/// Signed in as "admin", the way the Navidrome owner is.
class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'admin', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer()
      : super(const PlayerState(
          queue: [],
          currentIndex: -1,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: [],
          history: [],
          syncMode: SyncMode.activeHere,
        ));
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

Playlist pl(String id, String name, String? owner, {int songs = 12}) =>
    Playlist(id: id, name: name, comment: '', songCount: songs, duration: 3000, owner: owner);

/// What Navidrome returns to "admin": their own playlists and everyone's public ones.
final _server = [
  pl('1', 'Late Night Drive', 'admin'),
  pl('2', 'Gym', 'Admin'), // same person, different case
  pl('3', 'Focus', null), // the server did not say: yours
  pl('4', 'Road Trip Mix', 'maya'),
  pl('5', 'Sana’s Chill', 'Sana'),
];

const _collab = CollabPlaylist(
  id: 'c1',
  name: 'Friday Night',
  owner: 'admin',
  isOwner: true,
  status: 'active',
  songCount: 8,
  members: [CollabMember('admin', true), CollabMember('Arjun', true)],
);

List<Override> overrides({List<Playlist>? playlists, List<CollabPlaylist> collabs = const [_collab]}) => [
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      playerProvider.overrideWith((ref) => _FakePlayer()),
      updateCheckProvider.overrideWith((ref) async => null),
      invitationCountProvider.overrideWithValue(0),
      collabListProvider.overrideWith((ref) async => collabs),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      sortedPlaylistsProvider.overrideWithValue(AsyncData(playlists ?? _server)),
      sortedAlbumsProvider.overrideWithValue(AsyncData([
        Album(id: 'a1', name: 'Starboy', artist: 'The Weeknd', coverArt: 'a1', songCount: 10, duration: 2400, year: 2016),
      ])),
      libraryArtistsProvider.overrideWith((ref) async => [Artist(id: 'r1', name: 'Alan Walker', albumCount: 2)]),
    ];

Widget app(Widget child, List<Override> o) => PointerAnchor(
      child: ProviderScope(
        overrides: o,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(AppThemeTokens.fallback),
          builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
          home: Scaffold(body: child),
        ),
      ),
    );

void main() {
  late Directory dir;
  setUpAll(() async {
    await loadGoldenFonts();
    dir = Directory.systemTemp.createTempSync('hive_sections');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
  });
  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  setUp(() {
    PlatformUtils.debugDesktopOverride = true;
    DesktopLayout.debugReset();
  });
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    PointerAnchor.reset();
    activeTab.value = AppTab.home;
  });

  // ── who owns what ─────────────────────────────────────────────────────────

  group('ownership', () {
    test('signed in as admin: own playlists in any case, and ones with no owner, are yours', () {
      expect(pl('a', 'x', 'admin').isOwnedBy('admin'), isTrue);
      expect(pl('a', 'x', 'Admin').isOwnedBy('admin'), isTrue);
      expect(pl('a', 'x', ' admin ').isOwnedBy('admin'), isTrue);
      expect(pl('a', 'x', null).isOwnedBy('admin'), isTrue);
      expect(pl('a', 'x', '').isOwnedBy('admin'), isTrue);
      expect(pl('a', 'x', 'maya').isOwnedBy('admin'), isFalse);
    });

    test('with no signed-in name nothing is called someone else’s', () {
      expect(pl('a', 'x', 'maya').isOwnedBy(''), isTrue);
      final access = PlaylistAccess('')..learn([pl('a', 'x', 'maya')]);
      expect(access.canEdit('a'), isTrue);
    });

    test('a playlist the user just created (owner = them) stays in Yours', () {
      final s = splitByOwner([pl('new', 'Fresh', 'admin'), pl('o', 'Theirs', 'maya')], 'admin');
      expect(s.mine.map((p) => p.id), ['new']);
      expect(s.shared.map((p) => p.id), ['o']);
    });
  });

  // ── rows ──────────────────────────────────────────────────────────────────

  group('sectionRows', () {
    LibEntry e(String id, LibSection? s) => LibEntry(
          kind: LibKind.playlists,
          id: id,
          title: id,
          subtitle: '',
          secondary: '',
          count: 1,
          artUrl: null,
          placeholder: NaviGlyph.playlist,
          onTap: () {},
          onMenu: () {},
          onPlay: () {},
          section: s,
        );
    List<String> shape(List<LibRow> rows) => [
          for (final r in rows)
            switch (r) {
              LibHeaderRow() => '#${r.section.name}${r.collapsed ? '(folded)' : ''}',
              LibEntryRow() => r.entry.id,
            },
        ];

    test('headers appear in order, once something else than yours exists', () {
      final rows = sectionRows([e('s1', LibSection.shared), e('y1', LibSection.yours), e('c1', LibSection.collab), e('y2', LibSection.yours)]);
      expect(shape(rows), ['#yours', 'y1', 'y2', '#collab', 'c1', '#shared', 's1']);
    });

    test('only yours: a plain list, no header', () {
      expect(shape(sectionRows([e('y1', LibSection.yours), e('y2', LibSection.yours)])), ['y1', 'y2']);
    });

    test('an empty section has no header, and albums or artists pass through', () {
      expect(shape(sectionRows([e('y1', LibSection.yours), e('s1', LibSection.shared)])), ['#yours', 'y1', '#shared', 's1']);
      expect(shape(sectionRows([e('a1', null), e('a2', null)])), ['a1', 'a2']);
    });

    test('folding Shared with you keeps its header', () {
      final rows = sectionRows([e('y1', LibSection.yours), e('s1', LibSection.shared)], sharedCollapsed: true);
      expect(shape(rows), ['#yours', 'y1', '#shared(folded)']);
      expect((rows.last as LibHeaderRow).count, 1);
    });

    test('sorting stays inside a section', () {
      final sorted = sortWithinSections(
        [e('b-shared', LibSection.shared), e('z-yours', LibSection.yours), e('a-shared', LibSection.shared), e('c-yours', LibSection.yours)],
        (a, b) => a.id.compareTo(b.id),
      );
      expect(sorted.map((x) => x.id), ['c-yours', 'z-yours', 'a-shared', 'b-shared']);
    });
  });

  // ── the rail ──────────────────────────────────────────────────────────────

  group('Windows rail', () {
    Future<void> rail(WidgetTester tester,
        {List<Override>? o, double w = 1366, double h = 900, bool forceCollapsed = false}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(w, h);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(
        Row(children: [
          LibraryRail(tab: AppTab.home, onSelect: (_) {}, forceCollapsed: forceCollapsed),
          const Expanded(child: SizedBox()),
        ]),
        o ?? overrides(),
      ));
      await tester.pumpAndSettle();
    }

    double y(WidgetTester t, String text) => t.getTopLeft(find.text(text)).dy;

    testWidgets('three headed sections, pinned destinations above, yours first', (tester) async {
      await rail(tester);
      for (final h in ['Your playlists', 'Collab playlists', 'Shared with you']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(y(tester, 'Favorites'), lessThan(y(tester, 'Your playlists')));
      expect(y(tester, 'Downloaded'), lessThan(y(tester, 'Your playlists')));
      for (final mine in ['Late Night Drive', 'Gym', 'Focus']) {
        expect(y(tester, 'Your playlists'), lessThan(y(tester, mine)));
        expect(y(tester, mine), lessThan(y(tester, 'Collab playlists')));
      }
      expect(y(tester, 'Collab playlists'), lessThan(y(tester, 'Friday Night')));
      expect(y(tester, 'Friday Night'), lessThan(y(tester, 'Shared with you')));
      for (final theirs in ['Road Trip Mix', 'Sana’s Chill']) {
        expect(y(tester, 'Shared with you'), lessThan(y(tester, theirs)));
      }
    });

    testWidgets('someone else’s playlist names its owner; yours do not', (tester) async {
      await rail(tester);
      expect(find.text('maya · 12 songs'), findsOneWidget);
      expect(find.text('Sana · 12 songs'), findsOneWidget);
      expect(find.text('Playlist · 12 songs'), findsNWidgets(3));
    });

    testWidgets('Shared with you folds away and opens again, keeping its count', (tester) async {
      await rail(tester);
      await tester.tap(find.text('Shared with you'));
      await tester.pumpAndSettle();
      expect(find.text('Road Trip Mix'), findsNothing);
      expect(find.text('Shared with you'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Late Night Drive'), findsOneWidget);
      await tester.tap(find.text('Shared with you'));
      await tester.pumpAndSettle();
      expect(find.text('Road Trip Mix'), findsOneWidget);
    });

    testWidgets('find searches across the sections and keeps only the headers that still have a match', (tester) async {
      await rail(tester);
      await tester.enterText(find.byType(TextField), 'sana');
      await tester.pumpAndSettle();
      expect(find.text('Sana’s Chill'), findsOneWidget);
      expect(find.text('Shared with you'), findsOneWidget);
      expect(find.text('Your playlists'), findsNothing);
      expect(find.text('Gym'), findsNothing);

      await tester.enterText(find.byType(TextField), 'night');
      await tester.pumpAndSettle();
      expect(find.text('Late Night Drive'), findsOneWidget);
      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Your playlists'), findsOneWidget);
      expect(find.text('Collab playlists'), findsOneWidget);
      expect(find.text('Shared with you'), findsNothing);
    });

    testWidgets('a search opens a folded Shared with you so a match is never hidden', (tester) async {
      await rail(tester);
      await tester.tap(find.text('Shared with you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'road');
      await tester.pumpAndSettle();
      expect(find.text('Road Trip Mix'), findsOneWidget);
    });

    testWidgets('the Albums and Artists chips still swap the list; the Playlists view keeps the sections', (tester) async {
      await rail(tester, h: 1600); // tall enough that the lazy list builds the albums too
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('Your playlists'), findsNothing);
      expect(find.text('Shared with you'), findsNothing);
      await tester.tap(find.text('Albums')); // off again: everything
      await tester.pumpAndSettle();
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('Your playlists'), findsOneWidget);
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      expect(find.text('Starboy'), findsNothing);
      expect(find.text('Shared with you'), findsOneWidget);
      await tester.tap(find.text('Playlists'));
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      expect(find.text('Alan Walker'), findsOneWidget);
    });

    testWidgets('sorting A–Z sorts inside each section and never moves a playlist across them', (tester) async {
      await rail(tester);
      await tester.tap(find.byTooltip('Sort: library order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alphabetical'));
      await tester.pumpAndSettle();
      expect(y(tester, 'Focus'), lessThan(y(tester, 'Gym')));
      expect(y(tester, 'Gym'), lessThan(y(tester, 'Late Night Drive')));
      expect(y(tester, 'Late Night Drive'), lessThan(y(tester, 'Collab playlists')));
      expect(y(tester, 'Shared with you'), lessThan(y(tester, 'Road Trip Mix')));
      expect(y(tester, 'Road Trip Mix'), lessThan(y(tester, 'Sana’s Chill')));
    });

    testWidgets('with only your own playlists there is nothing to separate and no headers', (tester) async {
      await rail(tester, o: overrides(playlists: [pl('1', 'Gym', 'admin'), pl('2', 'Focus', null)], collabs: const []));
      expect(find.text('Your playlists'), findsNothing);
      expect(find.text('Shared with you'), findsNothing);
      expect(find.text('Gym'), findsOneWidget);
    });

    testWidgets('the icon-only rail keeps the order and shows hairlines, not words', (tester) async {
      await rail(tester, forceCollapsed: true);
      expect(tester.takeException(), isNull);
      expect(find.text('Shared with you'), findsNothing);
    });

    testWidgets('golden: the rail with all three sections', (tester) async {
      await rail(tester, h: 1100); // tall enough to show all three sections
      await expectLater(find.byType(LibraryRail), matchesGoldenFile('library/rail_sections.png'));
    });
  });

  // ── the Library page ──────────────────────────────────────────────────────

  group('Windows Library page', () {
    Future<void> page(WidgetTester tester, {bool grid = false}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.reset);
      DesktopLayout.setLibraryGrid(grid);
      await tester.pumpWidget(app(const DesktopLibraryPage(), overrides()));
      await tester.pumpAndSettle();
    }

    testWidgets('list view: three headers in order, Shared with you folds away', (tester) async {
      await page(tester);
      double y(String t) => tester.getTopLeft(find.text(t).first).dy;
      expect(y('Your playlists'), lessThan(y('Late Night Drive')));
      expect(y('Late Night Drive'), lessThan(y('Collab playlists')));
      expect(y('Collab playlists'), lessThan(y('Friday Night')));
      expect(y('Friday Night'), lessThan(y('Shared with you')));
      expect(y('Shared with you'), lessThan(y('Road Trip Mix')));
      await tester.tap(find.text('Shared with you'));
      await tester.pumpAndSettle();
      expect(find.text('Road Trip Mix'), findsNothing);
      expect(find.text('Late Night Drive'), findsOneWidget);
    });

    testWidgets('tile view keeps the same sections', (tester) async {
      await page(tester, grid: true);
      expect(find.text('Your playlists'), findsOneWidget);
      expect(find.text('Collab playlists'), findsOneWidget);
      expect(find.text('Shared with you'), findsOneWidget);
      expect(find.text('Road Trip Mix'), findsOneWidget);
      DesktopLayout.setLibraryGrid(false);
    });

    testWidgets('golden: list view with the sections', (tester) async {
      await page(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('library/page_sections.png'));
    });
  });
}
