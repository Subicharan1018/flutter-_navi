// "Search online" data, as returned by the shuffle server's /fetch routes
// (which proxy tg-fetcher). Plain immutable values; unknown fields ignored so
// the server can grow without breaking older apps.

/// What kind of recording a result is. Anything but [original] is labelled in
/// the list so a cover or remix is never picked by mistake.
enum FetchKind {
  original,
  cover,
  remix,
  instrumental,
  karaoke,
  dub,
  live,
  version;

  static FetchKind parse(Object? v) =>
      FetchKind.values.firstWhere((k) => k.name == v, orElse: () => FetchKind.version);

  /// Short label for the list, or null for the original.
  String? get label => switch (this) {
        FetchKind.original => null,
        FetchKind.cover => 'Cover',
        FetchKind.remix => 'Remix',
        FetchKind.instrumental => 'Instrumental',
        FetchKind.karaoke => 'Karaoke',
        FetchKind.dub => 'Other language',
        FetchKind.live => 'Live',
        FetchKind.version => 'Other version',
      };
}

/// What to search online for. [song] is the default; the others list whole
/// albums, artists or playlists.
enum FetchSearchType {
  song('Songs', 'Song, film or artist'),
  album('Albums', 'Album or film'),
  artist('Artists', 'Artist'),
  playlist('Playlists', 'Playlist');

  const FetchSearchType(this.label, this.placeholder);
  final String label;
  final String placeholder;

  static FetchSearchType parse(Object? v) =>
      FetchSearchType.values.firstWhere((t) => t.name == v, orElse: () => FetchSearchType.song);
}

/// Why [text] can't be sent as a playlist link, or null when it can — the
/// same rules (and words) as the server, so a bad paste is caught at once.
/// The music bot takes Deezer and Spotify playlist links; it ignores YouTube.
String? playlistLinkProblem(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
    return 'Paste a playlist link (it starts with https://).';
  }
  final host = uri.host.toLowerCase();
  final path = uri.path;
  if (host == 'deezer.com' || host == 'www.deezer.com') {
    return RegExp(r'^/(?:[a-z]{2}(?:-[a-z]{2})?/)?playlist/\d+/?$', caseSensitive: false).hasMatch(path)
        ? null
        : 'That Deezer link isn’t a playlist. Open the playlist and copy its link.';
  }
  if (host == 'open.spotify.com') {
    return RegExp(r'^/(?:intl-[a-z]{2}(?:-[a-z]{2})?/)?playlist/[A-Za-z0-9]{10,40}/?$').hasMatch(path)
        ? null
        : 'That Spotify link isn’t a playlist. Open the playlist and copy its link.';
  }
  if (host.endsWith('youtube.com') || host == 'youtu.be' || host.endsWith('music.apple.com')) {
    return 'Only Deezer and Spotify playlist links work. The music bot doesn’t take this site.';
  }
  return 'Only Deezer and Spotify playlist links work.';
}

/// Looks like a link the user meant to send (anything starting with http).
bool looksLikeLink(String text) => RegExp(r'^\s*https?://', caseSensitive: false).hasMatch(text);

/// One result the user can pick ("Is this the song?"), or an album, artist or
/// playlist ([type]).
class FetchCandidate {
  final int id;
  final String title;

  /// The artist; for a playlist, who made it.
  final String artist;
  final String album;
  final double score;
  final FetchKind kind;
  final FetchSearchType type;

  /// Albums and playlists: how many songs.
  final int? trackCount;

  /// Already in the Navidrome library under this exact title and artist.
  final bool inLibrary;

  /// The AI check has looked at this result.
  final bool aiChecked;

  /// Album art the source shows with this result (a public CDN image).
  final String? coverUrl;

  const FetchCandidate({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.score,
    required this.kind,
    required this.inLibrary,
    required this.aiChecked,
    this.coverUrl,
    this.type = FetchSearchType.song,
    this.trackCount,
  });

  bool get isSong => type == FetchSearchType.song;

  factory FetchCandidate.fromJson(Map<String, dynamic> j) => FetchCandidate(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? '',
        score: (j['score'] as num?)?.toDouble() ?? 0,
        kind: FetchKind.parse(j['kind']),
        inLibrary: j['library'] == 'in_library',
        aiChecked: j['llm'] != null,
        coverUrl: j['cover_url'] as String?,
        type: FetchSearchType.parse(j['type']),
        trackCount: (j['track_count'] as num?)?.toInt(),
      );
}

/// A library song that matched the typed query before anything was searched.
class LibraryMatch {
  final String songId;
  final String title;
  final String artist;
  const LibraryMatch({required this.songId, required this.title, required this.artist});

  factory LibraryMatch.fromJson(Map<String, dynamic> j) => LibraryMatch(
        songId: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
      );
}

enum FetchSearchStatus { queued, searching, done, noResults, inLibrary, failed }

