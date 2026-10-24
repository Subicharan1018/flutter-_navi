import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/jam_sync.dart';
import 'package:navivibe/features/social/ui/jam/code_entry.dart';
import 'package:navivibe/features/social/ui/jam/jam_room.dart';

JamState jam({int index = 0, bool playing = true, int pos = 10000, int serverMs = 1000000, int items = 2}) =>
    JamState.fromJson({
      'code': 'ABC234',
      'version': 3,
      'host': 'alice',
      'you_are_host': false,
      'members': [
        {'username': 'alice', 'is_host': true},
      ],
      'queue': [
        for (var i = 1; i <= items; i++) {'id': i, 'song_id': 's$i', 'title': 'T$i', 'added_by': 'alice', 'duration_s': 100},
      ],
      'index': index,
      'playing': playing,
      'position_ms': pos,
      'server_ms': serverMs,
    });

extension on JamState {
  JamState copyWithHost(bool host) => JamState(
        code: code,
        version: version,
        host: this.host,
        youAreHost: host,
        members: members,
        queue: queue,
        index: index,
        playing: playing,
        positionMs: positionMs,
        serverMs: serverMs,
      );
}

void main() {
  group('JamClock', () {
    test('offset comes from the midpoint of the fastest round trip', () {
      final c = JamClock();
      c.add(1000, 1400, 5200); // rtt 400 -> offset 5200 - 1200 = 4000
      expect(c.offsetMs, 4000);
      c.add(2000, 2100, 6050); // faster: offset 6050 - 2050 = 4000
      expect(c.offsetMs, 4000);
      c.add(3000, 3800, 9999); // slower sample is ignored
      expect(c.offsetMs, 4000);
      expect(c.serverNow(10), 4010);
    });

    test('ignores empty server time and negative round trips', () {
      final c = JamClock()..offsetMs = 7;
      c.add(10, 20, 0);
      c.add(30, 20, 500);
      expect(c.offsetMs, 7);
    });
  });

  group('projectPositionMs', () {
    test('advances while playing, holds while paused', () {
      expect(projectPositionMs(jam(), 1002500), 12500);
      expect(projectPositionMs(jam(playing: false), 1002500), 10000);
      expect(projectPositionMs(jam(), 999000), 10000); // clock behind: never goes backwards
    });
  });

  group('diffQueue', () {
    test('same queue changes nothing', () {
      expect(diffQueue([1, 2], [1, 2], 0).change, QueueChange.none);
    });
    test('songs added at the end append', () {
      final d = diffQueue([1, 2], [1, 2, 3], 0);
      expect(d.change, QueueChange.append);
      expect(d.at, 2);
    });
    test('removing another song removes just it', () {
      final d = diffQueue([1, 2, 3], [1, 3], 0);
      expect(d.change, QueueChange.removeOne);
      expect(d.at, 1);
    });
    test('removing the playing song, or anything else, rebuilds', () {
      expect(diffQueue([1, 2, 3], [1, 3], 1).change, QueueChange.replace);
      expect(diffQueue([1, 2, 3], [3, 2, 1], 0).change, QueueChange.replace);
    });
  });

  group('diffQueue moves', () {
    test('one song dragged elsewhere reorders in place', () {
      final d = diffQueue([1, 2, 3, 4], [1, 3, 4, 2], 0);
      expect(d.change, QueueChange.move);
      expect((d.at, d.to), (1, 3));
      final back = diffQueue([1, 2, 3, 4], [4, 1, 2, 3], 1);
      expect(back.change, QueueChange.move);
      expect((back.at, back.to), (3, 0));
    });
    test('a shuffle of several songs rebuilds', () {
      expect(diffQueue([1, 2, 3, 4], [2, 1, 4, 3], 0).change, QueueChange.replace);
    });
  });

  group('join code', () {
    test('cleans pasted text to the letters a code can hold', () {
      expect(cleanJamCode(' k7q-x2m '), 'K7QX2M');
      expect(cleanJamCode('o0i1'), ''); // never in a code
      expect(cleanJamCode('ABCDEFGHJK'), 'ABCDEF');
    });
  });

  group('sync status', () {
    test('host, waiting, syncing, in sync and catching up are told apart', () {
      expect(SyncPill.status(jam(playing: true).copyWithHost(true), null).$2, isTrue);
      expect(SyncPill.status(jam(playing: false), null).$1, 'Waiting for alice');
      expect(SyncPill.status(jam(), null).$1, 'Syncing…');
      expect(SyncPill.status(jam(), 400), ('In sync with alice', true));
      expect(SyncPill.status(jam(), 4000), ('Catching up…', false));
    });
  });

  group('needsDriftCorrection', () {
    test('only past the tolerance', () {
      expect(needsDriftCorrection(10000, 11000), isFalse);
      expect(needsDriftCorrection(10000, 12000), isTrue);
      expect(needsDriftCorrection(12000, 10000), isTrue);
    });
  });

  group('hostPublish', () {
    HostPublish? run(JamState s, {int index = 0, bool playing = true, int pos = 10000, int now = 1000000}) =>
        hostPublish(server: s, serverNowMs: now, localIndex: index, localPlaying: playing, localPositionMs: pos);

    test('in step publishes nothing', () {
      expect(run(jam()), isNull);
      expect(run(jam(), pos: 10400), isNull); // within jitter
    });
    test('a skip publishes a jump', () {
      final p = run(jam(), index: 1)!;
      expect(p.action, 'jump');
      expect(p.index, 1);
    });
    test('play and pause are published with the position', () {
      expect(run(jam(playing: false), playing: true)!.action, 'play');
      final pause = run(jam(), playing: false, pos: 7000)!;
      expect(pause.action, 'pause');
      expect(pause.positionMs, 7000);
    });
    test('a seek while playing syncs, while paused seeks', () {
      expect(run(jam(), pos: 60000)!.action, 'sync');
      expect(run(jam(playing: false), playing: false, pos: 60000)!.action, 'seek');
    });
  });

  group('models', () {
    test('JamItem builds a playable song with its id and length', () {
      final song = jam().queue.first.toSong();
      expect(song.id, 's1');
      expect(song.title, 'T1');
      expect(song.duration, 100);
    });

    test('settings default to off', () {
      final s = SocialSettings.fromJson(const {});
      expect(s.enabled, isFalse);
      expect(s.hideActivity, isFalse);
    });

    test('friend feed parses now playing and recent plays', () {
      final feed = FriendFeed.fromJson({
        'enabled': true,
        'friends': [
          {
            'username': 'Bob',
            'now_playing': {'song_id': 's9', 'title': 'Song', 'artist': 'A', 'minutes_ago': 2},
            'recent': [
              {'title': 'Old', 'played_at': 5, 'song_id': null},
            ],
          },
        ],
      });
      expect(feed.enabled, isTrue);
      expect(feed.friends.single.nowPlaying!.minutesAgo, 2);
      expect(feed.friends.single.recent.single.playable, isFalse);
    });

    test('collab playlist keeps who added each song', () {
      final p = CollabPlaylist.fromJson({
        'id': 'p1',
        'name': 'Trip',
        'owner': 'alice',
        'is_owner': false,
        'status': 'invited',
        'invited_by': 'alice',
        'members': [
          {'username': 'alice', 'status': 'active'},
        ],
        'songs': [
          {'entry_id': 4, 'song_id': 's1', 'added_by': 'Bob', 'added_at': 9},
        ],
      });
      expect(p.invited, isTrue);
      expect(p.songs.single.addedBy, 'Bob');
    });

    test('blend flags', () {
      final b = Blend.fromJson({
        'id': 'b1',
        'with': 'Bob',
        'status': 'pending',
        'incoming': true,
        'songs': [
          {'song_id': 's1', 'title': 'T', 'from': 'both'},
        ],
      });
      expect(b.pending && b.incoming, isTrue);
      expect(b.songs.single.from, 'both');
    });
  });
}
