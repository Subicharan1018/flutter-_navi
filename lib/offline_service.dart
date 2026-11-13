import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import 'features/status/logic/download_speed.dart';
import 'features/local_library/logic/download_location.dart';
import 'services/subsonic_service.dart';

class DownloadState {
  final bool isDownloading;
  final int currentProgress;
  final int totalCount;
  final int downloadedCount;

  DownloadState({
    this.isDownloading = false,
    this.currentProgress = 0,
    this.totalCount = 0,
    this.downloadedCount = 0,
  });

  DownloadState copyWith({
    bool? isDownloading,
    int? currentProgress,
    int? totalCount,
    int? downloadedCount,
  }) {
    return DownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      currentProgress: currentProgress ?? this.currentProgress,
      totalCount: totalCount ?? this.totalCount,
      downloadedCount: downloadedCount ?? this.downloadedCount,
    );
  }
}

class OfflineService {
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;
  OfflineService._internal();

  SharedPreferences? _prefs;
  String? _offlineDir;

  bool _offlineMode = false;
  bool get isOfflineMode => _offlineMode;
  void setOfflineMode(bool value) => _offlineMode = value;

  final Set<String> _downloadedFileNames = {};

  /// Cover-art id → song whose saved `<id>.jpg` holds it. A song's cover id is
  /// often not its own id (an album track shows the album's cover), but the
  /// file is named after the song.
  final Map<String, String> _coverOwner = {};

  /// How network requests are made; tests replace it.
  @visibleForTesting
  Dio Function() dioFactory = Dio.new;

  final ValueNotifier<DownloadState> downloadState = ValueNotifier(
    DownloadState(),
  );
  bool _isBackgroundDownloadActive = false;

  static const String _keyDownloadedSongs = 'offline_downloaded_songs';

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();
    final defaultDir = resolveOfflineDir(appDocs: dir.path);
    _offlineDir = resolveOfflineDir(appDocs: dir.path, custom: _locationStore.read());

