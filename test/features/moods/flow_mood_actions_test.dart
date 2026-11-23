import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/flow/logic/flow_controller.dart';
import 'package:navivibe/features/flow/ui/flow_pill.dart';
import 'package:navivibe/features/listen/data/listen_api.dart';
import 'package:navivibe/features/listen/logic/listen_providers.dart';
import 'package:navivibe/features/moods/logic/flow_mood_actions.dart';
import 'package:navivibe/features/moods/logic/mood_overrides_provider.dart';
import 'package:navivibe/features/moods/ui/flow_mood_buttons.dart';
import 'package:navivibe/features/moods/ui/mood_picker.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';

import '../../helpers/test_utils.dart' show makeSong;

// ── fakes ────────────────────────────────────────────────────────────────────

class _Flow extends FlowController {
  final FlowState initial;
  _Flow(this.initial);
  @override
  FlowState build() => initial;
}

class _Player extends StateNotifier<PlayerState> implements PlayerNotifier {
  final removed = <int>[];
  var skips = 0;
  _Player(List<Song> queue, int current)
      : super(PlayerState(
          queue: queue,
          currentIndex: current,
          isPlaying: true,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: const [],
          syncMode: SyncMode.activeHere,
        ));

  @override
  Future<void> removeFromQueue(int index, {bool track = true}) async {
    removed.add(index);
    state = state.copyWith(queue: [...state.queue]..removeAt(index));
  }

