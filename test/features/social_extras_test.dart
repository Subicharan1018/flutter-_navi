import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/social/data/social_api.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/people_providers.dart';
import 'package:navivibe/features/social/logic/reaction_rules.dart';
import 'package:navivibe/features/social/logic/recap_providers.dart';
import 'package:navivibe/features/social/logic/share_now_playing.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';
import 'package:navivibe/features/social/logic/social_rules.dart';
import 'package:navivibe/models/song.dart';

/// Reactions on a friend's song, "Share now playing" and the weekly recap.

// ── fakes ────────────────────────────────────────────────────────────────────

class _Adapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function()> routes;
  final List<(String, Object?)> sent = [];
  _Adapter(this.routes);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async {
    sent.add((o.path, o.data));
    final r = routes[o.path];
    return r == null ? _json(404, {'error': 'Not found'}) : r();
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {'content-type': ['application/json']});

SocialApi _api(_Adapter a) => SocialApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = a);

class _Api extends Fake implements SocialApi {
  final List<PeopleList> script;
  int polls = 0;
  _Api(this.script);
  @override
  Future<PeopleList> people() async => script[(polls++).clamp(0, script.length - 1)];
}

class _Sink implements ReactionAlertSink {
  final shown = <Reaction>[];
  @override
  Future<void> show(Reaction r) async => shown.add(r);
}

class _Seen implements ReactionSeenStore {
  int? mark;
  _Seen([this.mark]);
  @override
  int? read() => mark;
  @override
  void write(int id) => mark = id;
}

class _Prefs implements AlertPrefsStore {
  Map<String, Object?> saved;
  _Prefs([this.saved = const {}]);
  @override
  Map<String, Object?> read() => saved;
  @override
  void write(Map<String, Object?> value) => saved = value;
}

class _On extends SocialSettingsNotifier {
  @override
  Future<SocialSettings> build() async => const SocialSettings(enabled: true);
}

class _Dismiss implements RecapDismissStore {
  String? week;
  @override
  String? read() => week;
  @override
  void write(String w) => week = w;
}

Reaction rx(int id, {String from = 'Bob', int? at, String note = ''}) => Reaction(
    id: id,
    from: from,
    emoji: '🔥',
    note: note,
    title: 'Song',
    artist: 'Art',
    at: at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000);

PeopleList people(List<Reaction> r, {bool supported = true}) => PeopleList(
      enabled: true,
      reactionsSupported: supported,
      reactions: r,
      people: const [Person(username: 'Bob', state: PresenceState.idle)],
    );

Future<({ProviderContainer c, _Sink sink, _Seen seen})> rig(List<PeopleList> script, {bool alerts = true, int? seen, Set<String> muted = const {}}) async {
  final sink = _Sink();
  final store = _Seen(seen);
  final c = ProviderContainer(overrides: [
    socialApiProvider.overrideWithValue(_Api(script)),
    socialSettingsProvider.overrideWith(_On.new),
    alertPrefsStoreProvider.overrideWithValue(_Prefs({'enabled': alerts, 'muted': muted.toList()})),
    friendAlertSinkProvider.overrideWithValue(_SilentFriends()),
    reactionAlertSinkProvider.overrideWithValue(sink),
    reactionSeenStoreProvider.overrideWithValue(store),
  ]);
  addTearDown(c.dispose);
  await c.read(socialSettingsProvider.future);
  c.read(peopleProvider);
  return (c: c, sink: sink, seen: store);
}

class _SilentFriends implements FriendAlertSink {
  @override
  Future<void> show(FriendAlert alert) async {}
}

