import 'dart:io';

import 'package:flutter/services.dart';

import 'local_models.dart';

const audioExtensions = {
  'mp3', 'flac', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'wav', 'aiff', 'aif', 'wma', 'ape', 'mka', 'webm', //
};
const _artNames = {'cover', 'folder', 'front', 'album', 'albumart'};
const _artExtensions = {'jpg', 'jpeg', 'png', 'webp'};

String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

String baseNameOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

/// Whether a file name is worth listing: audio, a `.lrc`, or folder art.
bool isScannable(String name) {
  final ext = extensionOf(name);
  if (audioExtensions.contains(ext) || ext == 'lrc') return true;
  return _artExtensions.contains(ext) && _artNames.contains(baseNameOf(name).toLowerCase());
}

String lyricsKey(String dir, String name) => '$dir|${baseNameOf(name).toLowerCase()}';

/// Sorts a flat list of files into audio, sidecar lyrics and folder art.
FolderListing buildListing(Iterable<ScanEntry> entries) {
  final audio = <ScanEntry>[];
  final lyrics = <String, ScanEntry>{};
  final art = <String, ScanEntry>{};
  for (final e in entries) {
    final ext = extensionOf(e.name);
    if (audioExtensions.contains(ext)) {
      audio.add(e);
    } else if (ext == 'lrc') {
      lyrics[lyricsKey(e.dir, e.name)] = e;
    } else if (_artExtensions.contains(ext) && _artNames.contains(baseNameOf(e.name).toLowerCase())) {
      art[e.dir] = e;
    }
  }
  return FolderListing(audio: audio, lyrics: lyrics, folderArt: art);
}

/// A file opened for reading through `dart:io`.
class OpenedFile {
  final File file;
  final Future<void> Function() close;
  const OpenedFile(this.file, this.close);
}

/// Where the scanner reads from: plain folders, or an Android folder the user
/// granted through the Storage Access Framework.
abstract class LocalFileSource {
  Future<FolderListing> list(LocalFolder folder);
  Future<OpenedFile> open(String path);
}

class IoFileSource implements LocalFileSource {
  const IoFileSource();

  @override
  Future<FolderListing> list(LocalFolder folder) async {
    final root = Directory(folder.uri);
    if (!await root.exists()) {
      throw FileSystemException('Folder not found', folder.uri);
    }
    final found = <ScanEntry>[];
    final stream = root.list(recursive: true, followLinks: false);
    // A folder we cannot read (permissions, a vanished mount) is skipped, not
    // fatal: the rest of the library still scans.
    await for (final entity in stream.handleError((_) {}, test: (e) => e is FileSystemException)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!isScannable(name)) continue;
      try {
        final stat = await entity.stat();
        found.add(ScanEntry(
          path: entity.path,
          name: name,
          dir: entity.parent.path,
          size: stat.size,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
        ));
      } on FileSystemException {
        continue;
      }
    }
    return buildListing(found);
  }

  @override
  Future<OpenedFile> open(String path) async => OpenedFile(File(path), () async {});
}

/// Reads folders granted through Android's document picker. Everything is
/// served by `SafChannel` in MainActivity; this side only sees paths through
/// `/proc/self/fd`, so the tag reader can use a normal [File].
class SafFileSource implements LocalFileSource {
  static const _channel = MethodChannel('com.navivibe/saf');
  const SafFileSource();

  /// Opens Android's folder picker. Null when the user cancels.
  static Future<LocalFolder?> pickFolder() async {
    final r = await _channel.invokeMapMethod<String, String>('pickTree');
    final uri = r?['uri'];
    if (uri == null) return null;
    return LocalFolder(id: folderIdFor(uri), uri: uri, name: r?['name'] ?? 'Music');
  }

  static Future<void> release(String uri) async {
    try {
      await _channel.invokeMethod('releaseTree', {'uri': uri});
    } on PlatformException {
      // Already released or never persisted: nothing to undo.
    }
  }

  /// Whether the permission granted for [uri] is still held.
  static Future<bool> hasAccess(String uri) async =>
      await _channel.invokeMethod<bool>('hasAccess', {'uri': uri}) ?? false;

  @override
  Future<FolderListing> list(LocalFolder folder) async {
    final rows = await _channel.invokeListMethod<Map>('listTree', {'uri': folder.uri}) ?? const [];
    return buildListing([
      for (final r in rows)
        ScanEntry(
          path: r['uri'] as String,
          name: r['name'] as String,
          dir: r['dir'] as String,
          size: (r['size'] as num?)?.toInt() ?? 0,
          modifiedMs: (r['modified'] as num?)?.toInt() ?? 0,
        ),
    ]);
  }

  @override
  Future<OpenedFile> open(String path) async {
    final r = await _channel.invokeMapMethod<String, Object?>('openFd', {'uri': path});
    final fdPath = r?['path'] as String?;
    final token = r?['token'];
    if (fdPath == null) throw FileSystemException('Could not open', path);
    return OpenedFile(File(fdPath), () async {
      await _channel.invokeMethod('closeFd', {'token': token});
    });
  }
}
