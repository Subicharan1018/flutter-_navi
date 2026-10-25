import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/player/devices_sheet.dart';
import 'package:navivibe/player/remote_view.dart';
import 'package:navivibe/services/session_sync_service.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Sink implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];

  final pings = <Map<String, dynamic>>[];

  @override
  void add(dynamic data) {
    final frame = jsonDecode(data as String) as Map<String, dynamic>;
    (frame['type'] == 'ping' ? pings : sent).add(frame);
  }

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

  void serverSends(Map<String, dynamic> m) => _in.add(jsonEncode(m));

  void serverCloses() => _in.close();
}

class _FailingChannel extends StreamChannelMixin implements WebSocketChannel {
  @override
  Stream get stream => const Stream.empty();

  @override
  WebSocketSink get sink => _Sink();

  @override
  Future<void> get ready => Future.error(WebSocketChannelException('was not upgraded to websocket'));

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class _SlowChannel extends _Channel {
  final Future<void> _ready;
  _SlowChannel(this._ready);

  @override
  Future<void> get ready => _ready;
}

class _NoJitter implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0.5;
  @override
  int nextInt(int max) => 0;
}

Future<(SessionSyncService, _Channel, List<Uri>)> _connected({String? name, SyncDeviceType type = SyncDeviceType.unknown}) async {
  final ch = _Channel();
  final uris = <Uri>[];
  final service = SessionSyncService(
    jwt: 'tok en/+=',
    deviceIdProvider: () async => 'dev-1',
    deviceName: name,
    deviceType: type,
    channelFactory: (u) {
      uris.add(u);
      return ch;
    },
    httpClient: MockClient((_) async => http.Response('{}', 404)),
  );
  await service.connect();
  return (service, ch, uris);
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  test('connecting says who this device is and asks for the new protocol, with a safe query', () async {
    final (service, _, uris) = await _connected(name: 'Pixel 8', type: SyncDeviceType.phone);
    final q = uris.single.queryParameters;
    expect(q['proto'], '3');
    expect(q['device_name'], 'Pixel 8');
    expect(q['device_type'], 'phone');
    expect(q['token'], 'tok en/+=');               // survives encoding
    service.dispose();
  });

  test('a state message is read from "payload" (and flat, as older servers sent it)', () async {
    final (service, ch, _) = await _connected();
    final seen = <PlaybackState>[];
    service.stateStream.listen(seen.add);
    ch.serverSends({
      'type': 'state',
      'active_device': 'x',
      'payload': {
        'active_device': 'dev-2',
        'active_device_name': 'Windows PC',
        'track_id': 't1',
        'track_title': 'Song',
        'cover_art_id': 'c9',
        'duration_s': 201.5,
        'position_ms': 4000,
        'is_playing': true,
        'queue': ['t1', 't2'],
        'queue_index': 0,
        'updated_at': 1800000000.25, // unix seconds, as the server stamps it
      },
    });
    await _pump();
    final s = seen.last;
    expect(s.activeDevice, 'dev-2');
    expect(s.coverArtId, 'c9');
    expect(s.durationS, 201.5);
    expect(s.updatedAt!.millisecondsSinceEpoch, 1800000000250);
    ch.serverSends({'type': 'state', 'active_device': 'flat-dev', 'is_playing': false});
    await _pump();
    expect(service.currentState.activeDevice, 'flat-dev');
    service.dispose();
  });

  test('devices, commands and results arrive on their own streams and never become state', () async {
    final (service, ch, _) = await _connected();
    final states = <PlaybackState>[];
    final devices = <List<SyncDevice>>[];
    final commands = <RemoteCommand>[];
    final results = <CommandResult>[];
    service.stateStream.listen(states.add);
    service.devicesStream.listen(devices.add);
    service.commandStream.listen(commands.add);
    service.resultStream.listen(results.add);

    ch.serverSends({
      'type': 'devices',
      'payload': [
        {'id': 'a', 'name': 'Pixel', 'type': 'phone', 'active': true},
        {'id': 'b', 'name': 'Den TV', 'type': 'tv', 'active': false},
      ],
    });
    ch.serverSends({'type': 'command', 'action': 'seek', 'position_ms': 9000, 'from_device': 'a', 'from_name': 'Pixel'});
    ch.serverSends({'type': 'command_result', 'ok': false, 'action': 'pause', 'reason': 'device_offline'});
    await _pump();

    expect(states, isEmpty);
    expect(devices.single.map((d) => d.name), ['Pixel', 'Den TV']);
    expect(devices.single.first.active, isTrue);
    expect(service.currentDevices, hasLength(2));
    expect(commands.single.action, 'seek');
    expect(commands.single.positionMs, 9000);
    expect(commands.single.fromName, 'Pixel');
    expect(results.single.ok, isFalse);
    expect(results.single.message, 'That device went offline.');
    service.dispose();
  });

  test('outbound frames: command, transfer with a name, release, device request, state with song details', () async {
    final (service, ch, _) = await _connected();
    service.sendCommand('volume', volume: 0.4, target: 'b');
    service.sendCommand('set_queue', queue: ['x', 'y'], index: 1);
    service.transferPlayback('b', deviceName: 'Den TV');
    service.releasePlayback();
    service.requestDevices();
    service.pushStateUpdate(trackId: 't', trackTitle: 'Song', artist: 'A', coverArtId: 'c', durationS: 180, queueIndex: 2);
    final sent = ch.out.sent;
    expect(sent[0], {'type': 'command', 'action': 'volume', 'volume': 0.4, 'target': 'b'});
    expect(sent[1], {'type': 'command', 'action': 'set_queue', 'queue': ['x', 'y'], 'index': 1});
    expect(sent[2], {'type': 'transfer_playback', 'device_id': 'b', 'device_name': 'Den TV'});
    expect(sent[3], {'type': 'release_playback'});
    expect(sent[4], {'type': 'get_devices'});
    expect(sent[5]['track_title'], 'Song');
    expect(sent[5]['cover_art_id'], 'c');
    expect(sent[5]['queue_index'], 2);
    expect(sent[5].containsKey('album'), isFalse);
    service.dispose();
  });

  test('connection status follows the socket and the device list empties offline', () async {
    final (service, ch, _) = await _connected();
    final seen = <SyncConnection>[];
    service.connectionStream.listen(seen.add);
    expect(service.connection, SyncConnection.online);
    ch.serverSends({'type': 'devices', 'payload': [{'id': 'a', 'name': 'Pixel', 'type': 'phone', 'active': true}]});
    await _pump();
    expect(service.currentDevices, isNotEmpty);
    ch.serverCloses();
    await _pump();
    expect(seen, contains(SyncConnection.offline));
    expect(service.currentDevices, isEmpty);
    service.dispose();
  });

  test('connecting twice does not open a second socket', () async {
    final (service, _, uris) = await _connected();
    await service.connect();
    expect(uris, hasLength(1));
    service.dispose();
  });

  test('a connection that failed to open does not block the retry (the TV after a slow network start)', () async {
    final good = _Channel();
    var attempts = 0;
    final service = SessionSyncService(
      jwt: 'tok',
      deviceIdProvider: () async => 'dev-1',
      random: _NoJitter(),
      channelFactory: (u) {
        attempts++;
        return attempts == 1 ? _FailingChannel() : good;
      },
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    await service.connect();
    expect(service.connection, SyncConnection.offline);
    expect(service.isConnected, isFalse);
    await service.connect(); // what the scheduled retry does
    expect(attempts, 2);
    expect(service.connection, SyncConnection.online);
    service.dispose();
  });

  test('a claim sent while the socket is still opening is delivered once it opens', () async {
    final ch = _Channel();
    final service = SessionSyncService(
      jwt: 'tok',
      deviceIdProvider: () async => 'dev-1',
      channelFactory: (u) => ch,
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    service.transferPlayback('dev-1', deviceName: 'Android TV'); // before connect(): the first play after launch
    service.pushStateUpdate(trackId: 'a', isPlaying: true);
    service.pushStateUpdate(trackId: 'b', isPlaying: true);       // newest wins
    service.sendCommand('pause');                                 // commands are for now, not later
    expect(ch.out.sent, isEmpty);
    await service.connect();
    expect(ch.out.sent.map((m) => m['type']), ['transfer_playback', 'state_update']);
    expect(ch.out.sent[1]['track_id'], 'b');
    service.dispose();
  });

  test('a person-asked claim carries force, an automatic one does not', () async {
    final (service, ch, _) = await _connected();
    service.transferPlayback('dev-1', force: true);
    service.transferPlayback('dev-1');
    expect(ch.out.sent[0]['force'], true);
    expect(ch.out.sent[1].containsKey('force'), isFalse);
    service.dispose();
  });

  test('the device list says who is the host and when each was last heard', () async {
    final (service, ch, _) = await _connected();
    ch.serverSends({
      'type': 'devices',
      'payload': [
        {'id': 'a', 'name': 'Windows PC (LAPTOP)', 'type': 'desktop', 'active': true, 'host': true, 'last_seen_s': 1.2},
        {'id': 'b', 'name': 'OnePlus CPH2581', 'type': 'phone', 'active': false, 'host': false, 'last_seen_s': 41.0},
      ],
    });
    await _pump();
    final d = service.currentDevices;
    expect(d[0].active, isTrue);
    expect(d[1].lastSeenS, 41.0);
    final rows = deviceRows(d, thisId: 'b', thisPlayingHere: false);
    expect(rows[0].caption, 'This device · Tap to play here');
    expect(rows[1].caption, 'Host · playing now');
    expect(CommandResult(ok: false, action: 'transfer', reason: 'claim_cooldown').message, contains('just took over'));
    service.dispose();
  });

  test('the device name is looked up once, when connecting', () async {
    final ch = _Channel();
    final uris = <Uri>[];
    var asked = 0;
    final service = SessionSyncService(
      jwt: 'tok',
      deviceIdProvider: () async => 'dev-1',
      deviceNameProvider: () async {
        asked++;
        return 'Android TV (MiTV-MOOQ1)';
      },
      channelFactory: (u) {
        uris.add(u);
        return ch;
      },
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    await service.connect();
    expect(uris.single.queryParameters['device_name'], 'Android TV (MiTV-MOOQ1)');
    expect(service.deviceName, 'Android TV (MiTV-MOOQ1)');
    expect(asked, 1);
    service.dispose();
  });

  group('switching account on one device', () {
    test('the new account connects with its own token, never the cached one', () async {
      var user = 'vijay';
      final channels = <_Channel>[];
      final uris = <Uri>[];
      final service = SessionSyncService(
        jwtSupplier: ({bool forceRefresh = false}) => 'token-for-$user',
        deviceIdProvider: () async => 'same-device',
        channelFactory: (u) {
          uris.add(u);
          final c = _Channel();
          channels.add(c);
          return c;
        },
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      await service.connect();
      expect(uris.last.queryParameters['token'], 'token-for-vijay');

      user = 'admin'; // signed out of vijay, signed in as admin on the same install
      service.resetAccount();
      await service.connect();
      expect(uris, hasLength(2));
      expect(uris.last.queryParameters['token'], 'token-for-admin');
      expect(uris.last.queryParameters['device_id'], 'same-device'); // the device is the same; the room comes from the login
      service.dispose();
    });

    test('the old socket closing late does not take the new one down', () async {
      final channels = <_Channel>[];
      final service = SessionSyncService(
        jwtSupplier: ({bool forceRefresh = false}) => 'tok',
        deviceIdProvider: () async => 'd',
        channelFactory: (u) {
          final c = _Channel();
          channels.add(c);
          return c;
        },
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      await service.connect();
      service.resetAccount();
      await service.connect();
      expect(service.connection, SyncConnection.online);
      channels.first.serverCloses(); // the first socket's close notice arrives now
      await _pump();
      expect(service.connection, SyncConnection.online);
      expect(service.isConnected, isTrue);
      service.dispose();
    });

    test('devices and state of the old account are gone the moment it is left', () async {
      final ch = _Channel();
      final service = SessionSyncService(
        jwtSupplier: ({bool forceRefresh = false}) => 'tok',
        deviceIdProvider: () async => 'd',
        channelFactory: (u) => ch,
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      await service.connect();
      ch.serverSends({'type': 'devices', 'payload': [{'id': 'a', 'name': 'Vijay laptop', 'type': 'desktop', 'active': true}]});
      ch.serverSends({'type': 'state', 'payload': {'active_device': 'a', 'track_title': 'Secret'}});
      await _pump();
      expect(service.currentDevices, isNotEmpty);
      service.resetAccount();
      expect(service.currentDevices, isEmpty);
      expect(service.currentState.trackTitle, isNull);
      expect(service.currentState.activeDevice, isNull);
      service.dispose();
    });

    test('a connect that was still opening when the account changed is thrown away', () async {
      final slow = Completer<void>();
      final first = _SlowChannel(slow.future);
      var n = 0;
      final service = SessionSyncService(
        jwtSupplier: ({bool forceRefresh = false}) => 'tok',
        deviceIdProvider: () async => 'd',
        channelFactory: (u) => n++ == 0 ? first : _Channel(),
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      final connecting = service.connect();
      await _pump();
      service.resetAccount(); // signed out while the socket was opening
      slow.complete();
      await connecting;
      expect(service.isConnected, isFalse);
      expect(service.connection, SyncConnection.offline);
      service.dispose();
    });
  });

  group('Devices sheet rows', () {
    const phone = SyncDevice(id: 'aaaa1111', name: 'Android phone', type: SyncDeviceType.phone, active: false);
    const phone2 = SyncDevice(id: 'bbbb2222', name: 'Android phone', type: SyncDeviceType.phone, active: true);
    const pc = SyncDevice(id: 'cccc3333', name: 'Windows PC', type: SyncDeviceType.desktop);

    test('this device first, then the one playing, then the rest; clashing names get an id suffix', () {
      final rows = deviceRows([pc, phone2, phone], thisId: 'aaaa1111', thisPlayingHere: false);
      expect([for (final r in rows) r.device.id], ['aaaa1111', 'bbbb2222', 'cccc3333']);
      expect(rows[0].title, 'Android phone · 1111');
      expect(rows[1].title, 'Android phone · 2222');
      expect(rows[2].title, 'Windows PC');
      expect(rows[0].caption, 'This device · Tap to play here');
      expect(rows[1].caption, 'Host · playing now');
      expect(rows[2].caption, 'Tap to move playback here');
    });

    test('glyphs by kind', () {
      expect(syncDeviceGlyph(SyncDeviceType.phone), syncDeviceGlyph(SyncDeviceType.tablet));
      expect(syncDeviceGlyph(SyncDeviceType.desktop), syncDeviceGlyph(SyncDeviceType.tv));
      expect(syncDeviceGlyph(SyncDeviceType.phone) == syncDeviceGlyph(SyncDeviceType.desktop), isFalse);
    });
  });

  group('remotePosition', () {
    final stamp = DateTime.utc(2026, 10, 25, 12);
    PlaybackState state({bool playing = true, int pos = 10000, double dur = 100}) =>
        PlaybackState(isPlaying: playing, positionMs: pos, durationS: dur, updatedAt: stamp);

    test('advances while playing, holds while paused, never passes the end', () {
      expect(remotePosition(state(), stamp.add(const Duration(seconds: 5))), const Duration(seconds: 15));
      expect(remotePosition(state(playing: false), stamp.add(const Duration(seconds: 5))), const Duration(seconds: 10));
      expect(remotePosition(state(pos: 99000), stamp.add(const Duration(seconds: 30))), const Duration(seconds: 100));
      expect(remotePosition(state(), stamp.subtract(const Duration(seconds: 2))), const Duration(seconds: 10));
    });
  });
}
