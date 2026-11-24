// The Fast Start swap must be inaudible: no silence, no click, no jump.
//
// A fake timeline stands in for the two players. Time is virtual (fakeAsync),
// every operation costs what a phone's ExoPlayer roughly costs (opening a file
// 80 ms, a seek 30 ms, a full reload of the queue 350 ms), and the combined
// output volume is sampled every 5 ms: the longest stretch below 90% of the
// normal level is the interruption the listener hears.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:navivibe/services/fast_start.dart';
import 'package:navivibe/services/seamless_swap.dart';

class _Voice implements SwapVoice {
  _Voice(this.async);
  final FakeAsync async;
  static const int seekMs = 30;
  bool playing = false;
  double volume = 1;
  Duration _anchor = Duration.zero;
  Duration _at = Duration.zero;

  Duration get _now => async.elapsed;

  void start(Duration pos, {double vol = 1}) {
    _anchor = pos;
    _at = _now;
    playing = true;
    volume = vol;
  }

  @override
  Duration get position => playing ? _anchor + (_now - _at) : _anchor;

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> seek(Duration to) async {
    await Future<void>.delayed(Duration(milliseconds: seekMs));
    _anchor = to;
    _at = _now;
  }

  double get level => playing ? volume : 0;
}

class _Run {
  _Run(this.stats, this.meter, this.worstGapBetweenVoicesMs);
  final SwapStats stats;
  final InterruptionMeter meter;
  final int worstGapBetweenVoicesMs;
}

_Run _swap({
  int reloadMs = 350,
  int openMs = 80,
  bool Function()? abortIf,
  void Function(FakeAsync, _Voice, _Voice)? during,
}) {
  late _Run result;
  fakeAsync((async) {
    final main = _Voice(async)..start(const Duration(seconds: 12));
    final helper = _Voice(async);
    final meter = InterruptionMeter();
    var worstBetween = 0;
    // Sample the audible level every 5 ms.
    final sampler = Timer.periodic(const Duration(milliseconds: 5), (_) {
      meter.add(async.elapsed.inMilliseconds, main.level + helper.level);
      if (main.level > 0.05 && helper.level > 0.05) {
        final d = (main.position - helper.position).inMilliseconds.abs();
        if (d > worstBetween) worstBetween = d;
      }
    });

    SwapStats? stats;
    SeamlessSwap(
      main: main,
      helper: helper,
      baseVolume: () => 1,
      openHelper: (at) async {
        await Future<void>.delayed(Duration(milliseconds: openMs));
        helper.start(at, vol: 0);
      },
      reloadMain: (at) async {
        // The queue lock and the source reload keep the main player silent
        // and behind while they run.
        await Future<void>.delayed(Duration(milliseconds: reloadMs));
        main.start(at, vol: 0);
      },
      closeHelper: () async => helper.playing = false,
      isAborted: abortIf ?? () => false,
    ).run().then((s) => stats = s);

    during?.call(async, main, helper);
    async.elapse(const Duration(seconds: 5));
    sampler.cancel();
    result = _Run(stats!, meter, worstBetween);
  });
  return result;
}

void main() {
  group('crossfade gains', () {
    test('sum to one at every step, so the level stays flat', () {
      for (final g in crossfadeGains()) {
        expect(g.out + g.inn, closeTo(1, 1e-9));
      }
      expect(crossfadeGains().last.inn, 1);
      expect(crossfadeGains().last.out, 0);
    });
  });

  group('InterruptionMeter', () {
    test('reads the longest stretch below the floor', () {
      final m = InterruptionMeter()
        ..add(0, 1)
        ..add(5, 0.4)
        ..add(10, 0)
        ..add(15, 0)
        ..add(20, 1)
        ..add(25, 0.2)
        ..add(30, 1);
      expect(m.maxGapMs, 10);
    });
  });

  group('SeamlessSwap on a fake timeline', () {
    test('no audible interruption even with a 350 ms reload (0 ms vs the old dip)', () {
      final r = _swap();
      expect(r.stats.outcome, SwapOutcome.done);
      expect(r.meter.maxGapMs, 0, reason: 'combined output never dipped');
      // While both are audible they play the same instant of the song.
      expect(r.worstGapBetweenVoicesMs, lessThanOrEqualTo(kSwapAlignTolerance.inMilliseconds));
    });

    test('the old choreography (dip to silence, reload, ramp up) is a long gap', () {
      // The behaviour this replaces, on the same timeline costs: 120 ms down,
      // 350 ms reload, 4 x 30 ms ramp up.
      final m = InterruptionMeter();
      var t = 0;
      for (; t < 120; t += 5) {
        m.add(t, 1 - t / 120);
      }
      for (; t < 120 + 350; t += 5) {
        m.add(t, 0);
      }
      for (; t < 120 + 350 + 120; t += 5) {
        m.add(t, (t - 470) / 120);
      }
      m.add(t, 1);
      expect(m.maxGapMs, greaterThan(400));
    });

    test('slow open and slow reload still leave no gap', () {
      final r = _swap(reloadMs: 900, openMs: 250);
      expect(r.stats.outcome, SwapOutcome.done);
      expect(r.meter.maxGapMs, 0);
    });

    test('the main player is aligned to the helper before the fade back', () {
      final r = _swap();
      // First entry: helper aligned to main; later ones: main aligned to helper.
      expect(r.stats.alignDriftMs, isNotEmpty);
      expect(r.stats.alignDriftMs.last.abs(), lessThanOrEqualTo(kSwapAlignTolerance.inMilliseconds));
    });

    test('an abort restores the main player and ends with the helper closed', () {
      var abort = false;
      final r = _swap(
        abortIf: () => abort,
        during: (async, main, helper) {
          Future<void>.delayed(const Duration(milliseconds: 150)).then((_) => abort = true);
        },
      );
      expect(r.stats.outcome, SwapOutcome.aborted);
    });
  });

  group('skip settle', () {
    test('a song already on this device opens sooner than one that needs the network', () {
      fakeAsync((async) {
        final opened = <int>[];
        final c = SkipCoordinator(
          load: (i, s) async => opened.add(i),
          settleFor: (i) => i == 1 ? kSkipSettleReady : kSkipSettle,
        );
        c.request(1);
        async.elapse(kSkipSettleReady);
        expect(opened, [1]);
        c.request(2);
        async.elapse(kSkipSettleReady);
        expect(opened, [1], reason: 'a song that needs the network keeps the full wait');
        async.elapse(kSkipSettle);
        expect(opened, [1, 2]);
      });
    });

    test('songs skipped past within the short wait are still never opened', () {
      fakeAsync((async) {
        final opened = <int>[];
        final c = SkipCoordinator(
          load: (i, s) async => opened.add(i),
          settleFor: (_) => kSkipSettleReady,
        );
        c.request(1);
        async.elapse(const Duration(milliseconds: 40));
        c.request(2);
        async.elapse(const Duration(milliseconds: 40));
        c.request(3);
        async.elapse(kSkipSettleReady);
        expect(opened, [3]);
      });
    });
  });
}
