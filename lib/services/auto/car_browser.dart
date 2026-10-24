import 'package:audio_service/audio_service.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../subsonic_service.dart';
import 'browse_tree.dart';

/// The slice of the server the car needs. Lets tests run without a network.
abstract class CarLibrary {
  bool get isSignedIn;
  Uri? artUri(String coverArt);
  Future<List<Album>> recentAlbums();
  Future<List<Album>> albums();
  Future<List<Playlist>> playlists();
  Future<List<Artist>> artists();
  Future<List<Album>> artistAlbums(String artistId);
  Future<List<Song>> albumSongs(String albumId);
  Future<List<Song>> playlistSongs(String playlistId);
  Future<List<Song>> starredSongs();
  Future<List<Song>> allSongs();
  Future<List<Song>> randomSongs(int count);
  Future<List<Song>> newestSongs(int count);
  Future<List<Song>> similarSongs(String songId, int count);
  Future<Song?> song(String id);
  Future<({List<Song> songs, List<Album> albums, List<Artist> artists})> search(String query);
}

class SubsonicCarLibrary implements CarLibrary {
  final SubsonicService Function() _service;
  SubsonicCarLibrary(this._service);
  SubsonicService get _s => _service();

  @override
  bool get isSignedIn => _s.serverUrl.isNotEmpty;
  @override
  Uri? artUri(String coverArt) =>
      BrowseTree.uriOrNull(_s.getCoverArtUrl(coverArt, size: 300));
  @override
  Future<List<Album>> recentAlbums() => _s.getAlbumList(type: 'recent', size: 30);
  @override
  Future<List<Album>> albums() => _s.getAlbumList(type: 'alphabeticalByName', size: 100);
  @override
  Future<List<Playlist>> playlists() => _s.getPlaylists();
  @override
  Future<List<Artist>> artists() async => [
    for (final m in await _s.getArtists()) Artist.fromJson(m),
  ];
  @override
  Future<List<Album>> artistAlbums(String id) => _s.getArtistAlbums(id);
  @override
  Future<List<Song>> albumSongs(String id) => _s.getAlbum(id);
  @override
  Future<List<Song>> playlistSongs(String id) => _s.getPlaylistSongs(id);
  @override
  Future<List<Song>> starredSongs() async => (await _s.getStarred()).songs;
  @override
  Future<List<Song>> allSongs() async {
    // Paged with a hard cap and a duplicate-page guard (no unbounded loops).
    final out = <Song>[];
    final seen = <String>{};
    for (var page = 0; page < 12; page++) {
      final batch = await _s.getAllSongs(size: 500, offset: page * 500);
      final fresh = batch.where((s) => seen.add(s.id)).toList();
      if (fresh.isEmpty) break;
      out.addAll(fresh);
      if (batch.length < 500) break;
    }
    return out;
  }

