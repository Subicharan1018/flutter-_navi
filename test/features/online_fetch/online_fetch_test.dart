import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/data/fetch_models.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/online_fetch/ui/widgets/fetch_candidate_row.dart';

/// The exact body the live server returned for "rowdy baby" (2026-10-16).
const _inLibraryJson = '''
{"candidates":[],"created_at":1792164192.4,"did_you_mean":null,"error":null,"id":18,
 "library":{"artist":"","matches":[{"album":"Rowdy Baby (From \\"Maari 2\\")",
   "artist":"Yuvan Shankar Raja • Prashant Pandey","id":"BVLDhaybfNoZVSx3g1kBTF",
   "reason":"exact title","score":100.0,"suffix":"flac","title":"Rowdy Baby (From \\"Maari 2\\")"}],
   "query":"rowdy baby","verdict":"in_library"},
 "llm_state":"off","query":"rowdy baby","status":"in_library"}
''';

Map<String, dynamic> _results({String llm = 'done', String status = 'done'}) => {
      'id': 10,
      'query': 'kanmani anbodu',
      'status': status,
      'did_you_mean': null,
      'llm_state': llm,
      'error': null,
      'library': {'verdict': 'not_found', 'matches': []},
      'candidates': [
        {
          'id': 71, 'title': 'Kanmani Anbodu Kadhalan (From "Guna")', 'artist': 'Kamal Haasan',
          'album': 'Guna (Original Motion Picture Soundtrack)', 'score': 100.0, 'kind': 'original',
          'reasons': ['film release', 'AI: best match'], 'library': 'not_found',
          'llm': {'kind': 'original', 'is_requested_song': true},
        },
        {
          'id': 63, 'title': 'Kanmani Anbodu', 'artist': 'Suhail Kadavath', 'album': 'Kanmani Anbodu',
          'score': 55.0, 'kind': 'cover', 'reasons': ['AI: cover'], 'library': 'not_found', 'llm': null,
        },
      ],
    };

/// Answers /fetch requests from a script instead of the network.
class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions o) handler;
  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async => handler(o);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {'content-type': ['application/json']},
    );

OnlineFetchApi _api(ResponseBody Function(RequestOptions o) handler) =>
    OnlineFetchApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = _FakeAdapter(handler));

