import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/artist.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/auto/browse_tree.dart';
import 'package:navivibe/services/auto/car_browser.dart';

Song mkSong(String id, String title) => Song(
  id: id,
  title: title,
  artist: 'A',
  album: 'Al',
  coverArt: 'c$id',
  duration: 100,
  track: 1,
  year: 2020,
);

Album mkAlbum(String id, String name) =>
    Album(id: id, name: name, artist: 'A', coverArt: 'c', songCount: 3, duration: 1);

class FakeLibrary implements CarLibrary {
  bool signedIn = true;
  bool failing = false;
  int allSongsCalls = 0;
  final albumsById = {
    'al1': [mkSong('s1', 'One'), mkSong('s2', 'Two'), mkSong('s3', 'Three')],
  };

  T _ok<T>(T v) {
    if (failing) throw Exception('offline');
    return v;
  }

  @override
  bool get isSignedIn => signedIn;
  @override
  Uri? artUri(String c) => Uri.parse('https://x/getCoverArt?id=$c');
  @override
  Future<List<Album>> recentAlbums() async => _ok([mkAlbum('al1', 'N')]);
  @override
  Future<List<Album>> albums() => recentAlbums();
  @override
  Future<List<Playlist>> playlists() async =>
      _ok([Playlist(id: 'p1', name: 'P', comment: '', songCount: 1, duration: 1)]);
  @override
  Future<List<Artist>> artists() async => _ok([const Artist(id: 'r', name: 'Radiohead')]);
  @override
  Future<List<Album>> artistAlbums(String id) => recentAlbums();
  @override
  Future<List<Song>> albumSongs(String id) async => _ok(albumsById[id] ?? <Song>[]);
  @override
  Future<List<Song>> playlistSongs(String id) async => _ok([mkSong('s9', 'Nine')]);
  @override
  Future<List<Song>> starredSongs() async => _ok([mkSong('s7', 'Liked')]);
  @override
  Future<List<Song>> allSongs() async {
    allSongsCalls++;
    return _ok([mkSong('a', 'Alpha'), mkSong('b', 'Beta')]);
  }

  @override
  Future<List<Song>> randomSongs(int n) async => _ok([mkSong('r1', 'Rand')]);
  @override
  Future<List<Song>> newestSongs(int n) async => _ok([mkSong('n1', 'New')]);
  @override
  Future<List<Song>> similarSongs(String id, int n) async =>
      _ok([mkSong('x1', 'Sim'), mkSong(id, 'Self')]);
  @override
  Future<Song?> song(String id) async => mkSong(id, 'T$id');
  @override
  Future<({List<Song> songs, List<Album> albums, List<Artist> artists})> search(String q) async =>
      _ok((
        songs: [mkSong('s1', 'One')],
        albums: [mkAlbum('al1', 'One Album')],
        artists: <Artist>[],
      ));
}

void main() {
  late FakeLibrary lib;
  Song? current;
  String? last;
  late CarBrowser car;

  setUp(() {
    lib = FakeLibrary();
    current = null;
    last = null;
    car = CarBrowser(lib, currentSong: () => current, lastSongId: () => last);
  });

  test('root works signed out; folders then show a sign-in notice', () async {
    lib.signedIn = false;
    expect((await car.children(BrowseIds.root)).length, 4);
    final n = await car.children(BrowseIds.playlists);
    expect(n.single.title, contains('sign in'));
  });

  test('server failure becomes a notice, not an exception', () async {
    lib.failing = true;
    final n = await car.children(BrowseIds.albums);
    expect(n.single.title, contains('reach'));
    expect(await car.resolve(BrowseIds.smartShuffle), isNull);
  });

  test('album folder lists play-all, shuffle, then songs', () async {
    final items = await car.children('album:al1');
    expect(items.length, 5);
    expect(items.first.id, 'playctx:album:al1');
  });

  test('tapping a song plays the album from that song', () async {
    final r = (await car.resolve(BrowseIds.song('album:al1', 's2')))!;
    expect(r.songs.length, 3);
    expect(r.startIndex, 1);
    expect(r.shuffle, isFalse);
  });

  test('shuffle context shuffles; starred and letters resolve', () async {
    expect((await car.resolve(BrowseIds.shuffleContext('album:al1')))!.shuffle, isTrue);
    expect(
      (await car.resolve(BrowseIds.playContext(BrowseIds.ctxStarred)))!.songs.single.id,
      's7',
    );
    final letter = (await car.resolve(BrowseIds.song('letter:A', 'a')))!;
    expect(letter.songs.single.id, 'a');
  });

  test('letters fetch the library once', () async {
    await car.children('letter:A');
    await car.children('letter:B');
    expect(lib.allSongsCalls, 1);
  });

  test('shortcuts: shuffle shuffles, discover is newest, flow seeds from current', () async {
    expect((await car.resolve(BrowseIds.smartShuffle))!.shuffle, isTrue);
    expect((await car.resolve(BrowseIds.discover))!.songs.single.id, 'n1');
    current = mkSong('cur', 'Cur');
    final flow = (await car.resolve(BrowseIds.flow))!;
    expect(flow.songs.first.id, 'cur');
    expect(flow.songs.where((s) => s.id == 'cur').length, 1);
    current = null;
    expect((await car.resolve(BrowseIds.flow))!.shuffle, isTrue);
  });

  test('cold start: the recent root offers the last played song', () async {
    expect(await car.children(AudioService.recentRootId), isEmpty);
    last = 'abc';
    final r = await car.children(AudioService.recentRootId);
    expect(r.single.id, BrowseIds.song(BrowseIds.ctxSingle, 'abc'));
    expect((await car.resolve(r.single.id))!.songs.single.id, 'abc');
  });

  test('search returns songs and albums; blank returns nothing', () async {
    expect((await car.search('one')).length, 2);
    expect(await car.search('  '), isEmpty);
  });

  test('voice: empty plays shuffle; query plays matches; failure plays nothing', () async {
    expect((await car.resolveVoice(''))!.shuffle, isTrue);
    expect((await car.resolveVoice('one'))!.songs.single.id, 's1');
    lib.failing = true;
    expect(await car.resolveVoice('one'), isNull);
  });

  test('notice taps do nothing', () async {
    expect(await car.resolve(BrowseIds.notice), isNull);
  });
}
