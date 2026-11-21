import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/features/playlist_cover/playlist_image_api.dart';

void main() {
  late List<http.BaseRequest> seen;
  late List<int> bodies;
  PlaylistImageApi make(int status) => PlaylistImageApi(
        base: 'https://music.example',
        jwt: () async => 'JWT',
        client: MockClient.streaming((req, body) async {
          seen.add(req);
          bodies.addAll(await body.expand((c) => c).toList());
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), status);
        }),
      );
  setUp(() {
    seen = [];
    bodies = [];
  });

  test('upload posts the picture to Navidrome as the "image" field', () async {
    await make(200).upload('pl1', [1, 2, 3, 4], 'cover.jpg');
    final r = seen.single;
    expect(r.method, 'POST');
    expect(r.url.toString(), 'https://music.example/api/playlist/pl1/image');
    expect(r.headers['X-ND-Authorization'], 'Bearer JWT');
    final text = latin1.decode(bodies);
    expect(text, contains('name="image"'));
    expect(text, contains('filename="cover.jpg"'));
  });

  test('remove deletes the picture', () async {
    await make(200).remove('pl1');
    expect(seen.single.method, 'DELETE');
    expect(seen.single.url.path, '/api/playlist/pl1/image');
  });

  test('a refusal says what to do, with no stack trace', () async {
    expect(() => make(403).upload('pl1', [1], 'a.png'),
        throwsA(isA<PlaylistImageException>().having((e) => e.message, 'message', contains('your own playlists'))));
    expect(() => make(500).upload('pl1', [1], 'a.png'), throwsA(isA<PlaylistImageException>()));
  });
}