class FetchSearch {
  final int id;
  final String query;

  /// A pasted playlist link's playlist name.
  final String? title;
  final FetchSearchStatus status;
  final String? didYouMean;

  /// The AI check is still running; candidates may be re-ordered when it lands.
  final bool aiPending;
  final String? error;

  /// Owned songs matching the query (set when [status] is inLibrary).
  final List<LibraryMatch> libraryMatches;
  final List<FetchCandidate> candidates;

  const FetchSearch({
    required this.id,
    required this.query,
    required this.status,
    this.title,
    this.didYouMean,
    this.aiPending = false,
    this.error,
    this.libraryMatches = const [],
    this.candidates = const [],
  });

  bool get isSearching => status == FetchSearchStatus.queued || status == FetchSearchStatus.searching;

  /// Nothing left to poll for: the search finished and the AI check (if any)
  /// has answered.
  bool get isSettled => !isSearching && !aiPending;

  static FetchSearchStatus _status(Object? v) => switch (v) {
        'queued' => FetchSearchStatus.queued,
        'searching' => FetchSearchStatus.searching,
        'done' => FetchSearchStatus.done,
        'no_results' => FetchSearchStatus.noResults,
        'in_library' => FetchSearchStatus.inLibrary,
        _ => FetchSearchStatus.failed,
      };

  factory FetchSearch.fromJson(Map<String, dynamic> j) {
    final library = j['library'];
    final matches = library is Map && library['verdict'] == 'in_library'
        ? [for (final m in (library['matches'] as List? ?? const [])) LibraryMatch.fromJson(m as Map<String, dynamic>)]
        : const <LibraryMatch>[];
    return FetchSearch(
      id: (j['id'] as num).toInt(),
      query: j['query'] as String? ?? '',
      title: j['title'] as String?,
      status: _status(j['status']),
      didYouMean: j['did_you_mean'] as String?,
      aiPending: j['llm_state'] == 'pending',
      error: j['error'] as String?,
      libraryMatches: matches,
      candidates: [
        for (final c in (j['candidates'] as List? ?? const [])) FetchCandidate.fromJson(c as Map<String, dynamic>),
      ],
    );
  }
}

/// Where a download is, in the words the user sees.
enum FetchJobPhase {
  /// Waiting, or asking the source for the file.
  preparing,
  downloading,

  /// Tagging, moving into the library, waiting for Navidrome to index it.
  adding,
  ready,

  /// The song was already in the library or already downloaded.
  duplicate,

  /// The source only has a lossy file; nothing was downloaded.
  rejected,
  failed,
}

class FetchJob {
  final int id;
  final int candidateId;
  final FetchJobPhase phase;

  /// 0–1 while downloading.
  final double progress;

  /// The Navidrome song, once [phase] is ready (or duplicate of a library song).
  final String? songId;
  final String? error;
  final String? title;
  final String? artist;

  const FetchJob({
    required this.id,
    required this.candidateId,
    required this.phase,
    this.progress = 0,
    this.songId,
    this.error,
    this.title,
    this.artist,
  });

  bool get isFinished => switch (phase) {
        FetchJobPhase.ready || FetchJobPhase.duplicate || FetchJobPhase.rejected || FetchJobPhase.failed => true,
        _ => false,
      };

  static FetchJobPhase phaseOf(Object? v) => switch (v) {
        // 'waiting': a pasted link's song, waiting for the bot to post its file.
        'queued' || 'checking' || 'picking' || 'waiting' => FetchJobPhase.preparing,
        'downloading' => FetchJobPhase.downloading,
        // 'downloaded' and 'imported' are on their way into the library.
        'downloaded' || 'tagging' || 'moving' || 'scanning' || 'imported' => FetchJobPhase.adding,
        'ready' => FetchJobPhase.ready,
        'duplicate' => FetchJobPhase.duplicate,
        'rejected' => FetchJobPhase.rejected,
        _ => FetchJobPhase.failed,
      };

