import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/core/app_exception.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/services/subsonic_service.dart';

class _NoCache extends Fake implements PlaylistCacheService {}

const _ok = '{"subsonic-response":{"status":"ok","version":"1.16.1"}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final hive = await Directory.systemTemp.createTemp('navi_hive_retry_');
    Hive.init(hive.path);
    HiveBoxes.auth = await Hive.openBox('auth_retry_test');
  });

  SubsonicService svc(http.Client c) =>
      SubsonicService(serverUrl: 'https://navi.test', username: 'u', password: 'p', cache: _NoCache(), client: c);

  test('a request that hits a dead (stale keep-alive) connection is retried once', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) throw const SocketException('Connection reset by peer');
      return http.Response(_ok, 200);
    });
    await svc(client).verifyCredentials();
    expect(calls, 2);
  });

  test('a ClientException is retried once as well', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('Connection closed before full header was received');
      return http.Response(_ok, 200);
    });
    await svc(client).verifyCredentials();
    expect(calls, 2);
  });

  test('two failures in a row still surface as NetworkException (one retry only)', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      throw const SocketException('down');
    });
    await expectLater(svc(client).verifyCredentials(), throwsA(isA<NetworkException>()));
    expect(calls, 2);
  });

  test('auth and server errors are never retried', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('', 401);
    });
    await expectLater(svc(client).verifyCredentials(), throwsA(isA<AuthException>()));
    expect(calls, 1);
  });
}
