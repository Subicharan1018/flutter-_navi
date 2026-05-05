// ---------------------------------------------------------------------------
// TEST-2: Typed exception hierarchy for NaviVibe
//
// All network code in SubsonicService now throws one of these subtypes
// instead of raw Exception('...'). This lets the UI distinguish between
// "no internet", "wrong password", "server crashed", and "timed out" and
// show the appropriate message — instead of exposing raw exception strings.
// ---------------------------------------------------------------------------

/// Base class for all NaviVibe application exceptions.
sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

/// The device has no network connectivity (DNS failure, no route, etc.).
class NetworkException extends AppException {
  const NetworkException([super.message = 'No internet connection']);
}

/// The server rejected the credentials (HTTP 401 / Subsonic status "failed"
/// with error code 40 or 41).
class AuthException extends AppException {
  const AuthException([super.message = 'Invalid username or password']);
}

/// The server returned an unexpected HTTP error status.
class ServerException extends AppException {
  final int statusCode;
  ServerException(this.statusCode) : super('Server error ($statusCode)');
}

/// The request timed out before the server responded.
class TimeoutException extends AppException {
  const TimeoutException([super.message = 'Request timed out']);
}

/// A Subsonic API-level error (status == "failed", contains an error code
/// and description in the response body).
class SubsonicApiException extends AppException {
  final int code;
  SubsonicApiException(this.code, String description)
    : super('Subsonic error $code: $description');
}
