import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../models/song.dart';
import 'package:drift/drift.dart';

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

class PlaylistCacheService {
  final AppDatabase _db;
  final Duration ttl;

  static const Duration defaultTtl = Duration(minutes: 5);

  PlaylistCacheService(this._db, {this.ttl = defaultTtl});

  Future<CachedPlaylistResult?> getSongs(String playlistId) async {
    try {
      final query = _db.select(_db.playlistCache)
        ..where((t) => t.playlistId.equals(playlistId))
        ..orderBy([(t) => OrderingTerm(expression: t.position)]);

      final rows = await query.get();
      if (rows.isEmpty) return null;

      final cachedAt = DateTime.fromMillisecondsSinceEpoch(rows.first.cachedAt);
      final isStale = DateTime.now().difference(cachedAt) > ttl;

      final songs = await compute(_decodeSongsDrift, rows);

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

  Future<void> putSongs(String playlistId, List<Song> songs) async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final encoded = await compute(_encodeSongsDrift, songs);

      await _db.transaction(() async {
        await (_db.delete(_db.playlistCache)
              ..where((t) => t.playlistId.equals(playlistId)))
            .go();

        await _db.batch((batch) {
          for (var i = 0; i < encoded.length; i++) {
            batch.insert(
              _db.playlistCache,
              PlaylistCacheCompanion.insert(
                playlistId: playlistId,
                position: i,
                songJson: encoded[i],
                cachedAt: nowMs,
              ),
            );
          }
        });
      });
    } catch (e) {
      debugPrint('[PlaylistCache] putSongs error: $e');
    }
  }

  Future<void> invalidate(String playlistId) async {
    try {
      await (_db.delete(_db.playlistCache)
            ..where((t) => t.playlistId.equals(playlistId)))
          .go();
    } catch (e) {
      debugPrint('[PlaylistCache] invalidate error: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      await _db.delete(_db.playlistCache).go();
    } catch (e) {
      debugPrint('[PlaylistCache] clearAll error: $e');
    }
  }

  Future<void> dispose() async {}
}

List<Song> _decodeSongsDrift(List<PlaylistCacheEntity> rows) {
  final result = <Song>[];
  for (final row in rows) {
    try {
      final map = jsonDecode(row.songJson) as Map<String, dynamic>;
      if (map['starred'] == 1) {
        map['starred'] = 'starred';
      } else {
        map.remove('starred');
      }
      result.add(Song.fromJson(map));
    } catch (_) {}
  }
  return result;
}

List<String> _encodeSongsDrift(List<Song> songs) =>
    songs.map((s) => jsonEncode(s.toMap())).toList();
