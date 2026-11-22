import '../../../database/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart' show appDatabaseProvider;
import '../data/peak_store.dart';
import 'hotspots.dart';

/// A day you listened a lot: [plays] songs that lasted, [seconds] of audio.
class PeakDay {
  const PeakDay({required this.day, required this.plays, required this.seconds});
  final DateTime day;
  final int plays;
  final int seconds;

  /// From a `play_events` group row: `d` (yyyy-MM-dd, local), `plays`, `sec`.
  static PeakDay? fromRow(String? d, int plays, int seconds) {
    final day = d == null ? null : DateTime.tryParse(d);
    return day == null ? null : PeakDay(day: day, plays: plays, seconds: seconds);
  }
}

/// A listening session (songs less than 30 minutes apart): when it began,
/// how many songs, how long the audio ran.
class PeakSession {
  const PeakSession({required this.start, required this.songs, required this.seconds});
  final DateTime start;
  final int songs;
  final int seconds;
}

/// Everything "best listening moments" shows.
class BestMoments {
  const BestMoments({this.hotspots = const [], this.days = const [], this.sessions = const []});
  final List<Hotspot> hotspots;
  final List<PeakDay> days;
  final List<PeakSession> sessions;

  bool get isEmpty => hotspots.isEmpty && days.isEmpty && sessions.isEmpty;
}

const _topN = 5;

/// A play that counts as listening: not skipped early, not an accidental tap.
const _lasting = 'skip_before50 = 0 AND play_dur_sec >= 2';

/// The busiest days by listening time. Reads only this device's play log.
Future<List<PeakDay>> loadPeakDays(AppDatabase db, {int limit = _topN}) async {
  final rows = await db
      .customSelect(
        "SELECT date(ts_start / 1000, 'unixepoch', 'localtime') AS d, COUNT(*) AS plays, "
        'SUM(play_dur_sec) AS sec FROM play_events WHERE $_lasting '
        'GROUP BY d ORDER BY sec DESC, d DESC LIMIT $limit',
      )
      .get();
  return [
    for (final r in rows)
      ?PeakDay.fromRow(r.readNullable<String>('d'), r.read<int>('plays'), r.readNullable<int>('sec') ?? 0),
  ];
}

/// The longest sessions by audio time.
Future<List<PeakSession>> loadPeakSessions(AppDatabase db, {int limit = _topN}) async {
  final rows = await db
      .customSelect(
        'SELECT MIN(ts_start) AS s, COUNT(*) AS n, SUM(play_dur_sec) AS sec FROM play_events '
        'WHERE $_lasting GROUP BY session_id ORDER BY sec DESC, s DESC LIMIT $limit',
      )
      .get();
  return [
    for (final r in rows)
      PeakSession(
        start: DateTime.fromMillisecondsSinceEpoch(r.read<int>('s')),
        songs: r.read<int>('n'),
        seconds: r.readNullable<int>('sec') ?? 0,
      ),
  ];
}

/// The user's own peaks: scrub-back hotspots, most-played days, longest
/// sessions. A new one is read each time the screen opens.
final bestMomentsProvider = FutureProvider.autoDispose<BestMoments>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final log = ref.watch(seekLogProvider);
  final days = await loadPeakDays(db);
  final sessions = await loadPeakSessions(db);
  return BestMoments(hotspots: findHotspots(log).take(_topN * 2).toList(), days: days, sessions: sessions);
});
