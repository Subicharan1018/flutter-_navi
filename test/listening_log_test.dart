import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/listening_log_service.dart';

// =============================================================================
// Mock classes
// =============================================================================

class MockHttpClient extends Mock implements http.Client {}

// =============================================================================
// Helpers
// =============================================================================

Song _fakeSong({int durationSec = 240}) => Song(
  id: 'song-abc123',
  title: 'Test Song',
  artist: 'Test Artist',
  album: 'Test Album',
  coverArt: 'cover-id',
  duration: durationSec,
  track: 1,
  year: 2026,
);

ListeningLogService _makeService(
  MockHttpClient client, {
  String baseUrl = 'https://test.example.com',
  String user = 'testuser',
  String pass = 'testpass',
}) {
  return ListeningLogService(
    client: client,
    baseUrl: baseUrl,
    webdavUser: user,
    webdavPass: pass,
  );
}

/// Stubs the mock client to return [statusCode] for any POST.
void _stubPost(MockHttpClient client, int statusCode) {
  when(
    () => client.post(
      any(),
      headers: any(named: 'headers'),
      body: any(named: 'body'),
    ),
  ).thenAnswer((_) async => http.Response('', statusCode));
}

/// Stubs the mock client so POST throws a [SocketException].
void _stubPostTimeout(MockHttpClient client) {
  when(
    () => client.post(
      any(),
      headers: any(named: 'headers'),
      body: any(named: 'body'),
    ),
  ).thenThrow(const SocketException('Network unreachable'));
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 1 — Payload construction (new schema)
  // ══════════════════════════════════════════════════════════════════════════
  group('Payload construction', () {
    test('1.1 — basic feedback fields are present', () async {
      final client = MockHttpClient();
      Map<String, dynamic>? capturedPayload;
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) async {
        capturedPayload =
            jsonDecode(invocation.namedArguments[#body] as String)
                as Map<String, dynamic>;
        return http.Response('', 200);
      });

      final service = _makeService(client);
      await service.logPlay(song: _fakeSong());

      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['title'], 'Test Song');
      expect(capturedPayload!['composer'], 'Test Artist'); // falls back to artist
      expect(capturedPayload!['listen_ratio'], 1.0);
      expect(capturedPayload!['end_reason'], 'natural');
      expect(capturedPayload!['session_id'], isNotEmpty);
      expect(capturedPayload!['session_id'].toString().length, 36); // UUID v4
      expect(capturedPayload!['session_depth'], 1);
    });

    test('1.2 — composer field uses song.composer when not empty', () async {
      final client = MockHttpClient();
      Map<String, dynamic>? capturedPayload;
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) async {
        capturedPayload =
            jsonDecode(invocation.namedArguments[#body] as String)
                as Map<String, dynamic>;
        return http.Response('', 200);
      });

      final service = _makeService(client);
      final songWithComposer = Song(
        id: 'song-abc123',
        title: 'Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        composer: 'Test Composer',
        coverArt: 'cover-id',
        duration: 240,
        track: 1,
        year: 2026,
      );
      await service.logPlay(song: songWithComposer);

      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['composer'], 'Test Composer');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 2 — Retry queue
  // ══════════════════════════════════════════════════════════════════════════
  group('Retry queue', () {
    // 2.1 — A failed POST must persist the payload to SharedPreferences.
    test('2.1 — Failed POST → payload added to queue', () async {
      final client = MockHttpClient();
      _stubPostTimeout(client);

      final service = _makeService(client);
      await service.logPlay(song: _fakeSong());

      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList('listening_log_queue') ?? [];
      expect(queue.length, 1);

      // Verify it's parseable JSON with the right title.
      // Queue format: "<retries>|<json_payload>"
      final raw = queue[0];
      final sep = raw.indexOf('|');
      final payload =
          jsonDecode(raw.substring(sep + 1)) as Map<String, dynamic>;
      expect(payload['title'], 'Test Song');
    });

    // 2.2 — flushQueue() retries queued entries and clears them on success.
    test('2.2 — Queue flushed on app resume (successful retry)', () async {
      final client = MockHttpClient();

      _stubPostTimeout(client);
      final service = _makeService(client);
      await service.logPlay(song: _fakeSong());

      final prefs = await SharedPreferences.getInstance();
      expect((prefs.getStringList('listening_log_queue') ?? []).length, 1);

      _stubPost(client, 200);
      await service.flushQueue();

      final queueAfter = prefs.getStringList('listening_log_queue') ?? [];
      expect(queueAfter, isEmpty);
    });

    // 2.3 — Queue must be capped at 500 entries — oldest are dropped when full.
    test('2.3 — Queue capped at 500: oldest dropped when full', () async {
      final client = MockHttpClient();
      _stubPostTimeout(client);

      final prefs = await SharedPreferences.getInstance();
      final existing = List.generate(
        500,
        (i) =>
            '0|${jsonEncode({'song_id': 'old-$i', 'title': 'Old $i', 'artist': 'A', 'album': 'B', 'duration_s': 60, 'source': 'subsonic', 'album_id': null, 'artist_id': null, 'cover_art': null, 'played_at': '2026-01-01T00:00:00.000Z'})}',
      );
      await prefs.setStringList('listening_log_queue', existing);

      final service = _makeService(client);
      await service.logPlay(song: _fakeSong());

      final queue = prefs.getStringList('listening_log_queue') ?? [];
      expect(queue.length, lessThanOrEqualTo(500));
      final newestRaw = queue.last;
      final sep = newestRaw.indexOf('|');
      final newestPayload =
          jsonDecode(newestRaw.substring(sep + 1)) as Map<String, dynamic>;
      expect(newestPayload['title'], 'Test Song');
    });

    // 2.4 — A successfully retried entry is removed from the queue.
    test('2.4 — Successful retry removes entry from queue', () async {
      final client = MockHttpClient();

      final prefs = await SharedPreferences.getInstance();
      final preQueued =
          '0|${jsonEncode({'song_id': 'queued-song', 'title': 'Queued', 'artist': 'A', 'album': 'B', 'duration_s': 60, 'source': 'subsonic', 'album_id': null, 'artist_id': null, 'cover_art': null, 'played_at': '2026-01-01T00:00:00.000Z'})}';
      await prefs.setStringList('listening_log_queue', [preQueued]);

      _stubPost(client, 200);
      final service = _makeService(client);
      await service.flushQueue();

      final queueAfter = prefs.getStringList('listening_log_queue') ?? [];
      expect(queueAfter, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 3 — Offline guard
  // ══════════════════════════════════════════════════════════════════════════
  group('Offline guard', () {
    // 3.1 — When baseUrl is not configured the service must be a no-op.
    test('3.1 — No base URL → no POST and no queue entry', () async {
      final client = MockHttpClient();

      final service = ListeningLogService(client: client, baseUrl: null);

      await service.logPlay(song: _fakeSong());

      verifyNever(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList('listening_log_queue') ?? [];
      expect(queue, isEmpty);
    });

    // 3.2 — Network failure → POST fails, payload queued.
    test(
      '3.2 — Network error → POST fails, payload queued for retry',
      () async {
        final client = MockHttpClient();
        _stubPostTimeout(client);

        final service = _makeService(client);
        await service.logPlay(song: _fakeSong());

        verify(
          () => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).called(1);

        final prefs = await SharedPreferences.getInstance();
        final queue = prefs.getStringList('listening_log_queue') ?? [];
        expect(queue.length, 1);
      },
    );
  });
}
