import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/features/listenbrainz/listenbrainz_link.dart';

void main() {
  late List<http.Request> seen;
  ListenBrainzLink make(http.Response Function(http.Request) answer) => ListenBrainzLink(
        base: 'https://music.example',
        jwt: () async => 'JWT',
        client: MockClient((r) async {
          seen.add(r);
          return answer(r);
        }),
      );
  setUp(() => seen = []);

  test('status says who the account is linked to', () async {
    final link = make((_) => http.Response(jsonEncode({'status': true, 'user': 'admin_lb'}), 200));
    final s = await link.status();
    expect(s.linked, isTrue);
    expect(s.user, 'admin_lb');
    expect(seen.single.url.toString(), 'https://music.example/api/listenbrainz/link');
    expect(seen.single.headers['X-ND-Authorization'], 'Bearer JWT');
  });

  test('status when nothing is linked', () async {
    final s = await make((_) => http.Response(jsonEncode({'status': false}), 200)).status();
    expect(s.linked, isFalse);
    expect(s.user, isNull);
  });

  test('link sends the token Navidrome checks with ListenBrainz', () async {
    final link = make((_) => http.Response(jsonEncode({'status': true, 'user': 'me'}), 200));
    final s = await link.link('  abc-123 ');
    expect(s.linked, isTrue);
    expect(seen.single.method, 'PUT');
    expect(jsonDecode(seen.single.body), {'token': 'abc-123'});
  });

  test('a token ListenBrainz rejects says so', () async {
    final link = make((_) => http.Response(jsonEncode({'error': 'invalid token'}), 400));
    expect(() => link.link('nope'), throwsA(isA<ListenBrainzException>().having((e) => e.message, 'message', contains('rejected'))));
  });

  test('an empty token is refused before any request', () async {
    final link = make((_) => http.Response('{}', 200));
    expect(() => link.link('   '), throwsA(isA<ListenBrainzException>()));
    expect(seen, isEmpty);
  });

  test('unlink deletes the link', () async {
    final link = make((_) => http.Response(jsonEncode({'status': false}), 200));
    await link.unlink();
    expect(seen.single.method, 'DELETE');
  });

  test('an old server without the endpoint is explained', () async {
    final link = make((_) => http.Response('', 404));
    expect(() => link.status(), throwsA(isA<ListenBrainzException>().having((e) => e.message, 'message', contains('ListenBrainz'))));
  });
}
