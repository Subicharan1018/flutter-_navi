import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/queue_snapshot.dart';

Song s(String id, {bool starred = false, int duration = 200}) => Song(
      id: id,
      title: 'T$id',
      artist: 'A',
      album: 'B',
      coverArt: 'c$id',
      duration: duration,
      track: 1,
      year: 2020,
      starred: starred,
    );

SavedQueue snap(List<Song> q, int i, {String account = 'srv|me', List<Song>? unshuffled}) =>
    SavedQueue.capture(
      account: account,
      queue: q,
      currentIndex: i,
      unshuffled: unshuffled ?? q,
      shuffle: true,
      repeat: 1,
      source: 'Road trip',
    )!;

void main() {
  final q = [for (var i = 0; i < 5; i++) s('$i')];

  test('round trip keeps songs, order, index, modes and source', () {
    final back = SavedQueue.tryDecode(snap(q, 2, unshuffled: q.reversed.toList()).encode())!;
    expect(back.songs.map((e) => e.id), ['0', '1', '2', '3', '4']);
    expect(back.index, 2);
    expect(back.shuffle, isTrue);
    expect(back.repeat, 1);
    expect(back.source, 'Road trip');
    expect(back.unshuffledIds, ['4', '3', '2', '1', '0']);
    expect(back.songs.first.title, 'T0');
  });

  test('starred is kept as it was', () {
    final back = SavedQueue.tryDecode(snap([s('a', starred: true), s('b')], 0).encode())!;
    expect(back.songs[0].starred, isTrue);
    expect(back.songs[1].starred, isFalse);
  });

  test('a long queue is cut to the current song and 100 each side', () {
    final big = [for (var i = 0; i < 1000; i++) s('$i')];
    final c = snap(big, 500);
    expect(c.songs.length, 201);
    expect(c.songs[c.index].id, '500');
    final edge = snap(big, 3);
    expect(edge.songs.length, 104);
    expect(edge.index, 3);
  });

  test('corrupt data reads as no snapshot', () {
    expect(SavedQueue.tryDecode(null), isNull);
    expect(SavedQueue.tryDecode(''), isNull);
    expect(SavedQueue.tryDecode('{not json'), isNull);
    expect(SavedQueue.tryDecode('[]'), isNull);
    expect(SavedQueue.tryDecode('{"v":99,"account":"a","songs":[{"id":"1"}],"index":0,"shuffle":false,"repeat":0}'), isNull);
    expect(SavedQueue.tryDecode('{"v":1,"account":"a","songs":[5],"index":0,"shuffle":false,"repeat":0}'), isNull);
    expect(SavedQueue.tryDecode('{"v":1,"account":"a","songs":[],"index":0,"shuffle":false,"repeat":0}'), isNull);
    expect(SavedQueue.tryDecode('{"v":1,"account":"a","songs":[{"id":"1"}],"index":"x","shuffle":false,"repeat":0}'), isNull);
  });

  test('only the same account restores', () {
    final c = snap(q, 1);
    expect(c.resolve(account: 'srv|other'), isNull);
    expect(c.resolve(account: 'srv|me'), isNotNull);
    expect(SavedQueue.accountKey(' https://X.com ', 'Me'), 'https://x.com|me');
  });

  test('songs removed from the library are dropped; current one handed to the next', () {
    final r = snap(q, 2).resolve(account: 'srv|me', isGone: (id) => id == '2' || id == '0')!;
    expect(r.songs.map((e) => e.id), ['1', '3', '4']);
    expect(r.songs[r.index].id, '3');
    expect(r.positionMs, 0);
  });

  test('current song removed with none after it falls back to the last left', () {
    final r = snap(q, 4).resolve(account: 'srv|me', isGone: (id) => id == '4')!;
    expect(r.songs[r.index].id, '3');
  });

  test('everything removed restores nothing', () {
    expect(snap(q, 0).resolve(account: 'srv|me', isGone: (_) => true), isNull);
  });

  test('a stale index is pulled into range', () {
    final bad = SavedQueue(account: 'a', songs: q, unshuffledIds: const [], index: 99, shuffle: false, repeat: 0);
    expect(bad.resolve(account: 'a')!.index, 4);
    final neg = SavedQueue(account: 'a', songs: q, unshuffledIds: const [], index: -3, shuffle: false, repeat: 0);
    expect(neg.resolve(account: 'a')!.index, 0);
  });

  test('the saved position belongs to its own song only', () {
    final c = snap(q, 2);
    expect(c.resolve(account: 'srv|me', savedTrackId: '2', savedPositionMs: 42000)!.positionMs, 42000);
    expect(c.resolve(account: 'srv|me', savedTrackId: '1', savedPositionMs: 42000)!.positionMs, 0);
    // within the last 5 seconds counts as finished
    expect(c.resolve(account: 'srv|me', savedTrackId: '2', savedPositionMs: 198000)!.positionMs, 0);
  });

  test('unshuffled order falls back to queue order when it no longer matches', () {
    final r = snap(q, 0, unshuffled: q.reversed.toList()).resolve(account: 'srv|me', isGone: (id) => id == '4')!;
    expect(r.unshuffled.map((e) => e.id), ['3', '2', '1', '0']);
    final c = SavedQueue(account: 'a', songs: q, unshuffledIds: const ['9'], index: 0, shuffle: false, repeat: 0);
    expect(c.resolve(account: 'a')!.unshuffled.length, 5);
  });
}
