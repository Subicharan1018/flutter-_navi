/// Complete the album overnight: when a song you asked for lands, the rest of its film album is queued for the
/// night. The server (`/exportify/album-overnight`, see tool/server/album-overnight-v1) finds and downloads;
/// these are the shapes it sends.
library;

/// Where one track of a queued album is.
enum TrackStage { waiting, queued, ready, failed, cancelled }

/// Where a whole album is.
enum AlbumStage {
  /// Tracks are waiting for tonight's fetch.
  waiting,

  /// The bot has some of them now.
  queued,

  /// Every queued track is in the library.
  done,

  /// Some tracks did not come in and will be tried again.
  failed,

  /// The library already had all of it.
  nothing,
}

TrackStage _track(Object? v) => switch (v) {
      'queued' => TrackStage.queued,
      'ready' => TrackStage.ready,
      'failed' => TrackStage.failed,
      'cancelled' => TrackStage.cancelled,
      _ => TrackStage.waiting,
    };

AlbumStage _album(Object? v) => switch (v) {
      'queued' => AlbumStage.queued,
      'done' => AlbumStage.done,
      'failed' => AlbumStage.failed,
      'nothing' => AlbumStage.nothing,
      _ => AlbumStage.waiting,
    };

class AlbumTrack {
  final int id;
  final String title;
  final String artist;
  final int number;
  final TrackStage stage;

  /// The Navidrome song id once it is in the library.
  final String? songId;

  const AlbumTrack({
    required this.id,
    required this.title,
    this.artist = '',
    this.number = 0,
    this.stage = TrackStage.waiting,
    this.songId,
  });

  factory AlbumTrack.fromJson(Map<String, dynamic> j) => AlbumTrack(
        id: (j['id'] as num).toInt(),
        title: '${j['title'] ?? ''}',
        artist: '${j['artist'] ?? ''}',
        number: (j['number'] as num?)?.toInt() ?? 0,
        stage: _track(j['state']),
        songId: j['song_id'] as String?,
      );
}

class QueuedAlbum {
  final int id;
  final String album;
  final String artist;
  final String? coverUrl;
  final AlbumStage stage;

  /// Tracks the album has that count (owned + queued), and how many of them you already had.
  final int total;
  final int owned;

  /// The song you fetched that led to this album.
  final String fromSong;
  final DateTime? addedAt;
  final int waiting;
  final int queued;
  final int ready;
  final int failed;
  final List<AlbumTrack> tracks;

  const QueuedAlbum({
    required this.id,
    required this.album,
    this.artist = '',
    this.coverUrl,
    this.stage = AlbumStage.waiting,
    this.total = 0,
    this.owned = 0,
    this.fromSong = '',
    this.addedAt,
    this.waiting = 0,
    this.queued = 0,
    this.ready = 0,
    this.failed = 0,
    this.tracks = const [],
  });

  factory QueuedAlbum.fromJson(Map<String, dynamic> j) {
    final c = j['counts'] is Map ? Map<String, dynamic>.from(j['counts'] as Map) : const <String, dynamic>{};
    final at = j['added_at'];
    return QueuedAlbum(
      id: (j['id'] as num).toInt(),
      album: '${j['album'] ?? ''}',
      artist: '${j['artist'] ?? ''}',
      coverUrl: j['cover_url'] as String?,
      stage: _album(j['state']),
      total: (j['total'] as num?)?.toInt() ?? 0,
      owned: (j['owned'] as num?)?.toInt() ?? 0,
      fromSong: '${j['from_song'] ?? ''}',
      addedAt: at is num ? DateTime.fromMillisecondsSinceEpoch((at * 1000).round()) : null,
      waiting: (c['waiting'] as num?)?.toInt() ?? 0,
      queued: (c['queued'] as num?)?.toInt() ?? 0,
      ready: (c['ready'] as num?)?.toInt() ?? 0,
      failed: (c['failed'] as num?)?.toInt() ?? 0,
      tracks: [
        for (final t in (j['tracks'] as List?) ?? const [])
          if (t is Map) AlbumTrack.fromJson(Map<String, dynamic>.from(t)),
      ],
    );
  }

  /// Tracks still to come into the library.
  int get toCome => waiting + queued + failed;

