import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/catalog.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/catalog_provider.dart';

// The shape GET /catalog/songs returns (keys with no value are omitted).
const _doc = '''
{
  "songs": [
    {"id": "a", "language": "ta", "languages": ["ta"], "genre": "Melody", "bucket": "Melody",
     "film": "Thuppakki", "composer": "Harris Jayaraj", "year": 2012},
    {"id": "b", "language": "ta", "languages": ["ta", "en"], "genre": "Kuthu / Dance",
     "bucket": "Kuthu / Dance", "film": "Beast", "composer": "Anirudh Ravichander"},
    {"id": "c", "language": "en", "languages": ["en"], "genre": "Pop", "bucket": "Pop"},
    {"id": "d", "language": "ko", "languages": ["ko"], "genre": "K-Pop"},
    {"id": "e", "genre": "Film Soundtrack"}
  ],
  "categories": {
    "languages": [{"code": "ta", "name": "Tamil", "count": 2}, {"code": "en", "name": "English", "count": 1},
                  {"code": "ko", "name": "Korean", "count": 1}],
    "multilingual": 1,
    "genres": [{"name": "Melody", "count": 1}, {"name": "Kuthu / Dance", "count": 1}, {"name": "Pop", "count": 1}]
  },
  "coverage": {"songs": 5, "language": 0.8, "genre": 1.0}
}
''';

Song _song(String id, {String artist = 'Someone', String album = '', int year = 0}) => Song(
      id: id,
      title: 'Song $id',
      artist: artist,
      album: album,
      albumId: '',
      artistId: '',
      genre: '',
      composer: '',
      coverArt: '',
      duration: 200,
      track: 1,
      year: year,
      starred: false,
      playCount: 0,
      rating: 0,
    );

void main() {
  final doc = CatalogDocument.fromJson(jsonDecode(_doc) as Map<String, dynamic>);

  test('parses songs and the browse categories', () {
    expect(doc.songs.length, 5);
    expect(doc.songs['b']!.isMultilingual, isTrue);
    expect(doc.songs['e']!.language, isNull);
    expect(doc.languages.map((c) => c.name), ['Tamil', 'English', 'Korean']);
    expect(doc.multilingual?.count, 1);
    expect(doc.genres.map((c) => c.key), ['Melody', 'Kuthu / Dance', 'Pop']);
  });

  test('categories select the right songs', () {
    Set<String> ids(CatalogCategory c) => {for (final s in doc.songs.values) if (c.contains(s)) s.id};
    expect(ids(doc.languages.first), {'a', 'b'}); // Tamil includes the Tamil–English song
    expect(ids(doc.multilingual!), {'b'});
    expect(ids(doc.genres[1]), {'b'});
    // a song with only a display genre is in no genre category
    expect(doc.genres.any((g) => g.contains(doc.songs['e']!)), isFalse);
  });

  test('an empty or partial document parses without throwing', () {
    final empty = CatalogDocument.fromJson(const {});
    expect(empty.songs, isEmpty);
    expect(empty.multilingual, isNull);
    expect(CatalogDocument.fromJson(const {'categories': {'multilingual': 0}}).multilingual, isNull);
  });

  test('detail line names what tags lack, without repeating the album', () {
    expect(catalogDetailLine(doc.songs['b'], _song('b', album: 'Beast')), 'Tamil + English · Kuthu / Dance');
    expect(catalogDetailLine(doc.songs['a'], _song('a', album: 'Nanban')), 'Tamil · Melody · Thuppakki · 2012');
    // the file's own year wins over the catalog's
    expect(catalogDetailLine(doc.songs['a'], _song('a', album: 'Thuppakki', year: 2013)), 'Tamil · Melody · 2013');
    expect(catalogDetailLine(null, _song('x')), '');
  });

  test('a missing artist tag falls back to the catalog composer', () {
    expect(displayArtist(_song('a', artist: 'Unknown Artist'), doc.songs['a']), 'Harris Jayaraj');
    expect(displayArtist(_song('a', artist: '[Unknown Artist]'), doc.songs['a']), 'Harris Jayaraj');
    expect(displayArtist(_song('a', artist: 'Hariharan'), doc.songs['a']), 'Hariharan');
    expect(displayArtist(_song('z', artist: 'Unknown Artist'), null), 'Unknown Artist');
  });
}