void main() {
  group('models', () {
    test('parses the live in-library answer', () {
      final s = FetchSearch.fromJson(jsonDecode(_inLibraryJson) as Map<String, dynamic>);
      expect(s.status, FetchSearchStatus.inLibrary);
      expect(s.libraryMatches.single.songId, 'BVLDhaybfNoZVSx3g1kBTF');
      expect(s.isSettled, isTrue);
    });

    test('results: kinds, AI flag, pending AI keeps polling', () {
      final s = FetchSearch.fromJson(_results(llm: 'pending'));
      expect(s.candidates.first.kind, FetchKind.original);
      expect(s.candidates.first.aiChecked, isTrue);
      expect(s.candidates.last.kind.label, 'Cover');
      expect(s.isSettled, isFalse);
    });

    test('server job statuses map to what the user sees', () {
      FetchJobPhase phase(String s) => FetchJob.fromJson({'id': 1, 'candidate_id': 2, 'status': s}).phase;
      expect(phase('picking'), FetchJobPhase.preparing);
      expect(phase('downloading'), FetchJobPhase.downloading);
      expect(phase('scanning'), FetchJobPhase.adding);
      expect(phase('imported'), FetchJobPhase.adding);
      expect(phase('ready'), FetchJobPhase.ready);
      expect(phase('rejected'), FetchJobPhase.rejected);
      expect(phase('import_failed'), FetchJobPhase.failed);
      expect(FetchJob.fromJson({'id': 1, 'candidate_id': 2, 'status': 'ready'}).isFinished, isTrue);
    });
  });

  group('api', () {
    test('server wording is shown for limits', () async {
      final api = _api((_) => _json(429, {'error': 'daily download limit reached'}));
      await expectLater(
        api.startDownload(5),
        throwsA(isA<OnlineFetchException>().having((e) => e.message, 'message', 'daily download limit reached')),
      );
    });

    test('enabled is false on any error', () async {
      expect(await _api((_) => _json(503, {'error': 'offline'})).enabled(), isFalse);
      expect(await _api((_) => _json(200, {'enabled': true})).enabled(), isTrue);
    });
  });

  group('controllers', () {
    setUp(() {
      OnlineSearchController.pollEvery = Duration.zero;
      FetchJobsController.pollEvery = Duration.zero;
    });

    test('search polls until the AI check has answered', () async {
      var polls = 0;
      final api = _api((o) {
        if (o.method == 'POST') return _json(202, {'search_id': 10});
        polls++;
        return _json(200, _results(llm: polls < 3 ? 'pending' : 'done'));
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final sub = c.listen(onlineSearchProvider, (_, _) {});
      addTearDown(sub.close);

      await c.read(onlineSearchProvider.notifier).start('kanmani anbodu');
      final s = c.read(onlineSearchProvider);
      expect(polls, 3);
      expect(s.search!.isSettled, isTrue);
      expect(s.search!.candidates.first.artist, 'Kamal Haasan');
    });

    test('download goes preparing → downloading → ready', () async {
      final statuses = ['picking', 'downloading', 'scanning', 'ready'];
      var i = 0;
      final seen = <FetchJobPhase>[];
      final api = _api((o) {
        if (o.method == 'POST') return _json(202, {'job_id': 3});
        return _json(200, {
          'id': 3, 'candidate_id': 71, 'status': statuses[i++], 'progress': 0.5,
          'nd_song_id': i == statuses.length ? 'nd-new' : null,
        });
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      c.listen(fetchJobsProvider, (_, next) {
        final p = next[71]?.phase;
        if (p != null && (seen.isEmpty || seen.last != p)) seen.add(p);
      });

      await c.read(fetchJobsProvider.notifier).download(71);
      expect(seen, [FetchJobPhase.preparing, FetchJobPhase.downloading, FetchJobPhase.adding, FetchJobPhase.ready]);
      expect(c.read(fetchJobsProvider)[71]!.songId, 'nd-new');
    });

    test('a failed start is shown, and tapping again retries', () async {
      var posts = 0;
      final api = _api((o) {
        if (o.method == 'GET') return _json(200, {'id': 4, 'candidate_id': 71, 'status': 'rejected'});
        posts++;
        return posts == 1 ? _json(429, {'error': 'daily download limit reached'}) : _json(202, {'job_id': 4});
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final jobs = c.read(fetchJobsProvider.notifier);

      await jobs.download(71);
      expect(c.read(fetchJobsProvider)[71]!.phase, FetchJobPhase.failed);
      expect(c.read(fetchJobsProvider)[71]!.error, 'daily download limit reached');

      await jobs.download(71);                       // a failed job can be retried…
      expect(posts, 2);
      expect(c.read(fetchJobsProvider)[71]!.phase, FetchJobPhase.rejected);
      await jobs.download(71);                       // …a finished one is not restarted
      expect(posts, 2);
    });
  });

  group('row', () {
    Future<void> pump(WidgetTester tester, FetchCandidate cand, {FetchJob? job}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          if (job != null) fetchJobsProvider.overrideWith(() => _SeededJobs({cand.id: job})),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ThemeTokens(
              tokens: AppThemeTokens.fallback,
              child: FetchCandidateRow(candidate: cand, onDownload: () {}, onPlayOwned: () {}),
            ),
          ),
        ),
      ));
    }

    final cover = FetchCandidate.fromJson((_results()['candidates'] as List).last as Map<String, dynamic>);

    testWidgets('labels a cover', (tester) async {
      await pump(tester, cover);
      expect(find.text('Cover'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows download progress', (tester) async {
      await pump(tester, cover,
          job: const FetchJob(id: 3, candidateId: 63, phase: FetchJobPhase.downloading, progress: 0.42));
      expect(find.text('Downloading 42%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('explains a lossy-only result', (tester) async {
      await pump(tester, cover, job: const FetchJob(id: 3, candidateId: 63, phase: FetchJobPhase.rejected));
      expect(find.text('Not available in lossless quality'), findsOneWidget);
    });
  });
}

class _SeededJobs extends FetchJobsController {
  final Map<int, FetchJob> seed;
  _SeededJobs(this.seed);

  @override
  Map<int, FetchJob> build() => seed;
}
