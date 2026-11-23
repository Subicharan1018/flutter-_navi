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

    test('starts 3 s before the tap and keeps 20 s from there', () {
      final p = place(42000)!;
      expect([p.startMs, p.lengthMs], [39000, 20000]);
      expect(p.contains(42000), isTrue);
    });
    test('at the start of the song the lead-in is clamped to 0', () {
      expect(place(1500)!.startMs, 0);
      expect(place(0)!.startMs, 0);
      expect(place(3000)!.startMs, 0);
      expect(place(3001)!.startMs, 1);
    });
    test('the lead-in stops at the previous mark end', () {
      final p = place(41000, existing: [m('a', 20000)])!; // a = 20..40 s; 38 s would overlap it
      expect(p.startMs, 40000);
      expect(p.contains(41000), isTrue);
    });
    test('a short song: lead-in and length fit inside it', () {
      final p = place(8000, dur: 12000)!;
      expect([p.startMs, p.endMs], [5000, 12000]);
      expect(place(1000, dur: 4000), isNull); // under 5 s: no moment
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
      expect(place(10000, existing: [m('a', 10000)]), isNull); // 7..10 s is only 3 s
      expect(place(10000, existing: [m('a', 12000)]), isNotNull); // 7..12 s is exactly 5 s
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

  group('PeakMark.adjusted (start and end limits)', () {
    final a = m('a', 60000); // 60..80 s
    PeakMark? adj({int? s, int? e, List<PeakMark> others = const [], int dur = 200000}) =>
        a.adjusted(others, startMs: s, endMs: e, durationMs: dur);

    test('moving the start keeps the end', () {
      final r = adj(s: 55000)!;
      expect([r.startMs, r.endMs], [55000, 80000]);
    });
    test('the start never goes below 0', () => expect(m('b', 2000).adjusted(const [], startMs: -9000, durationMs: 200000)!.startMs, 0));
    test('the start cannot get closer than 5 s to the end', () {
      expect(adj(s: 79000)!.startMs, 75000);
    });
    test('the length never exceeds 90 s: dragging the start left stops there', () {
      final r = adj(s: 0)!;
      expect([r.startMs, r.endMs], [0, 80000]); // 80 s is fine
      final long = m('c', 100000, len: 80000).adjusted(const [], startMs: 0, durationMs: 300000)!;
      expect(long.lengthMs, PeakMark.maxLengthMs);
      expect(long.endMs, 180000);
    });
    test('the start stops at the previous mark end', () {
      final r = adj(s: 10000, others: [m('p', 20000)])!; // p = 20..40 s
      expect(r.startMs, 40000);
    });
    test('a mark after this one does not limit the start', () {
      expect(adj(s: 10000, others: [m('n', 100000)])!.startMs, 10000);
    });
    test('the end stops at the next mark and at the song end', () {
      expect(adj(e: 150000, others: [m('n', 100000)])!.endMs, 100000);
      expect(adj(e: 150000, dur: 120000)!.endMs, 120000);
    });
    test('hemmed in by neighbours: it cannot leave the gap', () {
      final others = [m('p', 40000), m('n', 80000)]; // the gap is exactly 60..80 s
      expect(adj(s: 30000, others: others), isNull);
      expect(adj(e: 95000, others: others), isNull);
      expect(adj(s: 63000, others: others)!.startMs, 63000);
    });
    test('a gap under 5 s leaves the mark unchanged', () {
      expect(m('t', 50000, len: 5000).adjusted([m('p', 30000), m('n', 56000)], startMs: 45000, durationMs: 200000), isNull);
    });
    test('an unchanged result is null', () => expect(adj(s: 60000), isNull));
    test('itself in others is ignored', () => expect(adj(s: 50000, others: [a])!.startMs, 50000));
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
      expect(c.read(songMarksProvider('s')).map((x) => x.startMs), [7000, 97000]);
    });
    test('long-press removes the mark under or nearest the playhead', () async {
      await n().toggleAt('s', 10000, durationMs: 200000);
      await n().toggleAt('s', 100000, durationMs: 200000);
      expect(await n().removeNear('s', 95000), isTrue);
      expect(c.read(songMarksProvider('s')).map((x) => x.startMs), [7000]);
      expect(await n().removeNear('other', 0), isFalse);
    });
    test('resize clamps to 5..90 s, the next mark and the song end', () async {
      await n().toggleAt('s', 10000, durationMs: 200000);
      await n().toggleAt('s', 50000, durationMs: 200000);
      final first = c.read(songMarksProvider('s')).first;
      await n().resize('s', first.id, 1000, durationMs: 200000);
      expect(c.read(songMarksProvider('s')).first.lengthMs, PeakMark.minLengthMs);
      await n().resize('s', first.id, 80000, durationMs: 200000);
      expect(c.read(songMarksProvider('s')).first.endMs, 47000); // stops at the next mark (47 s)
    });
    test('moveStart keeps the end, stays clear of the previous mark and of 0', () async {
      await n().toggleAt('s', 10000, durationMs: 200000); // 7..27 s
      await n().toggleAt('s', 50000, durationMs: 200000); // 47..67 s
      final second = c.read(songMarksProvider('s')).last;
      await n().moveStart('s', second.id, 40000, durationMs: 200000);
      var s2 = c.read(songMarksProvider('s')).last;
      expect([s2.startMs, s2.endMs], [40000, 67000]);
      await n().moveStart('s', second.id, 20000, durationMs: 200000); // into the first mark
      s2 = c.read(songMarksProvider('s')).last;
      expect(s2.startMs, 27000);
      final first = c.read(songMarksProvider('s')).first;
      await n().moveStart('s', first.id, -5000, durationMs: 200000);
      expect(c.read(songMarksProvider('s')).first.startMs, 0);
    });
    test('an edit bumps updatedAt so a sync takes the newest version', () async {
      await n().toggleAt('s', 50000, durationMs: 200000);
      final before = c.read(songMarksProvider('s')).single;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await n().moveStart('s', before.id, before.startMs + 2000, durationMs: 200000);
      final after = c.read(songMarksProvider('s')).single;
      expect(after.id, before.id);
      expect(after.updatedAt, greaterThan(before.updatedAt));
      expect(after.createdAt, before.createdAt);
      // and it is what is stored
      final stored = PeakMarks.decode(backend.values[HivePeakBackend.marksKey]).of('s').single;
      expect(stored.startMs, before.startMs + 2000);
    });
    test('nudge moves start or end by a second, within the limits', () async {
      await n().toggleAt('s', 50000, durationMs: 200000); // 47..67 s
      final id = c.read(songMarksProvider('s')).single.id;
      await n().nudge('s', id, startDeltaMs: -1000, durationMs: 200000);
      await n().nudge('s', id, endDeltaMs: 1000, durationMs: 200000);
      var x = c.read(songMarksProvider('s')).single;
      expect([x.startMs, x.endMs], [46000, 68000]);
      await n().nudge('s', id, startDeltaMs: 1000, durationMs: 200000);
      x = c.read(songMarksProvider('s')).single;
      expect(x.startMs, 47000);
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
