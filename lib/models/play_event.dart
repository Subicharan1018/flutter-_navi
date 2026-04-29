// ---------------------------------------------------------------------------
// PlayEvent — one row in the play_events analytics table.
//
// Schema v3 changes vs v2:
//   • Added:  skip_position_pct, repeat_count, queue_position, shuffle_active
//   • Removed: is_weekend (derivable from day_of_week), mood_tag (never used)
//
// All fields match column names in ListeningEventCollector._createAllTables().
// ---------------------------------------------------------------------------

class PlayEvent {
  /// Randomly generated UUID (v4) — unique per listening session of one song.
  final String playId;

  /// Subsonic/Navidrome song ID (foreign key into song_metadata).
  final String songId;

  /// Groups songs played within a 30-minute gap into the same session.
  final String sessionId;

  /// Wall-clock time when playback of this song started (ms since epoch).
  final DateTime timestampStart;

  /// Wall-clock time when playback ended (null until event is closed).
  DateTime? timestampEnd;

  /// Seconds of audio actually played (not the song's total duration).
  int playDurationSec;

  /// True if the song was skipped before the 50% mark.
  bool skipBeforeEnd;

  /// Fractional position [0.0–1.0] at which the user skipped.
  /// null if the song was not skipped (i.e. skipBeforeEnd == false).
  /// Combined with skipBeforeEnd this tells the model *where* in the track
  /// the user gave up, which is a much richer signal than binary skip/play.
  double? skipPositionPct;

  /// Number of times the user looped this specific play event (LoopMode.one).
  /// Looping is the strongest positive engagement signal available.
  int repeatCount;

  /// Zero-based position of this song in the queue at the time it started.
  /// Helps the model distinguish "deliberately chosen" (low index) from
  /// "happened to come up" (high index in shuffle).
  int queuePosition;

  /// Whether the queue was in shuffle mode when this song started playing.
  bool shuffleActive;

  /// How this song entered the queue.
  /// Values: 'user_queue' | 'playlist' | 'search' | 'autoplay' |
  ///         'manual_next' | 'user_selected'
  final String sourceContext;

  // ── Contextual fields ──────────────────────────────────────────────────────

  /// 0–23 hour extracted from [timestampStart] in local time.
  final int hourOfDay;

  /// 0 = Monday … 6 = Sunday (Dart's [DateTime.weekday] is 1-based;
  /// we store 0-based for ML compatibility).
  final int dayOfWeek;

  PlayEvent({
    required this.playId,
    required this.songId,
    required this.sessionId,
    required this.timestampStart,
    this.timestampEnd,
    this.playDurationSec = 0,
    this.skipBeforeEnd = false,
    this.skipPositionPct,
    this.repeatCount = 0,
    required this.queuePosition,
    required this.shuffleActive,
    required this.sourceContext,
    required this.hourOfDay,
    required this.dayOfWeek,
  });

  // ---------------------------------------------------------------------------
  // Factory: open a new event right when a song starts.
  // ---------------------------------------------------------------------------
  factory PlayEvent.open({
    required String playId,
    required String songId,
    required String sessionId,
    required String sourceContext,
    required int queuePosition,
    required bool shuffleActive,
  }) {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Mon … 7=Sun
    return PlayEvent(
      playId: playId,
      songId: songId,
      sessionId: sessionId,
      timestampStart: now,
      sourceContext: sourceContext,
      queuePosition: queuePosition,
      shuffleActive: shuffleActive,
      hourOfDay: now.hour,
      dayOfWeek: weekday - 1, // convert to 0-based
    );
  }

  // ---------------------------------------------------------------------------
  // Close the event when the song ends or is skipped.
  // [playedDuration]   — position at the moment of song change.
  // [totalDurationSec] — full song length from Song.duration.
  // [repeats]          — loop count accumulated during this event.
  // ---------------------------------------------------------------------------
  void close(Duration playedDuration, int totalDurationSec, {int repeats = 0}) {
    timestampEnd = DateTime.now();
    repeatCount = repeats;

    if (totalDurationSec > 0) {
      playDurationSec = playedDuration.inSeconds.clamp(0, totalDurationSec);
      final pct = playedDuration.inSeconds / totalDurationSec;
      // A song that was looped (repeats > 0) is NEVER a skip — looping is
      // the strongest positive engagement signal available.
      if (pct < 0.5 && repeats == 0) {
        skipBeforeEnd = true;
        skipPositionPct = pct.clamp(0.0, 1.0);
      } else {
        skipBeforeEnd = false;
        skipPositionPct = null;
      }
    } else {
      // Duration unknown — cap at wall-clock elapsed time to prevent
      // inflation from pause/resume cycles inflating the raw position.
      final elapsedSec =
          timestampEnd!.difference(timestampStart).inSeconds.abs();
      playDurationSec = playedDuration.inSeconds
          .clamp(0, elapsedSec > 0 ? elapsedSec : 86400);
      skipBeforeEnd = playedDuration.inSeconds < 30 && repeats == 0;
      skipPositionPct = null;
    }
  }

  // ---------------------------------------------------------------------------
  // SQLite serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() => {
        'play_id': playId,
        'song_id': songId,
        'session_id': sessionId,
        'ts_start': timestampStart.millisecondsSinceEpoch,
        'ts_end': timestampEnd?.millisecondsSinceEpoch,
        'play_dur_sec': playDurationSec,
        'skip_before_50': skipBeforeEnd ? 1 : 0,
        'skip_position_pct': skipPositionPct,
        'repeat_count': repeatCount,
        'queue_position': queuePosition,
        'shuffle_active': shuffleActive ? 1 : 0,
        'source_context': sourceContext,
        'hour_of_day': hourOfDay,
        'day_of_week': dayOfWeek,
      };
}
