/// Models for "Import Spotify History": the job the server keeps for a person's Spotify import and what it found.
/// (Server: tg-fetcher `tgfetch/spotify_history.py`, reached through `/spotify-import/*`.)
library;

class SpotifyJob {
  final int id;

  /// `ready` (pages still coming), `done`, `error` or `cancelled`.
  final String status;

  /// Plays the app said it would send (a hint for the bar).
  final int? total;
  final int fetched;

  /// Plays written to the listening log.
  final int imported;

  /// Listens of songs that are not in the library (they are on the Wishlist).
  final int wished;

  /// Plays an earlier run already had: not counted again.
  final int already;
  final int nearDups;

  /// Plays the server refused as malformed, in total and by reason.
  final int rejectedTotal;
  final Map<String, int> rejected;
  final int skips;
  final int listens;

  /// Short plays that ended another way (logout, app closed): neither a skip nor a listen, not imported.
  final int unclear;
  final int songsMatched;
  final int songsUnmatched;
  final int? wishlistId;
  final int? oldestTs;
  final int? newestTs;
  final String? error;

  const SpotifyJob({
    required this.id,
    required this.status,
    this.total,
    this.fetched = 0,
    this.imported = 0,
    this.wished = 0,
    this.already = 0,
    this.nearDups = 0,
    this.rejectedTotal = 0,
    this.rejected = const {},
    this.skips = 0,
    this.listens = 0,
    this.unclear = 0,
    this.songsMatched = 0,
    this.songsUnmatched = 0,
    this.wishlistId,
    this.oldestTs,
    this.newestTs,
    this.error,
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
  static int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

  factory SpotifyJob.fromJson(Map<String, dynamic> j) {
    final rej = j['rejected'];
    return SpotifyJob(
      id: _int(j['id']),
      status: '${j['status'] ?? 'ready'}',
      total: _intOrNull(j['total']),
      fetched: _int(j['fetched']),
      imported: _int(j['imported']),
      wished: _int(j['wished']),
      already: _int(j['already']),
      nearDups: _int(j['near_dups']),
      rejectedTotal: _int(j['rejected_total']),
      rejected: rej is Map ? {for (final e in rej.entries) '${e.key}': _int(e.value)} : const {},
      skips: _int(j['skips']),
      listens: _int(j['listens']),
      unclear: _int(j['unclear']),
      songsMatched: _int(j['songs_matched']),
      songsUnmatched: _int(j['songs_unmatched']),
      wishlistId: _intOrNull(j['wishlist_id']),
      oldestTs: _intOrNull(j['oldest_ts']),
      newestTs: _intOrNull(j['newest_ts']),
      error: j['error'] is String ? j['error'] as String : null,
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Nov 2026" for a UTC epoch-seconds time.
String monthYear(int epochS) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochS * 1000, isUtc: true);
  return '${_months[d.month - 1]} ${d.year}';
}
