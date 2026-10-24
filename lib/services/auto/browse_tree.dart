import 'package:audio_service/audio_service.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';

/// Media ids for the Android Auto / media-browser tree.
///
/// Folders (browsable): [home], [playlists], [albums], [artists], [recent],
/// [songs], [starred], `letter:<L>`, `album:<id>`, `artist:<id>`,
/// `playlist:<id>`. Leaves (playable): shortcuts, `song:<ctx>|<songId>`,
/// `playctx:<ctx>` and `shufflectx:<ctx>`.
///
/// A *context* names a list of songs a leaf plays from: `album:<id>`,
/// `playlist:<id>`, `artist:<id>`, `letter:<L>`, `starred`, `single`.
abstract final class BrowseIds {
  static const root = AudioService.browsableRootId;
  static const home = 'browse:home';
  static const recent = 'browse:recent';
  static const playlists = 'browse:playlists';
  static const albums = 'browse:albums';
  static const artists = 'browse:artists';
  static const songs = 'browse:songs';
  static const starred = 'browse:starred';

  static const smartShuffle = 'play:smart-shuffle';
  static const discover = 'play:discover';
  static const flow = 'play:flow';
  static const notice = 'notice';

  static const ctxStarred = 'starred';
  static const ctxSingle = 'single';

  static String album(String id) => 'album:$id';
  static String artist(String id) => 'artist:$id';
  static String playlist(String id) => 'playlist:$id';
  static String letter(String l) => 'letter:$l';
  static String song(String ctx, String songId) => 'song:$ctx|$songId';
  static String playContext(String ctx) => 'playctx:$ctx';
  static String shuffleContext(String ctx) => 'shufflectx:$ctx';

  static String? _after(String s, String prefix) =>
      s.startsWith(prefix) && s.length > prefix.length
      ? s.substring(prefix.length)
      : null;

  static String? albumIdOf(String id) => _after(id, 'album:');
  static String? artistIdOf(String id) => _after(id, 'artist:');
  static String? playlistIdOf(String id) => _after(id, 'playlist:');
  static String? letterOf(String id) => _after(id, 'letter:');

  /// `song:<ctx>|<songId>` → (ctx, songId).
  static ({String ctx, String songId})? songOf(String id) {
    final rest = _after(id, 'song:');
    final bar = rest?.lastIndexOf('|') ?? -1;
    if (rest == null || bar <= 0 || bar == rest.length - 1) return null;
    return (ctx: rest.substring(0, bar), songId: rest.substring(bar + 1));
  }

  static String? playContextOf(String id) => _after(id, 'playctx:');
  static String? shuffleContextOf(String id) => _after(id, 'shufflectx:');
}

/// Browse content-style hints (androidx.media constants), set on a folder to
/// choose how the car lays out *its children*.
abstract final class CarStyle {
  static const supported = 'android.media.browse.CONTENT_STYLE_SUPPORTED';
  static const browsableHint =
      'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
  static const playableHint = 'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
  static const list = 1;
  static const grid = 2;

  /// Root extras: lets the car honour the per-folder hints.
  static const rootExtras = <String, dynamic>{
    supported: true,
    browsableHint: grid,
    playableHint: list,
  };

  static Map<String, dynamic> children({int browsable = list, int playable = list}) => {
    supported: true,
    browsableHint: browsable,
    playableHint: playable,
  };
}

/// Maps artwork URIs to the app's `content://` art provider, which the car
/// host can always read (it can't fetch a server URL with a token, or read an
/// app-private file).
abstract final class CarArt {
  static const authority = 'com.navivibe.navivibe.art';

  static Uri? proxy(Uri? art, {bool enabled = true}) {
    if (art == null || !enabled) return art;
    switch (art.scheme) {
      case 'http':
      case 'https':
        return Uri(
          scheme: 'content',
          host: authority,
          path: '/net',
          queryParameters: {'u': art.toString()},
        );
      case 'file':
        return Uri(
          scheme: 'content',
          host: authority,
          path: '/file',
          queryParameters: {'p': art.toFilePath()},
        );
      default:
        return art;
    }
  }
}

/// Pure builders for the browse tree — no network, no player.
abstract final class BrowseTree {
  static Uri? uriOrNull(String url) => url.isEmpty ? null : Uri.tryParse(url);

