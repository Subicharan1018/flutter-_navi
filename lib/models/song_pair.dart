// ---------------------------------------------------------------------------
// SongPair — one row in the song_pairs analytics table (Table 4).
//
// Tracks how often Song B follows Song A for a given transition type.
//
// pair_strength is NOT stored — it is computed at query time as:
//   play_count * 1.0 / SUM(play_count WHERE prev_song_id = A)
// This avoids maintaining a stale float on every subsequent transition.
// ---------------------------------------------------------------------------

class SongPair {
  /// ID of the song that was playing.
  final String prevSongId;

  /// ID of the song that started next.
  final String currentSongId;

  /// How the transition happened.
  /// Values: 'autoplay' | 'manual_next' | 'user_selected'
  final String transitionType;

  /// How many times this exact (prev → current, transitionType) combination
  /// has occurred.
  int playCount;

  /// Epoch ms of the most recent occurrence.
  int lastSeen;

  SongPair({
    required this.prevSongId,
    required this.currentSongId,
    required this.transitionType,
    this.playCount = 1,
    required this.lastSeen,
  });

  Map<String, dynamic> toMap() => {
    'prev_song_id': prevSongId,
    'current_song_id': currentSongId,
    'transition_type': transitionType,
    'play_count': playCount,
    'last_seen': lastSeen,
  };
}
