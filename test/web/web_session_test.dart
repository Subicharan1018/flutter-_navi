import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/core/app_exception.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/web_session.dart';
import 'package:navivibe/core/web_storage.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/features/ai_shuffle/data/services/shuffle_api_service.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:drift/native.dart';

/// sessionStorage / localStorage stand-in.
class _MemStore extends WebStorage {
  _MemStore({super.persistent});
  final values = <String, String>{};
  @override
  String? read(String key) => values[key];
  @override
  void write(String key, String value) => values[key] = value;
  @override
  void remove(String key) => values.remove(key);
}

const _password = 'hunter2-secret';

Map<String, dynamic> _loginBody() => {
      'id': 'u1',
      'name': 'Subi',
      'username': 'subi',
      'isAdmin': false,
      'token': 'jwt-1',
      'subsonicSalt': 'salt123',
      'subsonicToken': 'tok456',
    };

void main() {
  late _MemStore tab;
  late _MemStore profile;
  late List<http.Request> requests;

  void configure(Future<http.Response> Function(http.Request) handler) {
    requests = [];
    WebSession.debugConfigure(
      tab: tab,
      profile: profile,
      client: () => MockClient((r) {
        requests.add(r);
        return handler(r);
      }),
    );
  }

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('hive_web_session');
    Hive.init(dir.path);
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.prefs = await Hive.openBox('prefs');
  });

  setUp(() {
    tab = _MemStore();
    profile = _MemStore(persistent: true);
    configure((r) async => http.Response(jsonEncode(_loginBody()), 200));
  });

  tearDown(() => WebSession.debugConfigure());

  group('sign-in', () {
    test('posts to Navidrome /auth/login once and keeps no password', () async {
      final s = await WebSession.signIn(serverUrl: 'https://music.example/rest', username: 'subi', password: _password);

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.toString(), 'https://music.example/auth/login');
      expect(jsonDecode(requests.single.body), {'username': 'subi', 'password': _password});

      expect(s.jwt, 'jwt-1');
      expect(WebSession.isActive, isTrue);
      expect(WebSession.subsonicAuthParams(), {'t': 'tok456', 's': 'salt123'});
      expect(WebSession.authorizationHeader(), 'Bearer jwt-1');

      // Browser storage: server, user and JWT only.
      final stored = [...tab.values.values, ...profile.values.values].join(' ');
      expect(stored, isNot(contains(_password)));
      expect(stored, isNot(contains('tok456')));
      expect(stored, isNot(contains('salt123')));
      expect(tab.values['nv_jwt'], 'jwt-1');
      expect(profile.values, isEmpty, reason: 'tab-only unless "Stay signed in"');
    });

    test('"Stay signed in" keeps the token in localStorage instead', () async {
      await WebSession.signIn(serverUrl: 'music.example', username: 'subi', password: _password, staySignedIn: true);
      expect(profile.values['nv_jwt'], 'jwt-1');
      expect(tab.values, isEmpty);
      expect(requests.single.url.toString(), 'https://music.example/auth/login');
    });

    test('a wrong password is an AuthException', () async {
      configure((r) async => http.Response('{"error":"Invalid username or password"}', 401));
      await expectLater(
        WebSession.signIn(serverUrl: 'https://music.example', username: 'subi', password: 'nope'),
        throwsA(isA<AuthException>()),
      );
      expect(WebSession.isActive, isFalse);
      expect(tab.values, isEmpty);
    });

    test('an unreachable server is a NetworkException', () async {
      configure((r) async => throw const SocketException('down'));
      await expectLater(
        WebSession.signIn(serverUrl: 'https://music.example', username: 'subi', password: _password),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a non-Navidrome answer is a ServerException', () async {
      configure((r) async => http.Response('<html>', 200));
      await expectLater(
        WebSession.signIn(serverUrl: 'https://music.example', username: 'subi', password: _password),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('reload, refresh, sign-out', () {
    test('restore picks the JWT back up and uses it for Subsonic (the t/s pair died with the page)', () {
      tab.values.addAll({'nv_server': 'https://music.example', 'nv_user': 'subi', 'nv_jwt': 'jwt-9'});
      final s = WebSession.restore();
      expect(s?.username, 'subi');
      expect(WebSession.subsonicAuthParams(), {'jwt': 'jwt-9'});
    });

    test('restore finds nothing when storage is empty', () {
      expect(WebSession.restore(), isNull);
      expect(WebSession.isActive, isFalse);
      expect(WebSession.subsonicAuthParams(), isEmpty);
      expect(WebSession.authorizationHeader(), isNull);
    });

    test('refresh swaps in the token Navidrome hands back', () async {
      configure((r) async => r.url.path == '/auth/login'
          ? http.Response(jsonEncode(_loginBody()), 200)
          : http.Response('{}', 200, headers: {'x-nd-authorization': 'jwt-2'}));
      await WebSession.signIn(serverUrl: 'https://music.example', username: 'subi', password: _password);
      expect(await WebSession.refresh(), 'jwt-2');
      expect(requests.last.url.path, '/api/keepalive/keepalive');
      expect(requests.last.headers['X-ND-Authorization'], 'Bearer jwt-1');
      expect(WebSession.authorizationHeader(), 'Bearer jwt-2');
      expect(tab.values['nv_jwt'], 'jwt-2');
      // The Subsonic pair from sign-in is still in memory.
      expect(WebSession.subsonicAuthParams(), {'t': 'tok456', 's': 'salt123'});
    });

    test('refresh reports an expired session', () async {
      configure((r) async =>
          r.url.path == '/auth/login' ? http.Response(jsonEncode(_loginBody()), 200) : http.Response('', 401));
      await WebSession.signIn(serverUrl: 'https://music.example', username: 'subi', password: _password);
      expect(await WebSession.refresh(), isNull);
    });

    test('sign-out forgets everything', () async {
      await WebSession.signIn(serverUrl: 'https://music.example', username: 'subi', password: _password, staySignedIn: true);
      WebSession.signOut();
      expect(WebSession.isActive, isFalse);
      expect(tab.values, isEmpty);
      expect(profile.values, isEmpty);
    });
  });

  test('navidromeBase strips /rest and adds https', () {
    expect(WebSession.navidromeBase('https://a.example/rest/'), 'https://a.example');
    expect(WebSession.navidromeBase('a.example'), 'https://a.example');
    expect(WebSession.navidromeBase('https://a.example/nd/rest'), 'https://a.example/nd');
  });

  group('clients use the session, not a password', () {
    test('SubsonicService builds URLs with the session token pair', () async {
      await WebSession.signIn(serverUrl: 'https://music.example', username: 'subi', password: _password);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final svc = SubsonicService(
        serverUrl: 'https://music.example',
        username: 'subi',
        password: WebSession.passwordPlaceholder,
        cache: PlaylistCacheService(db),
      );
      final stream = Uri.parse(svc.getStreamUrl('song-1'));
      expect(stream.queryParameters['u'], 'subi');
      expect(stream.queryParameters['t'], 'tok456');
      expect(stream.queryParameters['s'], 'salt123');
      final cover = Uri.parse(svc.getCoverArtUrl('al-1', size: 300));
      expect(cover.queryParameters['t'], 'tok456');
      expect(stream.toString(), isNot(contains(WebSession.passwordPlaceholder)));
    });

    test('after a reload SubsonicService authenticates with the JWT', () async {
      tab.values.addAll({'nv_server': 'https://music.example', 'nv_user': 'subi', 'nv_jwt': 'jwt-9'});
      WebSession.restore();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final svc = SubsonicService(
        serverUrl: 'https://music.example',
        username: 'subi',
        password: WebSession.passwordPlaceholder,
        cache: PlaylistCacheService(db),
      );
      final q = Uri.parse(svc.getStreamUrl('song-1')).queryParameters;
      expect(q['jwt'], 'jwt-9');
      expect(q.containsKey('t'), isFalse);
    });

    test('native credentials are unchanged: md5(password + salt)', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final svc = SubsonicService(
        serverUrl: 'https://music.example',
        username: 'subi',
        password: _password,
        cache: PlaylistCacheService(db),
      );
      final q = Uri.parse(svc.getStreamUrl('song-1')).queryParameters;
      expect(q['s'], hasLength(16));
      expect(q['t'], hasLength(32));
      expect(q.containsKey('jwt'), isFalse);
    });

    test('the shuffle server gets the JWT as a Bearer token', () async {
      await WebSession.signIn(serverUrl: 'https://music.example', username: 'subi', password: _password);
      final dio = createShuffleDio(() => ('subi', WebSession.passwordPlaceholder));
      String? sent;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        sent = o.headers['Authorization'] as String?;
        h.reject(DioException(requestOptions: o, type: DioExceptionType.cancel));
      }));
      await expectLater(dio.get<dynamic>('/social/jam'), throwsA(isA<DioException>()));
      expect(sent, 'Bearer jwt-1');
    });

    test('native shuffle calls still use Basic auth', () async {
      final dio = createShuffleDio(() => ('subi', _password));
      String? sent;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        sent = o.headers['Authorization'] as String?;
        h.reject(DioException(requestOptions: o, type: DioExceptionType.cancel));
      }));
      await expectLater(dio.get<dynamic>('/social/jam'), throwsA(isA<DioException>()));
      expect(sent, 'Basic ${base64Encode(utf8.encode('subi:$_password'))}');
    });
  });
}
