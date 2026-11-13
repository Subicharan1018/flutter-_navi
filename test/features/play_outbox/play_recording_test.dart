import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navivibe/features/ai_shuffle/data/models/feedback_request.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_repository.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/features/play_outbox/logic/play_outbox.dart';
import 'package:navivibe/features/play_outbox/logic/play_outbox_delivery.dart';
import 'package:navivibe/features/play_outbox/logic/play_outbox_providers.dart';
import 'package:navivibe/features/status/logic/status_providers.dart';
import 'package:navivibe/services/scrobble_service.dart';
import 'package:navivibe/services/subsonic_service.dart';

class _Api extends Mock implements SubsonicService {}

class _Conn extends Mock implements Connectivity {}

class _Repo extends Mock implements ShuffleRepository {}

void main() {
  late Directory dir;
  late Box box;
  late PlayOutbox outbox;
  late _Api api;
  late _Conn conn;
  late bool online;
  late PlayRecorder recorder;
  late PlayOutboxDelivery delivery;
  var n = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('navi_rec_');
    Hive.init(dir.path);
    box = await Hive.openBox('rec_${n++}');
    outbox = PlayOutbox(box);
    api = _Api();
    conn = _Conn();
    online = true;
    when(() => conn.checkConnectivity()).thenAnswer(
      (_) async => online ? [ConnectivityResult.wifi] : [ConnectivityResult.none],
    );
    when(() => api.scrobble(any(), submission: any(named: 'submission'), timeMs: any(named: 'timeMs'), strict: any(named: 'strict')))
        .thenAnswer((_) async {});
    delivery = PlayOutboxDelivery(
      outbox: outbox,
      canSend: () => online,
      sendScrobble: (id, t) => api.scrobble(id, submission: true, timeMs: t, strict: true),
      sendFeedback: (r) async {},
      pace: Duration.zero,
    );
    recorder = PlayRecorder(outbox, delivery);
  });
  tearDown(() async {
    delivery.dispose();
    await box.close();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  ScrobbleService svc() => ScrobbleService(api, conn, recorder: recorder);

  test('offline qualifying play: a row is written and nothing goes over the network', () async {
    online = false;
    svc().submit('song1', playId: 'p1', startedAtMs: 4242);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(outbox.pendingCount, 1);
    verifyNever(() => api.scrobble(any(), submission: any(named: 'submission'), timeMs: any(named: 'timeMs'), strict: any(named: 'strict')));

    online = true; // reconnect
    await delivery.flush();
    verify(() => api.scrobble('song1', submission: true, timeMs: 4242, strict: true)).called(1);
    expect(outbox.pendingCount, 0);
  });

  test('online play is delivered at once and leaves no row', () async {
    svc().submit('song1', playId: 'p1', startedAtMs: 99);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verify(() => api.scrobble('song1', submission: true, timeMs: 99, strict: true)).called(1);
    expect(outbox.pendingCount, 0);
  });

  test('a device-file song is never scrobbled to Navidrome', () async {
    svc().submit('local:abc', playId: 'p1', startedAtMs: 1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(outbox.pendingCount, 0);
    verifyNever(() => api.scrobble(any(), submission: any(named: 'submission'), timeMs: any(named: 'timeMs'), strict: any(named: 'strict')));
  });

  test('without a play id the old direct path still works', () async {
    svc().submit('song1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verify(() => api.scrobble('song1', submission: true)).called(1);
  });

  test('sendShuffleFeedback queues the request stamped with its play, and falls back to a direct post without an outbox', () async {
    registerFallbackValue(FeedbackRequest(title: 't', listenRatio: 0.5, endReason: 'natural', genreBucket: 'g', composer: 'c'));
    final repo = _Repo();
    when(() => repo.postFeedback(any())).thenAnswer((_) async {});
    final c = ProviderContainer(overrides: [
      playRecorderProvider.overrideWithValue(recorder),
      shuffleRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
    c.read(shuffleQueueProvider.notifier).initSession();
    online = false;
    final req = FeedbackRequest(
      title: 'Song', filePath: 'song1', genreBucket: 'rock', composer: 'c', listenRatio: 1, endReason: 'natural',
    );
    // ignore: invalid_use_of_protected_member
    final ref = c.read(_refProvider);
    sendShuffleFeedback(ref, req, playId: 'p9', startedAtMs: 777);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final row = outbox.row('p9')!;
    expect(row.feedback!.playedAtMs, 777);
    expect(row.feedback!.playId, 'p9');
    verifyNever(() => repo.postFeedback(any()));

    // No outbox (e.g. its box is not open): the old fire-and-forget post.
    final c2 = ProviderContainer(overrides: [
      playRecorderProvider.overrideWithValue(null),
      shuffleRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c2.dispose);
    c2.read(shuffleQueueProvider.notifier).initSession();
    sendShuffleFeedback(c2.read(_refProvider), req, playId: 'p10');
    verify(() => repo.postFeedback(any())).called(1);
  });

  group('Status row', () {
    test('words the number of plays waiting', () {
      expect(describePendingPlays(0, networkOffline: false).detail, 'All plays are synced');
      expect(describePendingPlays(1, networkOffline: false).detail, '1 play waiting to sync');
      expect(describePendingPlays(12, networkOffline: true).detail, '12 plays waiting for a connection');
    });
  });
}

/// Exposes a [Ref] to code under test that takes one.
final _refProvider = Provider<Ref>((ref) => ref);
