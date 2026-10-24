import 'package:audio_service/audio_service.dart';
import '../../models/album.dart';
import '../../models/playlist.dart';

/// Media ids for the Android Auto / media-browser tree.
///
/// Browsable nodes: [root], [recent], [playlists], [albums].
/// Playable leaves: [shuffle], `album:<id>`, `playlist:<id>`.
abstract final class BrowseIds {
  static const root = AudioService.browsableRootId;
  static const recent = 'browse:recent';
  static const playlists = 'browse:playlists';
  static const albums = 'browse:albums';
  static const shuffle = 'play:smart-shuffle';

  static String album(String id) => 'album:$id';
  static String playlist(String id) => 'playlist:$id';

  static String? albumIdOf(String mediaId) => _after(mediaId, 'album:');
  static String? playlistIdOf(String mediaId) => _after(mediaId, 'playlist:');

  static String? _after(String s, String prefix) =>
      s.startsWith(prefix) && s.length > prefix.length
      ? s.substring(prefix.length)
      : null;
}

/// Pure builders for the browse tree — no network, no player.
abstract final class BrowseTree {

  static List<MediaItem> rootChildren() => const [
    MediaItem(
      id: BrowseIds.shuffle,
      title: 'Smart Shuffle',
      playable: true,
    ),
    MediaItem(
      id: BrowseIds.recent,
      title: 'Recent',
      playable: false,
    ),
    MediaItem(
      id: BrowseIds.playlists,
      title: 'Playlists',
      playable: false,
    ),
    MediaItem(
      id: BrowseIds.albums,
      title: 'Albums',
      playable: false,
    ),
  ];

  /// Albums are playable leaves: tapping one in the car plays the album.
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
          playable: true,
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
          playable: true,
        ),
  ];

  /// Cover-art URL string → Uri, or null when the server gave none.
  static Uri? uriOrNull(String url) => url.isEmpty ? null : Uri.tryParse(url);
}
