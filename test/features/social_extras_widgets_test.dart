import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/people_providers.dart';
import 'package:navivibe/features/social/logic/recap_providers.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';
import 'package:navivibe/features/social/ui/people.dart';
import 'package:navivibe/features/social/ui/recap_screens.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

import '../goldens/golden_fonts.dart';

/// The React action, the reactions list, and the recap sections on screen.

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'maya', password: 'p'));
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

class _Mem implements AlertPrefsStore {
  Map<String, Object?> saved = {};
  @override
  Map<String, Object?> read() => saved;
  @override
  void write(Map<String, Object?> value) => saved = value;
}

class _Dismiss implements RecapDismissStore {
  String? week;
  @override
  String? read() => week;
  @override
  void write(String w) => week = w;
}

PeopleList list({required bool supported, List<Reaction> reactions = const []}) => PeopleList(
      enabled: true,
      reactionsSupported: supported,
      reactions: reactions,
      people: const [
        Person(
          username: 'Sana',
          state: PresenceState.active,
          nowPlaying: FriendSong(songId: 's2', title: 'Espresso', artist: 'Sabrina Carpenter'),
        ),
        Person(username: 'Dev', state: PresenceState.idle),
      ],
    );

const recap = WeeklyRecap(
  minutes: 192,
  plays: 54,
  friends: [
    RecapFriend(
      username: 'Sana',
      blendId: 'b1',
      matchPct: 74,
      theirMinutes: 90,
      sharedArtists: [RecapEntry(name: 'Anirudh', you: 3, them: 2)],
    ),
  ],
);

Widget _app(Widget home, {PeopleList? people, WeeklyRecap? weekly, _Dismiss? dismiss}) => ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
        socialSettingsProvider.overrideWith(_On.new),
        peopleProvider.overrideWith(() => _FakePeople(PeopleState(list: people))),
        alertPrefsStoreProvider.overrideWithValue(_Mem()),
        recapProvider.overrideWith((ref) async => weekly),
        recapDismissStoreProvider.overrideWithValue(dismiss ?? _Dismiss()),
      ],
      child: ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: MaterialApp(
          theme: AppTheme.build(AppThemeTokens.fallback),
          home: Scaffold(body: SingleChildScrollView(child: home)),
        ),
      ),
    );

void main() {
  setUpAll(loadGoldenFonts);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('a friend playing a song can be reacted to when the server supports it', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app(const PeopleSection(), people: list(supported: true)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(find.text('Sana'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('React to this song…'), findsOneWidget);
    await tester.tap(find.text('React to this song…'));
    await tester.pumpAndSettle();
    expect(find.text('React to Sana'), findsOneWidget);
    expect(find.text('Add a note (optional)'), findsOneWidget);
    expect(find.text('Send ❤️'), findsOneWidget);
    await tester.tap(find.text('🔥'));
    await tester.pump();
    expect(find.text('Send 🔥'), findsOneWidget);
  });

  testWidgets('no React on an older server, or for someone who is not playing', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app(const PeopleSection(), people: list(supported: false)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(find.text('Sana'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('React to this song…'), findsNothing);
    expect(find.text('Mute alerts'), findsOneWidget);
  });

  testWidgets('received reactions are listed, newest first', (tester) async {
    phone(tester);
    final reactions = [
      const Reaction(id: 1, from: 'Dev', emoji: '👏', title: 'Old', artist: 'A'),
      const Reaction(id: 2, from: 'Sana', emoji: '🔥', title: 'Espresso', artist: 'Sabrina', note: 'this one'),
    ];
    await tester.pumpWidget(_app(const PeopleSection(), people: list(supported: true, reactions: reactions)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reactions'), findsOneWidget);
    expect(find.text('Sana reacted 🔥'), findsOneWidget);
    expect(find.text('Espresso · Sabrina — “this one”'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Sana reacted 🔥')).dy, lessThan(tester.getTopLeft(find.text('Dev reacted 👏')).dy));
  });

  testWidgets('the Social recap lists each Blend friend and is absent without one', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app(const RecapSection(), weekly: recap));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your week'), findsOneWidget);
    expect(find.text('3 h 12 min'), findsOneWidget);
    expect(find.text('You + Sana'), findsOneWidget);
    expect(find.text('74% match · 1 shared artist'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(const RecapSection(), weekly: null));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your week'), findsNothing); // an older server: hidden
  });

  testWidgets('Home shows the recap and “Not now” hides it', (tester) async {
    phone(tester);
    final dismiss = _Dismiss();
    await tester.pumpWidget(_app(const HomeRecapSection(), weekly: recap, dismiss: dismiss));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Closest to Sana: 74% match · 1 shared artist'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your week'), findsNothing);
    expect(dismiss.week, isNotNull);
  });

  testWidgets('the full recap shows shared artists and listening time', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app(RecapBody(recap: recap)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Anirudh'), findsOneWidget);
    expect(find.text('3 · 2'), findsOneWidget);
    expect(find.text('You 3 h 12 min · Sana 1 h 30 min'), findsOneWidget);
  });
}