  static final letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split('');

  /// The four top-level tabs the car shows.
  static List<MediaItem> rootChildren() => [
    MediaItem(
      id: BrowseIds.home,
      title: 'Home',
      playable: false,
      extras: CarStyle.children(browsable: CarStyle.list, playable: CarStyle.list),
    ),
    MediaItem(
      id: BrowseIds.playlists,
      title: 'Playlists',
      playable: false,
      extras: CarStyle.children(browsable: CarStyle.grid),
    ),
    MediaItem(
      id: BrowseIds.albums,
      title: 'Albums',
      playable: false,
      extras: CarStyle.children(browsable: CarStyle.grid),
    ),
    MediaItem(
      id: BrowseIds.artists,
      title: 'Artists',
      playable: false,
      extras: CarStyle.children(browsable: CarStyle.list),
    ),
  ];

  static List<MediaItem> homeChildren() => [
    const MediaItem(id: BrowseIds.smartShuffle, title: 'Smart Shuffle', artist: 'Mixed from your library', playable: true),
    const MediaItem(id: BrowseIds.discover, title: 'Discover', artist: 'New and unplayed', playable: true),
    const MediaItem(id: BrowseIds.flow, title: 'Flow', artist: 'Keeps going from what you play', playable: true),
    MediaItem(
      id: BrowseIds.recent,
      title: 'Recent',
      playable: false,
      extras: CarStyle.children(browsable: CarStyle.grid),
    ),
    MediaItem(
      id: BrowseIds.starred,
      title: 'Liked Songs',
      playable: false,
      extras: CarStyle.children(),
    ),
    MediaItem(
      id: BrowseIds.songs,
      title: 'Songs A–Z',
      playable: false,
      extras: CarStyle.children(),
    ),
  ];

  static List<MediaItem> letterFolders() => [
    for (final l in letters)
      MediaItem(id: BrowseIds.letter(l), title: l, playable: false, extras: CarStyle.children()),
  ];

  /// Albums are folders; opening one lists its songs.
  static List<MediaItem> albumItems(
    List<Album> albums,
    Uri? Function(String coverArt) artUri,
  ) => [
    for (final a in albums)
      if (a.id.isNotEmpty)
        MediaItem(
          id: BrowseIds.album(a.id),
          title: a.name,
          artist: a.artist,
          artUri: artUri(a.coverArt),
          playable: false,
          extras: CarStyle.children(),
        ),
  ];

  static List<MediaItem> playlistItems(
    List<Playlist> playlists,
    Uri? Function(String coverArt) artUri,
  ) => [
    for (final p in playlists)
      if (p.id.isNotEmpty)
        MediaItem(
          id: BrowseIds.playlist(p.id),
          title: p.name,
          album: '${p.songCount} songs',
          artUri: (p.coverArt ?? '').isEmpty ? null : artUri(p.coverArt!),
          playable: false,
          extras: CarStyle.children(),
        ),
  ];

  static List<MediaItem> artistItems(
    List<Artist> artists,
    Uri? Function(String coverArt) artUri,
  ) => [
    for (final a in artists)
      if (a.id.isNotEmpty)
        MediaItem(
          id: BrowseIds.artist(a.id),
          title: a.name,
          artist: a.albumCount > 0 ? '${a.albumCount} albums' : null,
          artUri: artUri(a.coverArtId),
          playable: false,
          extras: CarStyle.children(browsable: CarStyle.grid),
        ),
  ];

  /// Songs of [ctx]: "Play all" and "Shuffle" first, then each song, which
  /// plays the whole context starting there.
  static List<MediaItem> songItems(
    String ctx,
    List<Song> songs,
    Uri? Function(String coverArt) artUri, {
    bool withPlayAll = true,
  }) => [
    if (withPlayAll && songs.isNotEmpty) ...[
      MediaItem(id: BrowseIds.playContext(ctx), title: 'Play all', playable: true),
      MediaItem(id: BrowseIds.shuffleContext(ctx), title: 'Shuffle', playable: true),
    ],
    for (final s in songs)
      if (s.id.isNotEmpty) songItem(ctx, s, artUri),
  ];

