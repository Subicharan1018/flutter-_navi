import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/smart_playlists/data/smart_evaluator.dart';
import 'package:navivibe/features/smart_playlists/data/smart_rules.dart';
import 'package:navivibe/models/catalog.dart';
import 'package:navivibe/models/song.dart';

final now = DateTime(2026, 6, 15, 12);

SongFacts facts(
  String id, {
  String artist = 'A',
  String genre = '',
  String composer = '',
  int year = 2021,
  int duration = 200,
  int playCount = 0,
  bool starred = false,
  int rating = 0,
  int? addedDaysAgo,
  List<int> playedDaysAgo = const [],
  List<String> languages = const ['ta'],
  String? mood,
}) =>
    SongFacts(
      song: Song(
        id: id,
        title: 'Song $id',
        artist: artist,
        album: 'Album',
        genre: genre,
        composer: composer,
        coverArt: id,
        duration: duration,
        track: 1,
        year: year,
        starred: starred,
        playCount: playCount,
        rating: rating,
        created: addedDaysAgo == null ? null : now.subtract(Duration(days: addedDaysAgo)),
      ),
      languages: languages,
      mood: mood,
      playTimes: [for (final d in playedDaysAgo) now.subtract(Duration(days: d)).millisecondsSinceEpoch],
    );

SmartPlaylist smart(List<SmartNode> rules,
        {bool all = true, SmartSort sort = SmartSort.title, bool asc = true, int? limit}) =>
    SmartPlaylist(
      id: 'smart:1',
      name: 'Test',
      rules: SmartGroup(matchAll: all, children: rules),
      sort: sort,
      ascending: asc,
      limit: limit,
      createdAt: 0,
    );

List<String> ids(SmartPlaylist p, List<SongFacts> lib) =>
    [for (final f in SmartEvaluator.evaluate(p, lib, now: now)) f.song.id];

SmartRule rule(SmartField f, SmartOp o, String v, {int window = 30}) =>
    SmartRule(field: f, op: o, value: v, window: window);