  @override
  Future<void> playNext() async {
    skips++;
    state = state.copyWith(currentIndex: state.currentIndex + 1);
  }

  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

/// The shuffle server's /moods routes.
class _Server implements HttpClientAdapter {
  final marks = <String, Set<String>>{};
  final puts = <String, List<String>>{};
  bool admin = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? requestBody, Future<void>? cancel) async {
    Map<String, dynamic> out = {};
    if (o.path == '/moods/overrides') {
      out = {'overrides': {for (final e in marks.entries) e.key: e.value.toList()}};
    } else if (o.path == '/moods/me') {
      out = {'username': 'me', 'is_admin': admin};
    } else if (o.path.startsWith('/moods/songs/')) {
      final id = Uri.decodeComponent(o.path.split('/').last);
      puts[id] = [for (final m in (o.data as Map)['moods'] as List) m.toString()];
      out = {'ok': true, 'song': {'id': id, 'moods': puts[id]}};
    } else if (o.path == '/moods/not-this') {
      final b = o.data as Map;
      final s = marks[b['song_id']] ??= {};
      o.method == 'DELETE' ? s.remove(b['mood']) : s.add(b['mood'] as String);
      out = {'ok': true};
    }
    return ResponseBody.fromString(jsonEncode(out), 200, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Settings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _Settings() : super(SettingsState(serverUrl: 'https://music.example', username: 'me', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

final _songs = [for (var i = 0; i < 6; i++) makeSong(id: 's$i', title: 'Song $i')];

List<Override> _overrides(_Player player, _Server server, {String? mood = 'sad', bool active = true}) => [
      playerProvider.overrideWith((ref) => player),
      flowProvider.overrideWith(() => _Flow(FlowState(active: active, mood: mood))),
      listenApiProvider.overrideWithValue(ListenApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = server)),
      settingsProvider.overrideWith((ref) => _Settings()),
    ];

Widget _app(List<Override> overrides, Widget child) => ProviderScope(
      overrides: overrides,
      child: ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: MaterialApp(
          theme: AppTheme.build(AppThemeTokens.fallback),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

/// A test widget's own fake for the buttons' actions.
class _Actions implements FlowMoodActions {
  final calls = <String>[];
  @override
  Future<bool> notThisMood(Song song, String mood) async {
    calls.add('not ${song.id} $mood');
    return true;
  }

  @override
  Future<bool> setMoods(Song song, {required List<String> moods, required List<String> labels, required bool admin}) async {
    calls.add('set ${song.id} $moods admin=$admin');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  test('only songs still to come are dropped, highest index first', () {
    expect(upcomingToDrop(_songs, 1, (s) => s.id != 's3'), [5, 4, 2]);
    expect(upcomingToDrop(_songs, 5, (_) => true), isEmpty);
  });

  group('the actions', () {
    late _Player player;
    late _Server server;
    late ProviderContainer c;

    setUp(() {
      // s1 plays; s1 comes again later, s4 was marked "not sad" before.
      player = _Player([_songs[0], _songs[1], _songs[2], _songs[3], _songs[1], _songs[4]], 1);
      server = _Server()..marks['s4'] = {'sad'};
      c = ProviderContainer(overrides: _overrides(player, server));
      addTearDown(c.dispose);
      c.listen(moodOverridesProvider, (_, _) {});
    });

    Future<void> loaded() async {
      for (var i = 0; i < 300 && c.read(moodOverridesProvider).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('"Not this mood" records it, drops the song and the ones it affects, and skips', () async {
      await loaded();
      expect(await c.read(flowMoodActionsProvider).notThisMood(_songs[1], 'sad'), isTrue);
      expect(server.marks['s1'], {'sad'});
      expect(player.removed, [5, 4]); // s4 (marked before) and s1's second turn
      expect(player.skips, 1); // s1 was playing
      expect([for (final s in player.state.queue) s.id], ['s0', 's1', 's2', 's3']);
    });

    test('a song not playing leaves the queue without a skip', () async {
      await loaded();
      await c.read(flowMoodActionsProvider).notThisMood(_songs[3], 'sad');
      expect(player.skips, 0);
      expect(player.state.queue.map((s) => s.id), isNot(contains('s3')));
    });

    test('outside a mood Flow nothing in the queue moves', () async {
      final p = _Player([..._songs], 0);
      final c2 = ProviderContainer(overrides: _overrides(p, _Server(), mood: null));
      addTearDown(c2.dispose);
      await c2.read(flowMoodActionsProvider).notThisMood(_songs[0], 'sad');
      expect(p.removed, isEmpty);
      expect(p.skips, 0);
    });

    test('Change mood as a listener marks the left-out moods for them only', () async {
      await loaded();
      final ok = await c.read(flowMoodActionsProvider).setMoods(_songs[2], moods: ['romantic'], labels: ['sad', 'romantic'], admin: false);
      expect(ok, isTrue);
      expect(server.marks['s2'], {'sad'});
      expect(server.puts, isEmpty);
      expect(player.state.queue.map((s) => s.id), isNot(contains('s2'))); // no longer sad: out of the sad Flow
    });

    test('Change mood as an admin saves for everyone and shows at once', () async {
      await loaded();
      final ok = await c.read(flowMoodActionsProvider).setMoods(_songs[1], moods: ['happy', 'energetic'], labels: ['sad'], admin: true);
      expect(ok, isTrue);
      expect(server.puts['s1'], ['happy', 'energetic']);
      expect(c.read(songMoodEditsProvider)['s1'], ['happy', 'energetic']);
      expect(player.skips, 1);
      expect(server.marks.containsKey('s1'), isFalse);
    });
  });

  group('the buttons', () {
    testWidgets('Home shows Not <Mood> and Change Mood while a mood Flow plays', (tester) async {
      final actions = _Actions();
      final player = _Player([..._songs], 2);
      await tester.pumpWidget(_app(
        [..._overrides(player, _Server()), flowMoodActionsProvider.overrideWithValue(actions)],
        const FlowMoodButtons(),
      ));
      expect(find.text('Playing “Song 2”'), findsOneWidget);
      await tester.tap(find.text('Not Sad'));
      await tester.pump();
      expect(actions.calls, ['not s2 sad']);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('won’t play as Sad for you'), findsOneWidget);
      expect(find.text('Change Mood…'), findsWidgets); // the button and the toast's action
    });

    testWidgets('nothing shows when Flow plays any mood', (tester) async {
      await tester.pumpWidget(_app(_overrides(_Player([..._songs], 0), _Server(), mood: null), const FlowMoodButtons()));
      expect(find.byType(TextButton), findsNothing);
      expect(find.textContaining('Not '), findsNothing);
    });

    testWidgets('Now Playing\'s Flow pill has a Not <Mood> capsule', (tester) async {
      final actions = _Actions();
      await tester.pumpWidget(_app(
        [..._overrides(_Player([..._songs], 0), _Server(), mood: 'calm'), flowMoodActionsProvider.overrideWithValue(actions)],
        const SizedBox(width: 420, child: FlowPill()),
      ));
      await tester.tap(find.byKey(const ValueKey('flow-pill-not-this-mood')));
      await tester.pump();
      expect(actions.calls, ['not s0 calm']);
    });
  });

  group('the mood picker', () {
    Future<List<String>?> pick(WidgetTester tester, {required bool admin, List<String> labels = const ['sad', 'romantic'],
        Set<String> notMine = const {}, required Future<void> Function() taps}) async {
      List<String>? saved;
      await tester.pumpWidget(_app(const [], SingleChildScrollView(
        child: MoodPicker(title: 'Song', labels: labels, notMine: notMine, admin: admin, onSave: (m) => saved = m),
      )));
      await taps();
      await tester.tap(find.text(admin ? 'Save for Everyone' : 'Save'));
      await tester.pump();
      return saved;
    }

    Future<void> tapMood(WidgetTester tester, String m) async {
      await tester.tap(find.byKey(ValueKey('mood-$m')));
      await tester.pump();
    }

    testWidgets('an admin picks up to 2 moods in order', (tester) async {
      final saved = await pick(tester, admin: true, taps: () async {
        expect(find.byKey(const ValueKey('mood-gym')), findsOneWidget); // all 7 moods + gym
        await tapMood(tester, 'sad'); // off
        await tapMood(tester, 'happy'); // romantic, happy
        await tapMood(tester, 'calm'); // a third: refused
        expect(find.textContaining('at most 2'), findsOneWidget);
      });
      expect(saved, ['romantic', 'happy']);
    });

    testWidgets('Save waits for a change', (tester) async {
      expect(await pick(tester, admin: true, taps: () async {}), isNull);
    });

    testWidgets('a listener can only take moods off, for themself', (tester) async {
      final saved = await pick(tester, admin: false, taps: () async {
        expect(find.byKey(const ValueKey('mood-happy')), findsNothing); // can't add
        await tapMood(tester, 'sad');
      });
      expect(saved, ['romantic']);
    });

    testWidgets('a listener can take a mark back', (tester) async {
      final saved = await pick(tester, admin: false, notMine: {'sad'}, taps: () => tapMood(tester, 'sad'));
      expect(saved, ['romantic', 'sad']);
    });
  });
}
