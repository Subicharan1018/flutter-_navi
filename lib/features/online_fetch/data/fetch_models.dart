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

/// One result the user can pick ("Is this the song?").
class FetchCandidate {
  final int id;
  final String title;
  final String artist;
  final String album;
  final double score;
  final FetchKind kind;

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
  });

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

  static FetchJobPhase _phase(Object? v) => switch (v) {
        'queued' || 'checking' || 'picking' => FetchJobPhase.preparing,
        'downloading' => FetchJobPhase.downloading,
        // 'downloaded' and 'imported' are on their way into the library.
        'downloaded' || 'tagging' || 'moving' || 'scanning' || 'imported' => FetchJobPhase.adding,
        'ready' => FetchJobPhase.ready,
        'duplicate' => FetchJobPhase.duplicate,
        'rejected' => FetchJobPhase.rejected,
        _ => FetchJobPhase.failed,
      };

  factory FetchJob.fromJson(Map<String, dynamic> j) => FetchJob(
        id: (j['id'] as num).toInt(),
        candidateId: (j['candidate_id'] as num?)?.toInt() ?? 0,
        phase: _phase(j['status']),
        progress: ((j['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        songId: j['nd_song_id'] as String?,
        error: j['error'] as String?,
        title: j['title'] as String?,
        artist: j['artist'] as String?,
      );
}
