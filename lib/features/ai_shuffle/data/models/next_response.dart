// =============================================================================
// NextResponse — response from POST /next (v3.0.0)
// =============================================================================

import 'recommended_song.dart';

/// Context information returned alongside the queue.
class QueueContext {
  final String bucket;
  final int istHour;
  final String weather;

  const QueueContext({
    required this.bucket,
    required this.istHour,
    required this.weather,
  });

  factory QueueContext.fromJson(Map<String, dynamic> json) => QueueContext(
        bucket: json['bucket']?.toString() ?? '',
        istHour: _parseInt(json['ist_hour']),
        weather: json['weather']?.toString() ?? '',
      );

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Human-readable label for the time bucket.
  String get bucketLabel {
    final parts = bucket.split('__');
    final time = parts.isNotEmpty ? parts[0] : bucket;
    final season = parts.length > 1 ? parts[1] : '';
    final timeLabel = switch (time) {
      'morning' => 'Morning',
      'late_morning' => 'Late Morning',
      'afternoon' => 'Afternoon',
      'evening' => 'Evening',
      'night' => 'Night',
      'late_night' => 'Late Night',
      _ => time,
    };
    final seasonLabel = switch (season) {
      'summer' => 'Summer',
      'southwest_monsoon' => 'Monsoon',
      'northeast_monsoon' => 'NE Monsoon',
      'winter' => 'Winter',
      _ => season,
    };
    return seasonLabel.isEmpty ? timeLabel : '$timeLabel · $seasonLabel';
  }
}

/// Full response from the `/next` recommendation endpoint (v3.0.0).
class NextResponse {
  final String mode;
  final String source;
  final String? playlistId;
  final List<RecommendedSong> queue;
  final QueueContext? context;

  // Alias for compatibility with existing code that reads `.songs`
  List<RecommendedSong> get songs => queue;

  const NextResponse({
    required this.mode,
    required this.source,
    this.playlistId,
    required this.queue,
    this.context,
  });

  factory NextResponse.fromJson(Map<String, dynamic> json) => NextResponse(
        mode: json['mode']?.toString() ?? 'smart',
        source: json['source']?.toString() ?? 'smart',
        playlistId: json['playlist_id']?.toString(),
        queue: (json['queue'] as List<dynamic>? ?? [])
            .map((e) => RecommendedSong.fromJson(e as Map<String, dynamic>))
            .toList(),
        context: json['context'] is Map<String, dynamic>
            ? QueueContext.fromJson(json['context'] as Map<String, dynamic>)
            : null,
      );
}
