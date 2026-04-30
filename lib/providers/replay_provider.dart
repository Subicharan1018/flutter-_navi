import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'settings_provider.dart';

// =============================================================================
// ReplayProvider
//
// Queries the local Drift database (play_events + song_metadata) to
// compute real listening statistics for "Monthly Replay" and "Weekly Replay".
//
// Returns top songs ranked by total listening time in the period.
// Requires at least some play_events rows to return non-empty results.
// =============================================================================

/// A single entry in a Replay list.
class ReplaySong {
  final String songId;
  final String title;
  final String artist;
  final String albumName;
  final int playCount;        // number of play events in the period
  final int totalMinutesSec;  // total listening seconds in the period
  final String? coverArtId;  // for building the cover URL via SubsonicService

  const ReplaySong({
    required this.songId,
    required this.title,
    required this.artist,
    required this.albumName,
    required this.playCount,
    required this.totalMinutesSec,
    this.coverArtId,
  });

  /// Human-readable listening time, e.g. "3h 12m" or "47m".
  String get listeningLabel {
    final h = totalMinutesSec ~/ 3600;
    final m = (totalMinutesSec % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

/// Stats summary for the header card.
class ReplayStats {
  final int totalSec;
  final int uniqueArtists;
  final int uniqueSongs;
  final String? topGenre;

  const ReplayStats({
    required this.totalSec,
    required this.uniqueArtists,
    required this.uniqueSongs,
    this.topGenre,
  });

  String get totalTimeLabel {
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class ReplayData {
  final List<ReplaySong> songs;
  final ReplayStats stats;
  /// Per-day listening seconds: key = ISO weekday (1=Mon … 7=Sun).
  final Map<int, int> dailyListening;
  const ReplayData({
    required this.songs,
    required this.stats,
    this.dailyListening = const {},
  });
  bool get isEmpty => songs.isEmpty;
}

// ---------------------------------------------------------------------------
// Internal DB helper
// ---------------------------------------------------------------------------

Future<ReplayData> _queryReplay(AppDatabase db, int fromMs, int toMs) async {
  try {
    // ── Effective listening time formula ──────────────────────────────────
    // play_dur_sec stores the position at the moment of stop (clamped to
    // song duration). For LoopMode.one repeats, each completed loop played
    // the FULL track, so effective time = repeat_count × duration + partial.
    //
    // COALESCE guards against missing song_metadata rows.
    //
    // score = effective_sec × (1 + completion_rate) × skip_penalty
    //   completion_rate = effective_sec / expected_sec
    //   skip_penalty    = MAX(0.3, 1.0 - skip_count × 0.1)
    // ─────────────────────────────────────────────────────────────────────

    // Top 10 songs by recommendation-weighted score in the given window.
    final rows = await db.customSelect('''
      WITH song_stats AS (
        SELECT
          pe.song_id,
          sm.track_name,
          sm.artist_name,
          sm.album_name,
          sm.genre,
          COUNT(pe.play_id) AS play_count,
          SUM(
            pe.repeat_count * COALESCE(sm.duration_sec, pe.play_dur_sec)
            + pe.play_dur_sec
          ) AS effective_sec,
          SUM(
            (1 + pe.repeat_count) * COALESCE(sm.duration_sec, pe.play_dur_sec)
          ) AS expected_sec,
          SUM(pe.skip_before50) AS skip_count
        FROM play_events pe
        LEFT JOIN song_metadata sm ON sm.song_id = pe.song_id
        WHERE pe.ts_start >= ? AND pe.ts_start < ?
          AND pe.play_dur_sec > 0
        GROUP BY pe.song_id
      )
      SELECT
        song_id,
        track_name,
        artist_name,
        album_name,
        genre,
        play_count,
        effective_sec AS total_sec,
        CAST(effective_sec AS REAL) / MAX(expected_sec, 1) AS completion_rate,
        skip_count,
        (
          effective_sec
          * (1.0 + CAST(effective_sec AS REAL) / MAX(expected_sec, 1))
          * MAX(0.3, 1.0 - (skip_count * 0.1))
        ) AS score
      FROM song_stats
      ORDER BY score DESC
      LIMIT 10
    ''', variables: [Variable.withInt(fromMs), Variable.withInt(toMs)]).get();

    // Stats summary
    final statsRows = await db.customSelect('''
      SELECT
        SUM(
          pe.repeat_count * COALESCE(sm.duration_sec, pe.play_dur_sec)
          + pe.play_dur_sec
        ) AS total_sec,
        COUNT(DISTINCT sm.artist_name) AS unique_artists,
        COUNT(DISTINCT pe.song_id)     AS unique_songs
      FROM play_events pe
      LEFT JOIN song_metadata sm ON sm.song_id = pe.song_id
      WHERE pe.ts_start >= ? AND pe.ts_start < ?
        AND pe.play_dur_sec > 0
    ''', variables: [Variable.withInt(fromMs), Variable.withInt(toMs)]).get();

    // Top genre
    final genreRows = await db.customSelect('''
      SELECT sm.genre,
        SUM(
          pe.repeat_count * COALESCE(sm.duration_sec, pe.play_dur_sec)
          + pe.play_dur_sec
        ) AS total_sec
      FROM play_events pe
      LEFT JOIN song_metadata sm ON sm.song_id = pe.song_id
      WHERE pe.ts_start >= ? AND pe.ts_start < ?
        AND sm.genre IS NOT NULL
        AND pe.play_dur_sec > 0
      GROUP BY sm.genre
      ORDER BY total_sec DESC
      LIMIT 1
    ''', variables: [Variable.withInt(fromMs), Variable.withInt(toMs)]).get();

    // Per-day-of-week listening breakdown.
    // SQLite strftime('%w') returns 0=Sun,1=Mon…6=Sat.
    // Convert to ISO weekday: 1=Mon…7=Sun.
    final dailyRows = await db.customSelect('''
      SELECT
        CAST(strftime('%w', pe.ts_start / 1000, 'unixepoch', 'localtime') AS INTEGER) AS dow,
        SUM(
          pe.repeat_count * COALESCE(sm.duration_sec, pe.play_dur_sec)
          + pe.play_dur_sec
        ) AS total_sec
      FROM play_events pe
      LEFT JOIN song_metadata sm ON sm.song_id = pe.song_id
      WHERE pe.ts_start >= ? AND pe.ts_start < ?
        AND pe.play_dur_sec > 0
      GROUP BY dow
    ''', variables: [Variable.withInt(fromMs), Variable.withInt(toMs)]).get();

    final Map<int, int> dailyListening = {};
    for (final r in dailyRows) {
      final sqliteDow = r.read<int?>('dow') ?? 0; // 0=Sun,1=Mon…6=Sat
      final isoDow = sqliteDow == 0 ? 7 : sqliteDow; // → 1=Mon…7=Sun
      dailyListening[isoDow] = r.read<int?>('total_sec') ?? 0;
    }

    final statsRow = statsRows.isNotEmpty ? statsRows.first : null;
    final stats = ReplayStats(
      totalSec: statsRow?.read<int?>('total_sec') ?? 0,
      uniqueArtists: statsRow?.read<int?>('unique_artists') ?? 0,
      uniqueSongs: statsRow?.read<int?>('unique_songs') ?? 0,
      topGenre: genreRows.isNotEmpty ? genreRows.first.read<String?>('genre') : null,
    );

    final songs = rows.map((r) => ReplaySong(
      songId: r.read<String>('song_id'),
      title: r.read<String?>('track_name') ?? 'Unknown',
      artist: r.read<String?>('artist_name') ?? 'Unknown',
      albumName: r.read<String?>('album_name') ?? '',
      playCount: r.read<int?>('play_count') ?? 0,
      totalMinutesSec: r.read<int?>('total_sec') ?? 0,
      coverArtId: r.read<String>('song_id'), // Subsonic getCoverArt accepts song IDs
    )).toList();

    return ReplayData(songs: songs, stats: stats, dailyListening: dailyListening);
  } catch (e) {
    debugPrint('[ReplayProvider] query error: $e');
    return const ReplayData(
      songs: [],
      stats: ReplayStats(totalSec: 0, uniqueArtists: 0, uniqueSongs: 0),
    );
  }
}

// ---------------------------------------------------------------------------
// Date window helpers
// ---------------------------------------------------------------------------

/// Returns [start, end) in milliseconds for the current calendar month.
(int, int) _thisMonthWindow() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end   = DateTime(now.year, now.month + 1, 1);
  return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
}

/// Returns [start, end) in milliseconds for the current ISO week (Mon–Sun).
(int, int) _thisWeekWindow() {
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final start = DateTime(monday.year, monday.month, monday.day);
  final end   = start.add(const Duration(days: 7));
  return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final monthlyReplayProvider = FutureProvider<ReplayData>((ref) async {
  ref.keepAlive();
  final db = ref.watch(appDatabaseProvider);
  final (from, to) = _thisMonthWindow();
  return _queryReplay(db, from, to);
});

final weeklyReplayProvider = FutureProvider<ReplayData>((ref) async {
  ref.keepAlive();
  final db = ref.watch(appDatabaseProvider);
  final (from, to) = _thisWeekWindow();
  return _queryReplay(db, from, to);
});