  @override
  Future<List<Song>> randomSongs(int n) => _s.getRandomSongs(size: n);
  @override
  Future<List<Song>> newestSongs(int n) => _s.getNewestSongs(size: n);
  @override
  Future<List<Song>> similarSongs(String id, int n) => _s.getSimilarSongs(id, count: n);
  @override
  Future<Song?> song(String id) async {
    try {
      return await _s.getSong(id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<({List<Song> songs, List<Album> albums, List<Artist> artists})> search(String q) async {
    final r = await _s.search(q);
    return (songs: r.songs, albums: r.albums, artists: r.artists);
  }
}

/// A queue the car asked to play.
class CarPlayRequest {
  final List<Song> songs;
  final int startIndex;
  final bool shuffle;
  final String? name;
  const CarPlayRequest(this.songs, {this.startIndex = 0, this.shuffle = false, this.name});
}

/// Answers the car's browse, search and play requests from the library.
/// Never throws: a failed request yields a one-line notice or no request.
class CarBrowser {
  final CarLibrary library;
  final Song? Function() currentSong;
  final String? Function() lastSongId;

  CarBrowser(this.library, {required this.currentSong, required this.lastSongId});

  List<Song>? _songCache;
  DateTime? _songCacheAt;
  static const _songCacheTtl = Duration(minutes: 15);

  Future<List<Song>> _allSongs() async {
    final at = _songCacheAt;
    if (_songCache != null && at != null && DateTime.now().difference(at) < _songCacheTtl) {
      return _songCache!;
    }
    final songs = await library.allSongs();
    _songCache = songs;
    _songCacheAt = DateTime.now();
    return songs;
  }

  // ── Browse ────────────────────────────────────────────────────────────────

  Future<List<MediaItem>> children(String parent) async {
    if (parent == BrowseIds.root) return BrowseTree.rootChildren();
    if (!library.isSignedIn) {
      return BrowseTree.notice('Open NaviVibe on your phone to sign in');
    }
    final art = library.artUri;
    try {
      switch (parent) {
        case BrowseIds.home:
          return BrowseTree.homeChildren();
        case BrowseIds.recent:
          return BrowseTree.albumItems(await library.recentAlbums(), art);
        case BrowseIds.playlists:
          return BrowseTree.playlistItems(await library.playlists(), art);
        case BrowseIds.albums:
          return BrowseTree.albumItems(await library.albums(), art);
        case BrowseIds.artists:
          return BrowseTree.artistItems(await library.artists(), art);
        case BrowseIds.songs:
          return BrowseTree.letterFolders();
        case BrowseIds.starred:
          return BrowseTree.songItems(BrowseIds.ctxStarred, await library.starredSongs(), art);
        case AudioService.recentRootId:
          return await _lastPlayed();
      }
      final album = BrowseIds.albumIdOf(parent);
      if (album != null) {
        return BrowseTree.songItems(parent, await library.albumSongs(album), art);
      }
      final playlist = BrowseIds.playlistIdOf(parent);
      if (playlist != null) {
        return BrowseTree.songItems(parent, await library.playlistSongs(playlist), art);
      }
      final artist = BrowseIds.artistIdOf(parent);
      if (artist != null) {
        return BrowseTree.albumItems(await library.artistAlbums(artist), art);
      }
      final letter = BrowseIds.letterOf(parent);
      if (letter != null) {
        return BrowseTree.songItems(
          parent,
          BrowseTree.songsForLetter(await _allSongs(), letter),
          art,
        );
      }
    } catch (_) {
      return BrowseTree.notice("Can't reach your server");
    }
    return const [];
  }

  /// Auto's "resume" row: the song that was playing when the app last ran.
  Future<List<MediaItem>> _lastPlayed() async {
    final live = currentSong();
    final id = live?.id ?? lastSongId();
    if (id == null || id.isEmpty) return const [];
    final song = live ?? await library.song(id);
    if (song == null) return const [];
    return [BrowseTree.songItem(BrowseIds.ctxSingle, song, library.artUri)];
  }

  Future<MediaItem?> item(String mediaId) async {
    for (final i in [...BrowseTree.rootChildren(), ...BrowseTree.homeChildren()]) {
      if (i.id == mediaId) return i;
    }
    final s = BrowseIds.songOf(mediaId);
    if (s != null) {
      final song = await library.song(s.songId);
      if (song != null) return BrowseTree.songItem(s.ctx, song, library.artUri);
    }
    return null;
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<List<MediaItem>> search(String query) async {
    if (query.trim().isEmpty || !library.isSignedIn) return const [];
    try {
      final r = await library.search(query);
      final art = library.artUri;
      return [
        ...BrowseTree.songItems(BrowseIds.ctxSingle, r.songs.take(15).toList(), art, withPlayAll: false),
        ...BrowseTree.albumItems(r.albums.take(8).toList(), art),
        ...BrowseTree.artistItems(r.artists.take(5).toList(), art),
      ];
    } catch (_) {
      return const [];
    }
  }

  // ── Play ──────────────────────────────────────────────────────────────────

  /// Resolves a media id (from a tap) to a queue. Null: nothing to play.
  Future<CarPlayRequest?> resolve(String mediaId) async {
    try {
      switch (mediaId) {
        case BrowseIds.smartShuffle:
          return CarPlayRequest(await library.randomSongs(60), shuffle: true, name: 'Smart Shuffle');
        case BrowseIds.discover:
          return _nonEmpty(await library.newestSongs(50), name: 'Discover');
        case BrowseIds.flow:
          return await _flow();
        case BrowseIds.notice:
          return null;
      }
      final song = BrowseIds.songOf(mediaId);
      if (song != null) return await _song(song.ctx, song.songId);
      final play = BrowseIds.playContextOf(mediaId);
      if (play != null) return _nonEmpty(await _context(play));
      final shuffle = BrowseIds.shuffleContextOf(mediaId);
      if (shuffle != null) {
        final songs = await _context(shuffle);
        return songs.isEmpty ? null : CarPlayRequest(songs, shuffle: true);
      }
      // A folder id played directly (voice, or hosts that play folders).
      return _nonEmpty(await _context(mediaId));
    } catch (_) {
      return null;
    }
  }

  CarPlayRequest? _nonEmpty(List<Song> songs, {String? name}) =>
      songs.isEmpty ? null : CarPlayRequest(songs, name: name);

  Future<List<Song>> _context(String ctx) async {
    if (ctx == BrowseIds.ctxStarred) return library.starredSongs();
    final album = BrowseIds.albumIdOf(ctx);
    if (album != null) return library.albumSongs(album);
    final playlist = BrowseIds.playlistIdOf(ctx);
    if (playlist != null) return library.playlistSongs(playlist);
    final artist = BrowseIds.artistIdOf(ctx);
    if (artist != null) return _artistSongs(artist);
    final letter = BrowseIds.letterOf(ctx);
    if (letter != null) return BrowseTree.songsForLetter(await _allSongs(), letter);
    return const [];
  }

  /// First few albums, in release order — a bounded stand-in for "all songs".
  Future<List<Song>> _artistSongs(String artistId, {int maxAlbums = 6}) async {
    final albums = (await library.artistAlbums(artistId)).take(maxAlbums);
    final out = <Song>[];
    for (final a in albums) {
      out.addAll(await library.albumSongs(a.id));
    }
    return out;
  }

  Future<CarPlayRequest?> _song(String ctx, String songId) async {
    if (ctx == BrowseIds.ctxSingle) {
      final s = await library.song(songId);
      return s == null ? null : CarPlayRequest([s]);
    }
    final songs = await _context(ctx);
    if (songs.isEmpty) return null;
    final i = songs.indexWhere((s) => s.id == songId);
    return CarPlayRequest(songs, startIndex: i < 0 ? 0 : i);
  }

  /// Radio from what's playing (or what played last); random if neither.
  Future<CarPlayRequest?> _flow() async {
    final seed = currentSong()?.id ?? lastSongId();
    if (seed != null && seed.isNotEmpty) {
      final similar = await library.similarSongs(seed, 40);
      final head = currentSong() ?? await library.song(seed);
      if (head != null && similar.isNotEmpty) {
        return CarPlayRequest([head, ...similar.where((s) => s.id != head.id)], name: 'Flow');
      }
    }
    return CarPlayRequest(await library.randomSongs(40), shuffle: true, name: 'Flow');
  }

  /// Voice request ("play Radiohead"). An empty query plays Smart Shuffle.
  Future<CarPlayRequest?> resolveVoice(
    String query, {
    String? focus,
    String? artistHint,
    String? albumHint,
  }) async {
    try {
      if (query.trim().isEmpty && (artistHint ?? albumHint ?? '').isEmpty) {
        return await resolve(BrowseIds.smartShuffle);
      }
      final r = await library.search(query.trim().isEmpty ? (artistHint ?? albumHint)! : query);
      final target = VoiceSearch.choose(
        query: query,
        focus: focus,
        artistHint: artistHint,
        albumHint: albumHint,
        songs: r.songs,
        albums: r.albums,
        artists: r.artists,
      );
      switch (target.kind) {
        case VoiceKind.shuffle:
          return await resolve(BrowseIds.smartShuffle);
        case VoiceKind.songs:
          return CarPlayRequest(target.songs);
        case VoiceKind.album:
          return _nonEmpty(await library.albumSongs(target.id!));
        case VoiceKind.artist:
          return _nonEmpty(await _artistSongs(target.id!), name: null);
        case VoiceKind.none:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}
