// What the admin's data queue screen reads from the shuffle server's `/data-queue` routes
// (tool/server/data-queue-v1). Only the admin ever gets an answer; everyone else gets a 404.

int _int(Object? v) => v is num ? v.toInt() : 0;

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

/// Library songs with real Spotify audio features / predicted ones / none.
class QueueCoverage {
  final int total;
  final int real;
  final int predicted;
  final int none;
  const QueueCoverage({this.total = 0, this.real = 0, this.predicted = 0, this.none = 0});

  factory QueueCoverage.fromJson(Map<String, dynamic> j) =>
      QueueCoverage(total: _int(j['total']), real: _int(j['real']), predicted: _int(j['predicted']), none: _int(j['none']));

  /// 0..1 of the library; 0 when it is empty.
  double share(int n) => total <= 0 ? 0 : n / total;
}

/// What Spotify and the model gave back for one uploaded Exportify file.
class UploadSummary {
  final int batchId;
  final int rows;
  final int matched;
  final int notFound;
  final int onSpotifyWithoutFeatures;
  final int featuresStored;
  final int predicted;
  final bool repeated;
  const UploadSummary({
    required this.batchId,
    this.rows = 0,
    this.matched = 0,
    this.notFound = 0,
    this.onSpotifyWithoutFeatures = 0,
    this.featuresStored = 0,
    this.predicted = 0,
    this.repeated = false,
  });

  factory UploadSummary.fromJson(Map<String, dynamic> j) => UploadSummary(
        batchId: _int(j['batch_id']),
        rows: _int(j['rows']),
        matched: _int(j['matched']),
        notFound: _int(j['not_found']),
        onSpotifyWithoutFeatures: _int(j['on_spotify_without_features']),
        featuresStored: _int(j['features_stored']),
        predicted: _int(j['predicted']),
        repeated: j['repeated'] == true,
      );
}

/// One weekly batch: open (waiting for its Exportify file), closed (applied) or released.
class QueueBatch {
  final int id;
  final String state;
  final int size;
  final DateTime createdAt;
  final DateTime? uploadedAt;
  final UploadSummary? summary;
  const QueueBatch({
    required this.id,
    required this.state,
    required this.size,
    required this.createdAt,
    this.uploadedAt,
    this.summary,
  });

  bool get isOpen => state == 'open';

  static DateTime _at(Object? v) => DateTime.fromMillisecondsSinceEpoch((v is num ? v * 1000 : 0).round());

  factory QueueBatch.fromJson(Map<String, dynamic> j) => QueueBatch(
        id: _int(j['id']),
        state: '${j['state'] ?? 'open'}',
        size: _int(j['size']),
        createdAt: _at(j['created_at']),
        uploadedAt: j['uploaded_at'] == null ? null : _at(j['uploaded_at']),
        summary: j['summary'] is Map ? UploadSummary.fromJson(_map(j['summary'])) : null,
      );
}

/// The batch the next "Make this week's batch" would take.
class NextBatch {
  final int size;
  final bool full;
  final int withIsrc;
  const NextBatch({this.size = 0, this.full = false, this.withIsrc = 0});

  factory NextBatch.fromJson(Map<String, dynamic> j) =>
      NextBatch(size: _int(j['size']), full: j['full'] == true, withIsrc: _int(j['with_isrc']));
}

class QueueStatus {
  final int waiting;
  final int batchSize;
  final bool fullBatchReady;
  final NextBatch next;
  final QueueBatch? openBatch;
  final QueueCoverage coverage;

  /// Where the waiting songs came from (`request`, `youtube`, `exportify`, `backfill` ...).
  final Map<String, int> waitingBySource;
  final double? oldestWaitingDays;

  /// Share of judged songs Spotify had (0..1), null before the first upload.
  final double? matchRate;
  final Map<String, String> links;
  const QueueStatus({
    required this.waiting,
    required this.batchSize,
    required this.fullBatchReady,
    required this.next,
    required this.openBatch,
    required this.coverage,
    this.waitingBySource = const {},
    this.oldestWaitingDays,
    this.matchRate,
    this.links = const {},
  });

  factory QueueStatus.fromJson(Map<String, dynamic> j) {
    final q = _map(j['quality']);
    return QueueStatus(
      waiting: _int(j['waiting']),
      batchSize: _int(j['batch_size']) == 0 ? 200 : _int(j['batch_size']),
      fullBatchReady: j['full_batch_ready'] == true,
      next: NextBatch.fromJson(_map(j['next_batch'])),
      openBatch: j['open_batch'] is Map ? QueueBatch.fromJson(_map(j['open_batch'])) : null,
      coverage: QueueCoverage.fromJson(_map(j['coverage'])),
      waitingBySource: {
        for (final e in _map(q['waiting_by_source']).entries) e.key: _int(e.value),
      },
      oldestWaitingDays: (q['oldest_waiting_days'] as num?)?.toDouble(),
      matchRate: (q['match_rate'] as num?)?.toDouble(),
      links: {for (final e in _map(j['links']).entries) e.key: '${e.value}'},
    );
  }
}
