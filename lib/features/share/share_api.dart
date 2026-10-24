import 'dart:convert';

import 'package:http/http.dart' as http;

/// How long a public share link stays valid.
enum ShareExpiry {
  day('1 day'),
  week('7 days'),
  never('Never');

  final String label;
  const ShareExpiry(this.label);

  /// Navidrome's `expires` parameter: epoch milliseconds, or null for a link
  /// that never expires.
  int? toEpochMillis(DateTime now) => switch (this) {
    ShareExpiry.day => now.add(const Duration(days: 1)).millisecondsSinceEpoch,
    ShareExpiry.week => now.add(const Duration(days: 7)).millisecondsSinceEpoch,
    ShareExpiry.never => null,
  };

  static const ShareExpiry defaultChoice = ShareExpiry.week;
}

/// Why a share link couldn't be made.
enum ShareFailure { disabled, notAllowed, notFound, auth, network, server }

class ShareException implements Exception {
  final ShareFailure failure;
  final String message;
  const ShareException(this.failure, this.message);

  @override
  String toString() => message;
}

const _disabledMessage =
    'Sharing is turned off on your server. The server owner needs to set '
    'ND_ENABLESHARING=true and restart Navidrome.';

/// Maps a failed `createShare` reply to a [ShareException]. [httpStatus] is
/// the HTTP status; [apiCode]/[apiMessage] come from the Subsonic error body
/// when there is one.
ShareException mapShareError({
  required int httpStatus,
  int? apiCode,
  String? apiMessage,
}) {
  final text = (apiMessage ?? '').toLowerCase();
  // Navidrome answers 501 for createShare when sharing is switched off.
  final disabled = httpStatus == 501 ||
      httpStatus == 404 ||
      text.contains('not enabled') ||
      text.contains('disabled') ||
      text.contains('not implemented');
  if (disabled) return const ShareException(ShareFailure.disabled, _disabledMessage);
  if (httpStatus == 401 || apiCode == 40 || apiCode == 41) {
    return const ShareException(ShareFailure.auth, 'Sign in again to share.');
  }
  if (apiCode == 50) {
    return const ShareException(ShareFailure.notAllowed, 'Your account isn’t allowed to share.');
  }
  if (apiCode == 70) {
    return const ShareException(ShareFailure.notFound, 'That item is no longer on the server.');
  }
  return const ShareException(ShareFailure.server, 'The server couldn’t make a share link. Try again.');
}

/// The link to hand out. Navidrome returns a full URL; when it names a
/// loopback host (a reverse proxy that doesn't forward the public host) or
/// nothing at all, rebuild it from the server's own address.
String buildShareUrl({required String serverUrl, required String shareId, String? returnedUrl}) {
  final server = Uri.parse(serverUrl);
  final origin = '${server.scheme}://${server.authority}';
  final fallback = '$origin/share/$shareId';
  final raw = returnedUrl?.trim() ?? '';
  final parsed = Uri.tryParse(raw);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) return fallback;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return fallback;
  const loopback = {'localhost', '127.0.0.1', '::1', '0.0.0.0'};
  if (loopback.contains(parsed.host) && !loopback.contains(server.host)) {
    return Uri(
      scheme: server.scheme,
      host: server.host,
      port: server.hasPort ? server.port : null,
      path: parsed.path,
      query: parsed.hasQuery ? parsed.query : null,
    ).toString();
  }
  return raw;
}

/// Calls the Subsonic `createShare` endpoint. [buildUrl] signs a request the
/// way the rest of the service does.
class ShareApi {
  final http.Client client;
  final String serverUrl;
  final String Function(String endpoint, Map<String, String> params) buildUrl;
  final DateTime Function() now;

  ShareApi({
    required this.client,
    required this.serverUrl,
    required this.buildUrl,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  /// Creates a public link to the song, album or playlist [id].
  Future<String> createShare(String id, {String? description, ShareExpiry expiry = ShareExpiry.defaultChoice}) async {
    final params = <String, String>{'id': id};
    if (description != null && description.isNotEmpty) params['description'] = description;
    final expires = expiry.toEpochMillis(now());
    if (expires != null) params['expires'] = expires.toString();

    final http.Response response;
    try {
      response = await client.get(Uri.parse(buildUrl('createShare.view', params))).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const ShareException(ShareFailure.network, 'Couldn’t reach your server. Check your connection.');
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded['subsonic-response'] as Map<String, dynamic>?;
    } catch (_) {}

    if (response.statusCode != 200) {
      final error = body?['error'] as Map?;
      throw mapShareError(
        httpStatus: response.statusCode,
        apiCode: error?['code'] as int?,
        apiMessage: error?['message']?.toString(),
      );
    }
    if (body == null) throw mapShareError(httpStatus: 500);
    if (body['status'] != 'ok') {
      final error = body['error'] as Map?;
      throw mapShareError(
        httpStatus: 200,
        apiCode: error?['code'] as int?,
        apiMessage: error?['message']?.toString(),
      );
    }

    final shares = (body['shares'] as Map?)?['share'];
    final first = shares is List && shares.isNotEmpty ? shares.first : shares;
    if (first is! Map) throw mapShareError(httpStatus: 500);
    final shareId = first['id']?.toString() ?? '';
    final url = first['url']?.toString();
    if (shareId.isEmpty && (url == null || url.isEmpty)) throw mapShareError(httpStatus: 500);
    return buildShareUrl(serverUrl: serverUrl, shareId: shareId, returnedUrl: url);
  }
}
