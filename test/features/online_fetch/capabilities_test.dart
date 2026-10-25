import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart';
import 'package:navivibe/features/online_fetch/data/server_capabilities.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/providers/settings_provider.dart';

/// Download UI shows only when the build has it (!kPublicBuild) AND the server
/// says this account may download (GET /me/capabilities → {"download": bool}).

class _Adapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function()> routes;
  final List<String> asked = [];
  _Adapter(this.routes);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async {
    asked.add(o.path);
    final route = routes[o.path];
    if (route == null) return _json(404, {'error': 'not found'});
    return route();
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {'content-type': ['application/json']});

OnlineFetchApi _api(_Adapter a) =>
    OnlineFetchApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = a);

class _Settings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _Settings(String user, String pass)
      : super(SettingsState(serverUrl: 'https://music.example', username: user, password: pass));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

ProviderContainer _container(_Adapter adapter, {bool available = true, String user = 'u', String pass = 'p'}) {
  final c = ProviderContainer(overrides: [
    onlineFetchAvailableProvider.overrideWithValue(available),
    onlineFetchApiProvider.overrideWithValue(_api(adapter)),
    settingsProvider.overrideWith((ref) => _Settings(user, pass)),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<bool> _enabled(ProviderContainer c) async {
  final sub = c.listen(onlineFetchEnabledProvider, (_, _) {});
  addTearDown(sub.close);
  return c.read(onlineFetchEnabledProvider.future);
}

void main() {
  group('ServerCapabilities', () {
    test('parses the server answer and defaults to nothing', () {
      expect(ServerCapabilities.fromJson({'download': true}).download, isTrue);
      expect(ServerCapabilities.fromJson({'download': false}).download, isFalse);
      expect(ServerCapabilities.fromJson({'download': 'yes'}).download, isFalse);
      expect(ServerCapabilities.fromJson(null).download, isFalse);
      expect(ServerCapabilities.fromJson([1]).download, isFalse);
      expect(ServerCapabilities.none.download, isFalse);
    });
  });

  group('api.capabilities', () {
    test('reads /me/capabilities', () async {
      final yes = _Adapter({'/me/capabilities': () => _json(200, {'download': true})});
      final no = _Adapter({'/me/capabilities': () => _json(200, {'download': false})});
      expect((await _api(yes).capabilities()).download, isTrue);
      expect((await _api(no).capabilities()).download, isFalse);
    });

    test('any failure means no downloads', () async {
      for (final status in [401, 403, 429, 500, 503]) {
        final a = _Adapter({'/me/capabilities': () => _json(status, {'error': 'x'})});
        expect((await _api(a).capabilities()).download, isFalse, reason: '$status');
      }
    });

    test('a server without /me/capabilities (404) is asked the old question', () async {
      final old = _Adapter({'/fetch/enabled': () => _json(200, {'enabled': true})});
      expect((await _api(old).capabilities()).download, isTrue);
      expect(old.asked, ['/me/capabilities', '/fetch/enabled']);
      final oldNo = _Adapter({'/fetch/enabled': () => _json(200, {'enabled': false})});
      expect((await _api(oldNo).capabilities()).download, isFalse);
    });
  });

  group('onlineFetchEnabledProvider = !kPublicBuild && capabilities.download', () {
    test('available build + allowed account: downloads show', () async {
      final a = _Adapter({'/me/capabilities': () => _json(200, {'download': true})});
      expect(await _enabled(_container(a)), isTrue);
    });

    test('available build + account without access: hidden', () async {
      final a = _Adapter({'/me/capabilities': () => _json(200, {'download': false})});
      expect(await _enabled(_container(a)), isFalse);
    });

    test('public build: hidden even if the server would allow it, and never asked', () async {
      final a = _Adapter({'/me/capabilities': () => _json(200, {'download': true})});
      expect(await _enabled(_container(a, available: false)), isFalse);
      expect(a.asked, isEmpty);
    });

    test('signed out: hidden, and the server is not asked', () async {
      final a = _Adapter({'/me/capabilities': () => _json(200, {'download': true})});
      expect(await _enabled(_container(a, user: '', pass: '')), isFalse);
      expect(a.asked, isEmpty);
    });

    test('server error: hidden', () async {
      final a = _Adapter({'/me/capabilities': () => _json(503, {'error': 'offline'})});
      expect(await _enabled(_container(a)), isFalse);
    });
  });
}
