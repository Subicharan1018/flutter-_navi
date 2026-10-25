import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/player/remote_view.dart';
import 'package:navivibe/services/session_sync_service.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Sink implements WebSocketSink {
  final frames = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> of(String type) => [for (final f in frames) if (f['type'] == type) f];

  @override
  void add(dynamic data) => frames.add(jsonDecode(data as String) as Map<String, dynamic>);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {}

  @override
  Future close([int? closeCode, String? closeReason]) async {}

  @override
  Future get done => Future.value();
}

class _Channel extends StreamChannelMixin implements WebSocketChannel {
  final _in = StreamController<dynamic>.broadcast();
  final _Sink out = _Sink();

  @override
  Stream get stream => _in.stream;

  @override
  WebSocketSink get sink => out;

  @override
  Future<void> get ready => Future.value();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  void server(Map<String, dynamic> m) => _in.add(jsonEncode(m));
  void serverCloses() => _in.close();
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

SessionSyncService _service(List<_Channel> channels, {Random? random}) => SessionSyncService(
      jwt: 'tok',
      deviceIdProvider: () async => 'dev-1',
      random: random,
      channelFactory: (_) {
        final c = _Channel();
        channels.add(c);
        return c;
      },
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );

Map<String, dynamic> _state({int epoch = 1, int version = 1, String? active, String? track}) => {
      'type': 'state',
      'epoch': epoch,
      'version': version,
      'active_device': active,
      'track_id': track,
      'payload': {'epoch': epoch, 'version': version, 'active_device': active, 'track_id': track},
    };

void main() {
  group('ClockEstimator', () {
    /// The device clock runs [skewMs] behind the server's; the request takes [up] ms and the reply [down] ms.
    (int, int, int) trip(int deviceStart, int skewMs, int up, int down) {
      final t0 = deviceStart;
      final serverT = (deviceStart + up) + skewMs; // the server's clock when the request lands
      final t1 = deviceStart + up + down;
      return (t0, t1, serverT);
    }

    test('±5 s of skew with lopsided latency stays inside 300 ms', () {
      for (final skew in [-5000, 5000, 0, 123456]) {
        final c = ClockEstimator();
        // A few trips; one of them is slow and very lopsided (200 ms up, 20 ms down).
        for (final (up, down) in [(180, 30), (60, 20), (350, 40), (25, 25), (90, 15)]) {
          final (t0, t1, s) = trip(1000000, skew, up, down);
          c.add(t0, t1, s);
        }
        expect((c.offsetMs - skew).abs(), lessThan(300), reason: 'skew $skew');
        expect(c.rttMs, 50);
      }
    });

    test('a single slow reply does not drag the estimate', () {
      final c = ClockEstimator();
      for (var i = 0; i < 6; i++) {
        final (t0, t1, s) = trip(1000000 + i * 25000, 5000, 20, 20);
        c.add(t0, t1, s);
      }
      final before = c.offsetMs;
      final (t0, t1, s) = trip(2000000, 5000, 900, 40); // a 940 ms round trip, lopsided
      c.add(t0, t1, s);
      expect((c.offsetMs - before).abs(), lessThan(50));
    });

    test('server time follows the offset, and reset forgets it', () {
      final c = ClockEstimator()..add(1000, 1040, 6020); // offset 6020 - 1020 = 5000
      expect(c.ready, isTrue);
      expect(c.serverNowMs(2000), 7000);
      c.reset();
      expect(c.ready, isFalse);
      expect(c.serverNowMs(2000), 2000);
    });
  });

  group('remote playhead on a device whose clock is wrong', () {
    test('uses the server stamp and the measured offset, not the device clock', () {
      final serverStamp = DateTime.utc(2026, 10, 25, 12).millisecondsSinceEpoch;
      final s = PlaybackState(isPlaying: true, positionMs: 10000, durationS: 300, positionAtServerMs: serverStamp);
      // The device clock is 5 s fast; four real seconds have passed since the stamp.
      final deviceNow = DateTime.fromMillisecondsSinceEpoch(serverStamp + 4000 + 5000);
      expect(remotePosition(s, deviceNow, offsetMs: -5000), const Duration(seconds: 14));
      expect(remotePosition(s, deviceNow), const Duration(seconds: 19)); // without the offset it would jump ahead
    });
  });

  group('reconnect backoff', () {
    test('0.5 s · 2^n, capped at 30 s, with full jitter', () {
      final top = _Fixed(0.9999999);
      expect(SessionSyncService.reconnectDelayMs(1, top), inInclusiveRange(490, 500));
      expect(SessionSyncService.reconnectDelayMs(2, top), inInclusiveRange(990, 1000));
      expect(SessionSyncService.reconnectDelayMs(5, top), inInclusiveRange(7990, 8000));
      expect(SessionSyncService.reconnectDelayMs(12, top), inInclusiveRange(29990, 30000));
      expect(SessionSyncService.reconnectDelayMs(40, top), inInclusiveRange(29990, 30000));
      expect(SessionSyncService.reconnectDelayMs(6, _Fixed(0)), 200); // never a busy loop
      final spread = {for (var i = 0; i < 50; i++) SessionSyncService.reconnectDelayMs(8, Random(i))};
      expect(spread.length, greaterThan(30)); // a crowd does not come back in step
    });
  });

  group('protocol 3 on the wire', () {
    test('pings carry t0, and a pong teaches the clock', () async {
      final ch = <_Channel>[];
      final s = _service(ch);
      await s.connect();
      final ping = ch.single.out.of('ping').first;
      expect(ping['t0'], isA<int>());
      final now = DateTime.now().millisecondsSinceEpoch;
      ch.single.server({'type': 'pong', 't0': ping['t0'], 'server_t': now + 5000});
      await _pump();
      expect(s.clock.ready, isTrue);
      expect(s.clock.offsetMs, closeTo(5000, 400));
      s.dispose();
    });

    test('a state with an epoch tells the client the server speaks 3; commands become acked cmds', () async {
      final ch = <_Channel>[];
      final s = _service(ch);
      await s.connect();
      s.sendCommand('pause');
      expect(ch.single.out.of('cmd'), isEmpty);
      expect(ch.single.out.of('command'), hasLength(1)); // an older server still gets the old frame
      ch.single.server(_state(epoch: 4, version: 10, active: 'dev-2'));
      await _pump();
      expect(s.serverSpeaksV3, isTrue);
      s.sendCommand('seek', positionMs: 9000);
      s.transferPlayback('dev-1', force: true);
      final cmds = ch.single.out.of('cmd');
      expect(cmds[0]['cmdType'], 'seek');
      expect(cmds[0]['args']['position_ms'], 9000);
      expect(cmds[0]['baseVersion'], 10);
      expect(cmds[1]['cmdType'], 'transfer');
      expect(cmds[1]['args'], {'toDeviceId': 'dev-1', 'force': true, 'baseEpoch': 4});
      expect(cmds[0]['cmdId'] == cmds[1]['cmdId'], isFalse);
      s.dispose();
    });

    test('acks reach the UI: ok quietly, stale and rejected with a reason', () async {
      final ch = <_Channel>[];
      final s = _service(ch);
      await s.connect();
      ch.single.server(_state(epoch: 1, version: 1));
      await _pump();
      final results = <CommandResult>[];
      s.resultStream.listen(results.add);
      s.sendCommand('next');
      s.transferPlayback('dev-9');
      final ids = [for (final c in ch.single.out.of('cmd')) c['cmdId']];
      ch.single.server({'type': 'ack', 'cmdId': ids[0], 'status': 'ok'});
      ch.single.server({'type': 'ack', 'cmdId': ids[1], 'status': 'stale', 'reason': 'epoch_changed'});
      await _pump();
      expect(results.map((r) => (r.action, r.ok)), [('next', true), ('transfer', false)]);
      expect(results.last.reason, 'epoch_changed');
      s.dispose();
    });

    test('an unacknowledged transfer is resent with the same id after a reconnect, exactly once', () async {
      final ch = <_Channel>[];
      final s = _service(ch, random: _Fixed(0)); // retry after the 200 ms floor
      await s.connect();
      ch.last.server(_state(epoch: 2, version: 3));
      await _pump();
      s.transferPlayback('dev-7', force: true);
      final id = ch.first.out.of('cmd').single['cmdId'];
      ch.first.serverCloses(); // the socket dies before any ack
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(ch, hasLength(2));
      final resent = ch.last.out.of('cmd');
      expect(resent, hasLength(1));
      expect(resent.single['cmdId'], id);
      // the ack arrives this time: nothing more is sent on the next reconnect
      ch.last.server({'type': 'ack', 'cmdId': id, 'status': 'ok'});
      await _pump();
      ch.last.serverCloses();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(ch, hasLength(3));
      expect(ch.last.out.of('cmd'), isEmpty);
      s.dispose();
    });

    test('an older state within the same epoch is dropped; a new connection starts fresh', () async {
      final ch = <_Channel>[];
      final s = _service(ch);
      await s.connect();
      final seen = <PlaybackState>[];
      s.stateStream.listen(seen.add);
      ch.last.server(_state(epoch: 3, version: 9, track: 'new'));
      ch.last.server(_state(epoch: 3, version: 7, track: 'old')); // delayed in the network
      ch.last.server(_state(epoch: 2, version: 99, track: 'older-epoch'));
      await _pump();
      expect(seen.map((x) => x.trackId), ['new']);
      s.dispose();
    });

    test('a "prepare" order reaches the player and ready goes back with its id', () async {
      final ch = <_Channel>[];
      final s = _service(ch);
      await s.connect();
      final got = <PrepareTransfer>[];
      s.prepareStream.listen(got.add);
      ch.last.server({'type': 'exec', 'action': 'prepare', 'transfer_id': 'abc', 'epoch': 5, 'position_ms': 61000, 'track_id': 't2', 'queue': ['t1', 't2'], 'queue_index': 1, 'play': true});
      await _pump();
      expect(got.single.transferId, 'abc');
      expect(got.single.positionMs, 61000);
      expect(got.single.queue, ['t1', 't2']);
      s.sendReady('abc');
      expect(ch.last.out.of('ready').single['transfer_id'], 'abc');
      s.dispose();
    });
  });

  group('heartbeat', () {
    test('no pong within 10 s means the socket is half-open: the link is reported down and retried', () {
      fakeAsync((async) {
        final ch = <_Channel>[];
        final s = _service(ch, random: _Fixed(0));
        s.connect();
        async.flushMicrotasks();
        expect(s.connection, SyncConnection.online);
        async.elapse(const Duration(seconds: 9));
        expect(s.connection, SyncConnection.online);
        async.elapse(const Duration(seconds: 7, milliseconds: 50)); // 10 s after the last (unanswered) ping, sent at 6 s, the watchdog fires
        expect(s.connection, SyncConnection.offline);
        async.elapse(const Duration(seconds: 1)); // and a fresh socket is opened
        async.flushMicrotasks();
        expect(ch, hasLength(2));
        expect(s.connection, SyncConnection.online);
        s.dispose();
        async.flushTimers();
      });
    });

    test('an answered ping keeps the socket', () {
      fakeAsync((async) {
        final ch = <_Channel>[];
        final s = _service(ch);
        s.connect();
        async.flushMicrotasks();
        // answer every ping as it arrives
        var answered = 0;
        for (var i = 0; i < 40; i++) {
          async.elapse(const Duration(seconds: 1));
          for (final p in ch.first.out.of('ping').skip(answered)) {
            ch.first.server({'type': 'pong', 't0': p['t0'], 'server_t': DateTime.now().millisecondsSinceEpoch});
            answered++;
          }
          async.flushMicrotasks();
        }
        expect(ch, hasLength(1));
        expect(s.connection, SyncConnection.online);
        expect(ch.first.out.of('ping').length, greaterThanOrEqualTo(4)); // three quick ones, then one at 25 s
        s.dispose();
        async.flushTimers();
      });
    });
  });
}

class _Fixed implements Random {
  final double v;
  _Fixed(this.v);
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => v;
  @override
  int nextInt(int max) => 0;
}
