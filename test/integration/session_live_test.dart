/// The real app client against the real relay code over real WebSockets.
///
/// Needs a simulation server (see tools/session_sim/run_sim.py) and these variables:
///   SESSION_SIM=http://127.0.0.1:5599      relay with a 4 s reconnect grace
///   SESSION_SIM_REAL=http://127.0.0.1:5598 relay with production timings (for the soak)
///   SESSION_SOAK_MINUTES=10                 (optional) length of the idle soak
///
///   flutter test test/integration/session_live_test.dart --plain-name "scenario"
///
/// Without SESSION_SIM every test here is skipped, so the normal suite never needs a server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:navivibe/services/session_sync_service.dart';

final String? _sim = Platform.environment['SESSION_SIM'];
final String? _simReal = Platform.environment['SESSION_SIM_REAL'];

String _wsOf(String base) => '${base.replaceFirst('http', 'ws')}/ws/session';

/// A signed-in device: the real service, plus a record of everything it was told.
class Dev {
  final String user;
  final String id;
  final String name;
  final SessionSyncService service;
  final states = <PlaybackState>[];
  final devices = <List<SyncDevice>>[];
  final commands = <(RemoteCommand, DateTime)>[];
  final results = <CommandResult>[];
  final prepares = <PrepareTransfer>[];
  final connections = <SyncConnection>[];
  final connectionAt = <DateTime>[];
  bool autoReady = true;
  Duration loadTime = const Duration(milliseconds: 150);
  String _token;

  static Dev create(String base, String user, String id, String name, {SyncDeviceType type = SyncDeviceType.phone}) {
    late Dev d;
    final svc = SessionSyncService(
      jwtSupplier: ({bool forceRefresh = false}) => d._token,
      deviceIdProvider: () async => id,
      wsBaseUrl: _wsOf(base),
      httpBaseUrl: base,
      deviceName: name,
      deviceType: type,
    );
    d = Dev._(base, user, id, name, svc);
    d._wire();
    return d;
  }

  Dev._(String base, this.user, this.id, this.name, this.service) : _token = base64Encode(utf8.encode('$user:sim'));

  void _wire() {
    service.stateStream.listen(states.add);
    service.devicesStream.listen(devices.add);
    service.commandStream.listen((c) => commands.add((c, DateTime.now())));
    service.resultStream.listen(results.add);
    service.connectionStream.listen((c) {
      connections.add(c);
      connectionAt.add(DateTime.now());
    });
    service.prepareStream.listen((p) {
      prepares.add(p);
      if (autoReady) Future<void>.delayed(loadTime, () => service.sendReady(p.transferId));
    });
  }

  void signInAs(String newUser) {
    _token = base64Encode(utf8.encode('$newUser:sim'));
  }

  Future<void> connect() async {
    await service.connect();
    await until(() => service.connection == SyncConnection.online && states.isNotEmpty, what: '$name online');
  }

  PlaybackState get state => service.currentState;
  List<SyncDevice> get list => service.currentDevices;
  void dispose() => service.dispose();
}

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 8), String what = 'condition'}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<Map<String, dynamic>> rooms(String base) async =>
    jsonDecode((await http.get(Uri.parse('$base/_sim/rooms'))).body) as Map<String, dynamic>;

