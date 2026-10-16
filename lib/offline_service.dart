import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/playlist.dart';
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

  final ValueNotifier<DownloadState> downloadState = ValueNotifier(
    DownloadState(),
  );
  bool _isBackgroundDownloadActive = false;

  static const String _keyDownloadedSongs = 'offline_downloaded_songs';
  static const String _keyPendingScrobbles = 'pending_scrobbles';

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();
    _offlineDir = '${dir.path}/offline_music';

    final offlineDirectory = Directory(_offlineDir!);
    if (!await offlineDirectory.exists()) {
      await offlineDirectory.create(recursive: true);
    }

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
  }

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

      final dio = Dio();
      // BUG-2 FIX: Without timeouts, Dio hangs indefinitely on no-network,
      // leaving the download state stuck at "downloading" forever.
      dio.options.connectTimeout = const Duration(seconds: 15);
      dio.options.receiveTimeout = const Duration(seconds: 120);
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
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

      try {
        if (song.coverArt.isNotEmpty) {
          final coverUrl = subsonicService.getCoverArtUrl(
            song.coverArt,
            size: 600,
          );
          if (coverUrl.isNotEmpty) {
            final dioCover = Dio();
            await dioCover.download(coverUrl, _getCoverArtPath(song.id));
            _downloadedFileNames.add('${song.id}.jpg');
          }
        }
      } catch (e) {
        debugPrint('Error downloading cover art for ${song.title}: $e');
      }
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

  /// After a server upgrade changed song ids: move every downloaded file
  /// (`<id>.<ext>`, `.song.json`, `.lyrics.json`, `.jpg`) and the download and
  /// pending-scrobble lists to the new ids, so downloads stay downloaded.
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
    final scrobbles = _getPendingScrobbles()
        .map((s) => {...s, 'id': idMap[s['id']] ?? s['id'] ?? ''})
        .toList();
    await _prefs?.setString(_keyPendingScrobbles, json.encode(scrobbles));
    await initialize(); // rebuild the in-memory file index from disk
    return moved.length;
  }

  Future<void> queueScrobble(String songId, {bool submission = true}) async {
    if (_prefs == null) await initialize();
    final scrobbles = _getPendingScrobbles();
    scrobbles.add({
      'id': songId,
      'submission': submission ? 'true' : 'false',
      'time': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    await _prefs!.setString(_keyPendingScrobbles, json.encode(scrobbles));
    debugPrint(
      'Scrobble queued for $songId (submission=$submission). Total pending: ${scrobbles.length}',
    );
  }

  List<Map<String, String>> _getPendingScrobbles() {
    final raw = _prefs?.getString(_keyPendingScrobbles);
    if (raw == null) return [];
    try {
      final list = json.decode(raw) as List;
      return list.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  int getPendingScrobbleCount() => _getPendingScrobbles().length;

  Future<void> flushPendingScrobbles(SubsonicService subsonicService) async {
    if (_prefs == null) await initialize();
    final pending = _getPendingScrobbles();
    if (pending.isEmpty) return;

    debugPrint('Flushing ${pending.length} pending scrobble(s)...');
    final remaining = <Map<String, String>>[];
    for (final scrobble in pending) {
      try {
        await subsonicService.scrobble(
          scrobble['id']!,
          submission: scrobble['submission'] == 'true',
        );
      } catch (e) {
        debugPrint('Scrobble flush failed for ${scrobble['id']}: $e');
        remaining.add(scrobble);
      }
    }

    if (remaining.isEmpty) {
      await _prefs!.remove(_keyPendingScrobbles);
      debugPrint('All pending scrobbles flushed successfully.');
    } else {
      await _prefs!.setString(_keyPendingScrobbles, json.encode(remaining));
      debugPrint('${remaining.length} scrobble(s) still pending after flush.');
    }
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
