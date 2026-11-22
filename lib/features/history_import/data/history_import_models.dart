/// Models for "Import listening history": a ListenBrainz or Last.fm import and how far it has got.
/// (Server: tg-fetcher `tgfetch/history_import.py`, reached through `/history-import/*`.)
library;

enum HistorySource {
  listenbrainz('listenbrainz', 'ListenBrainz'),
  lastfm('lastfm', 'Last.fm');

  final String wire;
  final String label;
  const HistorySource(this.wire, this.label);

  static HistorySource? parse(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }
}

/// One import job: the server keeps its cursor, so it can be resumed from any device.
class HistoryJob {
  final int id;
  final HistorySource source;
  final String account;

  /// `ready` (more pages to read), `done`, `error` (can be resumed) or `cancelled`.
  final String status;

  /// Listens on the profile, when the service said (a hint for the bar).
  final int? total;
  final int fetched;

  /// Plays written to the listening log.
  final int imported;

  /// Plays of songs that are not in the library (they are on the Wishlist).
  final int wished;

  /// Listens an earlier run already had: not counted again.
  final int already;
  final int nearDups;
  final int skipped;
  final int songsMatched;
  final int songsUnmatched;
  final int? wishlistId;
  final String? error;

  /// Only listens since the last finished import were asked for.
  final bool incremental;

  const HistoryJob({
    required this.id,
    required this.source,
    required this.account,
    required this.status,
    this.total,
    this.fetched = 0,
    this.imported = 0,
    this.wished = 0,
    this.already = 0,
    this.nearDups = 0,
    this.skipped = 0,
    this.songsMatched = 0,
    this.songsUnmatched = 0,
    this.wishlistId,
    this.error,
    this.incremental = false,
  });

  bool get isDone => status == 'done';

  /// 0..1 while the total is known and the job is not finished.
  double? get progress {
    if (isDone) return 1;
    final t = total;
    if (t == null || t <= 0) return null;
    return (fetched / t).clamp(0.0, 1.0);
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  static HistoryJob? fromJson(Map<String, dynamic> j) {
    final source = HistorySource.parse(j['source']);
    if (source == null) return null;
    return HistoryJob(
      id: _int(j['id']),
      source: source,
      account: '${j['account'] ?? ''}',
      status: '${j['status'] ?? 'ready'}',
      total: j['total'] is num ? (j['total'] as num).toInt() : null,
      fetched: _int(j['fetched']),
      imported: _int(j['imported']),
      wished: _int(j['wished']),
      already: _int(j['already']),
      nearDups: _int(j['near_dups']),
      skipped: _int(j['skipped']),
      songsMatched: _int(j['songs_matched']),
      songsUnmatched: _int(j['songs_unmatched']),
      wishlistId: j['wishlist_id'] is num ? (j['wishlist_id'] as num).toInt() : null,
      error: j['error'] is String ? j['error'] as String : null,
      incremental: j['incremental'] == true,
    );
  }
}

/// The answer to reading one page.
class HistoryStep {
  final HistoryJob job;
  final bool done;

  /// Seconds the service asked us to wait before the next page (0: go on now).
  final int waitS;

  /// The job cannot go on as it is (a wrong name, a bad key): [HistoryJob.error] says what to fix.
  final bool fatal;
  const HistoryStep(this.job, {required this.done, required this.waitS, required this.fatal});
}
