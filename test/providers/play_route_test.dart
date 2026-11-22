// Where a tap on a song or "Play" starts music: the routing rule, and what the
// remote queue shows while the other device is still loading the new queue.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/play_route.dart';
import 'package:navivibe/providers/remote_queue_provider.dart';
import 'package:navivibe/providers/session_sync_provider.dart';
import 'package:navivibe/services/session_sync_service.dart';

import '../helpers/fake_queue_sync.dart';

Song _s(String id) => Song(id: id, title: 'Title $id', artist: 'A', album: 'B', coverArt: '', duration: 200, track: 1, year: 2024);

void main() {
  group('resolvePlayRoute', () {
    PlayRoute route({String? myId = 'me', String? activeId, String? chosenId, bool person = true, bool here = false}) =>
        resolvePlayRoute(myId: myId, activeId: activeId, chosenId: chosenId, person: person, here: here);

    test('alone, or when this device plays, a play is here', () {
      expect(route(), isA<PlayHere>());
      expect(route(activeId: 'me'), isA<PlayHere>());
    });

    test('another device plays: the play goes to it by default', () {
      final r = route(activeId: 'pc');
      expect(r, isA<PlayOnHost>());
      expect((r as PlayOnHost).deviceId, 'pc');
    });

    test('"Play here", a Jam, and plays with no touch behind them stay here', () {
      expect(route(activeId: 'pc', here: true), isA<PlayHere>());
      expect(route(activeId: 'pc', person: false), isA<PlayHere>());
      expect(route(myId: null, activeId: 'pc'), isA<PlayHere>());
    });

    test('a device picked in the sheet wins: the one playing, another one, or this one', () {
      expect(route(activeId: 'pc', chosenId: 'pc'), isA<PlayOnHost>());
      final other = route(activeId: 'pc', chosenId: 'tv');
      expect(other, isA<PlayOnOther>());
      expect((other as PlayOnOther).deviceId, 'tv');
      expect(route(activeId: 'pc', chosenId: 'me'), isA<PlayHere>());
      expect(route(chosenId: 'tv'), isA<PlayOnOther>()); // nobody plays, one picked
      expect(route(activeId: 'me', chosenId: 'pc'), isA<PlayOnOther>()); // this device plays, another one picked
    });
  });

  group('a queue sent to the playing device', () {
    late FakeQueueSync sync;
    late ProviderContainer c;

    setUp(() {
      sync = FakeQueueSync(const PlaybackState(activeDevice: 'host', queue: ['a', 'b', 'c'], queueIndex: 0, epoch: 1, version: 1));
      c = ProviderContainer(overrides: [
        sessionSyncServiceProvider.overrideWithValue(sync),
        remoteSongResolverProvider.overrideWithValue((ids) async => [for (final id in ids) _s(id)]),
      ]);
      addTearDown(() {
        c.dispose();
        sync.close();
      });
    });

    List<String> shown() => [for (final s in c.read(remoteQueueProvider).songs) s.id];
    final songs = [_s('x'), _s('y'), _s('z')];

    test('sendPlay to the host sends set_queue and shows the new queue at once', () {
      c.read(remoteQueueProvider);
      final ok = sendPlay(c.read(Provider((r) => r)), sync, const PlayOnHost('host'), songs, 1);
      expect(ok, isTrue);
      expect(sync.queuesSent.single.$1, ['x', 'y', 'z']);
      expect(sync.queuesSent.single.$2, 1);
      expect(shown(), ['x', 'y', 'z']);
      expect(c.read(remoteQueueProvider).index, 1);
    });

    test('it stays through "sent", and settles when the host reports the new queue', () {
      c.read(remoteQueueProvider);
      sendPlay(c.read(Provider((r) => r)), sync, const PlayOnHost('host'), songs, 0);
      final id = sync.queuesSent.single.$3;
      sync.answer(id, ok: true, action: 'set_queue'); // the server only forwarded it
      expect(shown(), ['x', 'y', 'z']);
      sync.hostState(['a', 'b', 'c'], 0, version: 2); // the host has not applied it yet
      expect(shown(), ['x', 'y', 'z']);
      sync.hostState(['x', 'y', 'z'], 0, version: 3); // now it has
      expect(shown(), ['x', 'y', 'z']);
      // Settled: a later queue from the host is shown as it is (no stale overlay).
      sync.hostState(['x', 'y', 'z', 'w'], 0, version: 4);
      expect(shown(), ['x', 'y', 'z', 'w']);
    });

    test('a refusal puts the old queue back without a second message (the play notice speaks)', () {
      c.read(remoteQueueProvider);
      sendPlay(c.read(Provider((r) => r)), sync, const PlayOnHost('host'), songs, 0);
      sync.answer(sync.queuesSent.single.$3, ok: false, reason: 'device_offline', action: 'set_queue');
      expect(shown(), ['a', 'b', 'c']);
      expect(c.read(remoteQueueProvider).notice, isNull);
    });

    test('sendPlay to a device that is not playing uses playOn; with no link it says so', () {
      expect(sendPlay(c.read(Provider((r) => r)), sync, const PlayOnOther('tv'), songs, 2), isTrue);
      expect(sync.playOns.single.$1, 'tv');
      expect(sync.playOns.single.$2, ['x', 'y', 'z']);
      expect(sync.playOns.single.$3, 2);
      sync.online = false;
      expect(sendPlay(c.read(Provider((r) => r)), sync, const PlayOnOther('tv'), songs, 0), isFalse);
      expect(sendPlay(c.read(Provider((r) => r)), sync, const PlayOnHost('host'), songs, 0), isFalse);
      expect(sendPlay(c.read(Provider((r) => r)), sync, const PlayHere(), songs, 0), isFalse);
    });

    test('device names for the toast come from the device list', () {
      sync.currentDevices = const [SyncDevice(id: 'pc', name: 'Windows PC')];
      expect(deviceNameFor(sync, 'pc'), 'Windows PC');
      expect(deviceNameFor(sync, 'zz', fallback: 'Somewhere'), 'Somewhere');
      expect(deviceNameFor(sync, 'zz'), 'your other device');
    });
  });
}