    // A chosen folder can disappear (SD card out, drive unplugged): fall back
    // to app storage rather than failing every download and playback.
    try {
      await Directory(_offlineDir!).create(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('Download folder $_offlineDir unavailable ($e); using app storage');
      _offlineDir = defaultDir;
      await Directory(_offlineDir!).create(recursive: true);
    }
    final offlineDirectory = Directory(_offlineDir!);

    _downloadedFileNames.clear();
    try {
      if (await offlineDirectory.exists()) {
        await for (final entity in offlineDirectory.list()) {
          if (entity is File) {
            _downloadedFileNames.add(entity.uri.pathSegments.last);
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning offline directory: $e');
    }
    unawaited(_indexCoverOwners());
  }

  /// Reads the saved songs' metadata to learn which cover id each saved cover
  /// file belongs to, so a tile that only knows the cover id still finds the
  /// file. Runs in the background; covers resolve by song id meanwhile.
  Future<void> _indexCoverOwners() async {
    try {
      final dir = _offlineDir;
      if (dir == null) return;
      final owners = <String, String>{};
      for (final name in _downloadedFileNames.toList()) {
        if (!name.endsWith('.jpg')) continue;
        final songId = name.substring(0, name.length - 4);
        try {
          final meta = File('$dir/$songId.song.json');
          if (!await meta.exists()) continue;
          final data = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
          final cover = data['coverArt']?.toString() ?? '';
          if (cover.isNotEmpty && cover != songId) owners[cover] = songId;
        } catch (_) {}
      }
      if (_offlineDir == dir) {
        _coverOwner
          ..clear()
          ..addAll(owners);
      }
    } catch (e) {
      debugPrint('Error indexing saved covers: $e');
    }
  }

  /// Where downloads are stored right now (null before [initialize]).
  String? get downloadsDirectory => _offlineDir;

  DownloadLocationStore _locationStore = const DownloadLocationStore();

  /// Points downloads at [parent] (a folder the user chose; `null` = app
  /// storage). With [moveExisting] the files already downloaded follow; the
  /// setting only changes once the new folder is known to be writable.
  /// Returns an error sentence for the user, or null on success.
  Future<String?> setDownloadLocation(
    String? parent, {
    bool moveExisting = false,
    void Function(int done, int total)? onProgress,
  }) async {
    if (_downloadActive()) return 'Wait for the current downloads to finish, then try again.';
    if (_offlineDir == null) await initialize();
    final docs = await getApplicationDocumentsDirectory();
    final target = resolveOfflineDir(appDocs: docs.path, custom: parent);
    final error = await checkWritable(target);
    if (error != null) return error;
    final from = _offlineDir!;
    if (moveExisting && from != target) {
      final result = await moveDirectoryFiles(from, target, onProgress: onProgress);
      if (result.failed > 0) {
        await _locationStore.write(parent);
        await initialize();
        return '${result.failed} songs couldn’t be moved and stay in the old folder.';
      }
    }
    await _locationStore.write(parent);
    await initialize();
    return null;
  }

  bool _downloadActive() => _isBackgroundDownloadActive || downloadState.value.isDownloading;

  /// Tests only: replace where the chosen folder is remembered.
  @visibleForTesting
  void useLocationStore(DownloadLocationStore store) => _locationStore = store;

  String _getSongPath(String songId, {String? suffix}) {
    final ext = (suffix != null && suffix.isNotEmpty) ? suffix.toLowerCase() : 'mp3';
    return '$_offlineDir/$songId.$ext';
  }

  String _getSongMetadataPath(String songId) {
    return '$_offlineDir/$songId.song.json';
  }

  String _getLyricsPath(String songId) {
    return '$_offlineDir/$songId.lyrics.json';
  }

  String _getCoverArtPath(String songId) {
    return '$_offlineDir/$songId.jpg';
  }

  String? getLocalCoverArtPath(String songId) {
    if (_offlineDir == null) return null;
    final filename = '$songId.jpg';
    if (_downloadedFileNames.contains(filename)) {
      return '$_offlineDir/$filename';
    }
    return null;
  }

  /// The saved cover for a song's *cover-art id* (what `Song.coverArt` holds),
  /// or null. Covers the common cases: the id is the song's own id, or it is
  /// the album/other id the song was saved with. No disk access.
  String? getLocalCoverForCoverId(String coverArtId) {
    final direct = getLocalCoverArtPath(coverArtId);
    if (direct != null) return direct;
    final owner = _coverOwner[coverArtId];
    return owner == null ? null : getLocalCoverArtPath(owner);
  }

  Future<void> saveLyrics(String songId, Map<String, dynamic> data) async {
    if (_offlineDir == null) await initialize();
    try {
      await File(_getLyricsPath(songId)).writeAsString(jsonEncode(data));
      _downloadedFileNames.add('$songId.lyrics.json');
    } catch (e) {
      debugPrint('Error saving lyrics: $e');
    }
  }

  Future<Map<String, dynamic>?> getLocalLyrics(String songId) async {
    if (_offlineDir == null) await initialize();
    try {
      final filename = '$songId.lyrics.json';
      if (!_downloadedFileNames.contains(filename)) return null;
      final file = File(_getLyricsPath(songId));
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  bool isSongDownloaded(String songId) {
    if (_offlineDir == null) return false;
    return getLocalPath(songId) != null;
  }

  /// Async, non-blocking variant of [isSongDownloaded].
  ///
  /// Uses the in-memory downloaded filenames set so it never blocks the main thread.
  Future<bool> isSongDownloadedAsync(String songId) async {
    if (_offlineDir == null) return false;
    return getLocalPath(songId) != null;
  }

  Future<List<Song>> getDownloadedSongsMetadata() async {
    if (_offlineDir == null) await initialize();
    final ids = getDownloadedSongIds();
    final List<Song> songs = [];
    for (final id in ids) {
      try {
        final file = File(_getSongMetadataPath(id));
        if (await file.exists()) {
          final data =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          songs.add(Song.fromJson(data));
        }
      } catch (e) {
        debugPrint('Error loading metadata for $id: $e');
      }
    }
    return songs;
  }

  List<String> getDownloadedSongIds() {
    return _prefs?.getStringList(_keyDownloadedSongs) ?? [];
  }

  int getDownloadedCount() {
    return getDownloadedSongIds().length;
  }

  Future<int> getDownloadedSize() async {
    if (_offlineDir == null) return 0;

    int totalSize = 0;
    final dir = Directory(_offlineDir!);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    }
    return totalSize;
  }

  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<bool> downloadSong(
    Song song,
    SubsonicService subsonicService, {
    Function(double progress)? onProgress,
  }) async {
    if (_offlineDir == null) await initialize();

    try {
      // Download original raw audio file with native format/suffix
      final url = subsonicService.getStreamUrl(song.id);
      final ext = song.suffix.isNotEmpty ? song.suffix.toLowerCase() : 'mp3';
      final filePath = _getSongPath(song.id, suffix: ext);

      final dio = dioFactory();
      // BUG-2 FIX: Without timeouts, Dio hangs indefinitely on no-network,
      // leaving the download state stuck at "downloading" forever.
      dio.options.connectTimeout = const Duration(seconds: 15);
      dio.options.receiveTimeout = const Duration(seconds: 120);
      DownloadSpeedMeter.instance.startFile();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          DownloadSpeedMeter.instance.record(received);
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      _downloadedFileNames.add('${song.id}.$ext');

      final downloadedIds = getDownloadedSongIds();
      if (!downloadedIds.contains(song.id)) {
        downloadedIds.add(song.id);
        await _prefs?.setStringList(_keyDownloadedSongs, downloadedIds);
      }

      try {
        final metadataFile = File(_getSongMetadataPath(song.id));
        await metadataFile.writeAsString(jsonEncode(song.toMap()));
        _downloadedFileNames.add('${song.id}.song.json');
      } catch (e) {
        debugPrint('Error saving song metadata: $e');
      }

      await _saveCover(song, subsonicService);
      try {
        final lyricsMap = <String, dynamic>{};
        final syncedLyrics = await subsonicService.getLyricsBySongId(song.id);
        if (syncedLyrics != null) lyricsMap['lyricsList'] = syncedLyrics;
        final plainLyrics = await subsonicService.getLyrics(
          artist: song.artist,
          title: song.title,
        );
        if (plainLyrics != null) lyricsMap['lyrics'] = plainLyrics;
        if (lyricsMap.isNotEmpty) await saveLyrics(song.id, lyricsMap);
      } catch (e) {
        debugPrint('Error downloading lyrics for ${song.title}: $e');
      }

      return true;
    } catch (e) {
      debugPrint('Error downloading song: $e');
      return false;
    }
  }

  /// Saves the 600 px cover as `<id>.jpg` beside the audio. Tries twice,
  /// keeps the file only if the bytes are an image, and never fails the
  /// download: a song without a cover is picked up by [backfillMissingCovers].
  Future<bool> _saveCover(Song song, SubsonicService subsonicService) async {
    final coverId = song.coverArt.isNotEmpty ? song.coverArt : song.id;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final url = subsonicService.getRemoteCoverArtUrl(coverId, size: 600);
        if (url.isEmpty) return false;
        final dio = dioFactory();
        dio.options.connectTimeout = const Duration(seconds: 10);
        dio.options.receiveTimeout = const Duration(seconds: 30);
        final res = await dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = res.data;
        final ok = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
        if (!ok || bytes == null || !_looksLikeImage(bytes)) continue;
        final part = File('${_getCoverArtPath(song.id)}.part');
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(_getCoverArtPath(song.id));
        _downloadedFileNames.add('${song.id}.jpg');
        if (coverId != song.id) _coverOwner[coverId] = song.id;
        return true;
      } catch (e) {
        debugPrint('Cover art for ${song.title} (try ${attempt + 1}): $e');
      }
    }
    return false;
  }

  static bool _looksLikeImage(List<int> b) {
    if (b.length < 12) return false;
    final jpeg = b[0] == 0xFF && b[1] == 0xD8;
    final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final gif = b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46;
    final webp = b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57;
    return jpeg || png || gif || webp;
  }

  /// Downloaded songs whose cover file is missing (a failed fetch, or a
  /// download made before covers were saved reliably).
  List<String> idsMissingCover() => [
        for (final id in getDownloadedSongIds())
          if (getLocalCoverArtPath(id) == null) id,
      ];

  /// Fetches the covers [idsMissingCover] lists, one at a time. Call when
  /// online; returns how many were saved.
  Future<int> backfillMissingCovers(SubsonicService subsonicService) async {
    if (_offlineDir == null) await initialize();
    var saved = 0;
    for (final id in idsMissingCover()) {
      try {
        final meta = File(_getSongMetadataPath(id));
        final Song song = await meta.exists()
            ? Song.fromJson(jsonDecode(await meta.readAsString()) as Map<String, dynamic>)
            : Song.fromJson({'id': id, 'title': id});
        if (await _saveCover(song, subsonicService)) saved++;
      } catch (e) {
        debugPrint('Cover backfill for $id: $e');
      }
    }
    if (saved > 0) coversChanged.value++;
    return saved;
  }

  /// Bumps when covers appear on disk after the fact, so tiles can repaint.
  final ValueNotifier<int> coversChanged = ValueNotifier(0);

  Future<void> downloadSongs(
    List<Song> songs,
    SubsonicService subsonicService, {
    Function(int current, int total)? onProgress,
    Function(Song song, bool success)? onSongComplete,
    Function()? onComplete,
  }) async {
    if (_offlineDir == null) await initialize();

    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];

      if (isSongDownloaded(song.id)) {
        onProgress?.call(i + 1, songs.length);
        onSongComplete?.call(song, true);
        continue;
      }

      final success = await downloadSong(song, subsonicService);
      onProgress?.call(i + 1, songs.length);
      onSongComplete?.call(song, success);
    }

    onComplete?.call();
  }

