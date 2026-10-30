// The download queue as the shuffle server's `GET /fetch/queue` reports it
// (tg-fetcher): batches waiting, downloading and recently finished. Plain
// immutable values; unknown fields ignored so the server can grow.

enum QueueStatus {
  queued,
  running,
  done,
  failed,
  cancelled;

  /// 'listing' is the server fetching the track list: already on its way.
  static QueueStatus parse(Object? v) => switch (v) {
        'queued' => queued,
        'listing' || 'running' => running,
        'done' => done,
        'cancelled' => cancelled,
        _ => failed,
      };
}

class FetchQueueItem {
  final int id;

  /// Whose download it is (an admin sees everyone's).
  final String user;

  /// album, playlist, label, artist, or songs for a loose selection.
  final String kind;
  final String title;
  final String artist;
  final String? coverUrl;
  final QueueStatus status;
  final String? error;

  /// A pasted / shared playlist link rather than a picked result.
  final bool isLink;

  /// 1 = next, among every user's queued downloads; null once it has started.
  final int? position;

  /// The song being downloaded right now ("Title — Artist").
  final String? current;
  final int total;
  final int added;
  final int owned;
  final int lossy;
  final int failed;

  /// 0–1 over the whole batch.
  final double progress;

  /// The server's own sentence once it's done ("12 songs added, 2 already owned").
  final String? summary;

  const FetchQueueItem({
    required this.id,
    required this.title,
    required this.status,
    this.user = '',
    this.kind = 'songs',
    this.artist = '',
    this.coverUrl,
    this.error,
    this.isLink = false,
    this.position,
    this.current,
    this.total = 0,
    this.added = 0,
    this.owned = 0,
    this.lossy = 0,
    this.failed = 0,
    this.progress = 0,
    this.summary,
  });

  /// Songs settled so far, whatever the outcome.
  int get handled => added + owned + lossy + failed;

  bool get canCancel => status == QueueStatus.queued || status == QueueStatus.running;
  bool get canRetry => status == QueueStatus.failed || status == QueueStatus.cancelled;

  factory FetchQueueItem.fromJson(Map<String, dynamic> j) => FetchQueueItem(
        id: (j['id'] as num).toInt(),
        user: j['user'] as String? ?? '',
        kind: j['kind'] as String? ?? 'songs',
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        coverUrl: j['cover_url'] as String?,
        status: QueueStatus.parse(j['status']),
        error: j['error'] as String?,
        isLink: j['is_link'] == true,
        position: (j['position'] as num?)?.toInt(),
        current: j['current'] as String?,
        total: (j['total'] as num?)?.toInt() ?? 0,
        added: (j['added'] as num?)?.toInt() ?? 0,
        owned: (j['owned'] as num?)?.toInt() ?? 0,
        lossy: (j['lossy'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        progress: ((j['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        summary: j['summary'] as String?,
      );
}

class FetchQueue {
  /// This account is an admin: it sees everyone's downloads and can reorder.
  final bool admin;

  /// Playlist links a non-admin may have waiting at once; null = no limit.
  final int? maxLinks;

  /// Running first, then queued in running order, then the latest finished.
  final List<FetchQueueItem> items;

  const FetchQueue({this.admin = false, this.maxLinks, this.items = const []});

  List<FetchQueueItem> get active => [for (final i in items) if (i.canCancel) i];
  List<FetchQueueItem> get finished => [for (final i in items) if (!i.canCancel) i];

  factory FetchQueue.fromJson(Map<String, dynamic> j) => FetchQueue(
        admin: j['admin'] == true,
        maxLinks: (j['max_links'] as num?)?.toInt(),
        items: [
          for (final i in (j['items'] as List? ?? const []))
            if (i is Map) FetchQueueItem.fromJson(Map<String, dynamic>.from(i)),
        ],
      );
}
