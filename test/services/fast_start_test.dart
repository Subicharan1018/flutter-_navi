import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/fast_start.dart';

FastStartInput _input({
  bool enabled = true,
  int durationSec = 240,
  String suffix = 'flac',
  int songKbps = 900,
  int targetKbps = 0,
  bool onDevice = false,
  bool buffered = false,
  int? bytesPerSec = 200 * 1024,
}) => FastStartInput(
  enabled: enabled,
  durationSec: durationSec,
  suffix: suffix,
  songKbps: songKbps,
  targetKbps: targetKbps,
  alreadyOnDevice: onDevice,
  alreadyBuffered: buffered,
  bytesPerSec: bytesPerSec,
);

/// A player that only records what it was asked to open.
class _FakePlayer {
  final List<int> opened = [];
  final List<int> finished = [];
  final List<int> leaked = []; // opened after a newer request took over
  Completer<void>? gate;

  Future<void> load(int index, bool Function() isStale) async {
    opened.add(index);
    if (gate != null) await gate!.future;
    if (isStale()) {
      leaked.add(index);
      return;
    }
    finished.add(index);
  }
}

void main() {
  group('FastStartPolicy.decide', () {
    test('lossless over a slow link uses fast start', () {
      expect(FastStartPolicy.decide(_input()).use, isTrue);
    });

    test('setting off never uses it', () {
      final d = FastStartPolicy.decide(_input(enabled: false));
      expect(d.use, isFalse);
      expect(d.reason, 'setting off');
    });

    test('downloaded, device and cached songs skip it', () {
      expect(FastStartPolicy.decide(_input(onDevice: true)).use, isFalse);
    });

    test('preloaded songs skip it', () {
      expect(FastStartPolicy.decide(_input(buffered: true)).use, isFalse);
    });

    test('tiny songs skip it', () {
      expect(FastStartPolicy.decide(_input(durationSec: 20)).use, isFalse);
    });

    test('the first seconds are never played at an audibly poor rate', () {
      // 64 kbps was noticeable next to a lossless song and listeners heard the swap.
      expect(kFastStartLowKbps, greaterThanOrEqualTo(160));
    });

    test('lossy at or below the low rate skips it', () {
      expect(
        FastStartPolicy.decide(_input(suffix: 'mp3', songKbps: kFastStartLowKbps)).use,
        isFalse,
      );
      expect(
        FastStartPolicy.decide(_input(suffix: 'mp3', songKbps: 64)).use,
        isFalse,
      );
      expect(
        FastStartPolicy.decide(_input(suffix: 'mp3', songKbps: 48)).use,
        isFalse,
      );
    });

    test('lossless is never "already low", whatever its tag says', () {
      expect(
        FastStartPolicy.decide(_input(suffix: 'flac', songKbps: 700)).use,
        isTrue,
      );
    });

    test('chosen quality at or below low skips it', () {
      expect(FastStartPolicy.decide(_input(targetKbps: 64)).use, isFalse);
      expect(FastStartPolicy.decide(_input(targetKbps: 48)).use, isFalse);
    });

    test('a fast connection skips it, a slow one uses it', () {
      expect(
        FastStartPolicy.decide(_input(bytesPerSec: 20 * 1024 * 1024)).use,
        isFalse,
      );
      expect(
        FastStartPolicy.decide(_input(bytesPerSec: 150 * 1024)).use,
        isTrue,
      );
    });

    test('a small gap to the low rate is not worth two requests', () {
      // 128 kbps mp3 on a fast-ish link saves almost nothing.
      expect(
        FastStartPolicy.decide(
          _input(suffix: 'mp3', songKbps: 128, bytesPerSec: 400 * 1024),
        ).use,
        isFalse,
      );
    });

    test('unknown speed assumes the default', () {
      final d = FastStartPolicy.decide(_input(bytesPerSec: null));
      expect(d.use, isTrue);
    });

    test('full kbps follows the chosen ceiling for lossless and lossy', () {
      expect(FastStartPolicy.fullKbps(_input(targetKbps: 320)), 320);
      expect(
        FastStartPolicy.fullKbps(
          _input(suffix: 'mp3', songKbps: 192, targetKbps: 320),
        ),
        192,
      );
      expect(FastStartPolicy.fullKbps(_input(songKbps: 0)), 900);
    });
  });

  group('FastStartPolicy.shouldSwap', () {
    bool swap({
      bool ready = true,
      bool same = true,
      bool pending = false,
      int pos = 6000,
      int dur = 240000,
    }) => FastStartPolicy.shouldSwap(
      fullReady: ready,
      sameSong: same,
      skipPending: pending,
      positionMs: pos,
      durationMs: dur,
    );

    test('swaps when the full copy is ready', () => expect(swap(), isTrue));
    test('waits for the full copy', () => expect(swap(ready: false), isFalse));
    test('never swaps a song the listener left', () {
      expect(swap(same: false), isFalse);
      expect(swap(pending: true), isFalse);
    });
    test('does not swap in the last seconds', () {
      expect(swap(pos: 237000), isFalse);
      expect(swap(pos: 200000), isTrue);
    });
  });

  group('ThroughputTracker', () {
    test('ignores tiny or instant transfers', () {
      final t = ThroughputTracker();
      t.add(1000, const Duration(seconds: 1));
      t.add(10 * 1024 * 1024, const Duration(milliseconds: 20));
      expect(t.bytesPerSec, isNull);
    });

    test('smooths samples', () {
      final t = ThroughputTracker();
      t.add(1024 * 1024, const Duration(seconds: 1));
      final first = t.bytesPerSec!;
      expect(first, 1024 * 1024);
      t.add(3 * 1024 * 1024, const Duration(seconds: 1));
      expect(t.bytesPerSec!, greaterThan(first));
      expect(t.bytesPerSec!, lessThan(3 * 1024 * 1024));
    });
  });

  group('SkipCoordinator', () {
    test('five quick skips open only the song they rest on', () {
      fakeAsync((async) {
        final p = _FakePlayer();
        final c = SkipCoordinator(load: p.load);
        for (var i = 1; i <= 5; i++) {
          c.request(i);
          async.elapse(const Duration(milliseconds: 80));
        }
        expect(p.opened, isEmpty);
        expect(c.pendingIndex, 5);
        async.elapse(kSkipSettle);
        async.flushMicrotasks();
        expect(p.opened, [5]);
        expect(p.finished, [5]);
        expect(c.isBusy, isFalse);
      });
    });

    test('a pause longer than the settle time opens each rest point', () {
      fakeAsync((async) {
        final p = _FakePlayer();
        final c = SkipCoordinator(load: p.load);
        c.request(1);
        async.elapse(kSkipSettle * 2);
        c.request(2);
        async.elapse(kSkipSettle * 2);
        async.flushMicrotasks();
        expect(p.finished, [1, 2]);
      });
    });

    test('a skip during a load makes it stale; nothing leaks', () {
      fakeAsync((async) {
        final p = _FakePlayer()..gate = Completer<void>();
        final c = SkipCoordinator(load: p.load);
        c.request(1);
        async.elapse(kSkipSettle);
        expect(p.opened, [1]);
        expect(c.isLoading, isTrue);
        // The listener moves on while song 1 is still opening.
        c.request(2);
        p.gate!.complete();
        async.flushMicrotasks();
        expect(p.leaked, [1], reason: 'the stale load saw it was stale');
        expect(p.finished, isEmpty);
        p.gate = null;
        async.elapse(kSkipSettle);
        async.flushMicrotasks();
        expect(p.finished, [2]);
        expect(c.isBusy, isFalse);
      });
    });

    test('cancel drops the pending skip', () {
      fakeAsync((async) {
        final p = _FakePlayer();
        final c = SkipCoordinator(load: p.load);
        c.request(3);
        c.cancel();
        async.elapse(kSkipSettle * 2);
        expect(p.opened, isEmpty);
        expect(c.hasPending, isFalse);
      });
    });

    test('loadNow skips the wait and supersedes a pending skip', () {
      fakeAsync((async) {
        final p = _FakePlayer();
        final c = SkipCoordinator(load: p.load);
        c.request(1);
        unawaited(c.loadNow(7));
        async.flushMicrotasks();
        expect(p.finished, [7]);
        async.elapse(kSkipSettle * 2);
        expect(p.opened, [7], reason: 'the pending skip was dropped');
      });
    });

    test('a failing load reports, and the next one still runs', () {
      fakeAsync((async) {
        final errors = <Object>[];
        final p = _FakePlayer();
        final c = SkipCoordinator(
          load: (i, stale) async {
            if (i == 1) throw StateError('boom');
            await p.load(i, stale);
          },
          onError: (e, _) => errors.add(e),
        );
        c.request(1);
        async.elapse(kSkipSettle);
        async.flushMicrotasks();
        expect(errors, hasLength(1));
        expect(c.isBusy, isFalse, reason: 'not stuck loading');
        c.request(2);
        async.elapse(kSkipSettle);
        async.flushMicrotasks();
        expect(p.finished, [2]);
      });
    });

    test('loadNow rethrows to its caller', () async {
      final c = SkipCoordinator(load: (i, s) async => throw StateError('x'));
      await expectLater(c.loadNow(1), throwsStateError);
      expect(c.isBusy, isFalse);
    });

    test('zero settle loads at once', () {
      fakeAsync((async) {
        final p = _FakePlayer();
        final c = SkipCoordinator(load: p.load, settle: Duration.zero);
        c.request(4);
        async.flushMicrotasks();
        expect(p.finished, [4]);
      });
    });
  });

  _extra();

  test('FirstAudioProbe reports once', () {
    final probe = FirstAudioProbe()..begin('tap');
    expect(probe.firstAudio(), startsWith('tap: '));
    expect(probe.firstAudio(), isNull);
  });
}

void _extra() {
  group('next-song preload and swap ramp', () {
    test('preload waits for 25% or 20 s, whichever is later', () {
      expect(nextPreloadDue(positionMs: 10000, durationMs: 200000), isFalse);
      expect(nextPreloadDue(positionMs: 25000, durationMs: 200000), isFalse); // 50 s = 25%
      expect(nextPreloadDue(positionMs: 50000, durationMs: 200000), isTrue);
      expect(nextPreloadDue(positionMs: 20000, durationMs: 60000), isTrue); // 20 s later
    });
  });
}
