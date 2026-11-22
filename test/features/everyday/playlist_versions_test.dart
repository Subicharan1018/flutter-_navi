import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/everyday/playlist_versions.dart';
import 'package:navivibe/features/everyday/playlist_versions_providers.dart';
import 'package:navivibe/models/song.dart';

Song s(String id) => Song(id: id, title: 'T$id', artist: 'A$id', album: 'B', coverArt: id, duration: 100, track: 1, year: 2000);
List<Song> l(String csv) => csv.isEmpty ? [] : [for (final i in csv.split(',')) s(i)];
DateTime at(int h) => DateTime(2026, 11, 20, h);
List<String> ids(PlaylistVersion v) => v.ids;

class MemBackend implements PlaylistVersionsBackend {
  String? value;
  @override
  String? read() => value;
  @override
  Future<void> write(String v) async => value = v;
}

void main() {
  group('record', () {
    test('first look is a version; the same songs are not a new one', () {
      var v = PlaylistVersions.record(const [], l('a,b,c'), at(1));
      expect(v, hasLength(1));
      expect(identical(PlaylistVersions.record(v, l('a,b,c'), at(2)), v), isTrue);
    });
    test('a change, or only an order change, makes a version, newest first', () {
      var v = PlaylistVersions.record(const [], l('a,b,c'), at(1));
      v = PlaylistVersions.record(v, l('a,c'), at(2));
      v = PlaylistVersions.record(v, l('c,a'), at(3));
      expect(v.map((x) => x.ids.join()), ['ca', 'ac', 'abc']);
    });
    test('a first look at an empty playlist is not kept, but emptying one is', () {
      expect(PlaylistVersions.record(const [], const [], at(1)), isEmpty);
      var v = PlaylistVersions.record(const [], l('a'), at(1));
      v = PlaylistVersions.record(v, const [], at(2));
      expect(v, hasLength(2));
    });
    test('capped at ${PlaylistVersions.keep}', () {
      var v = <PlaylistVersion>[];
      for (var i = 0; i < 30; i++) {
        v = PlaylistVersions.record(v, l('s$i'), at(0));
      }
      expect(v, hasLength(PlaylistVersions.keep));
      expect(v.first.ids, ['s29']);
    });
    test('a playlist too long to snapshot whole is not snapshotted', () {
      final big = [for (var i = 0; i < PlaylistVersions.maxSongs + 1; i++) s('$i')];
      expect(PlaylistVersions.record(const [], big, at(1)), isEmpty);
    });
  });

  group('diff', () {
    PlaylistVersion v(String csv) => PlaylistVersion(at(1), [for (final x in l(csv)) VSong.of(x)]);
    test('added, removed', () {
      final d = PlaylistVersions.diff(v('a,b,c'), v('a,c,d,e'));
      expect(d.added.map((x) => x.id), ['d', 'e']);
      expect(d.removed.map((x) => x.id), ['b']);
      expect(d.reordered, isFalse);
      expect(d.summary, '+2 −1');
    });
    test('reordered only', () {
      final d = PlaylistVersions.diff(v('a,b,c'), v('c,b,a'));
      expect(d.reordered, isTrue);
      expect(d.summary, 'reordered');
    });
    test('an add does not count as a reorder', () {
      expect(PlaylistVersions.diff(v('a,b'), v('a,x,b')).reordered, isFalse);
    });
    test('identical', () => expect(PlaylistVersions.diff(v('a'), v('a')).isEmpty, isTrue));
  });

  group('recentlyRemoved', () {
    test('finds what was taken out, newest removal first, once each', () {
      var v = PlaylistVersions.record(const [], l('a,b,c,d'), at(1));
      v = PlaylistVersions.record(v, l('a,b,d'), at(2)); // c removed at 2
      v = PlaylistVersions.record(v, l('a'), at(3)); // b, d removed at 3
      final r = PlaylistVersions.recentlyRemoved(v, ['a']);
      expect(r.map((x) => x.song.id).toSet(), {'b', 'd', 'c'});
      expect(r.map((x) => x.song.id).last, 'c');
      expect(r.last.removedAt, at(2));
      expect(r.first.removedAt, at(3));
    });
    test('a song put back is no longer removed', () {
      var v = PlaylistVersions.record(const [], l('a,b'), at(1));
      v = PlaylistVersions.record(v, l('a'), at(2));
      expect(PlaylistVersions.recentlyRemoved(v, ['a', 'b']), isEmpty);
    });
    test('removed by someone else since the last look still shows', () {
      final v = PlaylistVersions.record(const [], l('a,b'), at(1));
      final r = PlaylistVersions.recentlyRemoved(v, ['a']);
      expect(r.single.song.id, 'b');
    });
    test('respects max', () {
      var v = PlaylistVersions.record(const [], l('a,b,c,d,e'), at(1));
      v = PlaylistVersions.record(v, l('a'), at(2));
      expect(PlaylistVersions.recentlyRemoved(v, ['a'], max: 2), hasLength(2));
    });
    test('the title and artist survive for songs that left the library', () {
      var v = PlaylistVersions.record(const [], l('a,b'), at(1));
      v = PlaylistVersions.record(v, l('a'), at(2));
      final r = PlaylistVersions.recentlyRemoved(v, ['a']).single.song;
      expect((r.title, r.artist), ('Tb', 'Ab'));
    });
  });

  test('withAdded appends and skips what is there', () {
    expect(PlaylistVersions.withAdded(['a', 'b'], ['b', 'c', 'c']), ['a', 'b', 'c']);
  });

  test('restoreIds is the version in order', () {
    final v = PlaylistVersions.record(const [], l('c,a,b'), at(1)).single;
    expect(PlaylistVersions.restoreIds(v), ['c', 'a', 'b']);
  });

  group('storage', () {
    test('round trip keeps order, times and titles', () {
      var v = PlaylistVersions.record(const [], l('a,b,c'), at(1));
      v = PlaylistVersions.record(v, l('c,a'), at(2));
      final back = PlaylistVersions.decode(PlaylistVersions.encode({'p1': v, 'p2': v}));
      expect(back.keys, ['p1', 'p2']);
      expect(back['p1']!.map(ids), [['c', 'a'], ['a', 'b', 'c']]);
      expect(back['p1']!.first.at, at(2));
      expect(back['p1']!.last.songs[1].title, 'Tb');
    });
    test('titles are stored once per playlist', () {
      var v = <PlaylistVersion>[];
      for (var i = 0; i < 10; i++) {
        v = PlaylistVersions.record(v, l('a,b,c,d,e,x$i'), at(i));
      }
      final text = PlaylistVersions.encode({'p': v});
      expect('"Ta"'.allMatches(text).length, 1);
    });
    test('junk and one damaged playlist', () {
      expect(PlaylistVersions.decode('nope'), isEmpty);
      expect(PlaylistVersions.decode(null), isEmpty);
      final good = PlaylistVersions.encode({'ok': PlaylistVersions.record(const [], l('a,b'), at(1))});
      final mixed = good.replaceFirst('{', '{"bad":{"d":1},');
      expect(PlaylistVersions.decode(mixed).keys, ['ok']);
    });
  });

  group('notifier', () {
    test('records, persists, ignores repeats, forgets', () {
      final backend = MemBackend();
      ProviderContainer make() => ProviderContainer(overrides: [playlistVersionsBackendProvider.overrideWithValue(backend)]);
      final c = make();
      addTearDown(c.dispose);
      final n = c.read(playlistVersionsProvider.notifier);
      n.record('p', l('a,b'), now: at(1));
      final written = backend.value;
      n.record('p', l('a,b'), now: at(2)); // unchanged: no write, no new version
      expect(backend.value, written);
      n.record('p', l('a'), now: at(3));
      expect(c.read(playlistVersionsProvider)['p'], hasLength(2));
      final c2 = make();
      addTearDown(c2.dispose);
      expect(c2.read(playlistVersionsProvider)['p'], hasLength(2));
      n.forget('p');
      expect(c.read(playlistVersionsProvider), isEmpty);
    });
    test('keeps only the most recently changed playlists', () {
      final backend = MemBackend();
      final c = ProviderContainer(overrides: [playlistVersionsBackendProvider.overrideWithValue(backend)]);
      addTearDown(c.dispose);
      final n = c.read(playlistVersionsProvider.notifier);
      for (var i = 0; i < playlistsWithHistory + 5; i++) {
        n.record('p$i', l('a$i'), now: DateTime(2026, 1, 1).add(Duration(days: i)));
      }
      final m = c.read(playlistVersionsProvider);
      expect(m, hasLength(playlistsWithHistory));
      expect(m.containsKey('p0'), isFalse);
      expect(m.containsKey('p${playlistsWithHistory + 4}'), isTrue);
    });
  });
}
