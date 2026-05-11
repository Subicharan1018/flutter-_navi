// =============================================================================
// NextResponse — response from GET /next
// =============================================================================

import 'recommended_song.dart';

/// Full response from the `/next` recommendation endpoint.
class NextResponse {
  final List<RecommendedSong> songs;

  /// Source strategy the server used: 'model', 'cold_start', 'fallback', etc.
  final String source;

  /// Session identifier for this recommendation sequence.
  final String sessionId;

  const NextResponse({
    required this.songs,
    required this.source,
    required this.sessionId,
  });

  factory NextResponse.fromJson(Map<String, dynamic> json) {
    // Support both envelope format {"songs":[...], "source":"..."} and
    // legacy flat list format [{...}, {...}] from the old Flask server.
    if (json.containsKey('songs')) {
      return NextResponse(
        songs: (json['songs'] as List<dynamic>? ?? [])
            .map((e) => RecommendedSong.fromJson(e as Map<String, dynamic>))
            .toList(),
        source: json['source']?.toString() ?? 'model',
        sessionId: json['session_id']?.toString() ?? '',
      );
    }
    // Fallback: treat the entire response as a single-key object containing
    // a list (shouldn't happen with the new server but handles migration).
    return NextResponse(songs: [], source: 'unknown', sessionId: '');
  }

  /// Convenience factory for a flat list response (legacy Flask format).
  factory NextResponse.fromList(List<dynamic> list) => NextResponse(
        songs: list
            .map((e) => RecommendedSong.fromJson(e as Map<String, dynamic>))
            .toList(),
        source: 'legacy',
        sessionId: '',
      );
}
