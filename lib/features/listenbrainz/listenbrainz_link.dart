import 'dart:convert';

import 'package:http/http.dart' as http;

/// Whether this account's plays are forwarded to a ListenBrainz account.
class ListenBrainzStatus {
  final bool linked;
  final String? user;
  const ListenBrainzStatus({required this.linked, this.user});
}

class ListenBrainzException implements Exception {
  final String message;
  const ListenBrainzException(this.message);
  @override
  String toString() => message;
}

/// Links a listener's own ListenBrainz account through Navidrome.
///
/// The app already reports every play to Navidrome; once the account has a
/// ListenBrainz token, Navidrome forwards each one. The token goes to the
/// user's own server and is never stored in the app.
class ListenBrainzLink {
  final String base;
  final Future<String> Function() jwt;
  final http.Client _client;

  ListenBrainzLink({required this.base, required this.jwt, http.Client? client}) : _client = client ?? http.Client();

  Uri get _url => Uri.parse('$base/api/listenbrainz/link');

  Future<Map<String, String>> _headers() async =>
      {'X-ND-Authorization': 'Bearer ${await jwt()}', 'Content-Type': 'application/json'};

  Future<ListenBrainzStatus> status() async => _read(await _send('GET'));

  Future<ListenBrainzStatus> link(String token) async {
    final t = token.trim();
    if (t.isEmpty) throw const ListenBrainzException('Paste your ListenBrainz user token first.');
    return _read(await _send('PUT', body: jsonEncode({'token': t})));
  }

  Future<void> unlink() async {
    await _send('DELETE');
  }

  Future<http.Response> _send(String method, {String? body}) async {
    final req = http.Request(method, _url)..headers.addAll(await _headers());
    if (body != null) req.body = body;
    http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw const ListenBrainzException('Couldn’t reach your server. Check your connection and try again.');
    }
    if (res.statusCode == 404) {
      throw const ListenBrainzException('This server doesn’t offer ListenBrainz linking. Update Navidrome.');
    }
    if (res.statusCode == 400 || res.statusCode == 422) {
      throw const ListenBrainzException('ListenBrainz rejected that token. Copy it again from your ListenBrainz profile.');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const ListenBrainzException('Your sign-in expired. Sign in again.');
    }
    if (res.statusCode >= 300) throw ListenBrainzException('The server answered ${res.statusCode}. Try again later.');
    return res;
  }

  ListenBrainzStatus _read(http.Response res) {
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final user = j['user']?.toString();
      return ListenBrainzStatus(linked: j['status'] == true, user: user == null || user.isEmpty ? null : user);
    } catch (_) {
      return const ListenBrainzStatus(linked: false);
    }
  }
}

/// A Navidrome sign-in token for [username], for the account-link calls above.
Future<String> navidromeLoginToken({
  required String base,
  required String username,
  required String password,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .post(
          Uri.parse('$base/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const ListenBrainzException('Your sign-in expired. Sign in again.');
    }
    final token = (jsonDecode(res.body) as Map<String, dynamic>)['token']?.toString() ?? '';
    if (res.statusCode != 200 || token.isEmpty) throw const ListenBrainzException('Couldn’t sign in to your server.');
    return token;
  } on ListenBrainzException {
    rethrow;
  } catch (_) {
    throw const ListenBrainzException('Couldn’t reach your server. Check your connection and try again.');
  } finally {
    if (client == null) c.close();
  }
}
