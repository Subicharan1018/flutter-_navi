import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navivibe/features/ai_shuffle/data/models/feedback_request.dart';
import 'package:navivibe/features/ai_shuffle/data/models/next_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/recommended_song.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_repository.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/features/play_outbox/logic/play_event.dart';
import 'package:navivibe/features/play_outbox/logic/play_outbox_providers.dart' show playRecorderProvider;

class _Repo extends Mock implements ShuffleRepository {}

RecommendedSong _rec(String title, int rank, double score) => RecommendedSong(
      rank: rank,
      title: title,
      filePath: 'p/$title',
      genreBucket: 'Pop',
      composer: 'A',
      audio: const AudioFeatures(energy: 0.5, valence: 0.5, acousticness: 0.5, danceability: 0.5),
      scores: SongScores(contextHistory: 0, audioFit: 0, composerLoyalty: 0, finalScore: score),
      why: '',
    );

FeedbackRequest _aux(PlayEventType t) => FeedbackRequest(
      title: 'Song',
      genreBucket: 'g',
      composer: 'c',
      listenRatio: 0,
      endReason: t.wire,
      eventType: t,
    );

Duration _s(double s) => Duration(milliseconds: (s * 1000).round());

/// Plays [seconds] of a song through [t] in 0.2 s ticks, from [from].
void _play(ListenTracker t, double seconds, {double from = 0}) {
  for (var x = from; x <= from + seconds + 1e-9; x += 0.2) {
    t.onPosition(_s(x), playing: true);
  }
}