void main() {
  group('models', () {
    test('People parse friends’ reactions and note whether the server knows them', () {
      final l = PeopleList.fromJson({
        'enabled': true,
        'people': [],
        'reactions': [
          {'id': 3, 'from': 'Bob', 'emoji': '🔥', 'note': 'yes', 'title': 'T', 'artist': 'A', 'song_id': 's', 'at': 9},
          'junk',
        ],
      });
      expect(l.reactionsSupported, isTrue);
      expect(l.reactions.single.id, 3);
      expect(l.reactions.single.note, 'yes');
      // An older server has no `reactions` key at all.
      final old = PeopleList.fromJson({'enabled': true, 'people': []});
      expect(old.reactionsSupported, isFalse);
      expect(old.reactions, isEmpty);
    });

    test('a recap parses, and hasContent needs a friend and some listening', () {
      final r = WeeklyRecap.fromJson({
        'enabled': true,
        'week_start': '2026-11-01',
        'you': {
          'minutes': 192,
          'plays': 54,
          'top_artists': [
            {'name': 'Ar', 'plays': 9}
          ],
          'top_songs': [
            {'title': 'S', 'song_id': 's1', 'plays': 4}
          ],
        },
        'friends': [
          {
            'username': 'Bob',
            'blend_id': 'b1',
            'match_pct': 74,
            'their_minutes': 100,
            'shared_artists': [
              {'name': 'Ar', 'you': 3, 'them': 2}
            ],
            'shared_songs': [
              {'title': 'S', 'song_id': 's1', 'you': 2, 'them': 1}
            ],
          },
          {'username': 'Cy', 'hidden': true},
        ],
      });
      expect(r.minutes, 192);
      expect(r.topArtists.single.you, 9);
      expect(r.topSongs.single.songId, 's1');
      expect(r.friends.first.sharedArtists.single.them, 2);
      expect(r.friends.first.sharedSongs.single.name, 'S');
      expect(r.friends.last.hidden, isTrue);
      expect(r.friends.last.theirMinutes, isNull);
      expect(r.hasContent, isTrue);
      expect(const WeeklyRecap(plays: 5).hasContent, isFalse);
      expect(const WeeklyRecap(friends: [RecapFriend(username: 'x')]).hasContent, isFalse);
    });
  });

  group('reaction rules', () {
    test('notes are trimmed, collapsed and cut to 80 characters', () {
      expect(cleanReactionNote('  so   good \n yes '), 'so good yes');
      expect(cleanReactionNote('x' * 200).length, reactionNoteMax);
      expect(cleanReactionNote('🔥' * 100).characters.length, reactionNoteMax); // an emoji counts once
    });

    test('React is offered only for a friend playing a song on a server that has it', () {
      const playing = Person(
          username: 'Bob', state: PresenceState.active, nowPlaying: FriendSong(songId: 's', title: 'T'));
      expect(canReact(playing, serverSupports: true), isTrue);
      expect(canReact(playing, serverSupports: false), isFalse);
      expect(canReact(const Person(username: 'Bob', state: PresenceState.idle), serverSupports: true), isFalse);
      expect(canReact(const Person(username: 'Bob', state: PresenceState.hidden), serverSupports: true), isFalse);
    });

    test('announce only new ones, skip muted friends and quiet hours', () {
      final now = DateTime(2026, 11, 8, 12);
      final nowS = now.millisecondsSinceEpoch ~/ 1000;
      const on = FriendAlertSettings(enabled: true);
      final inbox = [rx(1, at: nowS), rx(2, from: 'Cy', at: nowS), rx(3, at: nowS)];
      expect(reactionsToAnnounce(inbox, lastSeen: 1, settings: on, now: now).map((r) => r.id), [2, 3]);
      expect(
        reactionsToAnnounce(inbox, lastSeen: 1, settings: const FriendAlertSettings(enabled: true, muted: {'cy'}), now: now)
            .map((r) => r.id),
        [3],
      );
      final quiet = FriendAlertSettings(enabled: true, quietFromMin: 11 * 60, quietToMin: 13 * 60);
      expect(reactionsToAnnounce(inbox, lastSeen: 0, settings: quiet, now: now), isEmpty);
    });

    test('the first run does not replay old reactions', () {
      final now = DateTime(2026, 11, 8, 12);
      final nowS = now.millisecondsSinceEpoch ~/ 1000;
      final inbox = [rx(1, at: nowS - 5 * 3600), rx(2, at: nowS - 60)];
      expect(
        reactionsToAnnounce(inbox, lastSeen: null, settings: const FriendAlertSettings(enabled: true), now: now)
            .map((r) => r.id),
        [2],
      );
      expect(highestReactionId(inbox, null), 2);
      expect(highestReactionId(inbox, 9), 9);
      expect(highestReactionId(const [], null), isNull);
    });

    test('notification text', () {
      expect(reactionText(rx(1, note: 'banger')), ('Bob reacted 🔥', 'Song · Art — “banger”'));
      expect(reactionText(const Reaction(id: 1, from: 'Bob', emoji: '❤️')), ('Bob reacted ❤️', ''));
    });
  });

  group('People poll delivers reactions', () {
    test('each reaction is announced once, and the mark is remembered', () async {
      final r = await rig([
        people([]),
        people([rx(5)]),
        people([rx(5)]), // same one again on the next poll
        people([rx(5), rx(6, from: 'Cy')]),
      ]);
      final n = r.c.read(peopleProvider.notifier);
      await n.refresh();
      expect(r.sink.shown, isEmpty);
      await n.refresh();
      expect(r.sink.shown.map((x) => x.id), [5]);
      expect(r.seen.mark, 5);
      await n.refresh();
      expect(r.sink.shown.map((x) => x.id), [5]);
      await n.refresh();
      expect(r.sink.shown.map((x) => x.id), [5, 6]);
      expect(r.seen.mark, 6);
    });

    test('a restart does not repeat what was already shown', () async {
      final r = await rig([people([rx(5), rx(6)])], seen: 6);
      await r.c.read(peopleProvider.notifier).refresh();
      expect(r.sink.shown, isEmpty);
    });

    test('with friend alerts off nothing is raised, but the mark still moves', () async {
      final r = await rig([people([rx(5)])], alerts: false);
      await r.c.read(peopleProvider.notifier).refresh();
      expect(r.sink.shown, isEmpty);
      expect(r.seen.mark, 5);
      expect(r.c.read(peopleProvider).list!.reactions.single.id, 5); // the People view still lists it
    });

    test('a muted friend is not announced', () async {
      final r = await rig([people([rx(5, from: 'Bob')])], muted: {'bob'});
      await r.c.read(peopleProvider.notifier).refresh();
      expect(r.sink.shown, isEmpty);
    });

    test('an older server (no reactions key) just works', () async {
      final r = await rig([people([], supported: false)]);
      await r.c.read(peopleProvider.notifier).refresh();
      expect(r.c.read(peopleProvider).list!.reactionsSupported, isFalse);
      expect(r.sink.shown, isEmpty);
    });
  });

  group('API', () {
    test('react posts the reaction with the song', () async {
      final a = _Adapter({'/social/react': () => _json(200, {'reaction': {}})});
      await _api(a).react('Bob', '🔥', note: 'yes', songId: 's1', title: 'T', artist: 'A');
      final (path, data) = a.sent.single;
      expect(path, '/social/react');
      expect(data, {'to': 'Bob', 'emoji': '🔥', 'note': 'yes', 'song_id': 's1', 'title': 'T', 'artist': 'A'});
    });

    test('react on an older server reports 404; hidden friends report 403', () async {
      await expectLater(
        _api(_Adapter({})).react('Bob', '🔥'),
        throwsA(isA<SocialException>().having((e) => e.status, 'status', 404)),
      );
      final hidden = _Adapter({'/social/react': () => _json(403, {'error': 'They’re not sharing what they listen to.'})});
      await expectLater(
        _api(hidden).react('Bob', '🔥'),
        throwsA(isA<SocialException>().having((e) => e.message, 'message', contains('not sharing'))),
      );
    });

    test('recap is null on an older server (404) and when social is off, but real errors surface', () async {
      expect(await _api(_Adapter({})).recap(), isNull);
      expect(await _api(_Adapter({'/social/recap': () => _json(200, {'enabled': false, 'friends': []})})).recap(), isNull);
      final ok = await _api(_Adapter({
        '/social/recap': () => _json(200, {
              'enabled': true,
              'you': {'minutes': 5, 'plays': 2},
              'friends': [],
            })
      })).recap();
      expect(ok!.minutes, 5);
      await expectLater(
        _api(_Adapter({'/social/recap': () => _json(500, {'error': 'boom'})})).recap(),
        throwsA(isA<SocialException>()),
      );
    });
  });

  group('Share now playing', () {
    final song = Song.fromJson({'id': 'a b', 'title': 'Title', 'artist': 'Artist', 'album': 'Album'});

    test('the card has title, artist, album and a naviv:// link, with a plain fallback', () {
      final c = NowPlayingCard.of(song);
      expect(c.link, 'naviv://song/a%20b');
      expect(c.plainText, 'Listening to Title by Artist\nFrom Album\nShared from NaviVibe');
      expect(c.text, '${c.plainText}\nnaviv://song/a%20b');
      expect(c.subject, 'Title · Artist');
    });

    test('missing fields and id degrade to plain text', () {
      final c = NowPlayingCard.of(Song.fromJson({'id': '', 'title': 'Solo'}));
      expect(c.link, isNull);
      expect(c.text, 'Listening to Solo\nShared from NaviVibe');
    });

    test('on Windows it copies to the clipboard', () async {
      String? copied;
      final msg = await shareNowPlaying(song, desktop: true, copy: (t) async => copied = t);
      expect(copied, NowPlayingCard.of(song).text);
      expect(msg, contains('Copied'));
    });
  });

  group('weekly recap rules', () {
    test('durations', () {
      expect(recapDuration(0), '0 min');
      expect(recapDuration(59), '59 min');
      expect(recapDuration(60), '1 h');
      expect(recapDuration(192), '3 h 12 min');
    });

    test('a week is keyed by its Monday', () {
      expect(weekKey(DateTime(2026, 11, 8)), '2026-11-02'); // a Sunday
      expect(weekKey(DateTime(2026, 11, 2)), '2026-11-02');
      expect(weekKey(DateTime(2026, 11, 9)), '2026-11-09');
      expect(weekKey(DateTime(2026, 1, 1)), '2025-12-29'); // across a year
    });

    test('friend line and closest friend', () {
      const a = RecapFriend(
        username: 'A',
        matchPct: 40,
        sharedArtists: [RecapEntry(name: 'x')],
        sharedSongs: [RecapEntry(name: 'y'), RecapEntry(name: 'z')],
      );
      const b = RecapFriend(username: 'B', matchPct: 80, hidden: true);
      expect(recapFriendLine(a), '40% match · 1 shared artist · 2 shared songs');
      expect(recapFriendLine(b), '80% match');
      expect(recapFriendLine(const RecapFriend(username: 'C', hidden: true)), 'Not sharing what they listen to');
      expect(recapFriendLine(const RecapFriend(username: 'C')), 'Nothing shared yet this week');
      expect(closestFriend(const WeeklyRecap(friends: [a, b]))!.username, 'B');
      expect(closestFriend(const WeeklyRecap(friends: [RecapFriend(username: 'N')]))!.username, 'N');
      expect(closestFriend(const WeeklyRecap()), isNull);
    });
  });

  group('Home recap card', () {
    const recap = WeeklyRecap(plays: 4, minutes: 30, friends: [RecapFriend(username: 'Bob', matchPct: 50)]);
    final monday = DateTime(2026, 11, 2, 9);

    ProviderContainer home(WeeklyRecap? r, _Dismiss dismiss, DateTime Function() clock) {
      final c = ProviderContainer(overrides: [
        recapProvider.overrideWith((ref) async => r),
        recapDismissStoreProvider.overrideWithValue(dismiss),
        recapClockProvider.overrideWithValue(clock),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<WeeklyRecap?> shown(ProviderContainer c) async {
      c.listen(homeRecapProvider, (_, _) {});
      await c.read(recapProvider.future);
      return c.read(homeRecapProvider);
    }

    test('shows once there is a Blend friend and listening', () async {
      expect(await shown(home(recap, _Dismiss(), () => monday)), isNotNull);
    });

    test('hidden when the server has no recap or nothing happened', () async {
      expect(await shown(home(null, _Dismiss(), () => monday)), isNull);
      expect(await shown(home(const WeeklyRecap(), _Dismiss(), () => monday)), isNull);
    });

    test('“Not now” hides it for the week and it returns next week', () async {
      var clock = monday;
      final dismiss = _Dismiss();
      final c = home(recap, dismiss, () => clock);
      expect(await shown(c), isNotNull);
      c.read(recapDismissedProvider.notifier).dismissThisWeek();
      expect(dismiss.week, '2026-11-02');
      expect(c.read(homeRecapProvider), isNull);
      clock = DateTime(2026, 11, 8); // still that week
      expect(c.read(homeRecapProvider), isNull);
      clock = DateTime(2026, 11, 9); // next Monday
      c.invalidate(homeRecapProvider);
      expect(c.read(homeRecapProvider), isNotNull);
    });
  });
}
