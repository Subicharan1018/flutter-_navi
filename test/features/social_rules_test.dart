import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/social_rules.dart';
import 'package:navivibe/features/social/ui/collab_screens.dart' show collabSubtitle;

CollabPlaylist collab({String status = 'active', bool owner = false, List<(int, String, String)> songs = const []}) =>
    CollabPlaylist.fromJson({
      'id': 'p1',
      'name': 'Road trip',
      'owner': 'maya',
      'is_owner': owner,
      'status': status,
      'song_count': songs.length,
      'members': [
        {'username': 'Arjun', 'status': 'active'},
        {'username': 'maya', 'status': 'active'},
        {'username': 'Sana', 'status': 'invited'},
      ],
      'songs': [
        for (final s in songs) {'entry_id': s.$1, 'song_id': s.$2, 'added_by': s.$3},
      ],
    });

Person person(String name, PresenceState s, {String? code, bool joinable = true, JamMode mode = JamMode.collab}) => Person(
      username: name,
      state: s,
      nowPlaying: s == PresenceState.active ? FriendSong(songId: 'x', title: 'Song', artist: 'Art') : null,
      room: code == null ? null : PersonRoom(mode: mode, open: true, members: 2, code: code, joinable: joinable),
    );

PeopleList people(List<Person> p, {bool enabled = true}) => PeopleList(enabled: enabled, people: p);

