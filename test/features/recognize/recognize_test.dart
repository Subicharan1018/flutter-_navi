import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/recognize/data/mic_recorder.dart';
import 'package:navivibe/features/recognize/data/recognize_api.dart';
import 'package:navivibe/features/recognize/data/recognize_models.dart';
import 'package:navivibe/features/recognize/logic/recognize_controller.dart';
import 'package:navivibe/features/recognize/ui/recognize_sheet.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/test_utils.dart' show makeSong;

class _FakeMic implements MicRecorder {
  MicAccess answer;
  String? clip;
  bool started = false;
  bool cancelled = false;
  bool openedSettings = false;
  int accessCalls = 0;

  _FakeMic({this.answer = MicAccess.granted, this.clip = 'clip.wav'});

  @override
  Future<MicAccess> access({required bool request}) async {
    accessCalls++;
    return answer;
  }

  @override
  Future<String> start() async {
    started = true;
    return clip ?? 'none';
  }

  @override
  Future<String?> stop() async => clip;

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> openSettings() async => openedSettings = true;

  @override
  Future<void> dispose() async {}
}

class _FakeApi implements RecognizeApi {
  RecognizeResult? result;
  RecognizeException? error;
  final paths = <String>[];

  _FakeApi({this.result, this.error});

  @override
  Future<RecognizeResult> recognize(String audioPath) async {
    paths.add(audioPath);
    if (error != null) throw error!;
    return result!;
  }
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  final queued = <List<Song>>[];
  _FakePlayer(super.state);

