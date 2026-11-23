import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/download_keep_alive.dart';
import 'package:navivibe/services/download_notices.dart';
import 'package:navivibe/services/download_queue.dart';

import '../../helpers/test_utils.dart';

Song s(String id) => makeSong(id: id, title: 'Title $id');

void main() {
  late List<String> started;
  late List<String> ended;
  late List<DownloadBatchResult> batches;

  setUp(() {
    started = [];
    ended = [];
    batches = [];
  });

  DownloadQueue build(
    Future<bool> Function(Song) run, {
    int concurrency = 2,
    Future<bool> Function()? isOnline,
    Future<bool> Function()? waitForNetwork,
    void Function(String)? onCancelRunning,
  }) =>
      DownloadQueue(
        run: run,
        onJobStart: (song) => started.add(song.id),
        onJobEnd: (song, {required ok, required cancelled}) => ended.add('${song.id}:${cancelled ? 'c' : ok ? 'ok' : 'x'}'),
        onBatchDone: batches.add,
        concurrency: concurrency,
        delay: (_) async {},
        isOnline: isOnline,
        waitForNetwork: waitForNetwork,
        onCancelRunning: onCancelRunning,
      );

  test('never runs more than the concurrency limit at once', () async {
    var live = 0;
    var peak = 0;
    final gate = Completer<void>();
    final q = build((song) async {
      live++;
      peak = peak < live ? live : peak;
      await gate.future;
      live--;
      return true;
    });
    final futures = [for (var i = 0; i < 6; i++) q.enqueue(s('$i'))];
    await pumpMicrotasks();
    expect(peak, 2);
    expect(q.outstanding, 6);
    gate.complete();
    expect(await Future.wait(futures), everyElement(isTrue));
    expect(q.outstanding, 0);
  });

  test('one summary at the end of a batch, with counts', () async {
    final q = build((song) async => song.id != 'bad');
    await Future.wait([q.enqueue(s('a')), q.enqueue(s('b')), q.enqueue(s('bad'))]);
    expect(batches, hasLength(1));
    expect(batches.single.succeeded, 2);
    expect(batches.single.failed, 1);
  });

  test('a failed attempt is retried (the partial file resumes) and can then succeed', () async {
    var tries = 0;
    final q = build((song) async => ++tries >= 3);
    expect(await q.enqueue(s('a')), isTrue);
    expect(tries, 3);
    expect(batches.single.failed, 0);
  });

  test('gives up after the attempt limit', () async {
    var tries = 0;
    final q = build((song) async {
      tries++;
      return false;
    });
    expect(await q.enqueue(s('a')), isFalse);
    expect(tries, 3);
    expect(ended, ['a:x']);
  });

  test('waits for the network without spending attempts, then carries on', () async {
    var online = false;
    final back = Completer<bool>();
    var runs = 0;
    final q = build(
      (song) async {
        runs++;
        return true;
      },
      isOnline: () async => online,
      waitForNetwork: () => back.future,
    );
    final f = q.enqueue(s('a'));
    await pumpMicrotasks();
    expect(runs, 0);
    online = true;
    back.complete(true);
    expect(await f, isTrue);
    expect(runs, 1);
  });

  test('network that never returns fails the job instead of hanging', () async {
    final q = build((song) async => true, isOnline: () async => false, waitForNetwork: () async => false);
    expect(await q.enqueue(s('a')), isFalse);
    expect(batches.single.failed, 1);
  });

  test('cancel removes a waiting job and stops a running one', () async {
    final gate = Completer<void>();
    final stopped = <String>[];
    late DownloadQueue q;
    q = build(
      (song) async {
        await gate.future;
        return true;
      },
      concurrency: 1,
      onCancelRunning: (id) {
        stopped.add(id);
        gate.complete();
      },
    );
    final running = q.enqueue(s('r'));
    final waiting = q.enqueue(s('w'));
    await pumpMicrotasks();
    q.cancel('w');
    expect(await waiting, isFalse);
    q.cancel('r');
    expect(await running, isFalse);
    expect(stopped, ['r']);
    expect(ended, containsAll(['w:c', 'r:c']));
    expect(batches, isEmpty, reason: 'a cancelled batch is not announced');
  });

  test('cancelAll empties the queue', () async {
    final gate = Completer<void>();
    final q = build((song) async {
      await gate.future;
      return true;
    }, onCancelRunning: (_) {});
    final fs = [for (var i = 0; i < 4; i++) q.enqueue(s('$i'))];
    await pumpMicrotasks();
    q.cancelAll();
    gate.complete();
    expect(await Future.wait(fs), everyElement(isFalse));
    expect(q.outstanding, 0);
  });

  test('a song already queued is not queued twice', () async {
    final gate = Completer<void>();
    var runs = 0;
    final q = build((song) async {
      runs++;
      await gate.future;
      return true;
    });
    final a = q.enqueue(s('a'));
    final b = q.enqueue(s('a'));
    gate.complete();
    expect(await a, await b);
    expect(runs, 1);
  });

  test('quiet jobs (auto-download) stay out of the summary', () async {
    final q = build((song) async => true);
    await q.enqueue(s('a'), announce: false);
    expect(batches, isEmpty);
  });

  test('outstanding songs are listed for saving', () async {
    final gate = Completer<void>();
    final q = build((song) async {
      await gate.future;
      return true;
    }, concurrency: 1);
    unawaited(q.enqueue(s('a')));
    unawaited(q.enqueue(s('b')));
    await pumpMicrotasks();
    expect([for (final x in q.outstandingSongs) x.id], ['a', 'b']);
    gate.complete();
  });

  group('notices', () {
    test('one song: names it', () {
      final n = downloadNotices(const DownloadBatchResult(succeeded: 1, failed: 0, lastTitle: 'Kuyil'));
      expect(n.single.id, downloadDoneNoticeId);
      expect(n.single.body, 'Kuyil is ready offline.');
    });
    test('a batch: one summary', () {
      final n = downloadNotices(const DownloadBatchResult(succeeded: 12, failed: 0));
      expect(n, hasLength(1));
      expect(n.single.body, '12 songs downloaded.');
    });
    test('failures get their own notice', () {
      final n = downloadNotices(const DownloadBatchResult(succeeded: 5, failed: 2));
      expect(n.map((e) => e.id), [downloadDoneNoticeId, downloadFailedNoticeId]);
      expect(n.last.body, contains('2 songs couldn’t be downloaded'));
    });
    test('all failed: only the failure notice', () {
      final n = downloadNotices(const DownloadBatchResult(succeeded: 0, failed: 1));
      expect(n.single.id, downloadFailedNoticeId);
    });
  });

  group('keep alive', () {
    test('starts with work, updates with progress at a limited rate, stops when empty', () async {
      final calls = <String>[];
      var now = DateTime(2026);
      final k = DownloadKeepAlive(
        start: (t, x, d, n) async {
          calls.add('start $d/$n');
          return true;
        },
        stop: () async => calls.add('stop'),
        now: () => now,
      );
      k.update(done: 0, total: 3);
      k.update(done: 1, total: 3); // within a second: skipped
      now = now.add(const Duration(seconds: 2));
      k.update(done: 1, total: 3); // same numbers: skipped
      k.update(done: 2, total: 3);
      k.update(done: 3, total: 3); // the last one always goes through
      k.update(done: 0, total: 0);
      await pumpMicrotasks();
      expect(calls, ['start 0/3', 'start 1/3', 'start 3/3', 'stop']);
      expect(k.running, isFalse);
    });

    test('a refused start is retried by the next update', () async {
      var ok = false;
      var starts = 0;
      final k = DownloadKeepAlive(
        start: (t, x, d, n) async {
          starts++;
          return ok;
        },
        stop: () async {},
        minGap: Duration.zero,
      );
      k.update(done: 0, total: 2);
      await pumpMicrotasks();
      expect(k.running, isFalse);
      ok = true;
      k.update(done: 1, total: 2);
      await pumpMicrotasks();
      expect(starts, 2);
      expect(k.running, isTrue);
    });

    test('progress text', () {
      expect(downloadProgressText(done: 4, total: 20).text, '5 of 20');
      expect(downloadProgressText(done: 0, total: 1).title, 'Downloading a song');
    });
  });
}
