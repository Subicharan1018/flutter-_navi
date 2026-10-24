import 'local_models.dart';

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

  /// File path or `content://` URI to play for [songId], if one is on the
  /// device.
  String? pathFor(String songId) => _paths[songId];

  /// Saved cover of a local song (by its `local:` id).
  String? coverFor(String songId) => _covers[songId];

  int get length => _paths.length;

  void replace({required Map<String, String> paths, required Map<String, String> covers}) {
    _paths = Map.unmodifiable(paths);
    _covers = Map.unmodifiable(covers);
  }

  void clear() => replace(paths: const {}, covers: const {});

  /// What `just_audio` opens for a stored location.
  static Uri uriFor(String path) => path.startsWith('content://') ? Uri.parse(path) : Uri.file(path);

  /// Ids whose cover is a device file (see [coverFor]).
  static bool hasLocalCover(String coverArtId) => isLocalSongId(coverArtId);
}
