/// Models for "Import a Spotify playlist from an Exportify CSV": what the server
/// matched, what is on the Wishlist, and the plan for fetching it.
/// (Server: tg-fetcher `tgfetch/exportify.py`, reached through `/exportify/*`.)
library;

/// A song's place in the import.
enum WishlistState {
  owned,
  wishlist,
  queued,
  downloaded,
  failed,
  skippedDisk;

  static WishlistState parse(Object? v) => switch (v) {
        'owned' => owned,
        'queued' => queued,
        'downloaded' => downloaded,
        'failed' => failed,
        'skipped_disk' => skippedDisk,
        _ => wishlist,
      };

  /// The name the server uses in `/songs/<state>/<page>`.
  String get wire => this == skippedDisk ? 'skipped_disk' : name;
}

/// Which songs are fetched first.
enum ExportifyOrder {
  popularity,
  list;

  static ExportifyOrder parse(Object? v) => v == 'list' ? list : popularity;
}

enum PlanStatus {
  idle,
  active,
  paused,
  pausedDisk,
  done,
  cancelled;

  static PlanStatus parse(Object? v) => switch (v) {
        'active' => active,
        'paused' => paused,
        'paused_disk' => pausedDisk,
        'done' => done,
        'cancelled' => cancelled,
        _ => idle,
      };

  /// The server may queue a batch.
  bool get running => this == active || this == pausedDisk;
}

/// The settings of a fetch. A record, so equal drafts are equal keys for providers.
typedef PlanDraft = ({ExportifyOrder order, int minPopularity, int perNight, int floorGb, bool nightOnly});

const PlanDraft defaultPlanDraft = (
  order: ExportifyOrder.popularity,
  minPopularity: 0,
  perNight: 100,
  floorGb: 40,
  nightOnly: true,
);

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
double _double(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : fallback;

class ExportifyPlan {
  final PlanStatus status;
  final PlanDraft draft;

  /// What the server says is going on ("Paused: disk is low (31 GB free, floor 40 GB).").
  final String? note;

  const ExportifyPlan({required this.status, required this.draft, this.note});

  factory ExportifyPlan.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    return ExportifyPlan(
      status: PlanStatus.parse(m['status']),
      note: m['note'] is String && (m['note'] as String).isNotEmpty ? m['note'] as String : null,
      draft: (
        order: ExportifyOrder.parse(m['priority']),
        minPopularity: _int(m['min_popularity']),
        perNight: _int(m['per_night'], defaultPlanDraft.perNight),
        floorGb: _double(m['disk_floor_gb'], defaultPlanDraft.floorGb.toDouble()).round(),
        nightOnly: m['night_only'] != false,
      ),
    );
  }
}

/// The wire form of a plan (the body of PUT /plan, POST /start, POST /estimate).
Map<String, Object> planBody(PlanDraft d) => {
      'priority': d.order.name,
      'min_popularity': d.minPopularity,
      'per_night': d.perNight,
      'disk_floor_gb': d.floorGb,
      'night_only': d.nightOnly,
    };

/// One import: how many songs, how many matched, what is left to fetch.
class ExportifySummary {
  final int id;
  final String name;

  /// Rows in the file, including repeats and rows without a title.
  final int rows;

  /// Different songs after repeats are folded together.
  final int unique;
  final int duplicates;
  final int skippedRows;
  final int noIsrc;

  /// On the wishlist, but a song in the library has this title and artist at another length.
  final int maybeOwned;
  final String? playlistId;
  final Map<WishlistState, int> states;

  /// Estimated size of what is not in the library yet.
  final double wishlistGb;
  final double? freeGb;
  final ExportifyPlan plan;

  /// Navidrome ids of the songs in the library, in the file's order. Only sent right after the import.
  final List<String> ownedIds;

  const ExportifySummary({
    required this.id,
    required this.name,
    required this.rows,
    required this.unique,
    required this.duplicates,
    required this.skippedRows,
    required this.noIsrc,
    required this.maybeOwned,
    required this.playlistId,
    required this.states,
    required this.wishlistGb,
    required this.freeGb,
    required this.plan,
    this.ownedIds = const [],
  });

