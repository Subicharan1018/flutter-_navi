import 'dart:async';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../database/app_database.dart';
import '../../../models/song.dart';
import 'file_source.dart';
import 'local_index.dart';
import 'local_models.dart';
import 'matcher.dart';

/// Where the added folders are remembered (Hive in the app, a list in tests).
abstract class FolderStore {
  List<LocalFolder> read();
  Future<void> write(List<LocalFolder> folders);
}

class MemoryFolderStore implements FolderStore {
  List<LocalFolder> _folders = [];
  @override
  List<LocalFolder> read() => List.of(_folders);
  @override
  Future<void> write(List<LocalFolder> folders) async => _folders = List.of(folders);
}

/// Starts a scan; swapped for a direct call in tests.
typedef ScanRunner = Stream<ScanEvent> Function({
  required List<LocalFolder> folders,
  required Map<String, String> known,
});

class ScanSummary {
  final int added;
  final int removed;
  final int unreadable;
  final Map<String, String> failedFolders;
  const ScanSummary({this.added = 0, this.removed = 0, this.unreadable = 0, this.failedFolders = const {}});
}

/// Top level so the isolate closure cannot capture the service (and with it
/// the open database, which cannot cross isolates).
Future<Map<String, String>> _matchOffThread(List<MatchKey> local, List<MatchKey> server) =>
    Isolate.run(() => matchLocalToServer(local, server));

/// Owns the local songs table: folders in, scan results applied, server
/// matches, and the lookups the library and search screens use.
class LocalLibraryService {
  final AppDatabase _db;
  final FolderStore _store;
  final ScanRunner _runScan;
  final Future<void> Function(String uri) _releaseFolder;

  LocalLibraryService(
    this._db,
    this._store, {
    required ScanRunner runScan,
    Future<void> Function(String uri)? releaseFolder,
  })  : _runScan = runScan,
        _releaseFolder = releaseFolder ?? SafFileSource.release;

  List<LocalFolder> get folders => _store.read();

  Future<LocalFolder?> addFolder(LocalFolder folder) async {
    final all = folders;
    if (all.any((f) => f.uri == folder.uri)) return null;
    await _store.write([...all, folder]);
    return folder;
  }

  Future<void> removeFolder(String id) async {
    final all = folders;
    final gone = all.where((f) => f.id == id).firstOrNull;
    if (gone == null) return;
    await _store.write(all.where((f) => f.id != id).toList());
    await (_db.delete(_db.localSongs)..where((t) => t.folderId.equals(id))).go();
    if (gone.isSaf) await _releaseFolder(gone.uri);
    await rebuildIndex();
  }

  /// Walks every added folder (or just [only]), applying new, changed and
  /// removed files to the table as the events arrive. [onProgress] gets
  /// (done, total) of the files being read. The scan runs where [runScan]
  /// puts it; this method only awaits events and writes batches.
  Future<ScanSummary> scan({List<LocalFolder>? only, void Function(int done, int total)? onProgress}) async {
    final targets = only ?? folders;
    if (targets.isEmpty) return const ScanSummary();

    final known = <String, String>{};
    final ids = targets.map((f) => f.id).toList();
    final rows = await (_db.selectOnly(_db.localSongs)
          ..addColumns([_db.localSongs.path, _db.localSongs.fingerprint])
          ..where(_db.localSongs.folderId.isIn(ids)))
        .get();
    for (final r in rows) {
      known[r.read(_db.localSongs.path)!] = r.read(_db.localSongs.fingerprint)!;
    }

    var added = 0, removed = 0, unreadable = 0, doneBefore = 0, totalSoFar = 0;
    final failed = <String, String>{};
    await for (final event in _runScan(folders: targets, known: known)) {
      switch (event) {
        case ScanListed(:final changed):
          totalSoFar += changed;
          onProgress?.call(doneBefore, totalSoFar);
        case ScanBatch(:final tracks, :final done):
          await _upsert(tracks);
          added += tracks.length;
          onProgress?.call(doneBefore + done, totalSoFar);
        case ScanFolderDone(:final folderId, :final seen, unreadable: final bad):
          removed += await _removeMissing(folderId, seen);
          unreadable += bad;
          doneBefore = totalSoFar;
        case ScanFolderFailed(:final folderId, :final message):
          failed[folderId] = message;
      }
    }
    await rematch();
    return ScanSummary(added: added, removed: removed, unreadable: unreadable, failedFolders: failed);
  }