void main() {
  group('collab playlist rights', () {
    test('every active collaborator edits; invitees do not', () {
      expect(canEditCollab(collab(owner: true), 'maya'), isTrue);
      expect(canEditCollab(collab(), 'Arjun'), isTrue);
      expect(canEditCollab(collab(status: 'invited'), 'Sana'), isFalse);
    });

    test('only the owner manages the group', () {
      expect(canManageCollab(collab(owner: true), 'maya'), isTrue);
      expect(canManageCollab(collab(), 'Arjun'), isFalse);
      expect(isCollabOfOthers(collab()), isTrue);
      expect(isCollabOfOthers(collab(owner: true)), isFalse);
    });

    test('collaborators list the owner first and leave out invitees', () {
      expect(collaborators(collab()).map((m) => m.username), ['maya', 'Arjun']);
    });

    test('the Library row names the collaborators', () {
      expect(collabSubtitle(collab(songs: [(1, 'a', 'maya')])), '1 song · maya, Arjun');
      expect(collabSubtitle(collab()), '0 songs · maya, Arjun');
    });

    test('contributions count who added what, most first', () {
      final p = collab(songs: [(1, 'a', 'Arjun'), (2, 'b', 'maya'), (3, 'c', 'Arjun')]);
      expect(contributions(p), [('Arjun', 2), ('maya', 1)]);
    });

    test('movedTo puts the song where the server will', () {
      expect(movedTo([1, 2, 3, 4], 3, 0), [4, 1, 2, 3]);
      expect(movedTo([1, 2, 3, 4], 0, 2), [2, 3, 1, 4]);
      expect(movedTo([1, 2, 3], 1, 1), [1, 2, 3]);
      expect(movedTo([1, 2, 3], 5, 0), [1, 2, 3]);
    });
  });

  group('People', () {
    test('listening now first, then idle, offline, and people who are not sharing last', () {
      final sorted = sortPeople([
        person('d', PresenceState.hidden),
        person('c', PresenceState.offline),
        person('b', PresenceState.idle),
        person('z', PresenceState.active),
        person('a', PresenceState.active),
      ]);
      expect(sorted.map((p) => p.username), ['a', 'z', 'b', 'c', 'd']);
    });

    test('each state says something different, and a hidden person says nothing about music', () {
      expect(presenceLine(person('a', PresenceState.active)), 'Song · Art');
      expect(presenceLine(person('a', PresenceState.active, code: 'K7QX2M')), 'Song · Art · in a Collab room');
      expect(presenceLine(person('a', PresenceState.idle)), 'Idle');
      expect(presenceLine(person('a', PresenceState.hidden)), 'Not sharing what they listen to');
      expect(PresenceState.values.map((s) => s.label).toSet().length, PresenceState.values.length);
    });

    test('Join is offered only for an active person in an open room you are not in', () {
      expect(canJoin(person('a', PresenceState.active, code: 'K7QX2M')), isTrue);
      expect(canJoin(person('a', PresenceState.active, code: 'K7QX2M', joinable: false)), isFalse);
      expect(canJoin(person('a', PresenceState.active)), isFalse); // not in a room
      expect(canJoin(person('a', PresenceState.idle, code: 'K7QX2M')), isFalse);
    });

    test('a room without a code (not opened to friends) is never joinable', () {
      final p = PersonRoom.fromJson({'mode': 'jam', 'open': false, 'members': 3, 'joinable': true});
      expect(p.joinable, isFalse);
      expect(p.code, isNull);
    });

    test('the server list parses states, songs and rooms', () {
      final l = PeopleList.fromJson({
        'enabled': true,
        'people': [
          {'username': 'Bob', 'state': 'active', 'now_playing': {'song_id': 's', 'title': 'T', 'artist': 'A', 'minutes_ago': 1},
           'room': {'mode': 'collab', 'open': true, 'members': 2, 'code': 'K7QX2M', 'joinable': true}},
          {'username': 'Cy', 'state': 'hidden'},
          {'username': 'Di', 'state': 'weird'},
        ],
      });
      expect(l.people.map((p) => p.state), [PresenceState.active, PresenceState.hidden, PresenceState.offline]);
      expect(l.listeningNow.single.username, 'Bob');
      expect(l.people.first.room!.code, 'K7QX2M');
      expect(l.people[1].nowPlaying, isNull);
    });

    test('hide-listening follows hide-activity until the server says otherwise', () {
      expect(SocialSettings.fromJson({'enabled': true, 'hide_activity': true}).hideListening, isTrue);
      expect(SocialSettings.fromJson({'enabled': true, 'hide_activity': true, 'hide_listening': false}).hideListening, isFalse);
      expect(const SocialSettings(enabled: true).hideListening, isFalse);
    });
  });

  group('friend alerts', () {
    final t0 = DateTime(2026, 11, 8, 14, 0);
    const on = FriendAlertSettings(enabled: true);

    FriendAlertPolicy policy() => FriendAlertPolicy();

    test('alerts when a friend goes from not listening to listening', () {
      final before = people([person('Bob', PresenceState.idle)]);
      final now = people([person('Bob', PresenceState.active)]);
      final a = policy().evaluate(previous: before, current: now, settings: on, now: t0);
      expect(a.single.username, 'Bob');
      expect(a.single.song!.title, 'Song');
    });

    test('the first poll is only a baseline, and a song change is not news', () {
      final active = people([person('Bob', PresenceState.active)]);
      expect(policy().evaluate(previous: null, current: active, settings: on, now: t0), isEmpty);
      expect(policy().evaluate(previous: active, current: active, settings: on, now: t0), isEmpty);
    });

    test('off by default, and nothing when social is off', () {
      final before = people([person('Bob', PresenceState.offline)]);
      final now = people([person('Bob', PresenceState.active)]);
      expect(policy().evaluate(previous: before, current: now, settings: const FriendAlertSettings(), now: t0), isEmpty);
      expect(policy().evaluate(previous: before, current: people(now.people, enabled: false), settings: on, now: t0), isEmpty);
    });

    test('a muted friend is silent, others are not', () {
      final before = people([person('Bob', PresenceState.offline), person('Cy', PresenceState.offline)]);
      final now = people([person('Bob', PresenceState.active), person('Cy', PresenceState.active)]);
      final a = policy().evaluate(
          previous: before, current: now, settings: on.copyWith(muted: {'bob'}), now: t0);
      expect(a.map((x) => x.username), ['Cy']);
    });

    test('someone who hides what they listen to never alerts', () {
      final before = people([person('Bob', PresenceState.offline)]);
      final now = people([person('Bob', PresenceState.hidden)]);
      expect(policy().evaluate(previous: before, current: now, settings: on, now: t0), isEmpty);
    });

    test('one alert per friend per 30 minutes', () {
      final p = policy();
      final off = people([person('Bob', PresenceState.offline)]);
      final act = people([person('Bob', PresenceState.active)]);
      expect(p.evaluate(previous: off, current: act, settings: on, now: t0), hasLength(1));
      expect(p.evaluate(previous: off, current: act, settings: on, now: t0.add(const Duration(minutes: 10))), isEmpty);
      expect(p.evaluate(previous: off, current: act, settings: on, now: t0.add(const Duration(minutes: 29))), isEmpty);
      expect(p.evaluate(previous: off, current: act, settings: on, now: t0.add(const Duration(minutes: 31))), hasLength(1));
    });

    test('the limit is per friend', () {
      final p = policy();
      final off = people([person('Bob', PresenceState.offline), person('Cy', PresenceState.offline)]);
      expect(p.evaluate(previous: off, current: people([person('Bob', PresenceState.active), person('Cy', PresenceState.offline)]),
          settings: on, now: t0), hasLength(1));
      expect(p.evaluate(previous: off, current: people([person('Bob', PresenceState.offline), person('Cy', PresenceState.active)]),
          settings: on, now: t0.add(const Duration(minutes: 1))), hasLength(1));
    });

    test('quiet hours hold alerts back, including across midnight', () {
      final off = people([person('Bob', PresenceState.offline)]);
      final act = people([person('Bob', PresenceState.active)]);
      const night = FriendAlertSettings(enabled: true, quietFromMin: 22 * 60, quietToMin: 7 * 60);
      expect(policy().evaluate(previous: off, current: act, settings: night, now: DateTime(2026, 11, 8, 23, 30)), isEmpty);
      expect(policy().evaluate(previous: off, current: act, settings: night, now: DateTime(2026, 11, 9, 6, 59)), isEmpty);
      expect(policy().evaluate(previous: off, current: act, settings: night, now: DateTime(2026, 11, 9, 7, 0)), hasLength(1));
      expect(night.inQuietHours(DateTime(2026, 11, 8, 12, 0)), isFalse);
      expect(const FriendAlertSettings(enabled: true).inQuietHours(DateTime(2026, 11, 8, 3, 0)), isFalse);
    });

    test('a quiet-hours alert is not spent: the friend can still alert once it ends', () {
      final p = policy();
      final off = people([person('Bob', PresenceState.offline)]);
      final act = people([person('Bob', PresenceState.active)]);
      const night = FriendAlertSettings(enabled: true, quietFromMin: 22 * 60, quietToMin: 7 * 60);
      expect(p.evaluate(previous: off, current: act, settings: night, now: DateTime(2026, 11, 8, 23, 0)), isEmpty);
      expect(p.evaluate(previous: off, current: act, settings: night, now: DateTime(2026, 11, 9, 8, 0)), hasLength(1));
    });

    test('a friend in an open room gets a Join code; in a closed room, none', () {
      final off = people([person('Bob', PresenceState.offline)]);
      final open = people([person('Bob', PresenceState.active, code: 'K7QX2M')]);
      final a = policy().evaluate(previous: off, current: open, settings: on, now: t0);
      expect(a.single.joinCode, 'K7QX2M');
      expect(a.single.roomMode, JamMode.collab);
      final closed = people([
        Person(username: 'Bob', state: PresenceState.active, room: const PersonRoom(mode: JamMode.jam, members: 2)),
      ]);
      expect(policy().evaluate(previous: off, current: closed, settings: on, now: t0).single.joinCode, isNull);
    });

    test('someone newly listed (just turned social on) does not alert', () {
      final before = people([person('Cy', PresenceState.offline)]);
      final now = people([person('Cy', PresenceState.offline), person('Bob', PresenceState.active)]);
      expect(policy().evaluate(previous: before, current: now, settings: on, now: t0), isEmpty);
    });
  });
}
