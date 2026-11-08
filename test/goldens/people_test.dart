/// People: every user with a presence shape, what the active ones play, Join
/// for open rooms, and Windows' Listening now strip.
///
///   flutter test test/goldens/people_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/jam_controller.dart';
import 'package:navivibe/features/social/logic/people_providers.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';
import 'package:navivibe/features/social/ui/people.dart';
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

class _FakeSocial extends SocialSettingsNotifier {
  @override
  Future<SocialSettings> build() async => const SocialSettings(enabled: true);
}

class _FakePeople extends PeopleNotifier {
  final PeopleState initial;
  _FakePeople(this.initial);
  @override
  PeopleState build() => initial;
  @override
  VoidCallback watching() => () {};
  @override
  Future<void> refresh() async {}
}

class _JoinRecorder extends JamController {
  static final joined = <String>[];
  @override
  JamUiState build() => const JamUiState();
  @override
  Future<bool> join(String code) async {
    joined.add(code);
    return true;
  }
}

class _Mem implements AlertPrefsStore {
  Map<String, Object?> saved = {};
  @override
  Map<String, Object?> read() => saved;
  @override
  void write(Map<String, Object?> value) => saved = value;
}

final _list = PeopleList(enabled: true, people: [
  Person(
    username: 'Arjun',
    state: PresenceState.active,
    nowPlaying: const FriendSong(songId: 's1', title: 'Thaniye', artist: 'Anirudh Ravichander'),
    room: const PersonRoom(mode: JamMode.collab, open: true, members: 3, code: 'K7QX2M', joinable: true),
  ),
  Person(
    username: 'Sana',
    state: PresenceState.active,
    nowPlaying: const FriendSong(songId: 's2', title: 'Espresso', artist: 'Sabrina Carpenter'),
  ),
  const Person(username: 'Dev', state: PresenceState.idle),
  const Person(username: 'Ila', state: PresenceState.offline),
  const Person(username: 'Ravi', state: PresenceState.hidden),
]);

Widget _app(Widget home, {PeopleState? people, _Mem? prefs}) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      socialSettingsProvider.overrideWith(_FakeSocial.new),
      peopleProvider.overrideWith(() => _FakePeople(people ?? PeopleState(list: _list))),
      jamControllerProvider.overrideWith(_JoinRecorder.new),
      alertPrefsStoreProvider.overrideWithValue(prefs ?? _Mem()),
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(tokens),
        home: Scaffold(body: SingleChildScrollView(child: home)),
      ),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  Future<void> phone(WidgetTester tester, {double height = 900}) async {
    tester.view.physicalSize = Size(390, height) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('the People list: states by shape, songs, rooms and a Join button', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const PeopleSection()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('People · 2 listening'), findsOneWidget);
    expect(find.text('Thaniye · Anirudh Ravichander · in a Collab room'), findsOneWidget);
    expect(find.text('Not sharing what they listen to'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget); // only Arjun's room is open to friends
    // Each presence state has its own accessible name, so no state hangs on colour.
    final semantics = tester.ensureSemantics();
    await tester.pump();
    for (final s in PresenceState.values) {
      expect(find.bySemanticsLabel(RegExp(s.label)), findsWidgets);
    }
    semantics.dispose();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('people/list.png'));
  });

  testWidgets('Join enters the room by its code', (tester) async {
    await phone(tester);
    _JoinRecorder.joined.clear();
    await tester.pumpWidget(_app(const PeopleSection()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Join'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_JoinRecorder.joined, ['K7QX2M']);
  });

  testWidgets('long-pressing a person offers Mute alerts, and the mute is kept', (tester) async {
    await phone(tester);
    final mem = _Mem();
    await tester.pumpWidget(_app(const PeopleSection(), prefs: mem));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(find.text('Sana'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Mute alerts'), findsOneWidget);
    await tester.tap(find.text('Mute alerts'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(mem.saved['muted'], ['sana']);
    expect(find.text('Muted'), findsOneWidget);
  });

  testWidgets('nobody is listed before social features are on', (tester) async {
    await phone(tester);
    final tokens = AppThemeTokens.fallback;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        socialSettingsProvider.overrideWith(() => _Off()),
        peopleProvider.overrideWith(() => _FakePeople(PeopleState(list: _list))),
        alertPrefsStoreProvider.overrideWithValue(_Mem()),
      ],
      child: ThemeTokens(tokens: tokens, child: const MaterialApp(home: Scaffold(body: PeopleSection()))),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Arjun'), findsNothing);
    expect(find.textContaining('People'), findsNothing);
  });

  testWidgets('Windows: the Listening now strip shows only active people', (tester) async {
    tester.view.physicalSize = const Size(1200, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const ListeningNowStrip()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Listening now'), findsOneWidget);
    expect(find.text('Arjun'), findsOneWidget);
    expect(find.text('Sana'), findsOneWidget);
    expect(find.text('Dev'), findsNothing);
    expect(find.text('Ravi'), findsNothing);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('people/strip.png'));
  });

  testWidgets('the strip is empty when no one listens', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const ListeningNowStrip(), people: const PeopleState(list: PeopleList(enabled: true))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Listening now'), findsNothing);
  });
}

class _Off extends SocialSettingsNotifier {
  @override
  Future<SocialSettings> build() async => const SocialSettings();
}
