import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/services/session_sync_service.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Fake WebSocketSink to intercept outbound messages.
class _FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> sentMessages = [];
  bool isClosed = false;
  int? closeCode;
  String? closeReason;

  @override
  void add(dynamic data) {
    if (!isClosed) {
      sentMessages.add(data);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future close([int? closeCode, String? closeReason]) async {
    isClosed = true;
    this.closeCode = closeCode;
    this.closeReason = closeReason;
  }

  @override
  Future get done => Future.value();
}

/// Fake WebSocketChannel for unit tests.
class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final StreamController<dynamic> _inboundController =
      StreamController<dynamic>.broadcast();
  final _FakeWebSocketSink _sink = _FakeWebSocketSink();
  final Completer<void> _readyCompleter = Completer<void>()..complete();
  int? _closeCode;
  String? _closeReason;

  @override
  Stream get stream => _inboundController.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  void simulateInboundMessage(dynamic msg) {
    _inboundController.add(msg);
  }

  void simulateInboundError(dynamic error) {
    _inboundController.addError(error);
  }

  void simulateClose([int? code, String? reason]) {
    _closeCode = code;
    _closeReason = reason;
    _inboundController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackState Model', () {
    test('PlaybackState.initial() has correct default values', () {
      const state = PlaybackState.initial();
      expect(state.activeDevice, isNull);
      expect(state.activeDeviceName, isNull);
      expect(state.trackId, isNull);
      expect(state.trackTitle, isNull);
      expect(state.artist, isNull);
      expect(state.album, isNull);
      expect(state.positionMs, 0);
      expect(state.isPlaying, isFalse);
      expect(state.queue, isEmpty);
      expect(state.updatedAt, isNull);
      expect(state.syncUnknown, isFalse);
    });

    test('PlaybackState.fromJson parses snake_case server payload', () {
      final json = {
        'active_device': 'device-phone-1',
        'active_device_name': 'iPhone 15',
        'track_id': 'song-123',
        'track_title': 'Midnight City',
        'artist': 'M83',
        'album': 'Hurry Up, We\'re Dreaming',
        'position_ms': 45200,
        'is_playing': true,
        'queue': ['song-123', 'song-124', 'song-125'],
        'updated_at': '2026-08-22T06:00:00.000Z',
        'sync_unknown': false,
      };

      final state = PlaybackState.fromJson(json);

      expect(state.activeDevice, 'device-phone-1');
      expect(state.activeDeviceName, 'iPhone 15');
      expect(state.trackId, 'song-123');
      expect(state.trackTitle, 'Midnight City');
      expect(state.artist, 'M83');
      expect(state.album, 'Hurry Up, We\'re Dreaming');
      expect(state.positionMs, 45200);
      expect(state.isPlaying, isTrue);
      expect(state.queue, ['song-123', 'song-124', 'song-125']);
      expect(state.updatedAt, DateTime.parse('2026-08-22T06:00:00.000Z'));
      expect(state.syncUnknown, isFalse);
    });

    test('PlaybackState.fromJson handles camelCase and null fallbacks', () {
      final json = {
        'activeDevice': 'desktop-1',
        'activeDeviceName': 'MacBook Pro',
        'trackId': 'track-abc',
        'trackTitle': 'Starboy',
        'positionMs': 12000,
        'isPlaying': false,
        'syncUnknown': true,
      };

      final state = PlaybackState.fromJson(json);

      expect(state.activeDevice, 'desktop-1');
      expect(state.activeDeviceName, 'MacBook Pro');
      expect(state.trackId, 'track-abc');
      expect(state.trackTitle, 'Starboy');
      expect(state.artist, isNull);
      expect(state.album, isNull);
      expect(state.positionMs, 12000);
      expect(state.isPlaying, isFalse);
      expect(state.queue, isEmpty);
      expect(state.syncUnknown, isTrue);
    });

    test('PlaybackState.toJson produces correct serialization', () {
      final now = DateTime.parse('2026-08-22T06:30:00.000Z');
      final state = PlaybackState(
        activeDevice: 'dev-1',
        activeDeviceName: 'Pixel 9',
        trackId: 'track-99',
        trackTitle: 'After Hours',
        artist: 'The Weeknd',
        album: 'After Hours',
        positionMs: 60000,
        isPlaying: true,
        queue: const ['track-99', 'track-100'],
        updatedAt: now,
        syncUnknown: false,
      );

      final json = state.toJson();

      expect(json['active_device'], 'dev-1');
      expect(json['active_device_name'], 'Pixel 9');
      expect(json['track_id'], 'track-99');
      expect(json['track_title'], 'After Hours');
      expect(json['artist'], 'The Weeknd');
      expect(json['album'], 'After Hours');
      expect(json['position_ms'], 60000);
      expect(json['is_playing'], isTrue);
      expect(json['queue'], ['track-99', 'track-100']);
      expect(json['updated_at'], now.toIso8601String());
      expect(json['sync_unknown'], isFalse);
    });

    test('PlaybackState copyWith and value equality', () {
      const original = PlaybackState(
        activeDevice: 'dev-1',
        trackId: 'song-1',
        isPlaying: false,
        positionMs: 1000,
        queue: ['song-1', 'song-2'],
      );

      final updated = original.copyWith(isPlaying: true, positionMs: 2000);
      final identicalCopy = original.copyWith();

      expect(updated.isPlaying, isTrue);
      expect(updated.positionMs, 2000);
      expect(updated.activeDevice, 'dev-1');
      expect(original == identicalCopy, isTrue);
      expect(original == updated, isFalse);
      expect(original.hashCode == identicalCopy.hashCode, isTrue);
    });
  });

  group('SessionSyncService WebSocket & REST Lifecycle', () {
    late _FakeWebSocketChannel fakeChannel;
    late List<Uri> connectedUris;
    late MockClient fakeHttpClient;

    setUp(() {
      fakeChannel = _FakeWebSocketChannel();
      connectedUris = [];
      fakeHttpClient = MockClient((request) async {
        if (request.url.path == '/playback/state') {
          return http.Response(
            jsonEncode({
              'active_device': 'device-rest',
              'track_id': 'song-rest',
              'position_ms': 5000,
              'is_playing': true,
              'queue': ['song-rest'],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });
    });

    test('connect() opens WebSocket with token & device_id query params', () async {
      final service = SessionSyncService(
        jwt: 'mock_jwt_token',
        deviceIdProvider: () async => 'device-test-123',
        channelFactory: (uri) {
          connectedUris.add(uri);
          return fakeChannel;
        },
        httpClient: fakeHttpClient,
      );

      expect(service.isConnected, isFalse);

      await service.connect();

      expect(service.isConnected, isTrue);
      expect(connectedUris, hasLength(1));
      final uri = connectedUris.first;
      expect(uri.scheme, 'wss');
      expect(uri.host, 'session.subimusic.me');
      expect(uri.path, '/ws/session');
      expect(uri.queryParameters['token'], 'mock_jwt_token');
      expect(uri.queryParameters['device_id'], 'device-test-123');

      service.dispose();
    });

    test('onMessage receives authoritative state broadcast and emits to stateStream', () async {
      final service = SessionSyncService(
        jwt: 'mock_jwt',
        deviceIdProvider: () async => 'device-1',
        channelFactory: (uri) => fakeChannel,
        httpClient: fakeHttpClient,
      );

      final emissions = <PlaybackState>[];
      final sub = service.stateStream.listen(emissions.add);

      await service.connect();

      // Simulate state broadcast from server
      fakeChannel.simulateInboundMessage(jsonEncode({
        'active_device': 'device-phone',
        'track_id': 'song-broadcast-1',
        'position_ms': 30000,
        'is_playing': true,
        'queue': ['song-broadcast-1'],
      }));

      await Future.delayed(Duration.zero);

      expect(emissions.any((s) => s.trackId == 'song-broadcast-1'), isTrue);
      expect(service.currentState.trackId, 'song-broadcast-1');
      expect(service.currentState.positionMs, 30000);
      expect(service.currentState.isPlaying, isTrue);

      await sub.cancel();
      service.dispose();
    });

    test('pong messages are filtered without state emission', () async {
      final service = SessionSyncService(
        jwt: 'mock_jwt',
        deviceIdProvider: () async => 'device-1',
        channelFactory: (uri) => fakeChannel,
        httpClient: fakeHttpClient,
      );

      final emissions = <PlaybackState>[];
      final sub = service.stateStream.listen(emissions.add);

      await service.connect();
      await Future.delayed(Duration.zero);
      final countBefore = emissions.length;

      // Send pong
      fakeChannel.simulateInboundMessage(jsonEncode({'type': 'pong'}));
      await Future.delayed(Duration.zero);

      expect(emissions.length, countBefore); // No new state added

      await sub.cancel();
      service.dispose();
    });

    test('pushStateUpdate sends state_update JSON to sink', () async {
      final service = SessionSyncService(
        jwt: 'mock_jwt',
        deviceIdProvider: () async => 'device-1',
        channelFactory: (uri) => fakeChannel,
        httpClient: fakeHttpClient,
      );

      await service.connect();

      service.pushStateUpdate(
        trackId: 'track-55',
        positionMs: 15400,
        isPlaying: true,
        queue: ['track-55', 'track-56'],
      );

      expect(fakeChannel._sink.sentMessages, hasLength(1));
      final sentJson = jsonDecode(fakeChannel._sink.sentMessages.first as String);

      expect(sentJson['type'], 'state_update');
      expect(sentJson['track_id'], 'track-55');
      expect(sentJson['position_ms'], 15400);
      expect(sentJson['is_playing'], isTrue);
      expect(sentJson['queue'], ['track-55', 'track-56']);

      service.dispose();
    });

    test('transferPlayback sends transfer_playback JSON to sink', () async {
      final service = SessionSyncService(
        jwt: 'mock_jwt',
        deviceIdProvider: () async => 'device-1',
        channelFactory: (uri) => fakeChannel,
        httpClient: fakeHttpClient,
      );

      await service.connect();

      service.transferPlayback('target-device-99');

      expect(fakeChannel._sink.sentMessages, hasLength(1));
      final sentJson = jsonDecode(fakeChannel._sink.sentMessages.first as String);

      expect(sentJson['type'], 'transfer_playback');
      expect(sentJson['device_id'], 'target-device-99');

      service.dispose();
    });

    test('disconnect emits syncUnknown state and triggers backoff reconnect attempts', () async {
      final service = SessionSyncService(
        jwt: 'mock_jwt',
        deviceIdProvider: () async => 'device-1',
        channelFactory: (uri) => fakeChannel,
        httpClient: fakeHttpClient,
      );

      final emissions = <PlaybackState>[];
      final reconnectAttempts = <int>[];
      final stateSub = service.stateStream.listen(emissions.add);
      final reconnectSub = service.reconnectAttemptStream.listen(reconnectAttempts.add);

      await service.connect();

      // Simulate unexpected server disconnect
      fakeChannel.simulateClose(1006, 'Connection dropped');
      await Future.delayed(Duration.zero);

      expect(service.isConnected, isFalse);
      expect(emissions.last.syncUnknown, isTrue);
      expect(reconnectAttempts, contains(1));

      await stateSub.cancel();
      await reconnectSub.cancel();
      service.dispose();
    });

    test('4001 close code forces JWT refresh via jwtSupplier', () async {
      int refreshCount = 0;
      final service = SessionSyncService(
        jwtSupplier: ({bool forceRefresh = false}) {
          if (forceRefresh) refreshCount++;
          return 'refreshed_jwt_token';
        },
        deviceIdProvider: () async => 'device-1',
        channelFactory: (uri) => fakeChannel,
        httpClient: fakeHttpClient,
      );

      await service.connect();

      // Simulate 4001 close (auth invalid / token expired)
      fakeChannel.simulateClose(4001, 'Unauthorized');
      await Future.delayed(const Duration(milliseconds: 600));

      expect(refreshCount, greaterThanOrEqualTo(1));

      service.dispose();
    });

    test('REST fetchCurrentState retries on 401 with refreshed token', () async {
      int getCalls = 0;
      int tokenRefreshCalls = 0;

      final authHttpClient = MockClient((request) async {
        getCalls++;
        final authHeader = request.headers['Authorization'];
        if (authHeader == 'Bearer initial_expired_jwt') {
          return http.Response('{"error": "unauthorized"}', 401);
        }
        if (authHeader == 'Bearer fresh_jwt_token') {
          return http.Response(
            jsonEncode({
              'active_device': 'device-synced',
              'track_id': 'song-valid',
              'position_ms': 1000,
              'is_playing': true,
              'queue': ['song-valid'],
            }),
            200,
          );
        }
        return http.Response('Forbidden', 403);
      });

      final service = SessionSyncService(
        jwt: 'initial_expired_jwt',
        jwtSupplier: ({bool forceRefresh = false}) {
          if (forceRefresh) tokenRefreshCalls++;
          return 'fresh_jwt_token';
        },
        deviceIdProvider: () async => 'device-1',
        httpClient: authHttpClient,
      );

      final state = await service.fetchCurrentState();

      expect(getCalls, 2);
      expect(tokenRefreshCalls, 1);
      expect(state.trackId, 'song-valid');
      expect(state.activeDevice, 'device-synced');

      service.dispose();
    });

    test('manual disconnect() cleanly stops reconnect timers and closes sink', () async {
      final service = SessionSyncService(
        jwt: 'mock_jwt',
        deviceIdProvider: () async => 'device-1',
        channelFactory: (uri) => fakeChannel,
        httpClient: fakeHttpClient,
      );

      await service.connect();
      expect(service.isConnected, isTrue);

      service.disconnect();

      expect(service.isConnected, isFalse);
      expect(fakeChannel._sink.isClosed, isTrue);

      // Verify that closing socket after manual disconnect does not trigger reconnect attempts
      fakeChannel.simulateClose();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(service.reconnectAttempt, 0);

      service.dispose();
    });
  });
}