  @override
  Future<void> setQueue(List<Song> songs, int index,
      {String? playlistName, List<Song>? unshuffledSongs, bool forceShuffle = false}) async {
    queued.add(songs);
  }

  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

const _inLibrary = RecognizeResult(
  recognized: true,
  title: 'Kanmani Anbodu',
  artist: 'Kamal Haasan',
  album: 'Guna',
  score: 0.93,
  library: [LibraryHit(songId: 'lib-1', title: 'Kanmani Anbodu', artist: 'Kamal Haasan')],
);

const _outside = RecognizeResult(recognized: true, title: 'Rowdy Baby', artist: 'Dhanush');

ProviderContainer _container({required _FakeMic mic, required _FakeApi api}) {
  final c = ProviderContainer(overrides: [
    micRecorderProvider.overrideWithValue(mic),
    recognizeApiProvider.overrideWithValue(api),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _wait() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  setUp(() => RecognizeController.listenFor = const Duration(milliseconds: 10));

  group('models', () {
    test('a recognised track keeps its library matches; junk ids are dropped', () {
      final r = RecognizeResult.fromJson({
        'recognized': true,
        'title': 'T',
        'artist': 'A',
        'score': 0.8,
        'library': [
          {'song_id': 'a', 'title': 'T', 'artist': 'A'},
          {'title': 'no id'},
        ],
      });
      expect(r.inLibrary, isTrue);
      expect(r.library.single.songId, 'a');
      expect(r.searchText, 'T A');
    });

    test('anything not marked recognised is not found', () {
      expect(RecognizeResult.fromJson({'recognized': false, 'title': 'x'}).recognized, isFalse);
      expect(RecognizeResult.fromJson(const {}).inLibrary, isFalse);
    });
  });

  group('api', () {
    late File clip;
    setUp(() async {
      clip = File('${Directory.systemTemp.path}${Platform.pathSeparator}recognize_api_test.wav');
      await clip.writeAsBytes(List.filled(64, 1));
    });
    tearDown(() async {
      // Windows keeps the file open until the unread upload stream is collected.
      try {
        await clip.delete();
      } on FileSystemException {
        // a temp file; the OS clears it
      }
    });

    test('uploads the clip as multipart and parses the answer', () async {
      final adapter = FakeAdapter((_) => jsonBody(200, {
            'recognized': true,
            'title': 'T',
            'artist': 'A',
            'library': [
              {'song_id': 'x', 'title': 'T', 'artist': 'A'},
            ],
          }));
      final r = await RecognizeApi(fakeDio(adapter)).recognize(clip.path);
      final sent = adapter.requests.single;
      expect(sent.path, '/recognize');
      expect(sent.data, isA<FormData>());
      expect((sent.data as FormData).files.single.key, 'audio');
      expect(r.library.single.songId, 'x');
    });

    test('explains a server that has no key or no route', () async {
      Future<String> messageFor(int code, [Map<String, dynamic>? body]) async {
        final api = RecognizeApi(fakeDio(FakeAdapter((_) => jsonBody(code, body ?? const {}))));
        try {
          await api.recognize(clip.path);
        } on RecognizeException catch (e) {
          return e.message;
        }
        return '';
      }

      expect(await messageFor(404), contains('doesn’t support'));
      expect(await messageFor(503, {'error': 'ACOUSTID_API_KEY is not set'}), 'ACOUSTID_API_KEY is not set');
      expect(await messageFor(503), contains('isn’t set up'));
    });
  });

  group('controller', () {
    test('listens, sends the clip, shows the match, and the clip is not kept', () async {
      final mic = _FakeMic();
      final api = _FakeApi(result: _inLibrary);
      final c = _container(mic: mic, api: api);
      final sub = c.listen(recognizeProvider, (_, _) {});
      addTearDown(sub.close);

      final started = c.read(recognizeProvider.notifier).start();
      await started;
      expect(c.read(recognizeProvider).phase, RecognizePhase.listening);
      expect(mic.started, isTrue);

      await _wait();
      expect(c.read(recognizeProvider).phase, RecognizePhase.found);
      expect(c.read(recognizeProvider).result!.title, 'Kanmani Anbodu');
      expect(api.paths, ['clip.wav']);
    });

    test('an unrecognised clip is "not found", not an error', () async {
      final c = _container(mic: _FakeMic(), api: _FakeApi(result: RecognizeResult.notFound));
      final sub = c.listen(recognizeProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(recognizeProvider.notifier).start();
      await _wait();
      expect(c.read(recognizeProvider).phase, RecognizePhase.notFound);
    });

    test('a server failure is shown in its own words', () async {
      final c = _container(
        mic: _FakeMic(),
        api: _FakeApi(error: const RecognizeException('Song recognition isn’t set up on your server yet.')),
      );
      final sub = c.listen(recognizeProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(recognizeProvider.notifier).start();
      await _wait();
      expect(c.read(recognizeProvider).phase, RecognizePhase.failed);
      expect(c.read(recognizeProvider).message, contains('isn’t set up'));
    });

    test('permission: asked again when only denied, Settings when blocked, no recording either way', () async {
      final mic = _FakeMic(answer: MicAccess.denied);
      final c = _container(mic: mic, api: _FakeApi(result: _inLibrary));
      final sub = c.listen(recognizeProvider, (_, _) {});
      addTearDown(sub.close);
      final ctl = c.read(recognizeProvider.notifier);

      await ctl.start();
      expect(c.read(recognizeProvider).phase, RecognizePhase.needsPermission);
      expect(mic.started, isFalse);

      mic.answer = MicAccess.blocked;
      await ctl.start();
      expect(c.read(recognizeProvider).phase, RecognizePhase.blocked);
      await ctl.openSettings();
      expect(mic.openedSettings, isTrue);

      mic.answer = MicAccess.granted;
      await ctl.start();
      expect(c.read(recognizeProvider).phase, RecognizePhase.listening);
      expect(mic.accessCalls, 3);
    });

    test('cancel stops the microphone and nothing is sent', () async {
      final mic = _FakeMic();
      final api = _FakeApi(result: _inLibrary);
      RecognizeController.listenFor = const Duration(milliseconds: 200);
      final c = _container(mic: mic, api: api);
      final sub = c.listen(recognizeProvider, (_, _) {});
      addTearDown(sub.close);
      final ctl = c.read(recognizeProvider.notifier);

      await ctl.start();
      await ctl.cancel();
      expect(mic.cancelled, isTrue);
      expect(c.read(recognizeProvider).phase, RecognizePhase.idle);
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(api.paths, isEmpty);
      expect(c.read(recognizeProvider).phase, RecognizePhase.idle);
    });

    test('an empty recording fails cleanly', () async {
      final c = _container(mic: _FakeMic(clip: null), api: _FakeApi(result: _inLibrary));
      final sub = c.listen(recognizeProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(recognizeProvider.notifier).start();
      await _wait();
      expect(c.read(recognizeProvider).phase, RecognizePhase.failed);
    });
  });

  group('sheet', () {
    late _FakePlayer player;

    Widget app(RecognizeResult result, {bool online = false}) {
      player = _FakePlayer(PlayerState(
        queue: const [],
        currentIndex: 0,
        isPlaying: false,
        shuffleMode: false,
        autoplayMode: false,
        repeatMode: LoopMode.off,
        starredIds: const [],
        syncMode: SyncMode.activeHere,
      ));
      return ProviderScope(
        overrides: [
          micRecorderProvider.overrideWithValue(_FakeMic()),
          recognizeApiProvider.overrideWithValue(_FakeApi(result: result)),
          playerProvider.overrideWith((ref) => player),
          subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
          recognizedSongProvider.overrideWith((ref, id) async => makeSong(id: id, title: 'Kanmani Anbodu')),
          onlineFetchEnabledProvider.overrideWith((ref) async => online),
        ],
        child: Builder(builder: (context) {
          final tokens = AppThemeTokens.fallback;
          return ThemeTokens(
            tokens: tokens,
            child: MaterialApp(
              theme: AppTheme.build(tokens),
              home: Scaffold(body: SingleChildScrollView(child: RecognizeSheet(hostContext: context))),
            ),
          );
        }),
      );
    }

    Future<void> listen(WidgetTester tester) async {
      await tester.pump(); // starts listening
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20)); // answer is in
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a library song offers Play Now, queueing and playlists; Play Now plays it', (tester) async {
      await tester.pumpWidget(app(_inLibrary));
      await listen(tester);
      expect(find.text('Song identified'), findsOneWidget);
      expect(find.text('Kanmani Anbodu'), findsWidgets);
      expect(find.text('Play Next'), findsOneWidget);
      expect(find.text('Play Last'), findsOneWidget);
      expect(find.text('Add to Playlist…'), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      await tester.tap(find.text('Play Now'));
      await tester.pump();
      expect(player.queued.single.single.id, 'lib-1');
    });

    testWidgets('a song that is not in the library offers a download when online fetch is on', (tester) async {
      await tester.pumpWidget(app(_outside, online: true));
      await listen(tester);
      expect(find.text('Rowdy Baby'), findsOneWidget);
      expect(find.text('Play Now'), findsNothing);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('without online fetch it only says it is not in the library', (tester) async {
      await tester.pumpWidget(app(_outside));
      await listen(tester);
      expect(find.textContaining('isn’t in your library'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });
  });
}
