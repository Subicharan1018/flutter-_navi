import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/listen/data/listen_api.dart';
import 'package:navivibe/features/listen/data/listen_models.dart';
import 'package:navivibe/features/listen/logic/listen_providers.dart';
import 'package:navivibe/features/moods/data/mood_labels.dart';
import 'package:navivibe/features/moods/logic/mood_overrides_provider.dart';
import 'package:navivibe/models/catalog.dart';
import 'package:navivibe/providers/settings_provider.dart';

/// A stand-in for the server's `/moods/…` routes: remembers the marks.
class _Server implements HttpClientAdapter {
  final Map<String, Set<String>> marks;
  bool fail = false;
  final List<RequestOptions> seen = [];
  _Server([Map<String, Set<String>>? marks]) : marks = marks ?? {};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? requestBody, Future<void>? cancel) async {
    seen.add(o);
    if (fail) return ResponseBody.fromString('{}', 503, headers: _json);
    if (o.path == '/moods/overrides') {
      return ResponseBody.fromString(
        jsonEncode({'overrides': {for (final e in marks.entries) e.key: e.value.toList()}}),
        200,
        headers: _json,
      );
    }
    final body = o.data as Map;
    final id = body['song_id'] as String, mood = body['mood'] as String;
    o.method == 'DELETE' ? marks[id]?.remove(mood) : (marks[id] ??= {}).add(mood);
    return ResponseBody.fromString(jsonEncode({'ok': true, 'song_id': id}), 200, headers: _json);
  }

  @override
  void close({bool force = false}) {}
}

const _json = {
  'content-type': ['application/json'],
};

class _Settings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _Settings(String user) : super(SettingsState(serverUrl: 'https://music.example', username: user, password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

ProviderContainer _container(_Server server, {String user = 'me'}) {
  final c = ProviderContainer(overrides: [
    listenApiProvider.overrideWithValue(ListenApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = server)),
    settingsProvider.overrideWith((ref) => _Settings(user)),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// Waits (up to 3 s) for [done]: the provider's first load is a real Dio round
/// trip to the stand-in, which takes a few event-loop turns.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _settle([_Server? server]) async {
  await _until(() => server == null || server.seen.isNotEmpty);
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void main() {
  test('the catalog carries the server labels; no label means no mood', () {
    final s = CatalogSong.fromJson({
      'id': 'a',
      'moods': ['Sad', 'romantic', 3, ''],
    });
    expect(s.moods, ['sad', 'romantic']);
    expect(CatalogSong.fromJson({'id': 'b', 'genre': 'Melody'}).moods, isEmpty);
    expect(effectiveMoods(s.moods, {'sad'}), ['romantic']);
    expect(effectiveMoods(s.moods, null), ['sad', 'romantic']);
  });

  test('the overrides reply parses, junk is dropped', () {
    expect(
      parseMoodOverrides({
        'overrides': {
          'a': ['sad'],
          'b': <String>[],
          'c': 'calm',
        },
      }),
      {
        'a': {'sad'},
      },
    );
    expect(parseMoodOverrides(const {}), isEmpty);
  });

  test('loads your marks once signed in', () async {
    final server = _Server({
      'x': {'calm'},
    });
    final c = _container(server);
    c.listen(moodOverridesProvider, (_, _) {});
    expect(c.read(moodOverridesProvider), isEmpty);
    await _until(() => c.read(moodOverridesProvider).isNotEmpty);
    expect(c.read(moodOverridesProvider), {
      'x': {'calm'},
    });
  });

  test('signed out: asks nothing', () async {
    final server = _Server();
    final c = _container(server, user: '');
    c.listen(moodOverridesProvider, (_, _) {});
    await _settle();
    expect(server.seen, isEmpty);
  });

  test('"Not this mood" shows at once, reaches the server, and Undo takes it back', () async {
    final server = _Server();
    final c = _container(server);
    c.listen(moodOverridesProvider, (_, _) {});
    await _settle();
    final n = c.read(moodOverridesProvider.notifier);

    final mark = n.markNot('s1', 'sad');
    expect(c.read(moodOverridesProvider)['s1'], {'sad'}); // before the server answers
    expect(await mark, isTrue);
    expect(server.marks['s1'], {'sad'});
    final post = server.seen.last;
    expect((post.method, post.path), ('POST', '/moods/not-this'));
    expect(post.data, {'song_id': 's1', 'mood': 'sad'});

    expect(await n.unmark('s1', 'sad'), isTrue);
    expect(c.read(moodOverridesProvider).containsKey('s1'), isFalse);
    expect(server.seen.last.method, 'DELETE');
    expect(server.marks['s1'], isEmpty);
  });

  test('a refused mark is taken back', () async {
    final server = _Server();
    final c = _container(server);
    c.listen(moodOverridesProvider, (_, _) {});
    await _settle();
    server.fail = true;
    expect(await c.read(moodOverridesProvider.notifier).markNot('s1', 'calm'), isFalse);
    expect(c.read(moodOverridesProvider), isEmpty);
  });
}
