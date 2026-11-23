import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/data_queue/data/data_queue_api.dart';
import 'package:navivibe/features/data_queue/data/data_queue_models.dart';
import 'package:navivibe/features/data_queue/logic/data_queue_providers.dart';
import 'package:navivibe/features/data_queue/ui/data_queue_screen.dart';
import 'package:navivibe/features/exportify_import/logic/exportify_providers.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart';
import 'package:navivibe/widgets/ui/states.dart';

Map<String, dynamic> statusJson({int waiting = 230, bool full = true, Map<String, dynamic>? open, int real = 80}) => {
      'counts': {'waiting': waiting},
      'waiting': waiting,
      'batch_size': 200,
      'full_batch_ready': full,
      'next_batch': {'size': waiting > 200 ? 200 : waiting, 'full': full, 'with_isrc': 188, 'songs': []},
      'open_batch': open,
      'coverage': {'total': 400, 'real': real, 'predicted': 40, 'none': 400 - real - 40},
      'quality': {
        'waiting_by_source': {'request': 12, 'backfill': 218},
        'oldest_waiting_days': 9.4,
        'match_rate': 0.74,
      },
      'links': {'soundiiz': 'https://soundiiz.com/tutorial/import-excel-to-soundiiz', 'tunemymusic': 'https://www.tunemymusic.com/transfer/file-to-spotify'},
    };

Map<String, dynamic> batchJson({int id = 4, String state = 'open', int size = 200, Map<String, dynamic>? summary}) => {
      'id': id, 'state': state, 'size': size, 'created_at': 1763800000, 'uploaded_at': summary == null ? null : 1763900000,
      'released_at': null, 'summary': summary, 'songs': {},
    };

class _FakeApi implements DataQueueApi {
  QueueStatus? next;
  Object? statusError;
  Completer<void>? gate;
  final calls = <String>[];
  UploadSummary upload_ = const UploadSummary(batchId: 4, rows: 190, matched: 150, notFound: 50, featuresStored: 150, predicted: 50);
  @override
  Future<QueueStatus> status() async {
    calls.add('status');
    await gate?.future;
    if (statusError != null) throw statusError!;
    return next ?? QueueStatus.fromJson(statusJson());
  }

  @override
  Future<QueueBatch?> makeBatch() async {
    calls.add('make');
    next = QueueStatus.fromJson(statusJson(waiting: 30, full: false, open: batchJson()));
    return QueueBatch.fromJson(batchJson());
  }

  @override
  Future<List<QueueBatch>> history() async => [
        QueueBatch.fromJson(batchJson(id: 3, state: 'closed', summary: {'batch_id': 3, 'matched': 150, 'not_found': 50})),
      ];

  @override
  Future<Uint8List> file(int id, String format) async {
    calls.add('file:$id:$format');
    return Uint8List.fromList(utf8.encode('title,artist\n'));
  }

  @override
  Future<UploadSummary> upload(int id, String name, String csv) async {
    calls.add('upload:$id:$name:${csv.length}');
    return upload_;
  }

  @override
  Future<void> release(int id) async => calls.add('release:$id');
}

Widget _app(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: const DataQueueScreen())),
      ),
    );

List<Override> _overrides(_FakeApi api, {bool admin = true, Future<bool> Function(String, Uint8List, String)? saver, PickedCsv? picked}) => [
      dataQueueApiProvider.overrideWithValue(api),
      dataQueueAdminProvider.overrideWithValue(admin),
      if (saver != null) dataQueueSaverProvider.overrideWithValue(saver),
      exportifyCsvPickerProvider.overrideWithValue(() async => picked),
    ];

void _tall(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 3200);
  addTearDown(tester.view.reset);
}