  /// A one-line state for the row: "3 tonight · 2 in your library".
  String get line {
    if (stage == AlbumStage.nothing) return 'You already have all of it';
    final parts = <String>[
      if (queued > 0) '$queued on their way',
      if (waiting > 0) '$waiting waiting for tonight',
      if (failed > 0) '$failed to try again',
      if (ready > 0) '$ready in your library',
    ];
    return parts.isEmpty ? 'Nothing left to fetch' : parts.join(' · ');
  }
}

class AlbumOvernight {
  final bool enabled;

  /// Only film albums (soundtrack, score, "From …", an Indian film genre).
  final bool filmOnly;
  final int perNight;
  final List<int> perNightChoices;
  final int maxPerAlbum;
  final List<int> maxPerAlbumChoices;

  /// Tracks waiting or on their way, and the most the server queues at once.
  final int waiting;
  final int maxWaiting;

  /// "Downloads tonight, 1–7 am." Null when nothing is on its way.
  final String? downloadNote;
  final int nightFrom;
  final int nightTo;
  final List<QueuedAlbum> albums;

  const AlbumOvernight({
    this.enabled = false,
    this.filmOnly = true,
    this.perNight = 30,
    this.perNightChoices = const [10, 20, 30, 50, 100],
    this.maxPerAlbum = 25,
    this.maxPerAlbumChoices = const [5, 10, 15, 25, 40],
    this.waiting = 0,
    this.maxWaiting = 150,
    this.downloadNote,
    this.nightFrom = 1,
    this.nightTo = 7,
    this.albums = const [],
  });

  factory AlbumOvernight.fromJson(Map<String, dynamic> j) {
    final night = j['night'] is Map ? Map<String, dynamic>.from(j['night'] as Map) : const <String, dynamic>{};
    List<int> ints(Object? v, List<int> d) =>
        v is List && v.isNotEmpty ? [for (final n in v) if (n is num) n.toInt()] : d;
    return AlbumOvernight(
      enabled: j['enabled'] == true,
      filmOnly: j['film_only'] != false,
      perNight: (j['per_night'] as num?)?.toInt() ?? 30,
      perNightChoices: ints(j['per_night_choices'], const [10, 20, 30, 50, 100]),
      maxPerAlbum: (j['max_per_album'] as num?)?.toInt() ?? 25,
      maxPerAlbumChoices: ints(j['max_per_album_choices'], const [5, 10, 15, 25, 40]),
      waiting: (j['waiting'] as num?)?.toInt() ?? 0,
      maxWaiting: (j['max_waiting'] as num?)?.toInt() ?? 150,
      downloadNote: j['download_note'] as String?,
      nightFrom: (night['from'] as num?)?.toInt() ?? 1,
      nightTo: (night['to'] as num?)?.toInt() ?? 7,
      albums: [
        for (final a in (j['albums'] as List?) ?? const [])
          if (a is Map) QueuedAlbum.fromJson(Map<String, dynamic>.from(a)),
      ],
    );
  }

  AlbumOvernight copyWith({bool? enabled, bool? filmOnly, int? perNight, int? maxPerAlbum, List<QueuedAlbum>? albums}) =>
      AlbumOvernight(
        enabled: enabled ?? this.enabled,
        filmOnly: filmOnly ?? this.filmOnly,
        perNight: perNight ?? this.perNight,
        perNightChoices: perNightChoices,
        maxPerAlbum: maxPerAlbum ?? this.maxPerAlbum,
        maxPerAlbumChoices: maxPerAlbumChoices,
        waiting: waiting,
        maxWaiting: maxWaiting,
        downloadNote: downloadNote,
        nightFrom: nightFrom,
        nightTo: nightTo,
        albums: albums ?? this.albums,
      );

  /// Albums that still have tracks to come (what "Cancel all" would stop).
  List<QueuedAlbum> get open => [for (final a in albums) if (a.toCome > 0) a];
}

/// What cancelling did: tracks dropped, and tracks already with the bot (they finish).
class CancelResult {
  final int stopped;
  final int alreadyOnItsWay;
  const CancelResult(this.stopped, this.alreadyOnItsWay);

  factory CancelResult.fromJson(Map<String, dynamic> j) =>
      CancelResult((j['stopped'] as num?)?.toInt() ?? 0, (j['already_on_its_way'] as num?)?.toInt() ?? 0);
}