void main() {
  test('Tamil AND year >= 2020 AND not played in 30 days', () {
    final lib = [
      facts('keep', year: 2022, playedDaysAgo: [45]),
      facts('never', year: 2021),
      facts('recent', year: 2023, playedDaysAgo: [3]),
      facts('old', year: 2015),
      facts('english', year: 2022, languages: ['en']),
    ];
    final p = smart([
      rule(SmartField.language, SmartOp.isOp, 'ta'),
      rule(SmartField.year, SmartOp.gte, '2020'),
      rule(SmartField.lastPlayed, SmartOp.notWithin, '30'),
    ]);
    expect(ids(p, lib), ['keep', 'never']);
  });

  test('multilingual songs match any of their languages', () {
    final lib = [facts('duet', languages: ['ta', 'en'])];
    expect(ids(smart([rule(SmartField.language, SmartOp.isOp, 'en')]), lib), ['duet']);
    expect(ids(smart([rule(SmartField.language, SmartOp.isNot, 'en')]), lib), isEmpty);
  });

  test('added in the last 14 days; unknown date is not "recent"', () {
    final lib = [facts('new', addedDaysAgo: 5), facts('old', addedDaysAgo: 90), facts('unknown')];
    expect(ids(smart([rule(SmartField.added, SmartOp.within, '14')]), lib), ['new']);
    expect(ids(smart([rule(SmartField.added, SmartOp.notWithin, '14')]), lib), ['old', 'unknown']);
  });

  test('most played this month: window count, sorted high to low, limited', () {
    final lib = [
      facts('a', playedDaysAgo: [1, 2, 3]),
      facts('b', playedDaysAgo: [1, 40, 50]),
      facts('c', playedDaysAgo: [5, 6]),
      facts('d', playedDaysAgo: [90]),
    ];
    final p = smart(
      [rule(SmartField.recentPlays, SmartOp.gte, '1', window: 30)],
      sort: SmartSort.recentPlays,
      asc: false,
      limit: 2,
    );
    expect(ids(p, lib), ['a', 'c']);
  });

  test('plays window honours the rule days', () {
    final lib = [facts('a', playedDaysAgo: [10]), facts('b', playedDaysAgo: [2])];
    expect(ids(smart([rule(SmartField.recentPlays, SmartOp.gte, '1', window: 5)]), lib), ['b']);
    expect(ids(smart([rule(SmartField.recentPlays, SmartOp.gte, '1', window: 14)]), lib), ['a', 'b']);
  });

  test('mood, starred, genre, composer, artist rules', () {
    final lib = [
      facts('s', mood: 'sad', starred: true, genre: 'Melody', composer: 'Rahman', artist: 'Sid Sriram'),
      facts('h', mood: 'happy', genre: 'Kuthu'),
    ];
    expect(ids(smart([rule(SmartField.mood, SmartOp.isOp, 'sad')]), lib), ['s']);
    expect(ids(smart([rule(SmartField.starred, SmartOp.isOp, 'true')]), lib), ['s']);
    expect(ids(smart([rule(SmartField.starred, SmartOp.isOp, 'false')]), lib), ['h']);
    expect(ids(smart([rule(SmartField.genre, SmartOp.contains, 'kut')]), lib), ['h']);
    expect(ids(smart([rule(SmartField.composer, SmartOp.isOp, 'rahman')]), lib), ['s']);
    expect(ids(smart([rule(SmartField.artist, SmartOp.notContains, 'sriram')]), lib), ['h']);
  });

  test('length rules work in whole minutes', () {
    final lib = [facts('short', duration: 150), facts('three', duration: 200), facts('long', duration: 400)];
    expect(ids(smart([rule(SmartField.length, SmartOp.lt, '3')]), lib), ['short']);
    expect(ids(smart([rule(SmartField.length, SmartOp.eq, '3')]), lib), ['three']);
    expect(ids(smart([rule(SmartField.length, SmartOp.gte, '3')]), lib), ['long', 'three']);
    expect(ids(smart([rule(SmartField.length, SmartOp.gt, '3')]), lib), ['long']);
  });

  test('OR groups and nested groups', () {
    final lib = [
      facts('a', year: 2010, starred: true),
      facts('b', year: 2022, mood: 'sad'),
      facts('c', year: 2022),
    ];
    final any = smart([
      rule(SmartField.starred, SmartOp.isOp, 'true'),
      rule(SmartField.mood, SmartOp.isOp, 'sad'),
    ], all: false);
    expect(ids(any, lib), ['a', 'b']);

    // year >= 2020 AND (starred OR sad)
    final nested = smart([
      rule(SmartField.year, SmartOp.gte, '2020'),
      SmartGroup(matchAll: false, children: [
        rule(SmartField.starred, SmartOp.isOp, 'true'),
        rule(SmartField.mood, SmartOp.isOp, 'sad'),
      ]),
    ]);
    expect(ids(nested, lib), ['b']);
  });

  test('incomplete rules and empty groups match everything', () {
    final lib = [facts('a'), facts('b')];
    expect(ids(smart([]), lib), ['a', 'b']);
    expect(ids(smart([rule(SmartField.title, SmartOp.contains, '  ')]), lib), ['a', 'b']);
    expect(ids(smart([const SmartGroup()]), lib), ['a', 'b']);
  });

  test('unknown year never satisfies a year rule', () {
    final lib = [facts('none', year: 0)];
    expect(ids(smart([rule(SmartField.year, SmartOp.lt, '2000')]), lib), isEmpty);
  });

  test('sort by title, year desc, play count; random keeps the same songs', () {
    final lib = [facts('b', year: 2001, playCount: 5), facts('a', year: 2010, playCount: 1), facts('c', year: 2005, playCount: 9)];
    expect(ids(smart([], sort: SmartSort.title), lib), ['a', 'b', 'c']);
    expect(ids(smart([], sort: SmartSort.year, asc: false), lib), ['a', 'c', 'b']);
    expect(ids(smart([], sort: SmartSort.playCount, asc: false), lib), ['c', 'b', 'a']);
    final shuffled = SmartEvaluator.evaluate(smart([], sort: SmartSort.random), lib, now: now, random: Random(1));
    expect(shuffled.map((f) => f.song.id).toSet(), {'a', 'b', 'c'});
  });

  test('last played sort puts never-played last when descending', () {
    final lib = [facts('never'), facts('old', playedDaysAgo: [30]), facts('new', playedDaysAgo: [1])];
    expect(ids(smart([], sort: SmartSort.lastPlayed, asc: false), lib), ['new', 'old', 'never']);
  });

  test('definitions round-trip through JSON', () {
    final original = smart([
      rule(SmartField.recentPlays, SmartOp.gte, '3', window: 7),
      SmartGroup(matchAll: false, children: [rule(SmartField.mood, SmartOp.isOp, 'sad')]),
    ], sort: SmartSort.playCount, asc: false, limit: 25).copyWith(savedPlaylistId: 'pl-9');
    final back = SmartPlaylist.fromJson(original.toJson())!;
    expect(back.toJson(), original.toJson());
    expect(back.limit, 25);
    expect(back.savedPlaylistId, 'pl-9');
    expect(back.rules.ruleCount, 2);
  });

  test('fromJson drops junk instead of throwing', () {
    expect(SmartPlaylist.fromJson('x'), isNull);
    expect(SmartPlaylist.fromJson({'id': 'server-id'}), isNull);
    final p = SmartPlaylist.fromJson({
      'id': 'smart:5',
      'rules': {
        'children': [
          {'f': 'nope', 'o': 'isOp'},
          {'f': 'year', 'o': 'gt', 'v': '2000'},
        ],
      },
    })!;
    expect(p.rules.ruleCount, 1);
  });

  test('moodFromCatalog reads words in bucket and genre', () {
    CatalogSong s({String? bucket, String? genre}) => CatalogSong(id: '1', bucket: bucket, genre: genre);
    expect(moodFromCatalog(s(bucket: 'tamil__sad__melody')), 'sad');
    expect(moodFromCatalog(s(genre: 'Kuthu / Dance')), 'energetic');
    expect(moodFromCatalog(s(genre: 'Melody')), 'calm');
    expect(moodFromCatalog(s(genre: 'Film Soundtrack')), isNull);
    expect(moodFromCatalog(null), isNull);
  });
}
