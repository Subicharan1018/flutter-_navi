import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/song.dart';

// ---------------------------------------------------------------------------
// Result container returned by [PlaylistCacheService.getSongs]
// ---------------------------------------------------------------------------
class CachedPlaylistResult {
  final List<Song> songs;
  final DateTime cachedAt;
  final bool isStale;

  const CachedPlaylistResult({
    required this.songs,
    required this.cachedAt,
    required this.isStale,
  });
}

// ---------------------------------------------------------------------------
// PlaylistCacheService
//
// Persists playlist song lists in SQLite so that the playlist details screen
// can show data instantly on repeat opens instead of waiting for the full
// Subsonic network round-trip every time.
//
// Schema
// ──────
//   playlist_cache
//     playlist_id  TEXT  – Subsonic playlist ID
//     position     INTEGER – 0-based order within the playlist
//     song_json    TEXT  – JSON-encoded Song.toMap() output
//     cached_at    INTEGER – Unix epoch milliseconds when the row was written
//     PRIMARY KEY (playlist_id, position)
//
// Usage pattern (stale-while-revalidate)
// ───────────────────────────────────────
//   1. Screen opens → call getSongs(id)
//   2. If result != null → render immediately (even if isStale == true)
//   3. In the background, call the Subsonic API
//   4. On success → call putSongs(id, freshSongs) to update the DB
// ---------------------------------------------------------------------------
class PlaylistCacheService {
  static const _kDbName = 'navivibe_cache.db';
  static const _kTable = 'playlist_cache';

  // Default TTL: 5 minutes.  Stale data is still shown instantly; the network
  // refresh happens in the background so the user never waits.
  static const Duration defaultTtl = Duration(minutes: 5);

  final Duration ttl;
  Database? _db;

  PlaylistCacheService({this.ttl = defaultTtl});

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbPath = p.join(await getDatabasesPath(), _kDbName);
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_kTable (
          playlist_id TEXT NOT NULL,
          position    INTEGER NOT NULL,
          song_json   TEXT NOT NULL,
          cached_at   INTEGER NOT NULL,
          PRIMARY KEY (playlist_id, position)
        )
      '''),
    );
    return _db!;
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns cached songs for [playlistId], or `null` on cache miss.
  ///
  /// The [CachedPlaylistResult.isStale] flag signals that the data is older
  /// than [ttl] and the caller should trigger a background refresh.
  Future<CachedPlaylistResult?> getSongs(String playlistId) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'position ASC',
      );

      if (rows.isEmpty) return null;

      final cachedAt =
          DateTime.fromMillisecondsSinceEpoch(rows.first['cached_at'] as int);
      final isStale = DateTime.now().difference(cachedAt) > ttl;

      // Parse Song objects off the main thread when the list is large.
      // sqflite returns UnmodifiableMapView rows that cannot be transferred
      // across a SendPort on all platforms — convert to plain maps first.
      final plainRows =
          rows.map((r) => Map<String, Object?>.from(r)).toList();
      final songs = await compute(_decodeSongs, plainRows);

      return CachedPlaylistResult(
        songs: songs,
        cachedAt: cachedAt,
        isStale: isStale,
      );
    } catch (e) {
      debugPrint('[PlaylistCache] getSongs error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Persists [songs] for [playlistId], replacing any previous entries.
  Future<void> putSongs(String playlistId, List<Song> songs) async {
    try {
      final db = await _open();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Encode all Song objects to JSON strings on a background isolate.
      // For 1000 songs this takes ~50–100 ms — doing it here prevents that
      // work from blocking the main thread after the song list has rendered.
      final encoded = await compute(_encodeSongs, songs);

      await db.transaction((txn) async {
        // Delete stale rows for this playlist first.
        await txn.delete(
          _kTable,
          where: 'playlist_id = ?',
          whereArgs: [playlistId],
        );
        // Batch-insert new rows with pre-encoded JSON strings.
        final batch = txn.batch();
        for (var i = 0; i < encoded.length; i++) {
          batch.insert(_kTable, {
            'playlist_id': playlistId,
            'position': i,
            'song_json': encoded[i],
            'cached_at': nowMs,
          });
        }
        await batch.commit(noResult: true);
      });
    } catch (e) {
      debugPrint('[PlaylistCache] putSongs error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Invalidation
  // ---------------------------------------------------------------------------

  /// Removes all cached songs for a single [playlistId].
  /// Call this after adding or removing songs from the playlist.
  Future<void> invalidate(String playlistId) async {
    try {
      final db = await _open();
      await db.delete(
        _kTable,
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
    } catch (e) {
      debugPrint('[PlaylistCache] invalidate error: $e');
    }
  }

  /// Wipes the entire cache.  Call on logout or server change.
  Future<void> clearAll() async {
    try {
      final db = await _open();
      await db.delete(_kTable);
    } catch (e) {
      debugPrint('[PlaylistCache] clearAll error: $e');
    }
  }

  /// Closes the database connection.  Call when the service is disposed.
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}

// ---------------------------------------------------------------------------
// Top-level functions so they can be passed to [compute]
// (must not be closures — isolate SendPort requires top-level symbols)
// ---------------------------------------------------------------------------

/// Decodes SQLite rows back into [Song] objects.
List<Song> _decodeSongs(List<Map<String, Object?>> rows) {
  final result = <Song>[];
  for (final row in rows) {
    try {
      final map = jsonDecode(row['song_json'] as String) as Map<String, dynamic>;
      // starred was stored as int 0/1 — re-map to what Song.fromJson expects
      if (map['starred'] == 1) {
        map['starred'] = 'starred'; // truthy string → fromJson treats as starred
      } else {
        map.remove('starred'); // absent → fromJson treats as not starred
      }
      result.add(Song.fromJson(map));
    } catch (_) {
      // Skip corrupted rows silently.
    }
  }
  return result;
}

/// Encodes [Song] objects to JSON strings for SQLite storage.
/// Running this in a background isolate via [compute] keeps the main thread
/// free during writes of large playlists (500–1000+ songs).
List<String> _encodeSongs(List<Song> songs) =>
    songs.map((s) => jsonEncode(s.toMap())).toList();
