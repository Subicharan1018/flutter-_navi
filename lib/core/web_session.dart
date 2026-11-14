import 'dart:async' hide TimeoutException;
import 'dart:async' as dart_async show TimeoutException;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_exception.dart';
import 'web_storage.dart';

// =============================================================================
// web_session.dart — sign-in for the browser build, without keeping the
// password anywhere.
//
// Native apps keep the Navidrome password (encrypted Hive) and derive a Subsonic
// token per request. A browser can't keep a secret from scripts on its origin,
// so the web build signs in once with Navidrome's own login endpoint and drops
// the password:
//
//   POST {server}/auth/login {username, password}
//     -> token          Navidrome JWT (ND_SESSIONTIMEOUT, 24 h here), refreshed
//                       by /api/keepalive while the app is open
//     -> subsonicToken  md5(password + subsonicSalt), Navidrome's own pair
//        subsonicSalt
//
// * Subsonic calls use u + t + s while the tab lives (memory only), then
//   u + jwt after a reload (Navidrome accepts `jwt` as a Subsonic credential).
// * The shuffle and session servers get `Authorization: Bearer <jwt>`; both
//   validate it against Navidrome.
// * Only the server URL, user name and the JWT are written to the browser:
//   sessionStorage by default (gone when the tab closes), localStorage when
//   the person ticks "Stay signed in". Never the password, never t/s.
//
// Native builds never construct a session ([isActive] stays false), so every
// branch below is web-only in practice.
// =============================================================================

class WebSessionData {
  final String serverUrl;
  final String username;
  final String jwt;

  /// Navidrome's fixed Subsonic pair for this login. Memory only: null after a
  /// page reload.
  final String? subsonicToken;
  final String? subsonicSalt;

  const WebSessionData({
    required this.serverUrl,
    required this.username,
    required this.jwt,
    this.subsonicToken,
    this.subsonicSalt,
  });

  WebSessionData withJwt(String jwt) => WebSessionData(
        serverUrl: serverUrl,
        username: username,
        jwt: jwt,
        subsonicToken: subsonicToken,
        subsonicSalt: subsonicSalt,
      );
}

abstract final class WebSession {
  /// Stands in for the password in SettingsState on the web, so the many
  /// "signed in?" checks (`password.isNotEmpty`) keep working without the
  /// real password. Never sent anywhere: every consumer swaps it for the JWT
  /// or the Subsonic token (see [subsonicAuthParams], [authorizationHeader]).
  static const String passwordPlaceholder = '\u0001navivibe-web-session';

  static const _kServer = 'nv_server';
  static const _kUser = 'nv_user';
  static const _kJwt = 'nv_jwt';

  /// How often the JWT is renewed while the app is open (Navidrome issues a
  /// fresh one on each authenticated /api call; it lasts ND_SESSIONTIMEOUT).
  static const refreshEvery = Duration(minutes: 20);

  static WebSessionData? _current;
  static Timer? _refreshTimer;
  static WebStorage _tab = const WebStorage();
  static WebStorage _profile = const WebStorage(persistent: true);
  static http.Client Function() _client = http.Client.new;

  static WebSessionData? get current => _current;
  static bool get isActive => _current != null && _current!.jwt.isNotEmpty;
  static String? get jwt => _current?.jwt;

  /// True when [password] is the web stand-in rather than a real password.
  static bool isPlaceholder(String password) => password == passwordPlaceholder;

  /// Navidrome's root for a Subsonic server address: `https://x/rest` ->
  /// `https://x`. Adds https:// when the scheme is missing.
  static String navidromeBase(String serverUrl) {
    var url = serverUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/rest')) url = url.substring(0, url.length - 5);
    return url;
  }

  /// Subsonic auth query parameters for the current session: the token pair
  /// while it is in memory, else the JWT. Empty when signed out.
  static Map<String, String> subsonicAuthParams() {
    final s = _current;
    if (s == null) return const {};
    final t = s.subsonicToken, salt = s.subsonicSalt;
    if (t != null && t.isNotEmpty && salt != null && salt.isNotEmpty) return {'t': t, 's': salt};
    return {'jwt': s.jwt};
  }

  /// `Authorization` header value for the shuffle and session servers.
  static String? authorizationHeader() => isActive ? 'Bearer ${_current!.jwt}' : null;

