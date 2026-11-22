import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../providers/library_provider.dart' show songFromMetadata;
import '../../providers/settings_provider.dart' show appDatabaseProvider;
import 'history_logic.dart';

/// Plays read per page of the history.
const historyPageSize = 300;

/// Reads [limit] plays older than [beforeMs] (null = from now) from the local
/// play log, newest first, joined to the song mirror. A play whose song is not
/// in the mirror (removed from the library) is left out, since it cannot be
/// played again anyway. Plays that were skipped in the first two seconds are
/// noise and are left out too.
Future<List<HistoryEntry>> readHistory(AppDatabase db, {int? beforeMs, int limit = historyPageSize}) async {
  final events = await db.customSelect(
    'SELECT e.ts_start AS ts, e.play_dur_sec AS dur, m.song_id AS sid '
    'FROM play_events e JOIN song_metadata m ON m.song_id = e.song_id '
    'WHERE e.play_dur_sec >= 2 AND (? IS NULL OR e.ts_start < ?) '
    'ORDER BY e.ts_start DESC LIMIT ?',
    variables: [
      beforeMs == null ? Variable<int>(null) : Variable.withInt(beforeMs),
      beforeMs == null ? Variable<int>(null) : Variable.withInt(beforeMs),
      Variable.withInt(limit),
    ],
  ).get();
  if (events.isEmpty) return const [];
  final ids = {for (final r in events) r.read<String>('sid')};
  final metas = await (db.select(db.songMetadata)..where((t) => t.songId.isIn(ids))).get();
  final byId = {for (final m in metas) m.songId: songFromMetadata(m)};
  return [
    for (final r in events)
      if (byId[r.read<String>('sid')] case final song?)
        HistoryEntry(
          song: song,
          at: DateTime.fromMillisecondsSinceEpoch(r.read<int>('ts')),
          playedSec: r.read<int>('dur'),
        ),
  ];
}

/// The history as a growing list: the first page now, [loadMore] for older.
class HistoryState {
  const HistoryState({this.entries = const [], this.loading = true, this.reachedEnd = false});
  final List<HistoryEntry> entries;
  final bool loading;
  final bool reachedEnd;
}

class HistoryNotifier extends Notifier<HistoryState> {
  int? _cursor;
  bool _busy = false;

  @override
  HistoryState build() {
    Future.microtask(loadMore);
    return const HistoryState();
  }

  Future<void> loadMore() async {
    if (_busy || state.reachedEnd) return;
    _busy = true;
    try {
      final page = await readHistory(ref.read(appDatabaseProvider), beforeMs: _cursor);
      if (page.isNotEmpty) _cursor = page.last.at.millisecondsSinceEpoch;
      state = HistoryState(
        entries: [...state.entries, ...page],
        loading: false,
        reachedEnd: page.length < historyPageSize,
      );
    } catch (_) {
      state = HistoryState(entries: state.entries, loading: false, reachedEnd: true);
    } finally {
      _busy = false;
    }
  }
}

final historyProvider = NotifierProvider.autoDispose<HistoryNotifier, HistoryState>(HistoryNotifier.new);