void main() {
  group('models', () {
    test('status reads the counts, coverage, quality and links', () {
      final s = QueueStatus.fromJson(statusJson(open: batchJson()));
      expect(s.waiting, 230);
      expect(s.fullBatchReady, isTrue);
      expect(s.openBatch!.isOpen, isTrue);
      expect(s.coverage.share(s.coverage.real), 0.2);
      expect(s.waitingBySource['backfill'], 218);
      expect(s.matchRate, 0.74);
      expect(s.links.keys, containsAll(['soundiiz', 'tunemymusic']));
    });

    test('junk is tolerated', () {
      final s = QueueStatus.fromJson({'waiting': 'x', 'coverage': 5, 'open_batch': 'no'});
      expect(s.waiting, 0);
      expect(s.batchSize, 200);
      expect(s.openBatch, isNull);
      expect(s.coverage.share(1), 0);
    });
  });

  group('api', () {
    test('calls the admin routes', () async {
      final seen = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://x.test'))
        ..httpClientAdapter = _Adapter((o) {
          seen.add('${o.method} ${o.path}');
          if (o.path.endsWith('/file.csv')) return ResponseBody.fromBytes([1, 2, 3], 200);
          return ResponseBody.fromString(jsonEncode(o.path.endsWith('/upload')
              ? {'batch_id': 4, 'matched': 3, 'repeated': true}
              : statusJson()), 200, headers: {'content-type': ['application/json']});
        });
      final api = DataQueueApi(dio);
      expect((await api.status()).waiting, 230);
      expect(await api.file(4, 'csv'), [1, 2, 3]);
      final up = await api.upload(4, 'a.csv', 'x');
      expect((up.matched, up.repeated), (3, true));
      expect(seen, ['GET /data-queue/status', 'GET /data-queue/batches/4/file.csv', 'POST /data-queue/batches/4/upload']);
    });

    test('a 404 is a plain message, not a crash', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://x.test'))
        ..httpClientAdapter = _Adapter((o) => ResponseBody.fromString('{"error":"Not found"}', 404, headers: {'content-type': ['application/json']}));
      expect(DataQueueApi(dio).status(), throwsA(isA<OnlineFetchException>().having((e) => e.message, 'message', 'Not found')));
    });
  });

  group('screen', () {
    testWidgets('a full batch is ready: the nudge, the count and the make button', (tester) async {
      _tall(tester);
      final api = _FakeApi();
      await tester.pumpWidget(_app(_overrides(api)));
      await tester.pumpAndSettle();
      expect(find.text('230'), findsOneWidget);
      expect(find.text('A full batch of 200 is ready for this week.'), findsOneWidget);
      expect(find.text('Make this week’s batch'), findsOneWidget);
      expect(find.text('Real Spotify features'), findsOneWidget);
      expect(find.text('80 · 20%'), findsOneWidget);
      expect(find.text('Batch 3 · done'), findsOneWidget);
      expect(find.text('Soundiiz'), findsOneWidget);
    });

    testWidgets('making the batch shows its buttons; both files download', (tester) async {
      _tall(tester);
      final api = _FakeApi();
      final saved = <String>[];
      await tester.pumpWidget(_app(_overrides(api, saver: (n, b, m) async {
        saved.add('$n ${b.length} $m');
        return true;
      })));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make this week’s batch'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('make'));
      expect(find.text('This week’s batch'), findsOneWidget);
      expect(find.textContaining('Batch 4 · 200 songs'), findsOneWidget);
      expect(find.text('A full batch of 200 is ready for this week.'), findsNothing);
      await tester.tap(find.text('Download CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download TXT'));
      await tester.pumpAndSettle();
      expect(saved, ['navivibe_data_queue_04.csv 13 text/csv', 'navivibe_data_queue_04.txt 13 text/plain']);
      expect(find.text('Saved the txt file.'), findsOneWidget);
    });

    testWidgets('uploading the Exportify file shows what happened', (tester) async {
      _tall(tester);
      final api = _FakeApi()..next = QueueStatus.fromJson(statusJson(open: batchJson(), full: false));
      await tester.pumpWidget(_app(_overrides(api, picked: PickedCsv('mix.csv', utf8.encode('Track Name,Artist Name(s)\n')))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload Exportify CSV'));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.startsWith('upload:4:mix.csv')), hasLength(1));
      expect(find.text('Batch 4 applied'), findsOneWidget);
      expect(find.text('Matched on Spotify'), findsOneWidget);
      expect(find.text('150'), findsWidgets);
    });

    testWidgets('a repeated upload says nothing changed; a bad file shows the server’s sentence', (tester) async {
      _tall(tester);
      final api = _FakeApi()
        ..next = QueueStatus.fromJson(statusJson(open: batchJson(), full: false))
        ..upload_ = const UploadSummary(batchId: 4, matched: 150, repeated: true);
      await tester.pumpWidget(_app(_overrides(api, picked: PickedCsv('mix.csv', utf8.encode('x')))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload Exportify CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Already uploaded: nothing changed'), findsOneWidget);
    });

    testWidgets('an oversized file is refused before it is sent', (tester) async {
      _tall(tester);
      final api = _FakeApi()..next = QueueStatus.fromJson(statusJson(open: batchJson(), full: false));
      await tester.pumpWidget(_app(_overrides(api, picked: PickedCsv('big.csv', List.filled(8000001, 65)))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload Exportify CSV'));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.startsWith('upload')), isEmpty);
      expect(find.textContaining('bigger than 8 MB'), findsOneWidget);
    });

    testWidgets('releasing the batch', (tester) async {
      _tall(tester);
      final api = _FakeApi()..next = QueueStatus.fromJson(statusJson(open: batchJson(), full: false));
      await tester.pumpWidget(_app(_overrides(api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Release this batch'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('release:4'));
      expect(find.text('The songs are waiting again.'), findsOneWidget);
    });

    testWidgets('empty queue: no batch to make', (tester) async {
      _tall(tester);
      final api = _FakeApi()..next = QueueStatus.fromJson(statusJson(waiting: 0, full: false));
      await tester.pumpWidget(_app(_overrides(api)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing is waiting.'), findsOneWidget);
      await tester.tap(find.text('Make this week’s batch'));
      await tester.pump();
      expect(api.calls.where((c) => c == 'make'), isEmpty);
    });

    testWidgets('loading shows skeletons, a failure offers a retry that works', (tester) async {
      _tall(tester);
      final api = _FakeApi()
        ..statusError = const OnlineFetchException('down')
        ..gate = Completer<void>();
      await tester.pumpWidget(_app(_overrides(api)));
      await tester.pump();
      expect(find.byType(SkeletonBox), findsWidgets);
      api.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load the data queue'), findsOneWidget);
      api.statusError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('230'), findsOneWidget);
    });

    testWidgets('anyone but the admin sees nothing of the queue and the server is never asked', (tester) async {
      _tall(tester);
      final api = _FakeApi();
      await tester.pumpWidget(_app(_overrides(api, admin: false)));
      await tester.pumpAndSettle();
      expect(find.text('Only for the admin'), findsOneWidget);
      expect(find.text('230'), findsNothing);
      expect(api.calls, isEmpty);
    });
  });
}

class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions o) handler;
  _Adapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async => handler(o);

  @override
  void close({bool force = false}) {}
}
