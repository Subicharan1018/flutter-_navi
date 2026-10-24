import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/features/share/share_api.dart';

final _now = DateTime.utc(2026, 1, 10, 12);

ShareApi _api(http.Client client) => ShareApi(
  client: client,
  serverUrl: 'https://music.example.org/rest',
  buildUrl: (endpoint, params) => Uri.parse('https://music.example.org/rest/$endpoint').replace(queryParameters: params).toString(),
  now: () => _now,
);

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode({'subsonic-response': body}), status);

Map<String, dynamic> _ok(Map<String, dynamic> share) => {
  'status': 'ok',
  'shares': {'share': [share]},
};

void main() {
  group('expiry mapping', () {
    test('1 day and 7 days become epoch milliseconds from now', () {
      expect(ShareExpiry.day.toEpochMillis(_now), _now.add(const Duration(days: 1)).millisecondsSinceEpoch);
      expect(ShareExpiry.week.toEpochMillis(_now), _now.add(const Duration(days: 7)).millisecondsSinceEpoch);
    });

    test('never has no expiry, and the default is 7 days', () {
      expect(ShareExpiry.never.toEpochMillis(_now), isNull);
      expect(ShareExpiry.defaultChoice, ShareExpiry.week);
    });
  });

  group('link building', () {
    test('keeps the URL the server returned', () {
      expect(
        buildShareUrl(serverUrl: 'https://music.example.org/rest', shareId: 'abc', returnedUrl: 'https://music.example.org/share/abc'),
        'https://music.example.org/share/abc',
      );
    });

    test('rebuilds from the server address when the URL is missing', () {
      expect(
        buildShareUrl(serverUrl: 'https://music.example.org/rest', shareId: 'abc'),
        'https://music.example.org/share/abc',
      );
    });

    test('swaps a loopback host for the public server host', () {
      expect(
        buildShareUrl(serverUrl: 'https://music.example.org/rest', shareId: 'abc', returnedUrl: 'http://localhost:4533/share/abc'),
        'https://music.example.org/share/abc',
      );
    });

    test('rejects non-http schemes', () {
      expect(
        buildShareUrl(serverUrl: 'https://music.example.org/rest', shareId: 'abc', returnedUrl: 'javascript:alert(1)'),
        'https://music.example.org/share/abc',
      );
    });
  });

  group('createShare with a fake HTTP client', () {
    test('sends id, description and expiry, and returns the link', () async {
      late Uri sent;
      final api = _api(MockClient((req) async {
        sent = req.url;
        return _json(_ok({'id': 'abc', 'url': 'https://music.example.org/share/abc'}));
      }));
      final link = await api.createShare('song-1', description: 'Song — Artist');
      expect(link, 'https://music.example.org/share/abc');
      expect(sent.path, '/rest/createShare.view');
      expect(sent.queryParameters['id'], 'song-1');
      expect(sent.queryParameters['description'], 'Song — Artist');
      expect(sent.queryParameters['expires'], _now.add(const Duration(days: 7)).millisecondsSinceEpoch.toString());
    });

    test('never-expiring links omit the expires parameter', () async {
      late Uri sent;
      final api = _api(MockClient((req) async {
        sent = req.url;
        return _json(_ok({'id': 'abc', 'url': 'https://music.example.org/share/abc'}));
      }));
      await api.createShare('song-1', expiry: ShareExpiry.never);
      expect(sent.queryParameters.containsKey('expires'), isFalse);
    });

    test('HTTP 501 means sharing is disabled and names ND_ENABLESHARING', () async {
      final api = _api(MockClient((_) async => http.Response('', 501)));
      await expectLater(
        api.createShare('x'),
        throwsA(
          isA<ShareException>()
              .having((e) => e.failure, 'failure', ShareFailure.disabled)
              .having((e) => e.message, 'message', contains('ND_ENABLESHARING=true')),
        ),
      );
    });

    test('a Subsonic "not enabled" error is reported as disabled', () async {
      final api = _api(MockClient((_) async => _json({
        'status': 'failed',
        'error': {'code': 0, 'message': 'Sharing is not enabled'},
      })));
      await expectLater(
        api.createShare('x'),
        throwsA(isA<ShareException>().having((e) => e.failure, 'failure', ShareFailure.disabled)),
      );
    });

    test('a dead connection becomes a network error, not a crash', () async {
      final api = _api(MockClient((_) async => throw http.ClientException('offline')));
      await expectLater(
        api.createShare('x'),
        throwsA(isA<ShareException>().having((e) => e.failure, 'failure', ShareFailure.network)),
      );
    });

    test('a garbled body becomes a server error', () async {
      final api = _api(MockClient((_) async => http.Response('<html>', 200)));
      await expectLater(
        api.createShare('x'),
        throwsA(isA<ShareException>().having((e) => e.failure, 'failure', ShareFailure.server)),
      );
    });
  });

  group('error mapping', () {
    test('auth, permission and not-found codes', () {
      expect(mapShareError(httpStatus: 401).failure, ShareFailure.auth);
      expect(mapShareError(httpStatus: 200, apiCode: 40).failure, ShareFailure.auth);
      expect(mapShareError(httpStatus: 200, apiCode: 50).failure, ShareFailure.notAllowed);
      expect(mapShareError(httpStatus: 200, apiCode: 70).failure, ShareFailure.notFound);
    });

    test('anything else is a generic server error', () {
      expect(mapShareError(httpStatus: 500).failure, ShareFailure.server);
    });
  });
}
