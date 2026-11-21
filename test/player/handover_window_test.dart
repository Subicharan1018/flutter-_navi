import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/player/handover_window.dart';

void main() {
  final queue = [for (var i = 0; i < 30; i++) 's$i'];

  test('a handover starts from the playing song with a small first window', () {
    final w = handoverWindow(queue: queue, trackId: 's12', queueIndex: 12, window: 10);
    expect(w.first, [for (var i = 12; i < 22; i++) 's$i']);
    expect(w.rest, [for (var i = 22; i < 30; i++) 's$i']);
  });

  test('the track id wins over a stale index', () {
    final w = handoverWindow(queue: queue, trackId: 's5', queueIndex: 20, window: 3);
    expect(w.first, ['s5', 's6', 's7']);
  });

  test('without a track id the index is used, clamped into the queue', () {
    expect(handoverWindow(queue: queue, trackId: null, queueIndex: 28, window: 5).first, ['s28', 's29']);
    expect(handoverWindow(queue: queue, trackId: null, queueIndex: 99, window: 5).first, ['s29']);
    expect(handoverWindow(queue: queue, trackId: null, queueIndex: -4, window: 2).first, ['s0', 's1']);
  });

  test('a queue the song is not in plays just that song', () {
    final w = handoverWindow(queue: queue, trackId: 'zzz', queueIndex: 0, window: 4);
    expect(w.first, ['s0', 's1', 's2', 's3']);
  });

  test('an empty queue with a track id is that one song', () {
    final w = handoverWindow(queue: const [], trackId: 'a', queueIndex: 0, window: 4);
    expect(w.first, ['a']);
    expect(w.rest, isEmpty);
  });

  test('nothing at all gives nothing', () {
    final w = handoverWindow(queue: const [], trackId: null, queueIndex: 0, window: 4);
    expect(w.first, isEmpty);
  });
}
