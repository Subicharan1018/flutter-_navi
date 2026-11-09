import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/data/fetch_models.dart';
import 'package:navivibe/features/online_fetch/data/fetch_queue_models.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/online_fetch/ui/fetch_queue_sheet.dart';
import 'package:navivibe/features/online_fetch/ui/widgets/fetch_candidate_row.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';

/// (B) A song the author blocked: final, counted apart from failures, no Retry.

const _blockedSong = {
  'id': 90, 'title': 'Pulled Song', 'artist': 'Artist B', 'album': 'Album', 'score': 100.0, 'kind': 'original',
  'reasons': <String>[], 'library': 'not_found', 'llm': null,
  'blocked': true, 'blocked_reason': 'Blocked by the author — the bot can’t send this one (gone)',
};

Map<String, dynamic> _batch(String status, {Map<String, dynamic>? more}) => {
      'id': 5, 'kind': 'album', 'title': 'Maari 2', 'artist': 'Yuvan', 'status': status, 'error': null,
      'candidate_ids': [1, 2, 3], 'total': 3, 'added': 1, 'owned': 0, 'lossy': 0, 'failed': 0, 'blocked': 2,
      'progress': 1.0, 'items': <Object>[], ...?more,
    };

class _Seeded extends FetchJobsController {
  final FetchDownloads seed;
  _Seeded(this.seed);
  @override
  FetchDownloads build() => seed;
}

Finder _glyph(NaviGlyph g) => find.byWidgetPredicate((w) => w is NaviIcon && w.glyph == g);

void main() {
  group('models', () {
    test('a blocked job is a finished phase of its own, not a failure', () {
      final j = FetchJob.fromJson({'id': 1, 'candidate_id': 2, 'status': 'blocked', 'error': 'x'});
      expect(j.phase, FetchJobPhase.blocked);
      expect(j.isFinished, isTrue);
      expect(j.phase, isNot(FetchJobPhase.failed));
    });

    test('the candidate carries the server’s blocked flag', () {
      expect(FetchCandidate.fromJson(_blockedSong).blocked, isTrue);
      expect(FetchCandidate.fromJson({..._blockedSong, 'blocked': null}).blocked, isFalse);
    });

    test('batch counts blocked apart from failed, and says so in the summary', () {
      final b = FetchBatch.fromJson(_batch('done'));
      expect((b.added, b.blocked, b.failed), (1, 2, 0));
      expect(b.handled, 3);
      expect(b.summary, '1 song added, 2 are blocked by the author');
      expect(b.headline, 'Album downloaded');
      expect(FetchBatch.fromJson(_batch('done', more: {'kind': 'songs', 'total': 3})).headline, 'Songs downloaded');
      expect(FetchBatch.fromJson(_batch('done', more: {'blocked': 1, 'total': 2})).summary,
          '1 song added, 1 is blocked by the author');
      final playlist = FetchBatch.fromJson(_batch('done', more: {'kind': 'playlist'}));
      expect(playlist.summary, '1 of 3 songs. 2 are blocked by the author.');
    });

    test('an older server without the field still parses', () {
      final b = FetchBatch.fromJson({..._batch('done')}..remove('blocked'));
      expect(b.blocked, 0);
      expect(b.summary, '1 song added');
    });

    test('queue items count blocked among the songs handled, apart from failed', () {
      final i = FetchQueueItem.fromJson({
        'id': 1, 'status': 'running', 'kind': 'album', 'title': 'Maari 2', 'total': 10,
        'added': 3, 'owned': 1, 'lossy': 0, 'failed': 1, 'blocked': 2,
      });
      expect((i.blocked, i.failed, i.handled), (2, 1, 7));
      expect(describeQueueItem(i), 'Album · 7 of 10 songs');
      final done = FetchQueueItem.fromJson({
        'id': 2, 'status': 'done', 'kind': 'album', 'title': 'X', 'total': 3, 'added': 1, 'blocked': 2,
        'summary': '1 song added, 2 are blocked by the author',
      });
      expect(describeQueueItem(done), 'Album · 1 song added, 2 are blocked by the author');
      expect(done.canRetry, isFalse, reason: 'a finished batch with blocked songs offers no Retry');
    });
  });

  group('rules', () {
    test('a blocked song is not tappable: no download, no retry', () {
      final c = FetchCandidate.fromJson(_blockedSong);
      expect(fetchCandidateTappable(c, job: null, batch: null, selecting: false), isFalse);
      expect(fetchCandidateTappable(c, job: null, batch: null, selecting: true), isFalse);
      final fresh = FetchCandidate.fromJson({..._blockedSong, 'blocked': false});
      final blockedJob = FetchJob(id: 1, candidateId: 90, phase: FetchJobPhase.blocked);
      expect(fetchCandidateTappable(fresh, job: blockedJob, batch: null, selecting: false), isFalse);
      // …while a plainly failed one can still be tried again.
      final failedJob = FetchJob(id: 1, candidateId: 90, phase: FetchJobPhase.failed);
      expect(fetchCandidateTappable(fresh, job: failedJob, batch: null, selecting: false), isTrue);
    });

    test('the words', () {
      expect(fetchJobStatus(FetchJob(id: 1, candidateId: 2, phase: FetchJobPhase.blocked)), kBlockedByAuthor);
      expect(kBlockedByAuthor, 'Blocked by the author — the bot can’t send this one');
    });
  });

  group('rows', () {
    Future<void> pump(WidgetTester tester, FetchCandidate c, {FetchJob? job}) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          if (job != null) fetchJobsProvider.overrideWith(() => _Seeded(FetchDownloads(jobs: {c.id: job}))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ThemeTokens(
              tokens: AppThemeTokens.fallback,
              child: FetchCandidateRow(candidate: c, onDownload: () {}, onPlayOwned: () {}),
            ),
          ),
        ),
      ));
    }

    testWidgets('a result the bot already refused says so and offers no download', (tester) async {
      await pump(tester, FetchCandidate.fromJson(_blockedSong));
      expect(find.text(kBlockedByAuthor), findsOneWidget);
      expect(_glyph(NaviGlyph.downloadCircle), findsNothing);
      expect(_glyph(NaviGlyph.alert), findsNothing, reason: 'blocked is not an error');
    });

    testWidgets('a job that ended blocked shows the same words', (tester) async {
      final c = FetchCandidate.fromJson({..._blockedSong, 'blocked': false});
      await pump(tester, c, job: FetchJob(id: 1, candidateId: c.id, phase: FetchJobPhase.blocked));
      expect(find.text(kBlockedByAuthor), findsOneWidget);
      expect(_glyph(NaviGlyph.alert), findsNothing);
    });

    testWidgets('an ordinary result still offers the download', (tester) async {
      await pump(tester, FetchCandidate.fromJson({..._blockedSong, 'blocked': false}));
      expect(find.text(kBlockedByAuthor), findsNothing);
      expect(_glyph(NaviGlyph.downloadCircle), findsOneWidget);
    });
  });
}
