/// Weekly Exploration: about 20 songs a week the listener does not own, with a 30 s preview each.
/// The server (`/weekly/exploration`, see tool/server/weekly-exploration-v1) picks and downloads;
/// these are the shapes it sends.
library;

enum PickState { pending, kept, skipped, expired }

/// Where a kept song is on its way into the library.
enum DownloadStage {
  /// Not kept.
  none,

  /// Kept, but over this week's cap or not yet reached by the night's fetch.
  waiting,

  /// Handed to the fetcher; it comes in tonight or is coming in now.
  queued,

  /// In the library: [WeeklyPick.songId] plays it.
  ready,
  failed,
}

PickState _state(Object? v) => switch (v) {
      'kept' => PickState.kept,
      'skipped' => PickState.skipped,
      'expired' => PickState.expired,
      _ => PickState.pending,
    };

DownloadStage _stage(Object? v) => switch (v) {
      'waiting' => DownloadStage.waiting,
      'queued' => DownloadStage.queued,
      'ready' => DownloadStage.ready,
      'failed' => DownloadStage.failed,
      _ => DownloadStage.none,
    };

class WeeklyPick {
  final int id;
  final String title;
  final String artist;
  final String album;
  final int? year;
  final double? durationS;
  final String? coverUrl;

  /// A 30 s clip, or null (then the song can only be heard once it is kept and downloaded).
  final String? previewUrl;

  /// "Like Aarav Kumar": why it is here.
  final String reason;

  /// A "far" pick: two steps from what the listener plays. The rest are "near".
  final bool far;
  final PickState state;

  /// The Monday this pick was made (yyyy-mm-dd).
  final String week;

  /// When an untouched pick goes.
  final DateTime? expiresAt;
  final DownloadStage download;

  /// The Navidrome song id once downloaded.
  final String? songId;

  const WeeklyPick({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.year,
    this.durationS,
    this.coverUrl,
    this.previewUrl,
    this.reason = '',
    this.far = false,
    this.state = PickState.pending,
    this.week = '',
    this.expiresAt,
    this.download = DownloadStage.none,
    this.songId,
  });

  factory WeeklyPick.fromJson(Map<String, dynamic> j) {
    final dl = j['download'] is Map ? Map<String, dynamic>.from(j['download'] as Map) : const <String, dynamic>{};
    final exp = j['expires_at'];
    return WeeklyPick(
      id: (j['id'] as num).toInt(),
      title: '${j['title'] ?? ''}',
      artist: '${j['artist'] ?? ''}',
      album: '${j['album'] ?? ''}',
      year: (j['year'] as num?)?.toInt(),
      durationS: (j['duration_s'] as num?)?.toDouble(),
      coverUrl: j['cover_url'] as String?,
      previewUrl: j['preview_url'] as String?,
      reason: '${j['reason'] ?? ''}',
      far: j['kind'] == 'far',
      state: _state(j['state']),
      week: '${j['week'] ?? ''}',
      expiresAt: exp is num ? DateTime.fromMillisecondsSinceEpoch((exp * 1000).round()) : null,
      download: _stage(dl['state']),
      songId: dl['song_id'] as String?,
    );
  }

  bool get isPending => state == PickState.pending;
  bool get isKept => state == PickState.kept;

  WeeklyPick copyWith({PickState? state, DownloadStage? download, String? songId}) => WeeklyPick(
        id: id,
        title: title,
        artist: artist,
        album: album,
        year: year,
        durationS: durationS,
        coverUrl: coverUrl,
        previewUrl: previewUrl,
        reason: reason,
        far: far,
        state: state ?? this.state,
        week: week,
        expiresAt: expiresAt,
        download: download ?? this.download,
        songId: songId ?? this.songId,
      );
}

class WeeklyExploration {
  final bool enabled;

  /// Songs a week that may be downloaded, and the most the server allows.
  final int cap;
  final int maxCap;

  /// The Monday of this week (yyyy-mm-dd).
  final String week;
  final int keptThisWeek;

  /// The list is being made (about a minute, the first open of a week).
  final bool building;
  final String? buildNote;

  /// "Downloads tonight, 1–7 am." Null when nothing is on its way.
  final String? downloadNote;
  final int nightFrom;
  final int nightTo;
  final List<WeeklyPick> picks;

  const WeeklyExploration({
    this.enabled = true,
    this.cap = 10,
    this.maxCap = 25,
    this.week = '',
    this.keptThisWeek = 0,
    this.building = false,
    this.buildNote,
    this.downloadNote,
    this.nightFrom = 1,
    this.nightTo = 7,
    this.picks = const [],
  });

  factory WeeklyExploration.fromJson(Map<String, dynamic> j) {
    final night = j['night'] is Map ? Map<String, dynamic>.from(j['night'] as Map) : const <String, dynamic>{};
    return WeeklyExploration(
      enabled: j['enabled'] != false,
      cap: (j['cap'] as num?)?.toInt() ?? 10,
      maxCap: (j['max_cap'] as num?)?.toInt() ?? 25,
      week: '${j['week'] ?? ''}',
      keptThisWeek: (j['kept_this_week'] as num?)?.toInt() ?? 0,
      building: j['building'] == true,
      buildNote: j['build_note'] as String?,
      downloadNote: j['download_note'] as String?,
      nightFrom: (night['from'] as num?)?.toInt() ?? 1,
      nightTo: (night['to'] as num?)?.toInt() ?? 7,
      picks: [for (final p in (j['picks'] as List?) ?? const []) WeeklyPick.fromJson(Map<String, dynamic>.from(p as Map))],
    );
  }

  /// Still to decide, this week's first.
  List<WeeklyPick> get pending => [for (final p in picks) if (p.isPending) p];
  List<WeeklyPick> get kept => [for (final p in picks) if (p.isKept) p];

  WeeklyExploration copyWith({List<WeeklyPick>? picks, bool? enabled, int? cap, int? keptThisWeek}) => WeeklyExploration(
        enabled: enabled ?? this.enabled,
        cap: cap ?? this.cap,
        maxCap: maxCap,
        week: week,
        keptThisWeek: keptThisWeek ?? this.keptThisWeek,
        building: building,
        buildNote: buildNote,
        downloadNote: downloadNote,
        nightFrom: nightFrom,
        nightTo: nightTo,
        picks: picks ?? this.picks,
      );
}