  Future<void> startBackgroundDownload(
    List<Song> songs,
    SubsonicService subsonicService,
  ) async {
    if (_isBackgroundDownloadActive) {
      debugPrint('Background download already in progress');
      return;
    }

    _isBackgroundDownloadActive = true;
    final alreadyDownloadedCount = getDownloadedCount();

    downloadState.value = DownloadState(
      isDownloading: true,
      currentProgress: 0,
      totalCount: songs.length,
      downloadedCount: alreadyDownloadedCount,
    );

    if (_offlineDir == null) await initialize();

    try {
      for (int i = 0; i < songs.length; i++) {
        if (!_isBackgroundDownloadActive) {
          break;
        }

        final song = songs[i];

        if (isSongDownloaded(song.id)) {
          downloadState.value = downloadState.value.copyWith(
            currentProgress: i + 1,
          );
          continue;
        }

        final success = await downloadSong(song, subsonicService);

        final newDownloadedCount = getDownloadedCount();
        downloadState.value = downloadState.value.copyWith(
          currentProgress: i + 1,
          downloadedCount: newDownloadedCount,
        );

        if (!success) {
          debugPrint('Failed to download song: ${song.title}');
        }
      }
    } catch (e) {
      debugPrint('Error during background download: $e');
    } finally {
      _isBackgroundDownloadActive = false;
      downloadState.value = downloadState.value.copyWith(isDownloading: false);
    }
  }

