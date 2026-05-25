// =============================================================================
// ShuffleException — typed errors for the AI shuffle feature.
// Extends AppException so the existing error-handling hierarchy is preserved.
// =============================================================================

/// Base exception for AI shuffle feature
abstract class ShuffleException implements Exception {
  final String message;
  const ShuffleException(this.message);

  @override
  String toString() => message;
}

/// Network error talking to the shuffle server (DNS, no route, socket error).
class ShuffleNetworkError extends ShuffleException {
  const ShuffleNetworkError([
    super.message =
        'Cannot reach shuffle.subimusic.me. Check your internet connection.',
  ]);
}

/// The shuffle server responded with a non-2xx HTTP status.
class ShuffleServerError extends ShuffleException {
  final int statusCode;
  ShuffleServerError(this.statusCode)
    : super('Shuffle server error ($statusCode)');
}

/// The server responded with 401 — credentials are wrong or missing.
class ShuffleAuthError extends ShuffleException {
  const ShuffleAuthError([
    super.message =
        'Shuffle server authentication failed. Check your Navidrome credentials.',
  ]);
}

/// The server responded with 200 but the recommendation list was empty.
class ShuffleEmptyResponse extends ShuffleException {
  const ShuffleEmptyResponse([
    super.message = 'Shuffle server returned no recommendations.',
  ]);
}

/// The shuffle server URL is not configured in Settings.
class ShuffleNotConfigured extends ShuffleException {
  const ShuffleNotConfigured([
    super.message =
        'Navidrome credentials not configured. Set username and password in Settings.',
  ]);
}