  Future<void> _upsert(List<ScannedTrack> tracks) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.batch((b) {
      for (final t in tracks) {
        LocalSongsCompanion comp({required bool withAdded}) => LocalSongsCompanion(
              songId: Value(t.songId),
              path: Value(t.path),
              folderId: Value(t.folderId),
              fingerprint: Value(t.fingerprint),
              title: Value(t.title),
              artist: Value(t.artist),
              album: Value(t.album),
              albumArtist: Value(t.albumArtist),
              genre: Value(t.genre),
              track: Value(t.track),
              disc: Value(t.disc),
              year: Value(t.year),
              durationSec: Value(t.durationSec),
              bitRate: Value(t.bitRate),
              suffix: Value(t.suffix),
              trackGain: Value(t.trackGain),
              albumGain: Value(t.albumGain),
              trackPeak: Value(t.trackPeak),
              albumPeak: Value(t.albumPeak),
              coverPath: Value(t.coverPath),
              lyrics: Value(t.lyrics),
              addedAt: withAdded ? Value(now) : const Value.absent(),
            );
        b.insert(_db.localSongs, comp(withAdded: true), onConflict: DoUpdate((_) => comp(withAdded: false)));
      }
    });
  }

  Future<int> _removeMissing(String folderId, Set<String> seen) async {
    final rows = await (_db.selectOnly(_db.localSongs)
          ..addColumns([_db.localSongs.songId, _db.localSongs.path])
          ..where(_db.localSongs.folderId.equals(folderId)))
        .get();
    final gone = [
      for (final r in rows)
        if (!seen.contains(r.read(_db.localSongs.path))) r.read(_db.localSongs.songId)!,
    ];
    for (var i = 0; i < gone.length; i += 500) {
      final chunk = gone.sublist(i, (i + 500).clamp(0, gone.length));
      await (_db.delete(_db.localSongs)..where((t) => t.songId.isIn(chunk))).go();
    }
    return gone.length;
  }

  /// Marks local songs that are copies of server songs and refreshes the
  /// playback index. Safe to call any time; cheap when nothing is local.
  Future<void> rematch() async {
    final local = await _db.select(_db.localSongs).get();
    if (local.isEmpty) {
      LocalLibraryIndex.instance.clear();
      return;
    }
    final server = await _db.select(_db.songMetadata).get();
    final pairs = await _matchOffThread(
      [for (final l in local) MatchKey(l.songId, l.title, l.artist, l.durationSec)],
      [for (final s in server) MatchKey(s.songId, s.trackName, s.artistName, s.durationSec)],
    );
    final changed = [
      for (final l in local)
        if (l.serverId != pairs[l.songId]) (l.songId, pairs[l.songId]),
    ];
    if (changed.isNotEmpty) {
      await _db.batch((b) {
        for (final (id, serverId) in changed) {
          b.update(_db.localSongs, LocalSongsCompanion(serverId: Value(serverId)), where: (t) => t.songId.equals(id));
        }
      });
    }
    await rebuildIndex();
  }

  /// Reloads the id → file map playback reads.
  Future<void> rebuildIndex() async {
    final rows = await _db.select(_db.localSongs).get();
    final paths = <String, String>{};
    final covers = <String, String>{};
    for (final r in rows) {
      paths[r.songId] = r.path;
      final server = r.serverId;
      if (server != null) paths[server] = r.path;
      final cover = r.coverPath;
      if (cover != null) covers[r.songId] = cover;
    }
    LocalLibraryIndex.instance.replace(paths: paths, covers: covers);
  }

  // ── Reads ────────────────────────────────────────────────────────────────

  static Song toSong(LocalSongEntity r) => localSongToSong(
        id: r.songId,
        title: r.title,
        artist: r.artist,
        album: r.album,
        genre: r.genre,
        track: r.track,
        year: r.year,
        durationSec: r.durationSec,
        bitRate: r.bitRate,
        suffix: r.suffix,
        trackGain: r.trackGain,
        albumGain: r.albumGain,
        trackPeak: r.trackPeak,
        albumPeak: r.albumPeak,
        added: DateTime.fromMillisecondsSinceEpoch(r.addedAt),
      );

  /// Songs only on this device (copies of server songs are left to the
  /// server's own rows), ordered artist → album → disc → track.
  Stream<List<Song>> watchSongs() {
    final q = _db.select(_db.localSongs)
      ..where((t) => t.serverId.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.artist.collate(Collate.noCase)),
        (t) => OrderingTerm(expression: t.album.collate(Collate.noCase)),
        (t) => OrderingTerm(expression: t.disc),
        (t) => OrderingTerm(expression: t.track),
        (t) => OrderingTerm(expression: t.title.collate(Collate.noCase)),
      ]);
    return q.watch().map((rows) => rows.map(toSong).toList());
  }

  /// How many files are on the device, and how many of those the server
  /// already has.
  Stream<(int total, int duplicates)> watchCounts() {
    final total = _db.localSongs.songId.count();
    final dupes = _db.localSongs.serverId.count();
    return (_db.selectOnly(_db.localSongs)..addColumns([total, dupes]))
        .watchSingle()
        .map((r) => (r.read(total) ?? 0, r.read(dupes) ?? 0));
  }

  Future<List<Song>> search(String query, {int limit = 40}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final like = '%${q.replaceAllMapped(RegExp(r'[%_\\]'), (m) => '\\${m[0]}')}%';
    final rows = await (_db.select(_db.localSongs)
          ..where((t) =>
              t.serverId.isNull() &
              (t.title.like(like, escapeChar: r'\') |
                  t.artist.like(like, escapeChar: r'\') |
                  t.album.like(like, escapeChar: r'\')))
          ..orderBy([(t) => OrderingTerm(expression: t.title.collate(Collate.noCase))])
          ..limit(limit))
        .get();
    return rows.map(toSong).toList();
  }

  /// Synced or plain lyrics text that sat beside the file (or in its tags).
  Future<String?> lyricsFor(String songId) async {
    final row = await (_db.select(_db.localSongs)
          ..where((t) => t.songId.equals(songId) | t.serverId.equals(songId))
          ..limit(1))
        .getSingleOrNull();
    return row?.lyrics;
  }

  /// A song by its device id (for restoring a queue after restart).
  Future<Song?> songById(String id) async {
    final row = await (_db.select(_db.localSongs)..where((t) => t.songId.equals(id))).getSingleOrNull();
    return row == null ? null : toSong(row);
  }

  @visibleForTesting
  Future<List<LocalSongEntity>> allRows() => _db.select(_db.localSongs).get();
}