  void cancelBackgroundDownload() {
    _isBackgroundDownloadActive = false;
    downloadState.value = downloadState.value.copyWith(isDownloading: false);
  }

  bool get isBackgroundDownloadActive => _isBackgroundDownloadActive;

  Future<void> downloadPlaylist(
    Playlist playlist,
    SubsonicService subsonicService, {
    Function(int current, int total)? onProgress,
    Function()? onComplete,
  }) async {
    final songs = await subsonicService.getPlaylistSongs(playlist.id);
    await downloadSongs(
      songs,
      subsonicService,
      onProgress: onProgress,
      onComplete: onComplete,
    );
  }

  Future<bool> deleteSong(String songId) async {
    if (_offlineDir == null) return false;

    try {
      final localPath = getLocalPath(songId);
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      final lyricsFile = File(_getLyricsPath(songId));
      if (await lyricsFile.exists()) {
        await lyricsFile.delete();
      }
      final coverArtFile = File(_getCoverArtPath(songId));
      if (await coverArtFile.exists()) {
        await coverArtFile.delete();
      }
      final metadataFile = File(_getSongMetadataPath(songId));
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }

      final downloadedIds = getDownloadedSongIds();
      downloadedIds.remove(songId);
      await _prefs?.setStringList(_keyDownloadedSongs, downloadedIds);

      _downloadedFileNames.remove('$songId.mp3');
      _downloadedFileNames.remove('$songId.song.json');
      _downloadedFileNames.remove('$songId.jpg');
      _downloadedFileNames.remove('$songId.lyrics.json');
      _coverOwner.removeWhere((_, owner) => owner == songId);
      coversChanged.value++;
      _downloadedFileNames.remove('$songId.flac');
      _downloadedFileNames.remove('$songId.m4a');
      _downloadedFileNames.remove('$songId.ogg');

      return true;
    } catch (e) {
      debugPrint('Error deleting song: $e');
      return false;
    }
  }

  Future<void> deleteAllDownloads() async {
    if (_offlineDir == null) return;

    try {
      final dir = Directory(_offlineDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }

      await _prefs?.setStringList(_keyDownloadedSongs, []);
      _downloadedFileNames.clear();
      _coverOwner.clear();
      coversChanged.value++;
    } catch (e) {
      debugPrint('Error deleting all downloads: $e');
    }
  }

  String? getLocalPath(String songId) {
    if (_offlineDir == null) return null;
    for (final ext in [
      'flac',
      'mp3',
      'm4a',
      'ogg',
      'wav',
      'aac',
      'opus',
      'alac',
      'aiff',
    ]) {
      final filename = '$songId.$ext';
      if (_downloadedFileNames.contains(filename)) {
        return '$_offlineDir/$filename';
      }
    }
    final oldFilename = '$songId.mp3';
    if (_downloadedFileNames.contains(oldFilename)) {
      return '$_offlineDir/$oldFilename';
    }
    return null;
  }

  /// Async twin of [getLocalPath] — uses [File.exists] so it never blocks the
  /// main thread. Prefer this for queue-wide resolution: building a 200-song
  /// queue with the sync variant fires up to ~1000 blocking stat() syscalls.
  Future<String?> getLocalPathAsync(String songId) async {
    if (_offlineDir == null) return null;
    for (final ext in [
      'flac',
      'mp3',
      'm4a',
      'ogg',
      'wav',
      'aac',
      'opus',
      'alac',
      'aiff',
    ]) {
      final filename = '$songId.$ext';
      if (_downloadedFileNames.contains(filename)) {
        return '$_offlineDir/$filename';
      }
    }
    final oldFilename = '$songId.mp3';
    if (_downloadedFileNames.contains(oldFilename)) {
      return '$_offlineDir/$oldFilename';
    }
    return null;
  }

  /// Tests only: forget the cached preferences and folder of this app-wide
  /// instance, so the next call re-reads them.
  @visibleForTesting
  void resetForTest() {
    _prefs = null;
    _offlineDir = null;
    _downloadedFileNames.clear();
    _coverOwner.clear();
  }

  /// After a server upgrade changed song ids: move every downloaded file
  /// (`<id>.<ext>`, `.song.json`, `.lyrics.json`, `.jpg`) and the download list to the new ids, so downloads stay downloaded.
  /// Two-phase rename: one song's old id can be another song's new id.
  /// Returns how many songs moved.
  Future<int> remapSongIds(Map<String, String> idMap) async {
    if (_offlineDir == null) await initialize();
    if (idMap.isEmpty) return 0;
    const tmp = '__idmig__';
    final dir = Directory(_offlineDir!);
    final moved = <String>{};
    final staged = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final dot = name.indexOf('.');
      if (dot <= 0) continue;
      final newId = idMap[name.substring(0, dot)];
      if (newId == null) continue;
      staged.add(await entity.rename('$_offlineDir/$tmp$newId${name.substring(dot)}'));
      moved.add(newId);
    }
    for (final f in staged) {
      final name = f.uri.pathSegments.last.substring(tmp.length);
      final out = await f.rename('$_offlineDir/$name');
      if (name.endsWith('.song.json')) {
        // The saved song carries its id too; offline playback reads it.
        try {
          final data = jsonDecode(await out.readAsString()) as Map<String, dynamic>;
          final oldId = data['id'];
          if (oldId is String && idMap.containsKey(oldId)) {
            data['id'] = idMap[oldId];
            await out.writeAsString(jsonEncode(data));
          }
        } catch (e) {
          debugPrint('remapSongIds: $name not rewritten: $e');
        }
      }
    }
    final downloaded = getDownloadedSongIds().map((id) => idMap[id] ?? id).toList();
    await _prefs?.setStringList(_keyDownloadedSongs, downloaded);
    await initialize(); // rebuild the in-memory file index from disk
    return moved.length;
  }

  String getPlayableUrl(Song song, SubsonicService subsonicService) {
    // Check if the song has been downloaded locally first.
    final localPath = getLocalPath(song.id);
    if (localPath != null) {
      return Uri.file(localPath).toString();
    }
    return subsonicService.getStreamUrl(song.id);
  }
}
