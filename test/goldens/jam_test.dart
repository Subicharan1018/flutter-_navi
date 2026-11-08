/// The Jam experience at phone size (390×844 @3x): the empty room, a live room
/// as host and as guest, the code entry, and Home's Jam card.
///
///   flutter test test/goldens/jam_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/jam_controller.dart';
import 'package:navivibe/features/social/logic/jam_hints.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';
import 'package:navivibe/features/social/ui/jam/jam_hero.dart';
import 'package:navivibe/features/social/ui/jam/jam_pill.dart';
import 'package:navivibe/features/social/ui/jam/jam_tab.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/services/subsonic_service.dart';

import 'golden_fonts.dart';

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'maya', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _FakeJam extends JamController {
  final JamUiState initial;
  _FakeJam(this.initial);
  @override
  JamUiState build() => initial;
  @override
  Future<void> restore() async {}

  /// What the screens asked for, in order.
  static final log = <String>[];
  static bool note(String s) {
    log.add(s);
    return true;
  }
  @override
  Future<bool> removeItem(int itemId) async => note('remove $itemId');
  @override
  Future<bool> undoRemove(int itemId) async => note('undo $itemId');
  @override
  Future<bool> moveItem(int itemId, int toIndex) async => note('move $itemId to $toIndex');
  @override
  Future<bool> requestSkip() async => note('request-skip');
  @override
  Future<bool> resolveSkip({required bool approve, String? user}) async => note(approve ? 'approve' : 'dismiss');
}

class _MemHints implements HintStore {
  final seen_ = <String>{};
  @override
  bool seen(String key) => seen_.contains(key);
  @override
  void markSeen(String key) => seen_.add(key);
}

class _FakeSocial extends SocialSettingsNotifier {
  @override
  Future<SocialSettings> build() async => const SocialSettings(enabled: true);
}

JamState _jam({
  required bool host,
  bool playing = true,
  int people = 4,
  int songs = 5,
  String mode = 'jam',
  Map<String, Object?> extra = const {},
}) =>
    JamState.fromJson({
      'code': 'K7QX2M',
      'version': 9,
      'mode': mode,
      ...extra,
      'host': host ? 'maya' : 'Arjun',
      'you_are_host': host,
      'members': [
        for (final (i, n) in ['Arjun', 'maya', 'Sana', 'Dev', 'Ila'].take(people).indexed)
          {'username': n, 'is_host': host ? n == 'maya' : i == 0},
      ],
      'queue': [
        for (final (i, s) in [
          ('Thaniye', 'Anirudh Ravichander', 'Arjun'),
          ('Espresso', 'Sabrina Carpenter', 'maya'),
          ('Alone', 'Alan Walker', 'Sana'),
          ('Katrukkulle', 'G. V. Prakash Kumar', 'Dev'),
          ('Hangova', 'Anirudh Ravichander', 'Ila'),
        ].take(songs).indexed)
          {'id': i + 1, 'song_id': 's$i', 'title': s.$1, 'artist': s.$2, 'added_by': s.$3, 'duration_s': 200},
      ],
      'index': 1,
      'playing': playing,
      'position_ms': 61000,
      'server_ms': 1000000,
    });

