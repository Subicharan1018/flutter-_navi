import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/peak_moments/data/peak_mark.dart';
import 'package:navivibe/features/peak_moments/data/peak_store.dart';
import 'package:navivibe/features/peak_moments/data/seek_log.dart';

class MemBackend implements PeakBackend {
  final values = <String, String>{};
  @override
  String? read(String key) => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

PeakMark m(String id, int start, {int len = 20000, int at = 1000, int? deleted}) =>
    PeakMark(id: id, startMs: start, lengthMs: len, createdAt: at, updatedAt: at, deletedAt: deleted);

void main() {
  group('PeakMark.fitted', () {
    test('keeps a mark that fits', () => expect(m('a', 30000).fitted(200000), m('a', 30000)));
    test('shortens a mark past the end of the song', () {
      expect(m('a', 190000).fitted(200000)!.lengthMs, 10000);
    });
    test('moves a start too close to the end back so 5 s fit', () {
      final f = m('a', 198000).fitted(200000)!;
      expect(f.startMs, 195000);
      expect(f.endMs, 200000);
    });
    test('a song shorter than 5 s has no room', () => expect(m('a', 0).fitted(4000), isNull));
    test('clamps length to 5..90 s', () {
      expect(m('a', 0, len: 1000).fitted(300000)!.lengthMs, PeakMark.minLengthMs);
      expect(m('a', 0, len: 500000).fitted(600000)!.lengthMs, PeakMark.maxLengthMs);
    });
  });

  group('placeMark', () {
    PeakMark? place(int pos, {List<PeakMark> existing = const [], int dur = 200000}) =>
        placeMark(id: 'n', positionMs: pos, durationMs: dur, existing: existing, nowMs: 5);

    test('default 20 s from the playhead', () {
      final p = place(42000)!;
      expect([p.startMs, p.lengthMs], [42000, 20000]);
    });
    test('ends where the next mark starts', () {
      final p = place(10000, existing: [m('a', 25000)])!;
      expect(p.endMs, 25000);
    });
    test('starts where the previous mark ends when the playhead is inside it', () {
      final p = place(30000, existing: [m('a', 20000)])!; // a = 20..40 s
      expect(p.startMs, 40000);
    });
    test('no room (gap under 5 s) is null', () {
      expect(place(10000, existing: [m('a', 12000)]), isNull);
    });
    test('near the end of the song it slides back to fit 5 s', () {
      final p = place(198000)!;
      expect([p.startMs, p.endMs], [195000, 200000]);
    });
    test('never overlaps an existing mark', () {
      final existing = [m('a', 10000), m('b', 60000)];
      for (final pos in [0, 9000, 15000, 29000, 35000, 55000, 70000, 150000, 199000]) {
        final p = place(pos, existing: existing);
        if (p == null) continue;
        for (final e in existing) {
          expect(p.startMs < e.endMs && e.startMs < p.endMs, isFalse, reason: 'pos $pos overlaps ${e.id}');
        }
      }
    });
  });

  group('encoding', () {
    test('round trip keeps marks sorted by start, with ids', () {
      final marks = const PeakMarks().withSong('s', [m('b', 50000), m('a', 10000)]);
      final back = PeakMarks.decode(marks.encode());
      expect([for (final x in back.of('s')) x.id], ['a', 'b']);
    });
    test('junk decodes to empty and bad rows are dropped', () {
      expect(PeakMarks.decode('{{{').map, isEmpty);
      expect(PeakMarks.decode(null).map, isEmpty);
      final back = PeakMarks.decode('{"s":[{"i":"a","s":1000,"l":20000,"c":1},{"i":"","s":1},"x",{"i":"c","s":-4,"l":9}]}');
      expect(back.of('s').map((x) => x.id), ['a']);
    });
    test('a tombstone is hidden from reads but kept; old ones are pruned on load', () {
      const day = 86400000;
      final now = 200 * day;
      final marks = const PeakMarks().withSong('s', [m('live', 0), m('new', 30000, deleted: now - day), m('old', 60000, deleted: now - 100 * day)]);
      expect(marks.of('s').map((x) => x.id), ['live']);
      final back = PeakMarks.decode(marks.encode(), nowMs: now);
      expect(back.map['s']!.map((x) => x.id), ['live', 'new']);
      expect(back.liveCount, 1);
    });
  });

  group('PeakMarksNotifier', () {
    late MemBackend backend;
    late ProviderContainer c;
    setUp(() {
      backend = MemBackend();
      c = ProviderContainer(overrides: [peakBackendProvider.overrideWithValue(backend)]);
      addTearDown(c.dispose);
    });
    PeakMarksNotifier n() => c.read(peakMarksProvider.notifier);

    test('tap marks, a second tap inside the mark unmarks it', () async {
      expect(await n().toggleAt('s', 42000, durationMs: 200000), MarkOutcome.added);
      expect(c.read(songMarksProvider('s')), hasLength(1));
      expect(await n().toggleAt('s', 50000, durationMs: 200000), MarkOutcome.removed);
      expect(c.read(songMarksProvider('s')), isEmpty);
    });
    test('a song can hold several marks', () async {
      await n().toggleAt('s', 10000, durationMs: 200000);
      await n().toggleAt('s', 100000, durationMs: 200000);
      expect(c.read(songMarksProvider('s')).map((x) => x.startMs), [10000, 100000]);
    });
    test('long-press removes the mark under or nearest the playhead', () async {
      await n().toggleAt('s', 10000, durationMs: 200000);
      await n().toggleAt('s', 100000, durationMs: 200000);
      expect(await n().removeNear('s', 95000), isTrue);
      expect(c.read(songMarksProvider('s')).map((x) => x.startMs), [10000]);
      expect(await n().removeNear('other', 0), isFalse);
    });
    test('resize clamps to 5..90 s, the next mark and the song end', () async {
      await n().toggleAt('s', 10000, durationMs: 200000);
      await n().toggleAt('s', 50000, durationMs: 200000);
      final first = c.read(songMarksProvider('s')).first;
      await n().resize('s', first.id, 1000, durationMs: 200000);
      expect(c.read(songMarksProvider('s')).first.lengthMs, PeakMark.minLengthMs);
      await n().resize('s', first.id, 80000, durationMs: 200000);
      expect(c.read(songMarksProvider('s')).first.endMs, 50000); // stops at the next mark
    });
    test('saves to the backend and a new container reads it back', () async {
      await n().toggleAt('s', 10000, durationMs: 200000);
      final c2 = ProviderContainer(overrides: [peakBackendProvider.overrideWithValue(backend)]);
      addTearDown(c2.dispose);
      expect(c2.read(songMarksProvider('s')), hasLength(1));
    });
    test('a failing write does not fail the tap', () async {
      final bad = ProviderContainer(overrides: [peakBackendProvider.overrideWithValue(_Failing())]);
      addTearDown(bad.dispose);
      expect(await bad.read(peakMarksProvider.notifier).toggleAt('s', 1000, durationMs: 100000), MarkOutcome.added);
    });
  });

  group('seek log', () {
    test('only jumps back by 3 s or more count', () {
      expect(isReplaySeek(60000, 30000), isTrue);
      expect(isReplaySeek(60000, 58000), isFalse);
      expect(isReplaySeek(30000, 60000), isFalse); // forward
    });
    test('round trip, junk and the cap', () {
      final log = [for (var i = 0; i < SeekEntry.cap + 5; i++) SeekEntry(songId: 's$i', fromMs: 9000, toMs: 1000, atMs: i)];
      final back = decodeSeekLog(encodeSeekLog(log));
      expect(back.length, SeekEntry.cap);
      expect(back.last.songId, 's${SeekEntry.cap + 4}');
      expect(decodeSeekLog('nope'), isEmpty);
      expect(decodeSeekLog('[["a",1,2],["b",9000,1000,5]]').map((e) => e.songId), ['b']);
    });
    test('the notifier records replays and ignores nudges', () async {
      final c = ProviderContainer(overrides: [peakBackendProvider.overrideWithValue(MemBackend())]);
      addTearDown(c.dispose);
      final n = c.read(seekLogProvider.notifier);
      await n.recordSeek('s', fromMs: 60000, toMs: 30000);
      await n.recordSeek('s', fromMs: 60000, toMs: 59000);
      expect(c.read(seekLogProvider), hasLength(1));
    });
  });
}

class _Failing implements PeakBackend {
  @override
  String? read(String key) => throw StateError('no storage');
  @override
  Future<void> write(String key, String value) => throw StateError('disk full');
}
