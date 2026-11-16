import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/remote_queue_provider.dart';
import 'package:navivibe/providers/session_sync_provider.dart';
import 'package:navivibe/services/session_sync_service.dart';

import '../helpers/fake_queue_sync.dart';

Song _s(String id) => Song(id: id, title: 'Title $id', artist: 'A', album: 'B', coverArt: '', duration: 200, track: 1, year: 2024);

void main() {
  group('queue edit math (mirrors the server)', () {
    const q = (ids: ['a', 'b', 'c', 'd'], index: 1);
    // Records compare their lists by identity: compare the contents.
    List<Object> v(IdQueue r) => [r.ids, r.index];

    test('insert next / end / at, the playing index follows', () {
      expect(v(applyQueueInsert(q, ['x'], QueueSpot.next)), [['a', 'b', 'x', 'c', 'd'], 1]);
      expect(v(applyQueueInsert(q, ['x'], QueueSpot.end)), [['a', 'b', 'c', 'd', 'x'], 1]);
      expect(v(applyQueueInsert(q, ['x', 'y'], const QueueSpot.at(0))), [['x', 'y', 'a', 'b', 'c', 'd'], 3]);
      expect(v(applyQueueInsert((ids: const <String>[], index: 0), ['x'], QueueSpot.next)), [['x'], 0]);
    });

    test('insert at an index follows the song above it when the queue moved', () {
      const moved = (ids: ['n', 'a', 'b', 'c', 'd'], index: 2);
      expect(applyQueueInsert(moved, ['x'], const QueueSpot.at(2), afterId: 'b').ids, ['n', 'a', 'b', 'x', 'c', 'd']);
    });

    test('remove by id; the playing song and gone songs are left alone', () {
      expect(v(applyQueueRemove(q, 3, 'd')), [['a', 'b', 'c'], 1]);
      expect(v(applyQueueRemove(q, 0, 'd')), [['a', 'b', 'c'], 1]); // index stale, id finds it
      expect(v(applyQueueRemove(q, 0, 'a')), [['b', 'c', 'd'], 0]);
      expect(v(applyQueueRemove(q, 1, 'b')), v(q));
      expect(v(applyQueueRemove(q, 2, 'zz')), v(q));
      expect(v(applyQueueRemove((ids: ['a', 'c', 'c'], index: 0), 0, 'c')), [['a', 'c', 'c'], 0]); // twice: unclear
    });

    test('move keeps the playing song playing', () {
      expect(v(applyQueueMove(q, 3, 0, 'd')), [['d', 'a', 'b', 'c'], 2]);
      expect(v(applyQueueMove(q, 0, 3, 'a')), [['b', 'c', 'd', 'a'], 0]);
      expect(v(applyQueueMove(q, 1, 3, 'b')), [['a', 'c', 'd', 'b'], 3]);
      expect(v(applyQueueMove(q, 2, 9, 'c')), [['a', 'b', 'd', 'c'], 1]); // clamped to the end
    });

    test('clear upcoming', () {
      expect(v(applyQueueClearUpcoming(q)), [['a', 'b'], 1]);
      expect(v(applyQueueClearUpcoming((ids: ['a'], index: 0))), [['a'], 0]);
    });
  });

  group('RemoteQueueNotifier', () {
    late FakeQueueSync sync;
    late ProviderContainer c;
    final resolved = <List<String>>[];

    setUp(() {
      resolved.clear();
      sync = FakeQueueSync(const PlaybackState(
        activeDevice: 'host',
        queue: ['a', 'b', 'c', 'd'],
        queueIndex: 1,
        epoch: 1,
        version: 1,
      ));
      c = ProviderContainer(overrides: [
        sessionSyncServiceProvider.overrideWithValue(sync),
        remoteSongResolverProvider.overrideWithValue((ids) async {
          resolved.add(ids);
          return [for (final id in ids) _s(id)];
        }),
      ]);
      addTearDown(() {
        c.dispose();
        sync.close();
      });
    });

    List<String> shown() => [for (final s in c.read(remoteQueueProvider).songs) s.id];

    test("shows the host's queue as songs, looked up once", () async {
      c.read(remoteQueueProvider);
      await Future<void>.delayed(Duration.zero);
      expect(shown(), ['a', 'b', 'c', 'd']);
      expect(c.read(remoteQueueProvider).songs.first.title, 'Title a');
      expect(c.read(remoteQueueProvider).index, 1);
      sync.hostState(['a', 'b', 'c', 'd'], 2, version: 2);
      await Future<void>.delayed(Duration.zero);
      expect(resolved.length, 1);
      expect(c.read(remoteQueueProvider).index, 2);
    });

    test('an edit shows at once, and the confirming state takes over', () async {
      final n = c.read(remoteQueueProvider.notifier);
      expect(n.remove(3), isTrue);
      expect(shown(), ['a', 'b', 'c']);                                    // optimistic
      expect(sync.sent.single.$1, QueueEditType.remove);
      expect(sync.sent.single.$2, {'index': 3, 'track_id': 'd'});
      sync.hostState(['a', 'b', 'c'], 1, causedBy: 'cmd-1', version: 2);  // the server applied it
      expect(shown(), ['a', 'b', 'c']);                                    // not removed twice
      sync.answer('cmd-1', ok: true);
      expect(shown(), ['a', 'b', 'c']);
      expect(c.read(remoteQueueProvider).notice, isNull);
    });

    test('a refused edit is undone, with a short reason', () {
      final n = c.read(remoteQueueProvider.notifier);
      n.move(3, 2);
      expect(shown(), ['a', 'b', 'd', 'c']);
      sync.answer('cmd-1', ok: false, reason: 'queue_changed', action: 'queue_move');
      expect(shown(), ['a', 'b', 'c', 'd']);                               // rolled back
      final s = c.read(remoteQueueProvider);
      expect(s.notice, contains('queue changed'));
      expect(s.noticeSeq, 1);
    });

    test('an edit stays on top of states that do not confirm it yet', () {
      final n = c.read(remoteQueueProvider.notifier);
      n.insert([_s('x')], QueueSpot.next);
      expect(shown(), ['a', 'b', 'x', 'c', 'd']);
      expect(sync.sent.single.$2, {'track_ids': ['x'], 'position': 'next'});
      sync.hostState(['a', 'b', 'c', 'd'], 2, version: 2);                // the host moved on meanwhile
      expect(shown(), ['a', 'b', 'c', 'x', 'd']);                          // still shown, after the new current song
      sync.hostState(['a', 'b', 'c', 'x', 'd'], 2, causedBy: 'cmd-1', version: 3);
      expect(shown(), ['a', 'b', 'c', 'x', 'd']);
    });

    test('a drop names the song above it so the server can place it', () {
      c.read(remoteQueueProvider.notifier).insert([_s('x')], const QueueSpot.at(3));
      expect(sync.sent.single.$2, {'track_ids': ['x'], 'position': 3, 'after_id': 'c'});
      expect(shown(), ['a', 'b', 'c', 'x', 'd']);
    });

    test('clear upcoming is sent once, and only when there is something to clear', () {
      final n = c.read(remoteQueueProvider.notifier);
      expect(n.clearUpcoming(), isTrue);
      expect(shown(), ['a', 'b']);
      expect(n.clearUpcoming(), isFalse);                                  // nothing left to clear
      expect(sync.sent.length, 1);
    });

    test('offline: nothing changes on screen and the person is told', () {
      sync.online = false;
      expect(c.read(remoteQueueProvider.notifier).remove(2), isFalse);
      expect(shown(), ['a', 'b', 'c', 'd']);
      expect(c.read(remoteQueueProvider).notice, contains('Can’t reach'));
    });

    test('a queue that follows a Jam is view-only here', () {
      sync.hostState(['a', 'b', 'c', 'd'], 1, locked: 'jam', version: 2);
      final n = c.read(remoteQueueProvider.notifier);
      expect(c.read(remoteQueueProvider).editable, isFalse);
      expect(n.remove(3), isFalse);
      expect(sync.sent, isEmpty);
      expect(c.read(remoteQueueProvider).notice, contains('Jam'));
    });

    test('the playing song cannot be removed from here', () {
      expect(c.read(remoteQueueProvider.notifier).remove(1), isFalse);
      expect(sync.sent, isEmpty);
    });
  });
}
