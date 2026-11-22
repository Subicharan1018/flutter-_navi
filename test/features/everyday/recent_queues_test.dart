import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/everyday/recent_queues.dart';
import 'package:navivibe/features/everyday/recent_queues_providers.dart';
import 'package:navivibe/features/everyday/save_as_playlist.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/settings_provider.dart';

Song s(String id) => Song(id: id, title: 'T$id', artist: 'A', album: 'B', coverArt: id, duration: 100, track: 1, year: 2000);
List<Song> ids(String csv) => [for (final i in csv.split(',')) s(i)];
RecentQueue q(String csv, {String account = 'acc', int at = 0, String? source, int index = 0}) =>
    RecentQueue(account: account, savedAt: DateTime.fromMillisecondsSinceEpoch(at), songs: ids(csv), source: source, index: index);

class MemBackend implements RecentQueuesBackend {
  String? value;
  @override
  String? read() => value;
  @override
  Future<void> write(String v) async => value = v;
}

void main() {
  group('RecentQueues.remember', () {
    test('newest first; a single song is not a queue', () {
      var l = RecentQueues.remember(const [], q('a,b', at: 1));
      l = RecentQueues.remember(l, q('c', at: 2));
      l = RecentQueues.remember(l, q('d,e', at: 3));
      expect([for (final x in l) x.songs.first.id], ['d', 'a']);
    });
    test('the same songs replace the old entry and move to the top', () {
      var l = RecentQueues.remember(const [], q('a,b', at: 1));
      l = RecentQueues.remember(l, q('c,d', at: 2));
      l = RecentQueues.remember(l, q('a,b', at: 3, source: 'again'));
      expect(l, hasLength(2));
      expect(l.first.source, 'again');
    });
    test('same songs in another order are a different queue', () {
      var l = RecentQueues.remember(const [], q('a,b'));
      l = RecentQueues.remember(l, q('b,a'));
      expect(l, hasLength(2));
    });
    test('keeps ${RecentQueues.keep} per account, not overall', () {
      var l = <RecentQueue>[];
      for (var i = 0; i < 15; i++) {
        l = RecentQueues.remember(l, q('x$i,y$i', at: i));
      }
      l = RecentQueues.remember(l, q('o1,o2', account: 'other', at: 99));
      expect(RecentQueues.forAccount(l, 'acc'), hasLength(10));
      expect(RecentQueues.forAccount(l, 'acc').first.songs.first.id, 'x14');
      expect(RecentQueues.forAccount(l, 'other'), hasLength(1));
    });
    test('a very long queue is cut around the playing song', () {
      final long = RecentQueue(
        account: 'acc',
        savedAt: DateTime(2026),
        songs: [for (var i = 0; i < 500; i++) s('$i')],
        index: 300,
      );
      final kept = RecentQueues.remember(const [], long).single;
      expect(kept.songs, hasLength(RecentQueues.maxSongs));
      expect(kept.songs[kept.index].id, '300');
    });
  });

  group('serialisation', () {
    test('round trip', () {
      final l = [q('a,b,c', at: 5, source: 'Late night', index: 2)];
      final back = RecentQueues.decode(RecentQueues.encode(l)).single;
      expect(back.source, 'Late night');
      expect(back.index, 2);
      expect([for (final x in back.songs) x.id], ['a', 'b', 'c']);
      expect(back.savedAt, DateTime.fromMillisecondsSinceEpoch(5));
    });
    test('junk reads as empty, one bad entry is skipped', () {
      expect(RecentQueues.decode('not json'), isEmpty);
      expect(RecentQueues.decode(null), isEmpty);
      final good = RecentQueues.encode([q('a,b')]);
      final withBad = good.replaceFirst('[', '[{"x":1},');
      expect(RecentQueues.decode(withBad), hasLength(1));
    });
    test('title falls back to the first song', () {
      expect(RecentQueues.title(q('a,b,c')), 'Ta and 2 more');
      expect(RecentQueues.title(q('a,b', source: 'Mix')), 'Mix');
    });
  });

  group('notifier', () {
    test('remembers for this account, persists, and survives a restart', () {
      final backend = MemBackend();
      ProviderContainer make() => ProviderContainer(overrides: [recentQueuesBackendProvider.overrideWithValue(backend), recentQueuesAccountProvider.overrideWithValue('acc')]);
      final c = make();
      addTearDown(c.dispose);
      c.read(recentQueuesProvider.notifier).remember(ids('a,b'), source: 'One');
      c.read(recentQueuesProvider.notifier).remember(ids('c,d'));
      expect(c.read(recentQueuesProvider).map((x) => x.songs.first.id), ['c', 'a']);
      final c2 = make();
      addTearDown(c2.dispose);
      expect(c2.read(recentQueuesProvider), hasLength(2));
      c2.read(recentQueuesProvider.notifier).forget(c2.read(recentQueuesProvider).first);
      expect(c2.read(recentQueuesProvider), hasLength(1));
    });
    test('another account does not see it', () {
      final backend = MemBackend();
      final c = ProviderContainer(overrides: [recentQueuesBackendProvider.overrideWithValue(backend), recentQueuesAccountProvider.overrideWithValue('acc')]);
      addTearDown(c.dispose);
      c.read(recentQueuesProvider.notifier).remember(ids('a,b'));
      final raw = backend.value!.replaceFirst('"a":"', '"a":"someone-else|');
      backend.value = raw;
      final c2 = ProviderContainer(overrides: [recentQueuesBackendProvider.overrideWithValue(backend), recentQueuesAccountProvider.overrideWithValue('acc')]);
      addTearDown(c2.dispose);
      expect(c2.read(recentQueuesProvider), isEmpty);
    });
  });

  group('save as playlist helpers', () {
    test('distinctSongs keeps first occurrence', () {
      expect([for (final x in distinctSongs(ids('a,b,a,c,b'))) x.id], ['a', 'b', 'c']);
    });
    test('uniquePlaylistName', () {
      expect(uniquePlaylistName('Queue', ['Other']), 'Queue');
      expect(uniquePlaylistName(' queue ', ['Queue']), 'queue 2');
      expect(uniquePlaylistName('Queue', ['Queue', 'queue 2']), 'Queue 3');
      expect(uniquePlaylistName('  ', const []), 'New playlist');
    });
  });
}
