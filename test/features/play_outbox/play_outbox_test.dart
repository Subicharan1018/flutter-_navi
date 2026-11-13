import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:navivibe/features/ai_shuffle/data/models/feedback_request.dart';
import 'package:navivibe/features/play_outbox/logic/play_outbox.dart';
import 'package:navivibe/features/play_outbox/logic/play_outbox_delivery.dart';

FeedbackRequest _fb(String title, {String file = 's1'}) => FeedbackRequest(
      title: title,
      filePath: file,
      genreBucket: 'rock',
      composer: 'c',
      listenRatio: 0.9,
      endReason: 'natural',
      durationS: 200,
      sessionId: 'sess',
      weatherCode: 500,
      temperatureC: 12.5,
      volume: 0.4,
    );

void main() {
  late Directory dir;
  late Box box;
  late PlayOutbox outbox;
  var boxN = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('navi_outbox_');
    Hive.init(dir.path);
    box = await Hive.openBox('outbox_${boxN++}');
    outbox = PlayOutbox(box, clock: () => DateTime.fromMillisecondsSinceEpoch(2000000000000));
  });
  tearDown(() async {
    await box.close();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  group('FeedbackRequest wire format', () {
    test('carries play_id and played_at only when set, and round-trips', () {
      expect(_fb('a').toJson().containsKey('play_id'), isFalse);
      expect(_fb('a').toJson().containsKey('played_at'), isFalse);
      final stamped = _fb('a').withPlay(playId: 'p1', playedAtMs: 1700000000000);
      final j = stamped.toJson();
      expect(j['play_id'], 'p1');
      expect(j['played_at'], 1700000000000);
      final back = FeedbackRequest.fromJson(j);
      expect(back.toJson(), j);
      expect(back.weatherCode, 500); // captured at play time, not send time
      expect(back.volume, 0.4);
    });
  });

  group('PlayOutbox', () {
    test('a play with both legs is one row, keyed by play id', () async {
      await outbox.recordScrobble(playId: 'p1', songId: 's1', startedAtMs: 1000);
      await outbox.recordFeedback(playId: 'p1', songId: 's1', startedAtMs: 1000, request: _fb('a'));
      final rows = outbox.pending();
      expect(rows, hasLength(1));
      expect(rows.single.scrobblePending, isTrue);
      expect(rows.single.feedbackPending, isTrue);
      expect(rows.single.feedback!.playId, 'p1');
      expect(rows.single.feedback!.playedAtMs, 1000);
    });

    test('device-file songs are not queued for Navidrome', () async {
      await outbox.recordScrobble(playId: 'p1', songId: 'local:x', startedAtMs: 1, scrobble: false);
      expect(outbox.pendingCount, 0);
    });

    test('a second report of one play is ignored', () async {
      await outbox.recordFeedback(playId: 'p1', songId: 's1', startedAtMs: 1, request: _fb('first'));
      await outbox.recordFeedback(playId: 'p1', songId: 's1', startedAtMs: 1, request: _fb('second'));
      expect(outbox.row('p1')!.feedback!.title, 'first');
    });

    test('the row goes when both legs are sent, and survives a reopen', () async {
      await outbox.recordScrobble(playId: 'p1', songId: 's1', startedAtMs: 1);
      await outbox.recordFeedback(playId: 'p1', songId: 's1', startedAtMs: 1, request: _fb('a'));
      await outbox.markSent('p1', scrobble: true);
      expect(PlayOutbox(box).row('p1')!.scrobblePending, isFalse);
      await outbox.markSent('p1', feedback: true);
      expect(outbox.row('p1'), isNull);
    });

    test('plays older than 90 days are dropped', () async {
      final now = 2000000000000;
      final old = now - const Duration(days: 91).inMilliseconds;
      await outbox.recordFeedback(playId: 'old', songId: 's1', startedAtMs: old, request: _fb('a'));
      await outbox.recordFeedback(playId: 'new', songId: 's1', startedAtMs: now - 1000, request: _fb('b'));
      await outbox.prune();
      expect(outbox.pending().map((r) => r.playId), ['new']);
    });

    test('over 5000 rows the oldest scrobble legs go first, then the oldest rows', () async {
      final now = 2000000000000;
      for (var i = 0; i < PlayOutbox.maxRows; i++) {
        await outbox.recordScrobble(playId: 'p$i', songId: 's', startedAtMs: now - 100000 + i);
      }
      await outbox.recordFeedback(playId: 'extra', songId: 's', startedAtMs: now, request: _fb('a'));
      await outbox.prune();
      expect(box.length, lessThanOrEqualTo(PlayOutbox.maxRows));
      expect(outbox.row('extra'), isNotNull); // newest survives
      expect(outbox.row('p0'), isNull); // oldest dropped
    });

    test('a server upgrade that renamed ids is followed', () async {
      await outbox.recordScrobble(playId: 'p1', songId: 'A1', startedAtMs: 1);
      await outbox.recordFeedback(playId: 'p1', songId: 'A1', startedAtMs: 1, request: _fb('a', file: 'A1'));
      await outbox.remapSongIds({'A1': 'A2'});
      final r = outbox.row('p1')!;
      expect(r.songId, 'A2');
      expect(r.feedback!.filePath, 'A2');
    });
  });

  group('PlayOutboxDelivery', () {
    late List<(String, int)> scrobbles;
    late List<FeedbackRequest> feedbacks;
    late bool online;
    Object? scrobbleError;
    Object? feedbackError;

    PlayOutboxDelivery make({int maxAttempts = 30}) => PlayOutboxDelivery(
          outbox: outbox,
          canSend: () => online,
          sendScrobble: (id, t) async {
            if (scrobbleError != null) throw scrobbleError!;
            scrobbles.add((id, t));
          },
          sendFeedback: (r) async {
            if (feedbackError != null) throw feedbackError!;
            feedbacks.add(r);
          },
          pace: Duration.zero,
          maxAttempts: maxAttempts,
        );

    setUp(() {
      scrobbles = [];
      feedbacks = [];
      online = true;
      scrobbleError = null;
      feedbackError = null;
    });

    Future<void> qualifyingPlay(String id, {int at = 5000}) async {
      await outbox.recordScrobble(playId: id, songId: 's1', startedAtMs: at);
      await outbox.recordFeedback(playId: id, songId: 's1', startedAtMs: at, request: _fb('t'));
    }

    test('online: delivers both legs at once and leaves no row', () async {
      final d = make();
      await qualifyingPlay('p1');
      await d.flush();
      expect(scrobbles, [('s1', 5000)]);
      expect(feedbacks.single.playId, 'p1');
      expect(outbox.pendingCount, 0);
      d.dispose();
    });

    test('offline: nothing is sent, the row waits, reconnect sends it with the original time', () async {
      final d = make();
      online = false;
      await qualifyingPlay('p1', at: 1234);
      await d.flush();
      expect(scrobbles, isEmpty);
      expect(feedbacks, isEmpty);
      expect(outbox.pendingCount, 1);

      online = true; // connectivity regained
      await d.flush();
      expect(scrobbles, [('s1', 1234)]);
      expect(feedbacks.single.playedAtMs, 1234);
      expect(outbox.pendingCount, 0);
      d.dispose();
    });

    test('a failed scrobble keeps the row but the feedback is still delivered', () async {
      final d = make();
      scrobbleError = Exception('503');
      await qualifyingPlay('p1');
      await d.flush();
      expect(feedbacks, hasLength(1));
      final row = outbox.row('p1')!;
      expect(row.scrobblePending, isTrue);
      expect(row.feedbackPending, isFalse);
      expect(row.attempts, 1);

      scrobbleError = null;
      await d.flush();
      expect(scrobbles, [('s1', 5000)]);
      expect(feedbacks, hasLength(1)); // not sent twice
      expect(outbox.pendingCount, 0);
      d.dispose();
    });

    test('a restart mid-way does not resend what already went out', () async {
      final first = make();
      feedbackError = Exception('timeout');
      await qualifyingPlay('p1');
      await first.flush(); // scrobble went, feedback did not
      first.dispose();
      expect(scrobbles, hasLength(1));

      final reopened = PlayOutbox(box); // same box, as after an app restart
      final second = PlayOutboxDelivery(
        outbox: reopened,
        sendScrobble: (id, t) async => scrobbles.add((id, t)),
        sendFeedback: (r) async => feedbacks.add(r),
        pace: Duration.zero,
      );
      feedbackError = null;
      await second.flush();
      expect(scrobbles, hasLength(1));
      expect(feedbacks, hasLength(1));
      second.dispose();
    });

    test('plays go out oldest first, one at a time', () async {
      final d = make();
      online = false;
      await qualifyingPlay('late', at: 9000);
      await qualifyingPlay('early', at: 1000);
      online = true;
      await d.flush();
      expect(scrobbles.map((s) => s.$2), [1000, 9000]);
      d.dispose();
    });

    test('a refusal that can never succeed drops the leg instead of retrying', () async {
      final d = make();
      feedbackError = const OutboxRefused('400');
      await qualifyingPlay('p1');
      await d.flush();
      expect(outbox.pendingCount, 0);
      d.dispose();
    });

    test('a leg that keeps failing is given up after the attempt limit', () async {
      final d = make(maxAttempts: 2);
      feedbackError = Exception('boom');
      await outbox.recordFeedback(playId: 'p1', songId: 's1', startedAtMs: 1, request: _fb('a'));
      await d.flush();
      expect(outbox.pendingCount, 1);
      await d.flush();
      expect(outbox.pendingCount, 0);
      d.dispose();
    });

    test('feedback posts are paced', () async {
      final waits = <Duration>[];
      final d = PlayOutboxDelivery(
        outbox: outbox,
        sendScrobble: (id, t) async {},
        sendFeedback: (r) async {},
        pace: const Duration(seconds: 1),
        wait: (d) async => waits.add(d),
      );
      await outbox.recordFeedback(playId: 'a', songId: 's1', startedAtMs: 1, request: _fb('a'));
      await outbox.recordFeedback(playId: 'b', songId: 's1', startedAtMs: 2, request: _fb('b'));
      await d.flush();
      expect(waits, hasLength(2));
      d.dispose();
    });
  });
}
