import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/services/auto/browse_tree.dart';

void main() {
  Uri? art(String c) => BrowseTree.uriOrNull(c.isEmpty ? '' : 'https://x/$c');

  test('root has shuffle shortcut plus three browsable folders', () {
    final root = BrowseTree.rootChildren();
    expect(root.map((e) => e.id), [
      BrowseIds.shuffle,
      BrowseIds.recent,
      BrowseIds.playlists,
      BrowseIds.albums,
    ]);
    expect(root.first.playable, isTrue);
    expect(root.skip(1).every((e) => e.playable == false), isTrue);
  });

  test('album and playlist items carry ids and artwork', () {
    final albums = BrowseTree.albumItems([
      Album(id: 'a1', name: 'N', artist: 'A', coverArt: 'c1', songCount: 1, duration: 1),
      Album(id: '', name: 'bad', artist: '', coverArt: '', songCount: 0, duration: 0),
    ], art);
    expect(albums.length, 1);
    expect(BrowseIds.albumIdOf(albums.single.id), 'a1');
    expect(albums.single.artUri.toString(), 'https://x/c1');

    final pl = BrowseTree.playlistItems([
      Playlist(id: 'p1', name: 'P', comment: '', songCount: 3, duration: 9),
    ], art);
    expect(BrowseIds.playlistIdOf(pl.single.id), 'p1');
    expect(pl.single.artUri, isNull);
  });

  test('id parsing rejects other prefixes', () {
    expect(BrowseIds.albumIdOf('playlist:1'), isNull);
    expect(BrowseIds.albumIdOf('album:'), isNull);
  });
}