  static MediaItem songItem(String ctx, Song s, Uri? Function(String) artUri) =>
      MediaItem(
        id: BrowseIds.song(ctx, s.id),
        title: s.title,
        artist: s.artist,
        album: s.album,
        genre: s.genre.isEmpty ? null : s.genre,
        duration: s.duration > 0 ? Duration(seconds: s.duration) : null,
        artUri: artUri(s.coverArt),
        playable: true,
      );

  /// A single non-actionable line, for "sign in" / "can't reach server".
  static List<MediaItem> notice(String text) => [
    MediaItem(id: BrowseIds.notice, title: text, playable: true),
  ];

  /// Songs whose title begins with [letter] (`#` = anything not A–Z).
  static List<Song> songsForLetter(List<Song> all, String letter, {int max = 200}) {
    bool matches(Song s) {
      final first = s.title.trim().isEmpty ? '' : s.title.trim()[0].toUpperCase();
      final isAz = first.compareTo('A') >= 0 && first.compareTo('Z') <= 0 && first.length == 1;
      return letter == '#' ? !isAz : first == letter;
    }

    final out = all.where(matches).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return out.length > max ? out.sublist(0, max) : out;
  }
}

/// What a spoken request ("play Radiohead", "play OK Computer") should play.
enum VoiceKind { none, shuffle, songs, album, artist }

class VoiceTarget {
  final VoiceKind kind;
  final List<Song> songs;
  final String? id;
  const VoiceTarget(this.kind, {this.songs = const [], this.id});
  static const none = VoiceTarget(VoiceKind.none);
}

abstract final class VoiceSearch {
  /// Chooses what to play from search results. [focus] is the structured
  /// hint Android sends (`artist`, `album`, `song`, `playlist`, `genre`).
  /// An empty query means "play some music".
  static VoiceTarget choose({
    required String query,
    String? focus,
    String? artistHint,
    String? albumHint,
    required List<Song> songs,
    required List<Album> albums,
    required List<Artist> artists,
  }) {
    if (query.trim().isEmpty && (artistHint ?? albumHint ?? '').isEmpty) {
      return const VoiceTarget(VoiceKind.shuffle);
    }
    final q = query.trim().toLowerCase();
    Artist? artist() {
      final want = (artistHint ?? query).trim().toLowerCase();
      for (final a in artists) {
        if (a.name.toLowerCase() == want) return a;
      }
      for (final a in artists) {
        if (a.name.toLowerCase().contains(want) || want.contains(a.name.toLowerCase())) return a;
      }
      return null;
    }

    Album? album() {
      final want = (albumHint ?? query).trim().toLowerCase();
      for (final a in albums) {
        if (a.name.toLowerCase() == want) return a;
      }
      for (final a in albums) {
        if (a.name.toLowerCase().contains(want)) return a;
      }
      return null;
    }

    VoiceTarget byArtist() {
      final a = artist();
      return a == null ? VoiceTarget.none : VoiceTarget(VoiceKind.artist, id: a.id);
    }

    VoiceTarget byAlbum() {
      final a = album();
      return a == null ? VoiceTarget.none : VoiceTarget(VoiceKind.album, id: a.id);
    }

    VoiceTarget bySongs() => songs.isEmpty
        ? VoiceTarget.none
        : VoiceTarget(VoiceKind.songs, songs: songs);

    final order = switch (focus) {
      'artist' => [byArtist, byAlbum, bySongs],
      'album' => [byAlbum, byArtist, bySongs],
      'song' => [bySongs, byAlbum, byArtist],
      _ =>
        // No hint: an exact title match beats a loose artist/album match.
        songs.any((s) => s.title.toLowerCase() == q)
            ? [bySongs, byArtist, byAlbum]
            : [byArtist, byAlbum, bySongs],
    };
    for (final attempt in order) {
      final t = attempt();
      if (t.kind != VoiceKind.none) return t;
    }
    return VoiceTarget.none;
  }

  /// Android's `MediaStore.EXTRA_MEDIA_FOCUS` mime → our focus word.
  static String? focusOf(String? mime) => switch (mime) {
    'vnd.android.cursor.item/audio' => 'song',
    'vnd.android.cursor.item/album' => 'album',
    'vnd.android.cursor.item/artist' => 'artist',
    'vnd.android.cursor.item/playlist' => 'playlist',
    _ => null,
  };
}
