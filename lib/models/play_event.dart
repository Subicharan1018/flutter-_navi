// ---------------------------------------------------------------------------
// PlayEvent — one row in the play_events analytics table.
//
// Combines "Core Interaction Data" (Table 1) and "Contextual Data" (Table 2)
// from the schema, since they are captured at the same moment and stored
// together for simplicity.
//
// Fields that require manual input (mood_tag) are kept nullable and left NULL
// during recording; a future ML pass will infer them from pattern data.
// ---------------------------------------------------------------------------

class PlayEvent {
  /// Randomly generated UUID (v4) — unique per listening session of one song.
  final String playId;

  /// Subsonic/Navidrome song ID (foreign key into song_metadata).
  final String songId;

  /// Groups songs played within a 30-minute gap into the same session.
  final String sessionId;

  /// Wall-clock time when playback of this song started.
  final DateTime timestampStart;

  /// Wall-clock time when playback ended (null if event not yet closed).
  DateTime? timestampEnd;

  /// Seconds of audio actually played (not the song's total duration).
  int playDurationSec;

  /// True if the song was skipped before the 50% mark.
  bool skipBeforeEnd;

  /// How this song entered the queue.
  /// Values: 'user_queue' | 'playlist' | 'search' | 'autoplay' | 'manual_next' | 'user_selected'
  final String sourceContext;

  // ---- Contextual fields (Table 2) ----------------------------------------

  /// 0–23 hour extracted from [timestampStart] in local time.
  final int hourOfDay;

  /// 0 = Monday … 6 = Sunday (Dart's [DateTime.weekday] is 1-based;
  /// we store 0-based for ML compatibility).
  final int dayOfWeek;

  /// Convenience flag: true when [dayOfWeek] is 5 (Sat) or 6 (Sun).
  final bool isWeekend;

  /// Optional mood label — kept NULL during recording.
  /// A future inference step will populate this from listening patterns.
  String? moodTag;

  PlayEvent({
    required this.playId,
    required this.songId,
    required this.sessionId,
    required this.timestampStart,
    this.timestampEnd,
    this.playDurationSec = 0,
    this.skipBeforeEnd = false,
    required this.sourceContext,
    required this.hourOfDay,
    required this.dayOfWeek,
    required this.isWeekend,
    this.moodTag,
  });

  // ---------------------------------------------------------------------------
  // Factory: open a new event right when a song starts.
  // ---------------------------------------------------------------------------
  factory PlayEvent.open({
    required String playId,
    required String songId,
    required String sessionId,
    required String sourceContext,
  }) {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Mon … 7=Sun
    return PlayEvent(
      playId: playId,
      songId: songId,
      sessionId: sessionId,
      timestampStart: now,
      sourceContext: sourceContext,
      hourOfDay: now.hour,
      dayOfWeek: weekday - 1, // convert to 0-based
      isWeekend: weekday >= 6, // Saturday(6) or Sunday(7)
    );
  }

  // ---------------------------------------------------------------------------
  // Close the event when the song ends or is skipped.
  // [playedDuration]  — position at the moment of song change.
  // [totalDurationSec] — full song length from Song.duration (may be 0 if
  //                      not yet loaded — handled below).
  // ---------------------------------------------------------------------------
  void close(Duration playedDuration, int totalDurationSec) {
    timestampEnd = DateTime.now();

    // Clamp playDurationSec so it never exceeds the song length.
    // A stale positionStream read can slightly overshoot.
    if (totalDurationSec > 0) {
      playDurationSec = playedDuration.inSeconds.clamp(0, totalDurationSec);
    } else {
      playDurationSec = playedDuration.inSeconds;
    }

    if (totalDurationSec <= 0) {
      // Duration unknown (not yet loaded from server).
      // Fall back to a 30-second heuristic: if the user listened
      // for at least 30 s we consider it a genuine listen.
      skipBeforeEnd = playedDuration.inSeconds < 30;
    } else {
      skipBeforeEnd =
          playedDuration.inSeconds < (totalDurationSec * 0.5).floor();
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
        'source_context': sourceContext,
        'hour_of_day': hourOfDay,
        'day_of_week': dayOfWeek,
        'is_weekend': isWeekend ? 1 : 0,
        'mood_tag': moodTag,
      };
}