Widget _app(Widget home, JamUiState jam, {HintStore? hints}) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: [
      hintStoreProvider.overrideWithValue(hints ?? _MemHints()),
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      jamControllerProvider.overrideWith(() => _FakeJam(jam)),
      socialSettingsProvider.overrideWith(_FakeSocial.new),
      friendFeedProvider.overrideWith((ref) async => FriendFeed.fromJson({
            'enabled': true,
            'friends': [
              {
                'username': 'Arjun',
                'now_playing': {'song_id': 's1', 'title': 'Thaniye', 'artist': 'Anirudh Ravichander', 'minutes_ago': 0},
                'recent': <Object>[],
              },
              {
                'username': 'Sana',
                'now_playing': null,
                'recent': [
                  {'title': 'Alone', 'played_at': 1, 'song_id': 's2'},
                ],
              },
            ],
          })),
      collabListProvider.overrideWith((ref) async => [
            const CollabPlaylist(id: 'p1', name: 'Road trip', owner: 'maya', isOwner: true, status: 'active', songCount: 14, members: [
              CollabMember('maya', true),
              CollabMember('Arjun', true),
            ]),
            const CollabPlaylist(id: 'p2', name: 'Friday night', owner: 'Sana', isOwner: false, status: 'invited', invitedBy: 'Sana'),
          ]),
      blendListProvider.overrideWith((ref) async => [
            const Blend(id: 'b1', withUser: 'Arjun', status: 'active', matchPct: 72),
          ]),
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.build(tokens), home: ColoredBox(color: tokens.bgBase, child: home)),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  Future<void> phone(WidgetTester tester, {double height = 844}) async {
    tester.view.physicalSize = Size(390, height) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  // The ring breathes forever while music plays, so settle by time, not by idle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('empty room', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const JamTabScreen(), const JamUiState()));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('jam/stage.png'));
  });

  testWidgets('live room as host', (tester) async {
    await phone(tester, height: 1500);
    await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true))));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('jam/room_host.png'));
  });

  testWidgets('live room as guest, catching up', (tester) async {
    await phone(tester, height: 1000);
    await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: false, people: 3), driftMs: 3200)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('jam/room_guest.png'));
  });

  testWidgets('live collab room: everyone has the controls and each song names its contributor', (tester) async {
    await phone(tester, height: 1500);
    await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: false, mode: 'collab'))));
    await settle(tester);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.textContaining('Added by Sana'), findsOneWidget);
    expect(find.textContaining('everyone edits the queue'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('jam/room_collab.png'));
  });

  testWidgets('a Jam member gets no dead controls: a line saying who has them, and Add songs', (tester) async {
    await phone(tester, height: 2600);
    await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: false))));
    await settle(tester);
    expect(find.bySemanticsLabel('Pause'), findsNothing);
    expect(find.bySemanticsLabel('Previous'), findsNothing);
    expect(find.textContaining('The admin controls the queue'), findsOneWidget);
    expect(find.text('Add songs'), findsOneWidget);
    // The people list shows each person's role.
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Member'), findsNWidgets(3));
  });

  testWidgets('the admin has the controls and the room menu holds Leave and End', (tester) async {
    await phone(tester, height: 1000);
    await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true))));
    await settle(tester);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous'), findsOneWidget);
    expect(find.text('Leave Jam'), findsNothing); // no loose buttons: they live in the menu
    expect(find.bySemanticsLabel('Room options'), findsOneWidget);
  });

  group('skip requests, undo, recently left and the reorder hint', () {
    setUp(_FakeJam.log.clear);

    testWidgets('a Jam member can ask to skip, once', (tester) async {
      await phone(tester, height: 1000);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: false))));
      await settle(tester);
      expect(find.text('Ask to skip this song'), findsOneWidget);
      await tester.tap(find.text('Ask to skip this song'));
      await tester.pump();
      expect(_FakeJam.log, ['request-skip']);

      await tester.pumpWidget(const SizedBox()); // a fresh screen
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: false, extra: {'you_requested_skip': true}))));
      await settle(tester);
      expect(find.text('Skip requested'), findsOneWidget);
      expect(find.text('Ask to skip this song'), findsNothing);
    });

    testWidgets('the admin and Collab members are never offered Ask to skip', (tester) async {
      await phone(tester, height: 1000);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true))));
      await settle(tester);
      expect(find.text('Ask to skip this song'), findsNothing);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: false, mode: 'collab'))));
      await settle(tester);
      expect(find.text('Ask to skip this song'), findsNothing);
    });

    testWidgets('the admin sees who asks, and Approve or Dismiss reaches the controller', (tester) async {
      await phone(tester, height: 1000);
      final jam = _jam(host: true, extra: {
        'skip_requests': [
          {'username': 'Arjun', 'item_id': 2},
          {'username': 'Sana', 'item_id': 2},
        ],
      });
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: jam)));
      await settle(tester);
      expect(find.text('Arjun and Sana ask to skip'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.tap(find.text('Dismiss'));
      expect(_FakeJam.log, ['approve', 'dismiss']);
    });

    testWidgets('a member never sees the requests', (tester) async {
      await phone(tester, height: 1000);
      final jam = _jam(host: false, extra: {'skip_requests': [{'username': 'Sana', 'item_id': 2}]});
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: jam)));
      await settle(tester);
      expect(find.textContaining('ask to skip'), findsNothing);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('Removing a song says so with Undo, and Undo asks the controller to put it back', (tester) async {
      await phone(tester, height: 1200);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true))));
      await settle(tester);
      await tester.longPress(find.text('Alone'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Remove from room'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 1)); // the toast has slid in
      expect(_FakeJam.log, ['remove 3']);
      expect(find.text('Removed Alone'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(_FakeJam.log, ['remove 3', 'undo 3']);
    });

    testWidgets('the long-press sheet reorders without dragging', (tester) async {
      await phone(tester, height: 1200);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true))));
      await settle(tester);
      await tester.longPress(find.text('Alone'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Move up'), findsOneWidget);
      expect(find.text('Move down'), findsOneWidget);
      await tester.tap(find.text('Move up'));
      await tester.pump();
      expect(_FakeJam.log, ['move 3 to 1']);
    });

    testWidgets('screen readers get Reorder and Remove actions on each song', (tester) async {
      final semantics = tester.ensureSemantics();
      await phone(tester, height: 1200);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true))));
      await settle(tester);
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp('^Alone,')).first);
      final labels = [for (final id in node.getSemanticsData().customSemanticsActionIds ?? const <int>[]) CustomSemanticsAction.getAction(id)!.label];
      expect(labels, containsAll(['Reorder: move up', 'Reorder: move down', 'Remove from room']));
      semantics.dispose();
    });

    testWidgets('a member gets none of the editing actions', (tester) async {
      await phone(tester, height: 1200);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: false))));
      await settle(tester);
      await tester.longPress(find.text('Alone'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Move up'), findsNothing);
      expect(find.text('Remove from room'), findsNothing);
    });

    testWidgets('the reorder hint shows once, and goes for good after Got it', (tester) async {
      await phone(tester, height: 1200);
      final hints = _MemHints();
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true)), hints: hints));
      await settle(tester);
      expect(find.text('Press and hold a song to reorder or remove it.'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pump();
      expect(find.text('Press and hold a song to reorder or remove it.'), findsNothing);
      // A fresh session reads the saved flag: it stays gone.
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true)), hints: hints));
      await settle(tester);
      expect(find.text('Press and hold a song to reorder or remove it.'), findsNothing);
    });

    testWidgets('using what the hint teaches also retires it, and a member never sees it', (tester) async {
      await phone(tester, height: 1200);
      final hints = _MemHints();
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true)), hints: hints));
      await settle(tester);
      await tester.longPress(find.text('Alone'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Move down'));
      await tester.pump();
      expect(hints.seen(JamQueueHint.key), isTrue);

      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: false))));
      await settle(tester);
      expect(find.text('Press and hold a song to reorder or remove it.'), findsNothing);
    });

    testWidgets('Recently left lists the last people, newest first, with when', (tester) async {
      await phone(tester, height: 2600);
      final jam = _jam(host: true, extra: {
        'recently_left': [
          {'username': 'Ila', 'reason': 'removed', 'ago_s': 120},
          {'username': 'Dev', 'reason': 'left', 'ago_s': 2000},
        ],
      });
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: jam)));
      await settle(tester);
      expect(find.text('Recently left'), findsOneWidget);
      expect(find.text('Removed 2 min ago'), findsOneWidget);
      expect(find.text('Left 33 min ago'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Ila').last).dy, lessThan(tester.getTopLeft(find.text('Dev').last).dy));
    });

    testWidgets('no Recently left section when no one has left', (tester) async {
      await phone(tester, height: 2600);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true))));
      await settle(tester);
      expect(find.text('Recently left'), findsNothing);
    });
  });

  testWidgets('the room code has a visible Copy and Share', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true))));
    await settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  group('Windows room', () {
    setUp(() => PlatformUtils.debugDesktopOverride = true);
    tearDown(() => PlatformUtils.debugDesktopOverride = null);

    Future<void> desktop(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('admin: ring, code and people left, queue table right', (tester) async {
      await desktop(tester);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: true))));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('Added by'), findsOneWidget); // the table's column
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('jam/desktop_admin.png'));
    });

    testWidgets('member: the table has no drag handles and Delete does nothing', (tester) async {
      await desktop(tester);
      await tester.pumpWidget(_app(const JamTabScreen(), JamUiState(jam: _jam(host: false))));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('jam/desktop_member.png'));
    });
  });

  testWidgets('nothing overflows on a small phone (320 wide), room and empty room', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    for (final ui in [
      const JamUiState(),
      JamUiState(jam: _jam(host: true)),
      JamUiState(jam: _jam(host: false, people: 5), driftMs: 100),
      JamUiState(jam: _jam(host: false, mode: 'collab')),
    ]) {
      await tester.pumpWidget(_app(const JamTabScreen(), ui));
      await settle(tester);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(_app(const Scaffold(body: SafeArea(child: JamHero())), JamUiState(jam: _jam(host: true))));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home card and live pill', (tester) async {
    await phone(tester, height: 420);
    await tester.pumpWidget(_app(
      Scaffold(
        body: SafeArea(
          child: Column(children: [
            const JamHero(),
            const Spacer(),
            const JamLivePill(),
          ]),
        ),
      ),
      JamUiState(jam: _jam(host: true)),
    ));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('jam/home_live.png'));
  });

  testWidgets('home card before a Jam', (tester) async {
    await phone(tester, height: 300);
    await tester.pumpWidget(_app(const Scaffold(body: SafeArea(child: JamHero())), const JamUiState()));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('jam/home_idle.png'));
  });
}
