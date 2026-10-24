import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/artist.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/auto/browse_tree.dart';

Song song(String id, String title, {String artist = 'A'}) => Song(
  id: id,
  title: title,
  artist: artist,
  album: 'Al',
  coverArt: 'c$id',
  duration: 100,
  track: 1,
  year: 2020,
);

void main() {
  Uri? art(String c) =>
      BrowseTree.uriOrNull(c.isEmpty ? '' : 'https://x/getCoverArt?id=$c');

  test('root is four tabs; home carries the three shortcuts', () {
    expect(BrowseTree.rootChildren().map((e) => e.id), [
      BrowseIds.home,
      BrowseIds.playlists,
      BrowseIds.albums,
      BrowseIds.artists,
    ]);
    final home = BrowseTree.homeChildren();
    expect(home.take(3).map((e) => e.id), [
      BrowseIds.smartShuffle,
      BrowseIds.discover,
      BrowseIds.flow,
    ]);
    expect(home.take(3).every((e) => e.playable == true), isTrue);
    expect(home.skip(3).every((e) => e.playable == false), isTrue);
  });

  test('albums, playlists and artists are folders with ids and art', () {
    final albums = BrowseTree.albumItems([
      Album(id: 'a1', name: 'N', artist: 'A', coverArt: 'c1', songCount: 1, duration: 1),
      Album(id: '', name: 'bad', artist: '', coverArt: '', songCount: 0, duration: 0),
    ], art);
    expect(albums.length, 1);
    expect(albums.single.playable, isFalse);
    expect(BrowseIds.albumIdOf(albums.single.id), 'a1');
    expect(albums.single.artUri.toString(), contains('getCoverArt'));

    final pl = BrowseTree.playlistItems([
      Playlist(id: 'p1', name: 'P', comment: '', songCount: 3, duration: 9),
    ], art);
    expect(BrowseIds.playlistIdOf(pl.single.id), 'p1');
    expect(pl.single.artUri, isNull);

    final ar = BrowseTree.artistItems([
      const Artist(id: '7', name: 'X', albumCount: 2),
    ], art);
    expect(BrowseIds.artistIdOf(ar.single.id), '7');
  });

  test('song items: play all and shuffle first; ids round-trip with context', () {
    final items = BrowseTree.songItems('album:9', [song('s1', 'One'), song('s2', 'Two')], art);
    expect(items.map((e) => e.id).take(2), ['playctx:album:9', 'shufflectx:album:9']);
    final parsed = BrowseIds.songOf(items[2].id)!;
    expect(parsed.ctx, 'album:9');
    expect(parsed.songId, 's1');
    expect(BrowseIds.playContextOf('playctx:album:9'), 'album:9');
    expect(BrowseIds.shuffleContextOf('shufflectx:starred'), 'starred');
    expect(BrowseTree.songItems('x', const [], art), isEmpty);
  });

  test('id parsing rejects malformed ids', () {
    expect(BrowseIds.albumIdOf('playlist:1'), isNull);
    expect(BrowseIds.albumIdOf('album:'), isNull);
    expect(BrowseIds.songOf('song:album:1'), isNull);
    expect(BrowseIds.songOf('song:|x'), isNull);
  });

  test('letters: A to Z plus #, sorted, capped', () {
    expect(BrowseTree.letters.length, 27);
    final all = [
      song('1', 'beta'),
      song('2', 'Alpha'),
      song('3', '9 lives'),
      song('4', 'apple'),
      song('5', '  '),
    ];
    expect(BrowseTree.songsForLetter(all, 'A').map((s) => s.id), ['2', '4']);
    expect(BrowseTree.songsForLetter(all, '#').map((s) => s.id).toSet(), {'3', '5'});
    expect(BrowseTree.songsForLetter(all, 'A', max: 1).length, 1);
  });

  test('car art goes through the content provider; other schemes pass through', () {
    final net = CarArt.proxy(Uri.parse('https://h/rest/getCoverArt.view?id=1&t=x'))!;
    expect(net.scheme, 'content');
    expect(net.host, CarArt.authority);
    expect(net.path, '/net');
    expect(net.queryParameters['u'], 'https://h/rest/getCoverArt.view?id=1&t=x');
    final file = CarArt.proxy(Uri.file('/data/app_flutter/a.jpg'))!;
    expect(file.path, '/file');
    expect(CarArt.proxy(Uri.parse('content://x/y')).toString(), 'content://x/y');
    expect(CarArt.proxy(null), isNull);
    expect(CarArt.proxy(Uri.parse('https://h/a'), enabled: false).toString(), 'https://h/a');
  });

  group('voice', () {
    final artists = [const Artist(id: 'r', name: 'Radiohead')];
    final albums = [
      Album(id: 'ok', name: 'OK Computer', artist: 'Radiohead', coverArt: '', songCount: 12, duration: 1),
    ];
    VoiceTarget pick(String q, {String? focus, String? artistHint, List<Song>? songs}) =>
        VoiceSearch.choose(
          query: q,
          focus: focus,
          artistHint: artistHint,
          songs: songs ?? const [],
          albums: albums,
          artists: artists,
        );

    test('empty query plays Smart Shuffle', () => expect(pick('').kind, VoiceKind.shuffle));
    test('artist name picks the artist', () {
      expect(pick('radiohead').kind, VoiceKind.artist);
      expect(pick('radiohead').id, 'r');
    });
    test('album name picks the album', () => expect(pick('ok computer').kind, VoiceKind.album));
    test('exact song title beats loose matches', () {
      expect(pick('radiohead', songs: [song('1', 'Radiohead')]).kind, VoiceKind.songs);
    });
    test('focus steers the choice', () {
      expect(
        pick('ok computer', focus: 'song', songs: [song('1', 'OK Computer remix')]).kind,
        VoiceKind.songs,
      );
      expect(pick('x', focus: 'artist', artistHint: 'Radiohead').kind, VoiceKind.artist);
    });
    test('nothing found', () => expect(pick('zzz').kind, VoiceKind.none));
    test('focus mime mapping', () {
      expect(VoiceSearch.focusOf('vnd.android.cursor.item/artist'), 'artist');
      expect(VoiceSearch.focusOf('other'), isNull);
    });
  });
}