void main() {
  group('ListenTracker', () {
    test('counts the seconds really heard', () {
      final t = ListenTracker()..begin('a', 200);
      _play(t, 42);
      final r = t.finish();
      expect(r.hadEvidence, isTrue);
      expect(r.secondsPlayed, closeTo(42, 0.5));
      expect(r.seeks, 0);
    });

    test('a scrub is not listening and is reported', () {
      final t = ListenTracker()..begin('a', 300);
      _play(t, 10);
      final sig = t.onPosition(_s(200), playing: true);
      expect(sig, isA<SeekSignal>());
      expect((sig as SeekSignal).toMs, 200000);
      _play(t, 5, from: 200);
      final r = t.finish();
      expect(r.secondsPlayed, closeTo(15, 0.6)); // 10 s + 5 s, not 205
      expect(r.seeks, 1);
      expect(r.maxPositionS, closeTo(205, 0.5));
    });

    test('time paused is not listening', () {
      final t = ListenTracker()..begin('a', 100);
      _play(t, 10);
      for (var i = 0; i < 50; i++) {
        t.onPosition(_s(10), playing: false);
      }
      _play(t, 5, from: 10);
      expect(t.finish().secondsPlayed, closeTo(15, 0.6));
    });

    test('the position wrapping to the start near the end is a loop, not a seek', () {
      final t = ListenTracker()..begin('a', 100);
      _play(t, 98);
      expect(t.onPosition(_s(0.3), playing: true), isA<LoopSignal>());
    });

    test('finish is single-use: the second caller has no evidence', () {
      final t = ListenTracker()..begin('a', 100);
      _play(t, 5);
      expect(t.finish().hadEvidence, isTrue);
      expect(t.finish().hadEvidence, isFalse);
    });

    test('a new play starts from zero', () {
      final t = ListenTracker()..begin('a', 100);
      _play(t, 50);
      t.begin('b', 100);
      _play(t, 3);
      expect(t.finish().secondsPlayed, closeTo(3, 0.5));
    });
  });

  group('classifyEnd', () {
    ListenResult heard(double s) => ListenResult(secondsPlayed: s, seeks: 0, maxPositionS: s, hadEvidence: true);

    test('a song that played out is a complete with its real ratio', () {
      final v = classifyEnd(heard: heard(196), durationS: 200, naturalHint: true)!;
      expect(v.type, PlayEventType.complete);
      expect(v.endReason, 'natural');
      expect(v.ratio, closeTo(0.98, 1e-6));
    });

    test('"finished naturally" with nothing heard is dropped (the old fake burst row)', () {
      expect(classifyEnd(heard: heard(0), durationS: 200, naturalHint: true), isNull);
      expect(classifyEnd(heard: ListenResult.none, durationS: 200, naturalHint: true), isNull);
      expect(classifyEnd(heard: heard(0.4), durationS: 200, naturalHint: true), isNull);
    });

    test('a natural end that was really a partial listen is reported as the skip it was', () {
      final v = classifyEnd(heard: heard(40), durationS: 200, naturalHint: true)!;
      expect(v.type, PlayEventType.skip);
      expect(v.endReason, 'autoskip');
      expect(v.ratio, closeTo(0.2, 1e-6));
    });

    test('an instant skip is a real skip at 0 %, not dropped', () {
      final v = classifyEnd(heard: heard(0), durationS: 200, naturalHint: false)!;
      expect(v.type, PlayEventType.skip);
      expect(v.endReason, 'fwdbtn');
      expect(v.ratio, 0);
    });

    test('with no tracker data the player snapshot is used', () {
      final v = classifyEnd(heard: ListenResult.none, durationS: 100, naturalHint: false, snapshotSeconds: 30)!;
      expect(v.ratio, closeTo(0.3, 1e-6));
      final done = classifyEnd(heard: ListenResult.none, durationS: 100, naturalHint: true, snapshotSeconds: 99)!;
      expect(done.type, PlayEventType.complete);
    });

    test('a tracker that saw no ticks at all falls back to the snapshot', () {
      final seen = ListenResult(secondsPlayed: 0, seeks: 0, maxPositionS: 0, hadEvidence: true);
      final v = classifyEnd(heard: seen, durationS: 100, naturalHint: false, snapshotSeconds: 60)!;
      expect(v.ratio, closeTo(0.6, 1e-6));
    });

    test('seconds can never exceed the song', () {
      final v = classifyEnd(heard: heard(900), durationS: 200, naturalHint: true)!;
      expect(v.secondsPlayed, 200);
      expect(v.ratio, 1.0);
    });

    test('unknown duration: a long natural listen is a complete, a short one a skip, none dropped', () {
      expect(classifyEnd(heard: heard(200), durationS: 0, naturalHint: true)!.type, PlayEventType.complete);
      expect(classifyEnd(heard: heard(3), durationS: 0, naturalHint: true)!.type, PlayEventType.skip);
      expect(classifyEnd(heard: heard(0), durationS: 0, naturalHint: true), isNull);
    });
  });

  group('HoldoutPolicy', () {
    test('is deterministic', () {
      for (var i = 0; i < 200; i++) {
        expect(HoldoutPolicy.isHoldout('sess', i), HoldoutPolicy.isHoldout('sess', i));
      }
    });

    test('picks about 5 % over many slots', () {
      var hits = 0;
      const n = 20000;
      for (var i = 0; i < n; i++) {
        if (HoldoutPolicy.isHoldout('session-${i ~/ 50}', i % 50)) hits++;
      }
      expect(hits / n, closeTo(0.05, 0.01));
    });

    test('never in a session without an id, and the offset stays in range', () {
      expect(HoldoutPolicy.isHoldout('', 3), isFalse);
      for (var i = 0; i < 500; i++) {
        final o = HoldoutPolicy.offset('s', i, 7);
        expect(o, inInclusiveRange(0, 6));
      }
      expect(HoldoutPolicy.offset('s', 1, 0), 0);
    });
  });

  group('sourceFromContext', () {
    test('the server\'s placement wins, remote beats everything', () {
      expect(sourceFromContext('autoplay', serverPlaced: true), PlaySource.smartShuffle);
      expect(sourceFromContext('playlist', serverPlaced: false), PlaySource.playlist);
      expect(sourceFromContext('user_selected', serverPlaced: false), PlaySource.library);
      expect(sourceFromContext('whatever', serverPlaced: false), PlaySource.other);
      expect(sourceFromContext('autoplay', serverPlaced: true, remote: true), PlaySource.remote);
    });
  });

  group('served placement and the v2 gate', () {
    late ProviderContainer c;
    late _Repo repo;

    setUp(() {
      repo = _Repo();
      registerFallbackValue(_aux(PlayEventType.start));
      when(() => repo.postFeedback(any())).thenAnswer((_) async {});
      c = ProviderContainer(overrides: [
        shuffleRepositoryProvider.overrideWithValue(repo),
        playRecorderProvider.overrideWithValue(null),
      ]);
    });
    tearDown(() => c.dispose());

    test('registerServed keeps slot, score, engine and served id by title', () {
      final n = c.read(shuffleQueueProvider.notifier);
      expect(n.eventsSupported, isFalse);
      n.registerServed(NextResponse(
        mode: 'smart',
        source: 'smart',
        queue: [_rec('First', 1, 0.9), _rec('Second', 2, 0.4)],
        engine: 'v3+ai',
        servedId: 'sv1',
      ));
      expect(n.eventsSupported, isTrue);
      final o = n.servedOrigin('SECOND')!;
      expect(o.slot, 1);
      expect(o.score, closeTo(0.4, 1e-9));
      expect(o.servedBy, 'v3+ai');
      expect(o.servedId, 'sv1');
      expect(o.source, PlaySource.smartShuffle);
      expect(n.servedOrigin('Unknown song'), isNull);
    });

    test('a server that sent no served_id keeps the extra event types switched off', () {
      final n = c.read(shuffleQueueProvider.notifier);
      n.registerServed(NextResponse(mode: 'smart', source: 'smart', queue: [_rec('A', 1, 0.5)]));
      expect(n.eventsSupported, isFalse);
      c.read(Provider((ref) => sendShuffleFeedback(ref, _aux(PlayEventType.queueEdit), playId: 'e1')));
      c.read(Provider((ref) => sendShuffleFeedback(ref, _aux(PlayEventType.start), playId: 'e2')));
      verifyNever(() => repo.postFeedback(any()));
    });

    test('once the server confirms v2, those events go out stamped with version and platform', () {
      final n = c.read(shuffleQueueProvider.notifier);
      n.registerServed(NextResponse(mode: 'smart', source: 'smart', queue: [_rec('A', 1, 0.5)], servedId: 'x'));
      c.read(Provider((ref) => sendShuffleFeedback(ref, _aux(PlayEventType.seek), playId: 'e3')));
      final sent = verify(() => repo.postFeedback(captureAny())).captured.single as FeedbackRequest;
      expect(sent.eventType, PlayEventType.seek);
      expect(sent.tzOffsetMin, DateTime.now().timeZoneOffset.inMinutes);
      expect(sent.platform, isNotNull);
    });

    test('a direct post always carries an idempotency key (a v2 server refuses a play without one)', () {
      c.read(shuffleQueueProvider.notifier).initSession();
      final finish = FeedbackRequest(
        title: 'Song',
        genreBucket: 'g',
        composer: 'c',
        listenRatio: 1,
        endReason: 'natural',
        eventType: PlayEventType.complete,
      );
      c.read(Provider((ref) => sendShuffleFeedback(ref, finish)));
      final sent = verify(() => repo.postFeedback(captureAny())).captured.single as FeedbackRequest;
      expect(sent.playId, isNotEmpty);
      expect(sent.playedAtMs, isNotNull);
      expect(sent.toJson()['play_id'], sent.playId);
    });

    test('a play outside any shuffle session is dropped on an old server, kept on a v2 server', () {
      final n = c.read(shuffleQueueProvider.notifier);
      final finish = FeedbackRequest(
        title: 'Song',
        genreBucket: 'g',
        composer: 'c',
        listenRatio: 1,
        endReason: 'natural',
        eventType: PlayEventType.complete,
      );
      c.read(Provider((ref) => sendShuffleFeedback(ref, finish, playId: 'f1')));
      verifyNever(() => repo.postFeedback(any()));
      n.registerServed(NextResponse(mode: 'smart', source: 'smart', queue: [_rec('A', 1, 0.5)], servedId: 'x'));
      c.read(Provider((ref) => sendShuffleFeedback(ref, finish, playId: 'f2')));
      verify(() => repo.postFeedback(any())).called(1);
    });
  });

  group('FeedbackRequest v2 wire format', () {
    FeedbackRequest finish() => const FeedbackRequest(
          title: 'Song',
          filePath: 'nd1',
          genreBucket: 'film',
          composer: 'AR',
          listenRatio: 0.98,
          endReason: 'natural',
          durationS: 200,
          sessionId: 's1',
          eventType: PlayEventType.complete,
          secondsPlayed: 196.126,
          tzOffsetMin: 330,
          playSource: PlaySource.smartShuffle,
          slot: 3,
          score: 0.4213,
          servedBy: 'v3+ai',
          servedId: 'abc',
          holdout: false,
          clientVersion: '1.9.0',
          platform: 'android',
        );

    test('a finish event carries every field and no weather', () {
      final j = finish().withPlay(playId: 'p1', playedAtMs: 1700000000000).toJson();
      expect(j['schema_version'], 2);
      expect(j['event_type'], 'complete');
      expect(j['play_id'], 'p1');
      expect(j['played_at'], 1700000000000);
      expect(j['seconds_played'], 196.13);
      expect(j['tz_offset_min'], 330);
      expect(j['play_source'], 'smart_shuffle');
      expect(j['slot'], 3);
      expect(j['served_by'], 'v3+ai');
      expect(j['served_id'], 'abc');
      expect(j['holdout'], false);
      expect(j['client_version'], '1.9.0');
      expect(j.containsKey('weather_code'), isFalse);
      expect(j.containsKey('temperature_c'), isFalse);
      expect(j.containsKey('event_id'), isFalse);
    });

    test('survives the outbox: toJson then fromJson gives the same request', () {
      final j = finish().withPlay(playId: 'p1', playedAtMs: 5).toJson();
      expect(FeedbackRequest.fromJson(j).toJson(), j);
    });

    test('a queue edit has its own event id and points at no play', () {
      final r = const FeedbackRequest(
        title: 'Song',
        genreBucket: 'g',
        composer: 'c',
        listenRatio: 0,
        endReason: 'queue_edit',
        eventType: PlayEventType.queueEdit,
        queueEditKind: QueueEditKind.playNext,
        fromIndex: 9,
        toIndex: 1,
      ).withPlay(playId: 'ev1', playedAtMs: 7);
      final j = r.toJson();
      expect(j['event_id'], 'ev1');
      expect(j.containsKey('play_id'), isFalse);
      expect(j['queue_edit'], {'kind': 'play_next', 'from_index': 9, 'to_index': 1});
      expect(FeedbackRequest.fromJson(j).toJson(), j);
    });

    test('a start event is keyed by its own id and names its play', () {
      final j = const FeedbackRequest(
        title: 'Song',
        genreBucket: 'g',
        composer: 'c',
        listenRatio: 0,
        endReason: 'start',
        eventType: PlayEventType.start,
        parentPlayId: 'play1',
      ).withPlay(playId: 'play1:s', playedAtMs: 7).toJson();
      expect(j['event_id'], 'play1:s');
      expect(j['play_id'], 'play1');
      final back = FeedbackRequest.fromJson(j);
      expect(back.playId, 'play1:s');
      expect(back.parentPlayId, 'play1');
    });

    test('an old stored request (no v2 fields) still loads', () {
      final back = FeedbackRequest.fromJson({
        'title': 'Old',
        'listen_ratio': 0.5,
        'end_reason': 'fwdbtn',
        'play_id': 'x',
      });
      expect(back.eventType, isNull);
      expect(back.playId, 'x');
      expect(back.toJson()['event_type'], isNull);
    });
  });
}