void main() {
  final sim = _sim;
  if (sim == null) {
    test('session live scenarios (set SESSION_SIM to run)', () {}, skip: 'no simulation server');
    return;
  }
  final started = <Dev>[];
  Dev dev(String user, String id, String name, {SyncDeviceType type = SyncDeviceType.phone, String? base}) {
    final d = Dev.create(base ?? sim, user, '$id-${DateTime.now().microsecondsSinceEpoch}', name, type: type);
    started.add(d);
    return d;
  }

  tearDown(() {
    for (final d in started) {
      d.dispose();
    }
    started.clear();
  });

  test('S1 two devices of admin see each other with real names and roles; vijay sees none of it', () async {
    final phone = dev('s1admin', 'phone', 'OnePlus CPH2487');
    final laptop = dev('s1admin', 'laptop', 'Windows PC (Subicharan)', type: SyncDeviceType.desktop);
    final other = dev('s1vijay', 'phone', 'Android phone');
    await Future.wait([phone.connect(), laptop.connect(), other.connect()]);
    await until(() => phone.list.length == 2 && laptop.list.length == 2, what: 'both admin devices listed');
    expect({for (final d in phone.list) d.name: d.type}, {'OnePlus CPH2487': SyncDeviceType.phone, 'Windows PC (Subicharan)': SyncDeviceType.desktop});
    expect(phone.list.every((d) => !d.active), isTrue, reason: 'nobody is host yet');
    expect(other.list.map((d) => d.name), ['Android phone']);
    phone.service.transferPlayback(phone.id, deviceName: phone.name, force: true);
    await until(() => laptop.list.any((d) => d.active), what: 'host flag reaches the laptop');
    expect(laptop.list.firstWhere((d) => d.active).name, 'OnePlus CPH2487');
    expect(laptop.state.activeDeviceName, 'OnePlus CPH2487');
    expect(other.list.any((d) => d.active), isFalse);
    expect(other.state.activeDevice, isNull);
  });

  test('S2 play on A: B sees it and controls it, under a second', () async {
    final a = dev('s2', 'a', 'Phone');
    final b = dev('s2', 'b', 'Laptop', type: SyncDeviceType.desktop);
    await Future.wait([a.connect(), b.connect()]);
    a.service.transferPlayback(a.id, force: true);
    await until(() => a.state.activeDevice == a.id && b.state.activeDevice == a.id, what: 'A is host everywhere');
    a.service.pushStateUpdate(
        trackId: 't1', trackTitle: 'Thaniye', artist: 'Anirudh', durationS: 238, positionMs: 61000, isPlaying: true, queue: ['t1', 't2'], queueIndex: 0);
    await until(() => b.state.trackTitle == 'Thaniye' && b.state.isPlaying, what: 'B shows A\'s song');
    expect(b.state.activeDeviceName, 'Phone');

    final lag = <String, int>{};
    Future<void> control(String action, {int? positionMs, double? volume}) async {
      final before = a.commands.length;
      final t0 = DateTime.now();
      b.service.sendCommand(action, positionMs: positionMs, volume: volume);
      await until(() => a.commands.length > before, timeout: const Duration(seconds: 2), what: 'A receives $action');
      lag[action] = a.commands.last.$2.difference(t0).inMilliseconds;
      expect(a.commands.last.$1.action, action);
      expect(a.commands.last.$1.fromName, 'Laptop');
    }

    await control('pause');
    await until(() => !b.state.isPlaying, timeout: const Duration(seconds: 2), what: 'B sees the pause at once');
    await control('play');
    await control('seek', positionMs: 120000);
    await control('volume', volume: 0.3);
    await control('next');
    // ignore the first call (connection warm-up) when judging: all are real round trips over the tunnel
    // ignore: avoid_print
    print('S2 command lag ms: $lag');
    expect(lag.values.every((ms) => ms < 1000), isTrue, reason: '$lag');
    expect(b.results.where((r) => !r.ok), isEmpty);
  });

  test('S3 Play here: the old host plays until the new one is ready; then one epoch, no gap, A stops', () async {
    final a = dev('s3', 'a', 'Phone');
    final b = dev('s3', 'b', 'Laptop', type: SyncDeviceType.desktop);
    await Future.wait([a.connect(), b.connect()]);
    a.service.transferPlayback(a.id, force: true);
    await until(() => b.state.activeDevice == a.id, what: 'A host');
    a.service.pushStateUpdate(trackId: 't1', trackTitle: 'One', durationS: 200, positionMs: 30000, isPlaying: true, queue: ['t1', 't2', 't3'], queueIndex: 1, ); // ignore: avoid_redundant_argument_values
    await until(() => b.state.trackId == 't1', what: 'state');
    await Future<void>.delayed(const Duration(milliseconds: 1600)); // past the hysteresis
    final epochBefore = b.state.epoch!;
    b.loadTime = const Duration(milliseconds: 600); // loading the song takes a while
    final t0 = DateTime.now();
    b.service.transferPlayback(b.id, deviceName: 'Laptop', force: true);
    await until(() => b.prepares.isNotEmpty, what: 'B is asked to prepare');
    final prep = b.prepares.single;
    expect(prep.trackId, 't1');
    expect(prep.queue, ['t1', 't2', 't3']);
    expect(prep.positionMs, greaterThanOrEqualTo(30000));
    // while B loads, A is still the host and nobody was told otherwise
    var r = (await rooms(sim))['s3'] as Map<String, dynamic>;
    expect(r['active'], a.id, reason: 'no gap: the old host keeps playing during the load');
    expect(r['pending'], isTrue);
    expect(a.state.activeDevice, a.id);
    await until(() => b.state.activeDevice == b.id && a.state.activeDevice == b.id, what: 'handover committed');
    final total = DateTime.now().difference(t0).inMilliseconds;
    r = (await rooms(sim))['s3'] as Map<String, dynamic>;
    expect(r['epoch'], epochBefore + 1);
    expect(r['pending'], isFalse);
    expect(a.state.activeDevice, b.id, reason: 'A learns it was deposed and would stop');
    expect(b.results.where((x) => x.action == 'transfer' && !x.ok), isEmpty);
    // ignore: avoid_print
    print('S3 handover took $total ms (B needed 600 ms to load)');
    expect(total, lessThan(1500));
  });

  test('S4 simultaneous plays: exactly one wins and nothing flips afterwards', () async {
    final a = dev('s4', 'a', 'Phone');
    final b = dev('s4', 'b', 'Laptop', type: SyncDeviceType.desktop);
    final c = dev('s4', 'c', 'Tablet', type: SyncDeviceType.tablet);
    await Future.wait([a.connect(), b.connect(), c.connect()]);
    // all three start playing "here" in the same instant, none of them forced (nothing but a touch each, say)
    a.service.transferPlayback(a.id);
    b.service.transferPlayback(b.id);
    c.service.transferPlayback(c.id);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final seen = <String?>{};
    final flips = <String?>[];
    String? last;
    final end = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(end)) {
      final active = ((await rooms(sim))['s4'] as Map<String, dynamic>)['active'] as String?;
      seen.add(active);
      if (active != last) flips.add(active);
      last = active;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    expect(seen.length, 1, reason: 'one host the whole time: $seen');
    expect(flips.length, 1, reason: 'the host changed once, from nothing to someone: $flips');
    final winner = [a, b, c].firstWhere((d) => d.id == seen.single);
    final losers = [a, b, c].where((d) => d != winner);
    for (final l in losers) {
      expect(l.state.activeDevice, winner.id, reason: '${l.name} adopted the winner');
    }
    expect(losers.expand((l) => l.results).where((r) => !r.ok).length, 2, reason: 'both losers were told no');
  });

  test('S5 host drops out and comes back: inside the grace it stays host, past it the session pauses with nobody drafted', () async {
    final a = dev('s5', 'a', 'Phone');
    final b = dev('s5', 'b', 'Laptop', type: SyncDeviceType.desktop);
    await Future.wait([a.connect(), b.connect()]);
    a.service.transferPlayback(a.id, force: true);
    await until(() => b.state.activeDevice == a.id, what: 'A host');
    a.service.pushStateUpdate(trackId: 't1', durationS: 200, positionMs: 10000, isPlaying: true, queue: ['t1']);
    await until(() => b.state.isPlaying, what: 'playing');
    final epoch0 = b.state.epoch!;

    // brief background: back within the grace period
    a.service.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(b.state.activeDevice, a.id, reason: 'held for it');
    await a.service.connect();
    await until(() => a.service.connection == SyncConnection.online && a.state.activeDevice == a.id, what: 'A is still host on return');
    expect(a.state.epoch, epoch0, reason: 'no handover happened');

    // long background: past the 4 s grace
    a.service.disconnect();
    await until(() => b.state.activeDevice == null, timeout: const Duration(seconds: 10), what: 'the session lets go of A');
    expect(b.state.isPlaying, isFalse);
    expect(b.state.positionMs, greaterThanOrEqualTo(10000), reason: 'paused where the music was, not at 0');
    expect(b.state.epoch, epoch0 + 1);
    expect(b.prepares, isEmpty, reason: 'no one was drafted to take over');
    await a.service.connect();
    await until(() => a.state.epoch == epoch0 + 1 && a.state.activeDevice == null, what: 'A reconciles to the paused session');
  });

  test('S6 network drop: the client reconnects by itself, quickly, and the host seat survives', () async {
    final a = dev('s6', 'a', 'Phone');
    final b = dev('s6', 'b', 'Laptop', type: SyncDeviceType.desktop);
    await Future.wait([a.connect(), b.connect()]);
    a.service.transferPlayback(a.id, force: true);
    await until(() => b.state.activeDevice == a.id, what: 'A host');
    final epoch0 = b.state.epoch!;
    final offlineAt = a.connections.length;
    final t0 = DateTime.now();
    await http.get(Uri.parse('$sim/_sim/drop?user=s6&device=${a.id}'));
    await until(() => a.connections.skip(offlineAt).contains(SyncConnection.offline), what: 'A notices the drop');
    await until(() => a.service.connection == SyncConnection.online && a.connections.length > offlineAt + 1, timeout: const Duration(seconds: 6), what: 'A is back');
    final back = DateTime.now().difference(t0).inMilliseconds;
    // ignore: avoid_print
    final ev = [for (var i = offlineAt; i < a.connections.length; i++) '${a.connections[i].name}@${a.connectionAt[i].difference(t0).inMilliseconds}ms'];
    print('S6 reconnected after $back ms: $ev');
    expect(back, lessThan(3000));
    await until(() => a.state.activeDevice == a.id, what: 'the snapshot still names A');
    expect(a.state.epoch, epoch0);
    // and it can report again
    a.service.pushStateUpdate(trackId: 'after', isPlaying: true, queue: ['after']);
    await until(() => b.state.trackId == 'after', what: 'reports flow again');
  });

  test('S7 switching account on one device: complete isolation, and the other account\'s devices were never visible', () async {
    final adminLaptop = dev('s7admin', 'laptop', 'Windows PC (Subicharan)', type: SyncDeviceType.desktop);
    final adminPhone = dev('s7admin', 'phone', 'OnePlus CPH2487');
    final vijayPhone = dev('s7vijay', 'phone', 'Vijay phone');
    await Future.wait([adminLaptop.connect(), adminPhone.connect(), vijayPhone.connect()]);
    adminPhone.service.transferPlayback(adminPhone.id, force: true);
    adminPhone.service.pushStateUpdate(trackId: 'secret', trackTitle: 'Admin only', isPlaying: true, queue: ['secret']);
    await until(() => adminLaptop.state.trackTitle == 'Admin only', what: 'admin laptop sees admin phone');
    expect(vijayPhone.state.trackTitle, isNull);
    expect(vijayPhone.list.map((d) => d.name), ['Vijay phone']);

    // the laptop signs out of admin and into vijay, the way the app does it
    adminLaptop.signInAs('s7vijay');
    adminLaptop.service.resetAccount();
    expect(adminLaptop.state.trackTitle, isNull, reason: 'nothing of the old account lingers');
    expect(adminLaptop.list, isEmpty);
    await adminLaptop.service.connect();
    await until(() => adminLaptop.service.connection == SyncConnection.online && adminLaptop.list.length == 2, what: 'laptop joins vijay');
    final r = await rooms(sim);
    final adminDevs = ((r['s7admin'] as Map)['devices'] as Map).values.where((d) => (d as Map)['sockets'] as int > 0).length;
    final vijayDevs = ((r['s7vijay'] as Map)['devices'] as Map).values.where((d) => (d as Map)['sockets'] as int > 0).length;
    expect(adminDevs, 1);
    expect(vijayDevs, 2);
    expect(adminLaptop.list.map((d) => d.name).toSet(), {'Vijay phone', 'Windows PC (Subicharan)'});
    expect(adminLaptop.state.trackTitle, isNull, reason: 'vijay\'s room has no playback; admin\'s song did not follow');
    expect(adminPhone.list.map((d) => d.name), ['OnePlus CPH2487'], reason: 'admin lost the laptop at once');
    // admin plays on: the laptop (now vijay) must hear nothing
    adminPhone.service.pushStateUpdate(trackId: 'secret2', trackTitle: 'Still admin only', isPlaying: true, queue: ['secret2']);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(adminLaptop.state.trackTitle, isNull);
    expect(vijayPhone.state.trackTitle, isNull);
    // and vijay commands cannot reach admin's phone
    adminLaptop.service.sendCommand('pause');
    await until(() => adminLaptop.results.isNotEmpty, what: 'an answer');
    expect(adminLaptop.results.last.ok, isFalse);
    expect(adminPhone.commands, isEmpty);
  });

  test('S9 reconnect storm: 50 reconnects resending one command apply it once', () async {
    final host = dev('s9', 'host', 'Phone');
    final ctl = dev('s9', 'ctl', 'Laptop', type: SyncDeviceType.desktop);
    await Future.wait([host.connect(), ctl.connect()]);
    host.service.transferPlayback(host.id, force: true);
    await until(() => ctl.state.activeDevice == host.id && ctl.service.serverSpeaksV3, what: 'host + v3');
    final storm = <WebSocket>[];
    final token = base64Encode(utf8.encode('s9:sim'));
    for (var i = 0; i < 50; i++) {
      final ws = await WebSocket.connect('${_wsOf(sim)}?token=$token&device_id=storm-dev&device_name=Storm&proto=3');
      ws.add(jsonEncode({'type': 'cmd', 'cmdId': 'storm-1', 'cmdType': 'volume', 'args': {'volume': 0.5}}));
      storm.add(ws);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await ws.close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(host.commands.where((c) => c.$1.action == 'volume').length, 1);
  });

  test('S10 older builds (proto 1 and 2) keep working next to proto 3 and are never sent new frame types', () async {
    final new3 = dev('s10', 'new', 'New phone');
    await new3.connect();
    final seen = <String>{};
    for (final proto in [1, 2]) {
      if (proto == 2) await Future<void>.delayed(const Duration(milliseconds: 1700)); // past the transfer hysteresis
      final token = base64Encode(utf8.encode('s10:sim'));
      final ws = await WebSocket.connect('${_wsOf(sim)}?token=$token&device_id=old$proto&device_name=Old$proto&proto=$proto');
      final types = <String>[];
      ws.listen((m) => types.add((jsonDecode(m as String) as Map)['type'] as String));
      ws.add(jsonEncode({'type': 'transfer_playback', 'device_id': 'old$proto'}));
      ws.add(jsonEncode({'type': 'state_update', 'track_id': 'old-track-$proto', 'is_playing': true}));
      ws.add(jsonEncode({'type': 'ping'}));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (proto == 1) {
        expect(types.toSet().difference({'state', 'pong'}), isEmpty, reason: 'proto 1 got $types');
      }
      seen.addAll(types);
      await ws.close();
      await until(() => new3.state.trackId == 'old-track-$proto', what: 'proto $proto reports reach the new client');
      new3.service.requestDevices();
    }
    expect(seen, containsAll(['state', 'pong']));
  });

  test('S11 wrong credentials: the client backs off instead of hammering the server', () async {
    final before = jsonDecode((await http.get(Uri.parse('$sim/_sim/stats'))).body)['auth_fail'] as int;
    final d = Dev.create(sim, 's11', 'bad-${DateTime.now().microsecondsSinceEpoch}', 'Phone');
    started.add(d);
    d._token = base64Encode(utf8.encode('s11:wrong-password'));
    unawaited(d.service.connect());
    await Future<void>.delayed(const Duration(seconds: 20));
    final after = jsonDecode((await http.get(Uri.parse('$sim/_sim/stats'))).body)['auth_fail'] as int;
    // ignore: avoid_print
    print('S11 refused logins in 20 s: ${after - before}');
    expect(after - before, lessThanOrEqualTo(9), reason: 'three quick retries, then 0.5 s * 2^n with jitter');
    expect(d.service.connection, isNot(SyncConnection.online));
    // and it recovers on its own once the password is right
    d._token = base64Encode(utf8.encode('s11:sim'));
    await until(() => d.service.connection == SyncConnection.online, timeout: const Duration(seconds: 40), what: 'recovery with the right password');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('S8 soak: an idle device stays connected through minutes of silence on the production timings', () async {
    final real = _simReal;
    final minutes = int.tryParse(Platform.environment['SESSION_SOAK_MINUTES'] ?? '') ?? 0;
    if (real == null || minutes == 0) {
      markTestSkipped('set SESSION_SIM_REAL and SESSION_SOAK_MINUTES to run the soak');
      return;
    }
    final idle = dev('soak', 'idle', 'Phone (screen off)', base: real);
    final peer = dev('soak', 'peer', 'Laptop', type: SyncDeviceType.desktop, base: real);
    await Future.wait([idle.connect(), peer.connect()]);
    idle.service.transferPlayback(idle.id, force: true);
    await until(() => peer.state.activeDevice == idle.id, what: 'host');
    final drops = idle.connections.where((c) => c == SyncConnection.offline).length;
    final end = DateTime.now().add(Duration(minutes: minutes));
    var worstSilence = 0.0;
    var samples = 0;
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(seconds: 15));
      final rm = (await rooms(real))['soak'] as Map<String, dynamic>;
      expect((rm['devices'] as Map).length, 2, reason: 'both devices still known');
      expect(rm['active'], idle.id, reason: 'the idle host was never released');
      samples++;
      final listed = peer.list.firstWhere((d) => d.id == idle.id);
      worstSilence = worstSilence < (listed.lastSeenS ?? 0) ? (listed.lastSeenS ?? 0) : worstSilence;
    }
    expect(idle.connections.where((c) => c == SyncConnection.offline).length, drops, reason: 'the socket never dropped');
    expect(idle.service.clock.ready, isTrue);
    // ignore: avoid_print
    print('S8 soak $minutes min, $samples samples, never dropped; clock offset ${idle.service.clock.offsetMs} ms rtt ${idle.service.clock.rttMs} ms');
  }, timeout: Timeout(Duration(minutes: (int.tryParse(Platform.environment['SESSION_SOAK_MINUTES'] ?? '') ?? 0) + 3)));
}
