import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show BackgroundIsolateBinaryMessenger;

import 'file_source.dart';
import 'local_models.dart';
import 'tag_reader.dart';

const _batchSize = 25;

/// Version of how covers are found (embedded picture, folder file names,
/// platform thumbnail). Part of every fingerprint: raise it when the reader
/// learns to find more art, and songs that have none are read again once.
const artReaderVersion = 2;
const _artTag = '|art$artReaderVersion';

String _fingerprint(ScanEntry e, ScanEntry? lrc, ScanEntry? art) =>
    '${e.size}:${e.modifiedMs}|${lrc?.modifiedMs ?? ''}:${lrc?.size ?? ''}|${art?.modifiedMs ?? ''}$_artTag';

/// The fingerprint to compare a stored row against. A row written by an older
/// reader that already has a cover keeps its place (the tag is added); one
/// without a cover gets none, so it is read again with the current reader.
String? knownFingerprint(String stored, {required bool hasCover}) {
  if (stored.endsWith(_artTag)) return stored;
  if (RegExp(r'\|art\d+$').hasMatch(stored)) return null;
  return hasCover ? '$stored$_artTag' : null;
}

/// Walks [folders] and reads the tags of files that are new or changed since
/// [known] (path → fingerprint). Emits batches as it goes, then one
/// [ScanFolderDone] per folder with every path still there, so the caller can
/// drop the rest. Pure `dart:io` over a [LocalFileSource]; runs anywhere,
/// including a background isolate.
Stream<ScanEvent> scanFolders({
  required LocalFileSource Function(LocalFolder) sourceFor,
  required List<LocalFolder> folders,
  required Map<String, String> known,
  required Directory artDir,
}) async* {
  for (final folder in folders) {
    final source = sourceFor(folder);
    final FolderListing listing;
    try {
      listing = await source.list(folder);
    } catch (e) {
      yield ScanFolderFailed(folder.id, e.toString());
      continue;
    }

    final work = <(ScanEntry, String, ScanEntry?, ScanEntry?)>[];
    final seen = <String>{};
    for (final e in listing.audio) {
      seen.add(e.path);
      final lrc = listing.lyrics[lyricsKey(e.dir, e.name)];
      final art = listing.folderArt[e.dir];
      final print = _fingerprint(e, lrc, art);
      if (known[e.path] != print) work.add((e, print, lrc, art));
    }
    yield ScanListed(folder.id, listing.audio.length, work.length);

    var unreadable = 0;
    var artUnreadable = 0;
    var done = 0;
    var batch = <ScannedTrack>[];
    for (final (entry, print, lrc, art) in work) {
      try {
        final track = await readTrack(
          source: source,
          entry: entry,
          folderId: folder.id,
          fingerprint: print,
          artDir: artDir,
          lyricsFile: lrc,
          folderArt: art,
        );
        if (track.artFailed) artUnreadable++;
        batch.add(track);
      } on FileSystemException {
        unreadable++;
        seen.remove(entry.path);
      } catch (_) {
        unreadable++;
        seen.remove(entry.path);
      }
      done++;
      if (batch.length >= _batchSize) {
        yield ScanBatch(batch, done, work.length);
        batch = [];
      }
    }
    if (batch.isNotEmpty) yield ScanBatch(batch, done, work.length);
    if (artUnreadable > 0) {
      debugPrint('[LocalLibrary] ${folder.name}: art unreadable for $artUnreadable of ${work.length} songs read');
    }
    yield ScanFolderDone(folder.id, seen, unreadable, artUnreadable);
  }
}

LocalFileSource defaultSourceFor(LocalFolder f) => f.isSaf ? const SafFileSource() : const IoFileSource();

class _ScanRequest {
  final SendPort port;
  final List<LocalFolder> folders;
  final Map<String, String> known;
  final String artDir;
  final RootIsolateToken? token;
  const _ScanRequest(this.port, this.folders, this.known, this.artDir, this.token);
}

Future<void> _scanMain(_ScanRequest req) async {
  if (req.token != null) BackgroundIsolateBinaryMessenger.ensureInitialized(req.token!);
  try {
    await for (final event in scanFolders(
      sourceFor: defaultSourceFor,
      folders: req.folders,
      known: req.known,
      artDir: Directory(req.artDir),
    )) {
      req.port.send(event);
    }
    req.port.send(null);
  } catch (e) {
    req.port.send('error: $e');
  }
}

/// Runs [scanFolders] in its own isolate and forwards its events, so tag
/// parsing and folder walking never run on the UI thread. Cancelling the
/// subscription kills the isolate.
Stream<ScanEvent> scanInIsolate({
  required List<LocalFolder> folders,
  required Map<String, String> known,
  required String artDir,
}) {
  late StreamController<ScanEvent> controller;
  Isolate? isolate;
  final port = ReceivePort();

  void close() {
    isolate?.kill(priority: Isolate.immediate);
    isolate = null;
    port.close();
  }

  controller = StreamController<ScanEvent>(
    onListen: () async {
      port.listen((message) {
        if (message is ScanEvent) {
          controller.add(message);
        } else if (message is String) {
          controller.addError(message);
          close();
          controller.close();
        } else {
          close();
          controller.close();
        }
      });
      try {
        isolate = await Isolate.spawn(
          _scanMain,
          _ScanRequest(port.sendPort, folders, known, artDir, RootIsolateToken.instance),
          debugName: 'local-library-scan',
        );
      } catch (e) {
        controller.addError(e);
        close();
        await controller.close();
      }
    },
    onCancel: close,
  );
  return controller.stream;
}
