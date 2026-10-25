/// The Jam experience at phone size (390×844 @3x): the empty room, a live room
/// as host and as guest, the code entry, and Home's Jam card.
///
///   flutter test test/goldens/jam_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/jam_controller.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';
import 'package:navivibe/features/social/ui/jam/jam_hero.dart';
import 'package:navivibe/features/social/ui/jam/jam_pill.dart';
import 'package:navivibe/features/social/ui/jam/jam_tab.dart';
import 'package:navivibe/providers/settings_provider.dart';
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
}

class _FakeSocial extends SocialSettingsNotifier {
  @override
  Future<SocialSettings> build() async => const SocialSettings(enabled: true);
}

JamState _jam({required bool host, bool playing = true, int people = 4, int songs = 5}) => JamState.fromJson({
      'code': 'K7QX2M',
      'version': 9,
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

Widget _app(Widget home, JamUiState jam) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: [
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
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.build(tokens), home: home),
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

  testWidgets('nothing overflows on a small phone (320 wide), room and empty room', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    for (final ui in [const JamUiState(), JamUiState(jam: _jam(host: true)), JamUiState(jam: _jam(host: false, people: 5), driftMs: 100)]) {
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
