import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/everyday/song_trim.dart';
import 'package:navivibe/features/everyday/song_trim_providers.dart';

class MemBackend implements SongTrimBackend {
  String? value;
  @override
  String? read() => value;
  @override
  Future<void> write(String v) async => value = v;
}

void main() {
  group('SongTrim.normalized', () {
    test('keeps sensible points', () {
      expect(const SongTrim(startMs: 42000, endMs: 200000).normalized(240000), const SongTrim(startMs: 42000, endMs: 200000));
    });
    test('negatives become none', () => expect(const SongTrim(startMs: -5, endMs: -1).normalized(100000).isNone, isTrue));
    test('an end at the very end is no end', () {
      expect(const SongTrim(endMs: 239500).normalized(240000).hasEnd, isFalse);
    });
    test('an end too close to the start is dropped', () {
      expect(const SongTrim(startMs: 60000, endMs: 62000).normalized(240000), const SongTrim(startMs: 60000));
    });
    test('a start too close to the end of the song is dropped', () {
      expect(const SongTrim(startMs: 238000).normalized(240000).hasStart, isFalse);
    });
    test('unknown duration only fixes order', () {
      expect(const SongTrim(startMs: 10000, endMs: 12000).normalized(0), const SongTrim(startMs: 10000));
      expect(const SongTrim(startMs: 10000, endMs: 90000).normalized(0), const SongTrim(startMs: 10000, endMs: 90000));
    });
  });

  group('SongTrims', () {
    test('set, remove, round trip', () {
      var t = const SongTrims().with_('a', const SongTrim(startMs: 5000)).with_('b', const SongTrim(endMs: 90000));
      expect(t.of('a').startMs, 5000);
      expect(t.of('zzz').isNone, isTrue);
      final back = SongTrims.decode(t.encode());
      expect(back.of('b').endMs, 90000);
      t = t.with_('a', SongTrim.none);
      expect(t.map.containsKey('a'), isFalse);
    });
    test('junk decodes to empty and drops bad rows', () {
      expect(SongTrims.decode('{{{').map, isEmpty);
      expect(SongTrims.decode(null).map, isEmpty);
      expect(SongTrims.decode('{"a":{"s":-4},"b":"x","c":{"e":9000}}').map.keys, ['c']);
    });
  });

  group('TrimGuard', () {
    TrimGuard guard(Map<String, SongTrim> m) => TrimGuard(lookup: (id) => m[id] ?? SongTrim.none);

    test('no trim does nothing', () {
      final g = guard({})..trackChanged('a', 200);
      expect(g.onPosition(0, repeatOne: false), isA<TrimNothing>());
      expect(g.onPosition(150000, repeatOne: false), isA<TrimNothing>());
    });

    test('seeks to the start once, near the beginning', () {
      final g = guard({'a': const SongTrim(startMs: 42000)})..trackChanged('a', 200);
      final first = g.onPosition(300, repeatOne: false);
      expect(first, isA<TrimSeek>().having((s) => s.ms, 'ms', 42000));
      expect(g.onPosition(400, repeatOne: false), isA<TrimNothing>()); // once
    });

    test('a start already passed is left alone, and so is a later scrub back', () {
      final g = guard({'a': const SongTrim(startMs: 42000)})..trackChanged('a', 200);
      expect(g.onPosition(43000, repeatOne: false), isA<TrimNothing>());
      expect(g.onPosition(1000, repeatOne: false), isA<TrimNothing>());
    });

    test('a resume far from the start is not dragged to the start', () {
      final g = guard({'a': const SongTrim(startMs: 42000)})..trackChanged('a', 200);
      expect(g.onPosition(20000, repeatOne: false), isA<TrimNothing>());
    });

    test('advances at the end point, once', () {
      final g = guard({'a': const SongTrim(endMs: 100000)})..trackChanged('a', 200);
      expect(g.onPosition(99000, repeatOne: false), isA<TrimNothing>());
      expect(g.onPosition(100100, repeatOne: false), isA<TrimAdvance>());
      expect(g.onPosition(100300, repeatOne: false), isA<TrimNothing>());
    });

    test('seeking past the end also moves on', () {
      final g = guard({'a': const SongTrim(endMs: 100000)})..trackChanged('a', 200);
      expect(g.onPosition(150000, repeatOne: false), isA<TrimAdvance>());
    });

    test('repeat-one loops back to the start point instead of moving on', () {
      final g = guard({'a': const SongTrim(startMs: 10000, endMs: 100000)})..trackChanged('a', 200);
      expect(g.onPosition(11000, repeatOne: true), isA<TrimNothing>());
      final loop = g.onPosition(100500, repeatOne: true);
      expect(loop, isA<TrimSeek>().having((s) => s.ms, 'ms', 10000));
      expect(g.onPosition(12000, repeatOne: true), isA<TrimNothing>());
      expect(g.onPosition(100100, repeatOne: true), isA<TrimSeek>());
    });

    test('a new song re-arms; the trim is looked up per song', () {
      final g = guard({'a': const SongTrim(endMs: 60000), 'b': const SongTrim(endMs: 70000)})..trackChanged('a', 200);
      expect(g.onPosition(61000, repeatOne: false), isA<TrimAdvance>());
      g.trackChanged('b', 200);
      expect(g.onPosition(61000, repeatOne: false), isA<TrimNothing>());
      expect(g.onPosition(71000, repeatOne: false), isA<TrimAdvance>());
      g.trackChanged(null, 0);
      expect(g.onPosition(71000, repeatOne: false), isA<TrimNothing>());
    });

    test('an invalid trim (end past the song) is ignored for that song', () {
      final g = guard({'a': const SongTrim(endMs: 199800)})..trackChanged('a', 200);
      expect(g.onPosition(199900, repeatOne: false), isA<TrimNothing>());
    });

    test('refresh picks up an edit made while the song plays', () {
      final m = <String, SongTrim>{};
      final g = guard(m)..trackChanged('a', 200);
      expect(g.onPosition(50000, repeatOne: false), isA<TrimNothing>());
      m['a'] = const SongTrim(endMs: 60000);
      g.refresh();
      expect(g.onPosition(61000, repeatOne: false), isA<TrimAdvance>());
    });
  });

  group('notifier', () {
    test('saves normalised, persists, clears', () async {
      final backend = MemBackend();
      final c = ProviderContainer(overrides: [songTrimBackendProvider.overrideWithValue(backend)]);
      addTearDown(c.dispose);
      final n = c.read(songTrimsProvider.notifier);
      await n.set('a', const SongTrim(startMs: 30000, endMs: 31000), durationSec: 200);
      expect(c.read(songTrimsProvider).of('a'), const SongTrim(startMs: 30000)); // end too close, dropped
      final c2 = ProviderContainer(overrides: [songTrimBackendProvider.overrideWithValue(backend)]);
      addTearDown(c2.dispose);
      expect(c2.read(songTrimsProvider).of('a').startMs, 30000);
      await n.clear('a');
      expect(c.read(songTrimsProvider).map, isEmpty);
      expect(backend.value, '{}');
    });
  });
}
