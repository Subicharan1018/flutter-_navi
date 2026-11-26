import 'package:flutter/foundation.dart';

/// In-memory map from song id to the file on this device, read by playback
/// and artwork code that runs far from any provider (the audio handler is
/// built before the first widget). Rebuilt from the database after each scan
/// and match; lookups are plain map reads.
///
/// A server song that also exists on the device is registered under its
/// server id too, so the same queue entry plays the local file.
class LocalLibraryIndex {
  LocalLibraryIndex._();
  static final LocalLibraryIndex instance = LocalLibraryIndex._();

  Map<String, String> _paths = const {};
  Map<String, String> _covers = const {};

  /// Bumps whenever the index changes, so tiles drawn before it finished
  /// loading repaint with the covers it holds.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// File path or `content://` URI to play for [songId], if one is on the
  /// device.
  String? pathFor(String songId) => _paths[songId] ?? _opened[songId];

  /// Files registered one by one. Kept apart from the scanned library: that
  /// loads a moment after launch, and replacing it used to drop the file the
  /// app had just been opened with, which was then asked of the server.
  final Map<String, String> _opened = {};

  /// Saved cover of a local song (by its `local:` id).
  String? coverFor(String songId) => _covers[songId];

  int get length => _paths.length;

  void replace({required Map<String, String> paths, required Map<String, String> covers}) {
    _paths = Map.unmodifiable(paths);
    _covers = Map.unmodifiable(covers);
    revision.value++;
  }

  /// Adds one file (for example one opened from a file manager) without
  /// touching the scanned library.
  void register(String songId, String path) {
    _opened[songId] = path;
    revision.value++;
  }

  /// Forgets everything, opened files too.
  void clear() {
    _opened.clear();
    replace(paths: const {}, covers: const {});
  }

  /// What `just_audio` opens for a stored location.
  static Uri uriFor(String path) => path.startsWith('content://') ? Uri.parse(path) : Uri.file(path);
}

const _pendingCover = 'local-cover:';

/// What `getCoverArtUrl` returns for a device song whose cover is not in the
/// index yet (the index loads after the first screens draw). `CoverArt` turns
/// it into the file once the index has it, so no screen has to watch.
String pendingLocalCoverUrl(String songId) => '$_pendingCover$songId';

/// The song id inside [pendingLocalCoverUrl], or null for any other url.
String? pendingLocalCoverId(String url) => url.startsWith(_pendingCover) ? url.substring(_pendingCover.length) : null;

/// The folder a scanned path sits in. Works for file paths and for SAF
/// document URIs, whose separators are `%2F`.
String parentOf(String path) {
  final slash = path.lastIndexOf('/');
  final enc = path.toLowerCase().lastIndexOf('%2f');
  final cut = slash > enc ? slash : enc;
  return cut <= 0 ? '' : path.substring(0, cut);
}

/// Gives songs without art the art of a sibling: another track in the same
/// folder first, then another track of the same album and album artist.
/// "Unknown Album" never groups songs by album, only by folder.
class AlbumCoverFallback {
  final Map<String, String> _byDir = {};
  final Map<String, String> _byAlbum = {};
  // Albums that have art inside each folder: a flat folder holding several
  // albums must not lend one album's cover to the others.
  final Map<String, Set<String>> _dirAlbums = {};

  AlbumCoverFallback(Iterable<({String path, String album, String albumArtist, String? cover})> rows) {
    for (final r in rows) {
      final cover = r.cover;
      if (cover == null) continue;
      final dir = parentOf(r.path);
      _byDir.putIfAbsent(dir, () => cover);
      _dirAlbums.putIfAbsent(dir, () => {}).add(r.album.trim().toLowerCase());
      final key = _albumKey(r.album, r.albumArtist);
      if (key != null) _byAlbum.putIfAbsent(key, () => cover);
    }
  }

  static String? _albumKey(String album, String artist) {
    final a = album.trim().toLowerCase();
    if (a.isEmpty || a == 'unknown album') return null;
    return '$a|${artist.trim().toLowerCase()}';
  }

  String? coverFor({required String path, required String album, required String albumArtist}) {
    final dir = parentOf(path);
    final key = _albumKey(album, albumArtist);
    final albums = _dirAlbums[dir];
    final sameFolder = dir.isNotEmpty && albums != null && albums.length == 1 && albums.first == album.trim().toLowerCase();
    return (sameFolder ? _byDir[dir] : null) ?? (key == null ? null : _byAlbum[key]);
  }
}
