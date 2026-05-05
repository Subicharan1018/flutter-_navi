import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_audio_tagger/flutter_audio_tagger.dart';
import '../models/song.dart';
import '../core/app_exception.dart'; // for NetworkException
import 'package:permission_handler/permission_handler.dart';

// =============================================================================
// LocalLibraryService
//
// Responsible for:
//   1. Recursively scanning user-selected directories for audio files.
//      File discovery runs in a background isolate (pure Dart, no platform
//      channels) — safe per Flutter's isolate rules.
//   2. Extracting metadata (title, artist, album, cover art) via
//      FlutterAudioTagger on the MAIN isolate — platform channels
//      (MethodChannel) must not be called from background isolates.
//   3. Returning a List<Song> with IDs prefixed "local:<absolute_path>"
//      so they never collide with Subsonic server IDs.
// =============================================================================

/// Supported audio extensions for local scanning.
const _kSupportedExtensions = {'.mp3', '.flac', '.wav', '.m4a', '.ogg', '.aac'};

// ---------------------------------------------------------------------------
// Step 1 — Isolate worker (pure Dart / no platform channels)
// ---------------------------------------------------------------------------

/// Top-level function required by Isolate.run.
/// Returns only the list of absolute file paths — no metadata reading here.
List<String> _discoverFilePaths(List<String> folderPaths) {
  final paths = <String>[];
  for (final folderPath in folderPaths) {
    try {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) {
        print('Directory does not exist: $folderPath');
        continue;
      }

      // Use listSync with followLinks: false for safety.
      // We catch exceptions inside the loop in case a specific subdirectory is restricted.
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          final lower = entity.path.toLowerCase();
          if (_kSupportedExtensions.any((ext) => lower.endsWith(ext))) {
            paths.add(entity.path);
          }
        }
      }
    } catch (e) {
      print('Error scanning directory $folderPath: $e');
      // Continue to next folder instead of crashing the whole isolate
    }
  }
  print('Discovery finished. Found ${paths.length} potential audio files.');
  return paths;
}

/// Extracts filename without extension.
String _filenameWithoutExt(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dotIdx = name.lastIndexOf('.');
  return dotIdx > 0 ? name.substring(0, dotIdx) : name;
}

// ---------------------------------------------------------------------------
// LocalLibraryService
// ---------------------------------------------------------------------------

class LocalLibraryService {
  final _tagger = FlutterAudioTagger();

  /// Resolves the per-app cover-art cache directory.
  Future<String> _artCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final artDir = Directory('${appDir.path}/local_art_cache');
    if (!artDir.existsSync()) artDir.createSync(recursive: true);
    return artDir.path;
  }

  /// Recursively scans [folderPaths] for supported audio files.
  ///
  /// File discovery runs in a background isolate to avoid UI jank.
  /// Metadata is extracted on the main isolate (required by MethodChannel).
  ///
  /// Returns a list of [Song] objects with IDs prefixed `local:`.
  /// Throws [AppException] if no folders are provided.
  Future<List<Song>> scanFolders(List<String> folderPaths) async {
    if (folderPaths.isEmpty) {
      throw const NetworkException(
        'No local folders configured. Add folders in Settings.',
      );
    }

    if (Platform.isAndroid) {
      final audioStatus = await Permission.audio.request();
      final storageStatus = await Permission.storage.request();

      if (!audioStatus.isGranted && !storageStatus.isGranted) {
        throw const NetworkException(
          'Storage permission is required to read music files. Please grant it in app settings.',
        );
      }
    }

    // Step 1: discover file paths in isolate (pure Dart, no platform channels).
    final List<String> paths;
    try {
      paths = await Isolate.run(() => _discoverFilePaths(folderPaths));
    } catch (e) {
      throw NetworkException('Directory scan failed: $e');
    }

    if (paths.isEmpty) return [];

    // Step 2: read metadata on main isolate (MethodChannel constraint).
    final artDir = await _artCacheDir();
    final songs = <Song>[];

    print('Starting metadata extraction for ${paths.length} files...');
    for (int i = 0; i < paths.length; i++) {
      final path = paths[i];
      if (i % 10 == 0) print('Extracting metadata... ($i/${paths.length})');
      songs.add(await _readSong(path, artDir));
    }
    print('Scan complete. Successfully processed ${songs.length} songs.');
    return songs;
  }

  /// Reads metadata for a single file and converts it to [Song].
  Future<Song> _readSong(String path, String artCacheDir) async {
    String title = _filenameWithoutExt(path);
    String artist = 'Unknown Artist';
    String album = 'Unknown Album';
    String genre = '';
    String composer = '';
    String coverArtPath = '';

    try {
      // getTags is lighter (no artwork bytes) — use it first.
      final Map<dynamic, dynamic>? tags = await _tagger.getTags(path);
      if (tags != null) {
        title = (tags['title']?.toString().isNotEmpty == true)
            ? tags['title'].toString()
            : title;
        artist = (tags['artist']?.toString().isNotEmpty == true)
            ? tags['artist'].toString()
            : artist;
        album = (tags['album']?.toString().isNotEmpty == true)
            ? tags['album'].toString()
            : album;
        genre = tags['genre']?.toString() ?? '';
        composer = tags['composer']?.toString() ?? '';
      }

      // Artwork — try separately; if it fails we skip without crashing.
      try {
        final artwork = await _tagger.getArtWork(path);
        if (artwork != null && artwork.isNotEmpty) {
          final artFile = File('$artCacheDir/${path.hashCode.abs()}.jpg');
          if (!artFile.existsSync()) {
            await artFile.writeAsBytes(artwork);
          }
          coverArtPath = artFile.path;
        }
      } catch (_) {
        // Artwork read failed — no cover art, that's fine.
      }
    } catch (_) {
      // Full metadata read failed — use filename only, still add the song.
    }

    final ext = path.split('.').last.toLowerCase();
    return Song(
      id: 'local:$path',
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      composer: composer,
      track: 0,
      duration: 0,
      coverArt: coverArtPath,
      year: 0,
      path: path,
      isLocal: true,
      suffix: ext,
      contentType: 'audio/$ext',
    );
  }

  /// Returns `true` if [id] represents a local-scanned song.
  static bool isLocalId(String id) => id.startsWith('local:');

  /// Extracts the absolute file path from a local song ID.
  static String pathFromId(String id) => id.replaceFirst('local:', '');
}
