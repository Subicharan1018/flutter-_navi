import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/film_credits/data/film_info.dart';
import 'package:navivibe/features/film_credits/logic/credit_index.dart';
import 'package:navivibe/models/catalog.dart';
import 'package:navivibe/models/composer.dart';
import 'package:navivibe/models/song.dart';

Song song(String id, String title, String artist, {String composer = '', int track = 1, int year = 2016, String album = 'A'}) =>
    Song(id: id, title: title, artist: artist, album: album, composer: composer, coverArt: id, duration: 200, track: track, year: year);

CatalogSong meta(String id, {String? film, List<String> md = const [], List<String> ly = const [], List<String> sg = const [], String? lyricist}) =>
    CatalogSong(id: id, film: film, musicDirectors: md, lyricists: ly, singers: sg, lyricist: lyricist);

void main() {
  test('key vectors are the server\'s (derive.norm_key)', () {
    for (final (raw, key) in [('A. R. Rahman', 'arrahman'), ('Kaaki Sattai', 'kaakisattai'), ('  24 (Tamil) ', '24tamil'), ('', '')]) {
      expect(nameKey(raw), key);
    }
    expect(nameKey('காதல்'), 'காதல்'); // Tamil vowel signs are marks, not dropped
  });

  group('buildCreditIndex', () {
    final songs = [
      song('1', 'Sirikkadhey', 'Anirudh Ravichander ; Shweta Mohan', composer: 'Anirudh Ravichander', track: 2),
      song('2', 'Remo Theme', 'Anirudh Ravichander', composer: 'Anirudh Ravichander', track: 1),
      song('3', 'Alone', 'Alan Walker', year: 2015),
    ];
    final catalog = {
      '1': meta('1', film: 'Remo', md: ['Anirudh Ravichander'], ly: ['Thamarai'], sg: ['Anirudh Ravichander', 'Shweta Mohan']),
      '2': meta('2', film: 'REMO'),
      '3': meta('3'),
    };

    test('groups songs into films by key, in track order, with the most used spelling', () {
      final i = buildCreditIndex(songs, catalog, const {});
      expect(i.films.keys, ['remo']);
      final f = i.films['remo']!;
      expect([for (final s in f.songs) s.id], ['2', '1']);
      expect(f.title, anyOf('Remo', 'REMO'));
      expect(f.year, 2016);
      expect(i.filmOf, {'1': 'remo', '2': 'remo'}); // a song with no film stays out: unknown stays unknown
      expect(f.musicDirectors, ['Anirudh Ravichander']);
    });

    test('server facts win for year and music directors, and expose the missing soundtrack tracks', () {
      final info = FilmInfo(title: 'Remo', year: 2017, musicDirectors: const ['A. Ravichander'], tracklist: const [
        TrackStub(title: 'Sirikkadhey'),
        TrackStub(title: 'Remo Theme (Instrumental)'),
        TrackStub(title: 'Unheard Song'),
      ]);
      final f = buildCreditIndex(songs, catalog, {'remo': info}).films['remo']!;
      expect(f.year, 2017);
      expect(f.musicDirectors, ['A. Ravichander']);
      expect([for (final t in f.missing) t.title], ['Unheard Song']);
    });

    test('people by role; a lyricist is not also a singer; spellings fold', () {
      final i = buildCreditIndex(songs, catalog, const {});
      final md = i.people[nameKey('Anirudh Ravichander')]!;
      expect(md.roles, [CreditRole.musicDirector, CreditRole.singer]);
      expect(md.byRole[CreditRole.musicDirector]!.length, 2);
      expect(i.people[nameKey('Thamarai')]!.roles, [CreditRole.lyricist]);
      expect(i.peopleIn(CreditRole.lyricist).map((p) => p.name), ['Thamarai']);
      expect(i.peopleIn(CreditRole.musicDirector).first.name, 'Anirudh Ravichander');
    });

    test('without server credits the library tags still give music director and singers', () {
      final i = buildCreditIndex([song('9', 't', 'Vivek ; Karthik', composer: 'Yuvan Shankar Raja')],
          {'9': meta('9', film: 'Kodi', lyricist: 'Vivek')}, const {});
      expect(i.people[nameKey('Yuvan Shankar Raja')]!.roles, [CreditRole.musicDirector]);
      expect(i.people[nameKey('Vivek')]!.roles, [CreditRole.lyricist]);
      expect(i.people[nameKey('Karthik')]!.roles, [CreditRole.singer]);
    });

    test('groupByFilm: newest film first, songs with no film last', () {
      final i = buildCreditIndex([
        song('a', 'x', 'S', year: 2010),
        song('b', 'y', 'S', year: 2018),
        song('c', 'z', 'S', year: 2018),
      ], {'a': meta('a', film: 'Old'), 'b': meta('b', film: 'New')}, const {});
      final g = groupByFilm(i, i.people[nameKey('S')]!.songs);
      expect([for (final x in g) x.film?.title], ['New', 'Old', null]);
    });
  });

  test('parseFilmInfos keys by the app\'s own key and tolerates junk', () {
    final m = parseFilmInfos(
        '{"films":[{"fk":"x","title":"Remo","year":2016,"directors":["B"],"tracklist":[{"title":"A","artist":"Z"},{"title":""}]},{"title":""},5]}');
    expect(m.keys, ['remo']);
    expect(m['remo']!.tracklist.length, 1);
    expect(parseFilmInfos('{}'), isEmpty);
  });
}
