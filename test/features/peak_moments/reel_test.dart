import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/peak_moments/data/peak_mark.dart';
import 'package:navivibe/features/peak_moments/data/seek_log.dart';
import 'package:navivibe/features/peak_moments/logic/hotspots.dart';
import 'package:navivibe/features/peak_moments/logic/reel.dart';
import 'package:navivibe/models/song.dart';

Song song(String id, {int dur = 200}) =>
    Song(id: id, title: 'T$id', artist: 'A', album: 'B', coverArt: '', duration: dur, track: 1, year: 2020);

PeakMark mark(String id, int start, {int len = 20000, int at = 1}) =>
    PeakMark(id: id, startMs: start, lengthMs: len, createdAt: at, updatedAt: at);

SeekEntry seek(String id, int to, {int at = 1}) => SeekEntry(songId: id, fromMs: to + 30000, toMs: to, atMs: at);

void main() {
  group('buildReel', () {
    test('one entry per mark, in the order of the songs then start', () {
      final marks = const PeakMarks().withSong('a', [mark('a2', 90000), mark('a1', 10000)]).withSong('b', [mark('b1', 5000)]);
      final plan = buildReel([song('b'), song('a'), song('c')], marks);
      expect([for (final s in plan.songs) s.id], ['b', 'a', 'a']);
      expect([for (final s in plan.segments) s.startMs], [5000, 10000, 90000]);
      expect(plan.totalMs, 60000);
    });
    test('songs without marks are left out; an empty library gives an empty reel', () {
      expect(buildReel([song('x')], const PeakMarks()).isEmpty, isTrue);
      expect(buildReel(const [], const PeakMarks()).isEmpty, isTrue);
    });
    test('segments are fitted to the song, deleted marks ignored', () {
      final marks = const PeakMarks().withSong('a', [
        mark('late', 195000),
        PeakMark(id: 'gone', startMs: 0, createdAt: 1, updatedAt: 2, deletedAt: 2),
      ]);
      final plan = buildReel([song('a', dur: 200)], marks);
      expect(plan.segments.single.startMs, 195000);
      expect(plan.segments.single.endMs, 200000);
    });
    test('suggested peaks are opt-in and only for songs without marks', () {
      final marks = const PeakMarks().withSong('a', [mark('a1', 10000)]);
      final log = [seek('a', 60000), seek('a', 61000), seek('b', 80000), seek('b', 85000), seek('c', 5000)];
      final off = buildReel([song('a'), song('b'), song('c')], marks, seekLog: log);
      expect(off.songs.map((s) => s.id), ['a']);
      final on = buildReel([song('a'), song('b'), song('c')], marks, seekLog: log, includeSuggested: true);
      expect(on.songs.map((s) => s.id), ['a', 'b']); // a keeps its mark only; c has one scrub
      expect(on.segments.last.suggested, isTrue);
      expect(on.segments.last.startMs, 80000);
    });
    test('segmentAt rejects an entry whose song moved', () {
      final plan = buildReel([song('a')], const PeakMarks().withSong('a', [mark('a1', 0)]));
      expect(plan.segmentAt(0, 'a'), isNotNull);
      expect(plan.segmentAt(0, 'zzz'), isNull);
      expect(plan.segmentAt(3, 'a'), isNull);
    });
  });

  group('songsWithMarks', () {
    test('most recently marked first', () {
      final marks = const PeakMarks().withSong('a', [mark('a1', 0, at: 10)]).withSong('b', [mark('b1', 0, at: 20)]);
      expect(songsWithMarks([song('a'), song('b'), song('c')], marks).map((s) => s.id), ['b', 'a']);
    });
  });

  group('findHotspots', () {
    test('needs two landings in one 20 s window', () {
      expect(findHotspots([seek('a', 10000), seek('a', 90000)]), isEmpty);
      final h = findHotspots([seek('a', 10000), seek('a', 25000), seek('a', 90000)]);
      expect(h.single.count, 2);
      expect(h.single.startMs, 10000);
    });
    test('ranks by count then recency', () {
      final h = findHotspots([
        seek('a', 1000, at: 1), seek('a', 2000, at: 2),
        seek('b', 1000, at: 5), seek('b', 2000, at: 6), seek('b', 3000, at: 7),
        seek('c', 1000, at: 9), seek('c', 2000, at: 9),
      ]);
      expect(h.map((x) => x.songId), ['b', 'c', 'a']);
    });
  });

  group('SegmentGuard', () {
    final seg = const ReelSegment(songId: 'a', startMs: 60000, endMs: 80000);

    SegmentGuard guard({bool last = false, ReelSegment? s}) => SegmentGuard()..trackChanged(0, s ?? seg, isLast: last);

    test('seeks to the start once, from the beginning of the song', () {
      final g = guard();
      expect(g.onPosition(0, repeatOne: false), isA<SegmentSeek>().having((a) => a.ms, 'ms', 60000));
      expect(g.onPosition(100, repeatOne: false), isA<SegmentNothing>()); // not again
    });
    test('a segment starting at 0 needs no seek', () {
      final g = guard(s: const ReelSegment(songId: 'a', startMs: 0, endMs: 20000));
      expect(g.onPosition(0, repeatOne: false), isA<SegmentNothing>());
    });
    test('already inside the segment: no seek', () {
      expect(guard().onPosition(60100, repeatOne: false), isA<SegmentNothing>());
    });
    test('advances when the end is reached, once', () {
      final g = guard()..onPosition(60000, repeatOne: false);
      expect(g.onPosition(70000, repeatOne: false), isA<SegmentNothing>());
      expect(g.onPosition(80000, repeatOne: false), isA<SegmentAdvance>());
      expect(g.onPosition(80200, repeatOne: false), isA<SegmentNothing>());
    });
    test('the last segment finishes instead of advancing', () {
      final g = guard(last: true)..onPosition(60000, repeatOne: false);
      expect(g.onPosition(80100, repeatOne: false), isA<SegmentFinish>());
    });
    test('inside the last tick it times the cut exactly, then the timer ends it', () {
      final g = guard()..onPosition(60000, repeatOne: false);
      final a = g.onPosition(79900, repeatOne: false);
      expect(a, isA<SegmentAdvanceIn>().having((x) => x.ms, 'ms', 100));
      expect(g.onPosition(79950, repeatOne: false), isA<SegmentNothing>()); // already scheduled
      expect(g.onTimer(repeatOne: false), isA<SegmentAdvance>());
      expect(g.onPosition(80010, repeatOne: false), isA<SegmentNothing>()); // no double advance
    });
    test('scrubbing away from the end cancels the pending cut', () {
      final g = guard()..onPosition(60000, repeatOne: false);
      g.onPosition(79900, repeatOne: false);
      expect(g.onPosition(65000, repeatOne: false), isA<SegmentCancel>());
      expect(g.onPosition(79900, repeatOne: false), isA<SegmentAdvanceIn>()); // arms again
    });
    test('a position already past the end (seek beyond) advances', () {
      final g = guard()..onPosition(60000, repeatOne: false);
      expect(g.onPosition(150000, repeatOne: false), isA<SegmentAdvance>());
    });
    test('repeat-one loops the segment: back to its start, end counts again', () {
      final g = guard()..onPosition(60000, repeatOne: true);
      expect(g.onPosition(80000, repeatOne: true), isA<SegmentSeek>().having((a) => a.ms, 'ms', 60000));
      expect(g.onPosition(80300, repeatOne: true), isA<SegmentSeek>());
    });
    test('the same entry reported twice keeps its state; a new one starts fresh', () {
      final g = guard()..onPosition(60000, repeatOne: false);
      g.trackChanged(0, seg, isLast: false); // same call again
      expect(g.onPosition(80000, repeatOne: false), isA<SegmentAdvance>());
      g.trackChanged(1, const ReelSegment(songId: 'a', startMs: 100000, endMs: 120000), isLast: false);
      expect(g.onPosition(0, repeatOne: false), isA<SegmentSeek>().having((a) => a.ms, 'ms', 100000));
    });
    test('no segment (not a reel entry): nothing', () {
      final g = SegmentGuard()..trackChanged(0, null, isLast: false);
      expect(g.onPosition(1000, repeatOne: false), isA<SegmentNothing>());
      expect(g.onTimer(repeatOne: false), isA<SegmentNothing>());
    });
  });
}
