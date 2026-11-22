import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/settings_provider.dart' show appDatabaseProvider;
import 'play_stats.dart';

/// What this device's own play log knows about [songId]: plays that lasted
/// (not skipped in the first half), and the latest start. Cheap: both columns
/// are indexed (`idx_play_events_song`).
final localPlayStatsProvider = FutureProvider.autoDispose.family<PlayStats, String>((ref, songId) async {
  final db = ref.watch(appDatabaseProvider);
  final row = await db
      .customSelect(
        'SELECT COUNT(*) AS c, MAX(ts_start) AS last FROM play_events '
        'WHERE song_id = ? AND skip_before50 = 0 AND play_dur_sec >= 2',
        variables: [_text(songId)],
      )
      .getSingle();
  final c = row.read<int>('c');
  final last = row.readNullable<int>('last');
  return PlayStats(count: c, lastPlayed: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last));
});

/// Server and local figures for [song], merged. Falls back to the server's
/// alone while the local read is pending or fails.
final songPlayStatsProvider = Provider.autoDispose.family<PlayStats, Song>((ref, song) {
  final local = ref.watch(localPlayStatsProvider(song.id)).value ?? PlayStats.none;
  return PlayStats.merge(song, localCount: local.count, localLast: local.lastPlayed);
});

Variable _text(String s) => Variable.withString(s);
