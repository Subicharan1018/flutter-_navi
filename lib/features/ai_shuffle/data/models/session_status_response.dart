// =============================================================================
// SessionStatusResponse — model for GET /session/status
// =============================================================================

/// Session state returned by the `/session/status` endpoint.
class SessionStatusResponse {
  final String sessionId;
  final int songCount;
  final String startedAt;

  const SessionStatusResponse({
    required this.sessionId,
    required this.songCount,
    required this.startedAt,
  });

  factory SessionStatusResponse.fromJson(Map<String, dynamic> json) =>
      SessionStatusResponse(
        sessionId: json['session_id']?.toString() ?? '',
        songCount: _parseInt(json['song_count']),
        startedAt: json['started_at']?.toString() ?? '',
      );

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Human-readable description of when this session started.
  String get startedAtFormatted {
    final dt = DateTime.tryParse(startedAt);
    if (dt == null) return startedAt;
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