  /// Also reads a batch's items, which carry no job id.
  factory FetchJob.fromJson(Map<String, dynamic> j) => FetchJob(
        id: (j['id'] as num?)?.toInt() ?? 0,
        candidateId: (j['candidate_id'] as num?)?.toInt() ?? 0,
        phase: phaseOf(j['status']),
        progress: ((j['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        songId: j['nd_song_id'] as String?,
        error: j['error'] as String?,
        title: j['title'] as String?,
        artist: j['artist'] as String?,
      );
}

enum FetchBatchStatus {
  /// Created, or the server is fetching the album's / playlist's track list.
  starting,
  running,
  done,
  failed,
}

/// Several songs downloaded together, or a whole album / playlist / an
/// artist's top songs: one entry with overall progress, one item per track.
class FetchBatch {
  /// The server's id; 0 until it has answered the request.
  final int id;

  /// album, playlist or artist for one picked collection; null for songs.
  final FetchSearchType? kind;
  final String title;
  final String artist;
  final String? coverUrl;
  final FetchBatchStatus status;
  final String? error;

  /// What the user picked (result ids); used to show progress on those rows.
  final List<int> candidateIds;
  final int total;
  final int added;
  final int owned;

  /// Songs the source only has in a lossy format (skipped).
  final int lossy;

  /// Songs that couldn't be found or downloaded (skipped).
  final int failed;

  /// 0–1 over the whole batch.
  final double progress;
  final List<FetchJob> items;

  /// Playlist batches: the user's own playlist the app made from it, once made.
  final String? playlistId;

  const FetchBatch({
    required this.id,
    required this.candidateIds,
    this.kind,
    this.title = '',
    this.artist = '',
    this.coverUrl,
    this.status = FetchBatchStatus.starting,
    this.error,
    this.total = 0,
    this.added = 0,
    this.owned = 0,
    this.lossy = 0,
    this.failed = 0,
    this.progress = 0,
    this.items = const [],
    this.playlistId,
  });

  FetchBatch copyWith({int? id, FetchBatchStatus? status, String? error, String? playlistId}) => FetchBatch(
        id: id ?? this.id,
        candidateIds: candidateIds,
        kind: kind,
        title: title,
        artist: artist,
        coverUrl: coverUrl,
        status: status ?? this.status,
        error: error ?? this.error,
        total: total,
        added: added,
        owned: owned,
        lossy: lossy,
        failed: failed,
        progress: progress,
        items: items,
        playlistId: playlistId ?? this.playlistId,
      );

  bool get isFinished => status == FetchBatchStatus.done || status == FetchBatchStatus.failed;

  /// A finished playlist batch whose user playlist hasn't been made yet.
  bool get needsPlaylist => kind == FetchSearchType.playlist && status == FetchBatchStatus.done && playlistId == null;

  /// Library songs the batch ended with: new ones and ones already owned, in
  /// track order, each once — what Play, Add to Playlist and the playlist use.
  List<String> get songIds => {
        for (final i in items)
          if (i.songId != null && (i.phase == FetchJobPhase.ready || i.phase == FetchJobPhase.duplicate)) i.songId!,
      }.toList();

  /// "Album downloaded", "Playlist ready", "Songs downloaded".
  String get headline => switch (kind) {
        FetchSearchType.album => 'Album downloaded',
        FetchSearchType.playlist => 'Playlist ready',
        _ => added == 1 && owned == 0 && failed == 0 && lossy == 0 ? 'Song downloaded' : 'Songs downloaded',
      };

  static String _songs(int n) => n == 1 ? '1 song' : '$n songs';

  List<String> get _skipped => [
        if (lossy > 0) '$lossy ${lossy == 1 ? 'isn’t' : 'aren’t'} available in lossless',
        if (failed > 0) '$failed couldn’t be found',
      ];

  /// Album / songs: "12 songs added, 2 already owned, 1 isn’t available in
  /// lossless". Playlist: "18 of 20 songs. 2 aren’t available in lossless."
  String get summary {
    if (kind == FetchSearchType.playlist) {
      final have = added + owned;
      final head = have < total ? '$have of ${_songs(total)}.' : '${_songs(have)}.';
      return [head, for (final s in _skipped) '${s[0].toUpperCase()}${s.substring(1)}.'].join(' ');
    }
    return ['${_songs(added)} added', if (owned > 0) '$owned already owned', ..._skipped].join(', ');
  }

  static FetchBatchStatus _status(Object? v) => switch (v) {
        'queued' || 'listing' => FetchBatchStatus.starting,
        'running' => FetchBatchStatus.running,
        'done' => FetchBatchStatus.done,
        _ => FetchBatchStatus.failed,
      };

  factory FetchBatch.fromJson(Map<String, dynamic> j) {
    final kind = j['kind'];
    return FetchBatch(
      id: (j['id'] as num).toInt(),
      kind: kind == 'songs' ? null : FetchSearchType.parse(kind),
      title: j['title'] as String? ?? '',
      artist: j['artist'] as String? ?? '',
      coverUrl: j['cover_url'] as String?,
      status: _status(j['status']),
      error: j['error'] as String?,
      candidateIds: [for (final c in (j['candidate_ids'] as List? ?? const [])) (c as num).toInt()],
      total: (j['total'] as num?)?.toInt() ?? 0,
      added: (j['added'] as num?)?.toInt() ?? 0,
      owned: (j['owned'] as num?)?.toInt() ?? 0,
      lossy: (j['lossy'] as num?)?.toInt() ?? 0,
      failed: (j['failed'] as num?)?.toInt() ?? 0,
      progress: ((j['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      items: [for (final i in (j['items'] as List? ?? const [])) FetchJob.fromJson(i as Map<String, dynamic>)],
      playlistId: j['playlist_id'] as String?,
    );
  }
}