  /// Signs in with Navidrome's login endpoint. The password is used for this
  /// one request and not kept. Throws [AuthException] / [NetworkException] /
  /// [ServerException] like the native sign-in.
  static Future<WebSessionData> signIn({
    required String serverUrl,
    required String username,
    required String password,
    bool staySignedIn = false,
  }) async {
    final base = navidromeBase(serverUrl);
    final client = _client();
    http.Response res;
    try {
      res = await client
          .post(
            Uri.parse('$base/auth/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
    } on dart_async.TimeoutException {
      throw const TimeoutException();
    } catch (e) {
      throw NetworkException('Can’t reach $base: $e');
    } finally {
      client.close();
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const AuthException('Wrong username or password');
    }
    if (res.statusCode != 200) throw ServerException(res.statusCode);
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ServerException(res.statusCode); // not Navidrome's JSON
    }
    final jwt = body['token']?.toString() ?? '';
    if (jwt.isEmpty) throw ServerException(res.statusCode);
    final data = WebSessionData(
      serverUrl: serverUrl.trim(),
      username: (body['username'] ?? username).toString(),
      jwt: jwt,
      subsonicToken: body['subsonicToken']?.toString(),
      subsonicSalt: body['subsonicSalt']?.toString(),
    );
    _current = data;
    _persist(staySignedIn: staySignedIn);
    _startRefresh();
    return data;
  }

  /// Picks the session back up after a page reload (JWT only; the Subsonic
  /// pair is gone with the old page). Returns null when there is none.
  static WebSessionData? restore() {
    for (final store in [_tab, _profile]) {
      final server = store.read(_kServer), user = store.read(_kUser), token = store.read(_kJwt);
      if (server != null && server.isNotEmpty && user != null && user.isNotEmpty && token != null && token.isNotEmpty) {
        _current = WebSessionData(serverUrl: server, username: user, jwt: token);
        _startRefresh();
        return _current;
      }
    }
    return null;
  }

  /// Asks Navidrome for a fresh JWT. Returns it, or null when the session has
  /// expired (the person must sign in again).
  static Future<String?> refresh() async {
    final s = _current;
    if (s == null) return null;
    final client = _client();
    try {
      final res = await client.get(
        Uri.parse('${navidromeBase(s.serverUrl)}/api/keepalive/keepalive'),
        headers: {'X-ND-Authorization': 'Bearer ${s.jwt}'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) return null;
      var next = res.headers['x-nd-authorization'] ?? '';
      if (next.startsWith('Bearer ')) next = next.substring(7);
      if (next.isNotEmpty && _current != null) {
        _current = _current!.withJwt(next);
        _persist(staySignedIn: _profile.read(_kJwt) != null);
      }
      return _current?.jwt;
    } catch (e) {
      debugPrint('[WebSession] refresh failed: $e');
      return _current?.jwt; // offline for a moment: keep the token we have
    } finally {
      client.close();
    }
  }

  /// Forgets the session everywhere (memory, tab, profile).
  static void signOut() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _current = null;
    for (final store in [_tab, _profile]) {
      store.remove(_kServer);
      store.remove(_kUser);
      store.remove(_kJwt);
    }
  }

  static void _persist({required bool staySignedIn}) {
    final s = _current;
    if (s == null) return;
    final keep = staySignedIn ? _profile : _tab;
    final drop = staySignedIn ? _tab : _profile;
    keep.write(_kServer, s.serverUrl);
    keep.write(_kUser, s.username);
    keep.write(_kJwt, s.jwt);
    drop.remove(_kServer);
    drop.remove(_kUser);
    drop.remove(_kJwt);
  }

  static void _startRefresh() {
    _refreshTimer?.cancel();
    if (!kIsWeb) return; // tests drive refresh() directly
    _refreshTimer = Timer.periodic(refreshEvery, (_) => refresh());
  }

  @visibleForTesting
  static void debugConfigure({WebStorage? tab, WebStorage? profile, http.Client Function()? client}) {
    _tab = tab ?? const WebStorage();
    _profile = profile ?? const WebStorage(persistent: true);
    _client = client ?? http.Client.new;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _current = null;
  }
}