  factory ExportifySummary.fromJson(Map<String, dynamic> j) {
    final raw = j['states'] is Map ? j['states'] as Map : const {};
    return ExportifySummary(
      id: _int(j['id']),
      name: (j['name'] as String?)?.trim().isNotEmpty == true ? (j['name'] as String).trim() : 'Spotify playlist',
      rows: _int(j['rows']),
      unique: _int(j['unique']),
      duplicates: _int(j['duplicates']),
      skippedRows: _int(j['skipped_rows']),
      noIsrc: _int(j['no_isrc']),
      maybeOwned: _int(j['maybe_owned']),
      playlistId: j['playlist_id'] as String?,
      states: {for (final s in WishlistState.values) s: _int(raw[s.wire])},
      wishlistGb: _double(j['wishlist_gb']),
      freeGb: j['free_gb'] is num ? (j['free_gb'] as num).toDouble() : null,
      plan: ExportifyPlan.fromJson(j['plan']),
      ownedIds: [for (final id in (j['owned_ids'] as List?) ?? const []) '$id'],
    );
  }

  int count(WishlistState s) => states[s] ?? 0;

  /// Songs already in the library (matched, or fetched since).
  int get inLibrary => count(WishlistState.owned) + count(WishlistState.downloaded);

  /// Songs not in the library yet, whatever is happening to them.
  int get onWishlist => unique - inLibrary;

  /// Waiting for a fetch: on the wishlist and not in flight.
  int get waiting => count(WishlistState.wishlist) + count(WishlistState.skippedDisk);

  /// A fetch has begun (or finished): there is progress to show.
  bool get hasFetch => plan.status != PlanStatus.idle || count(WishlistState.queued) + count(WishlistState.downloaded) + count(WishlistState.failed) > 0;
}

/// What a fetch would cost with the current settings.
class ExportifyEstimate {
  final int songs;
  final double gb;
  final double hours;
  final double freeGb;
  final double floorGb;

  /// How many of the songs fit above the floor.
  final int fits;
  final int nights;

  /// Bot time, at about 20 s a song.
  final double botHours;
  final double gbPerHour;

  const ExportifyEstimate({
    required this.songs,
    required this.gb,
    required this.hours,
    required this.freeGb,
    required this.floorGb,
    required this.fits,
    required this.nights,
    required this.botHours,
    required this.gbPerHour,
  });

  factory ExportifyEstimate.fromJson(Map<String, dynamic> j) => ExportifyEstimate(
        songs: _int(j['songs']),
        gb: _double(j['gb']),
        hours: _double(j['hours']),
        freeGb: _double(j['free_gb']),
        floorGb: _double(j['floor_gb']),
        fits: _int(j['fits']),
        nights: _int(j['nights']),
        botHours: _double(j['bot_hours']),
        gbPerHour: _double(j['gb_per_hour'], 0.51),
      );

  /// Some of it would not fit above the floor.
  bool get tooBig => fits < songs;
}

/// One song of the import, as listed on the failed / skipped lists.
class ExportifySong {
  final String title;
  final String artist;
  final WishlistState state;
  final int popularity;

  /// Why it didn't come in (failed songs).
  final String? error;

  const ExportifySong({
    required this.title,
    required this.artist,
    required this.state,
    required this.popularity,
    this.error,
  });

  factory ExportifySong.fromJson(Map<String, dynamic> j) => ExportifySong(
        title: (j['title'] as String?) ?? '',
        artist: ((j['artist'] as String?) ?? '').split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', '),
        state: WishlistState.parse(j['state']),
        popularity: _int(j['popularity']),
        error: j['error'] as String?,
      );
}

/// "6,922" — thousands separated, no locale package needed.
String groupThousands(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// "17 GB", "0.5 GB": whole numbers from 10 up, one decimal below.
String formatGb(double gb) => gb >= 10 ? '${gb.round()} GB' : '${(gb * 10).round() / 10} GB';
