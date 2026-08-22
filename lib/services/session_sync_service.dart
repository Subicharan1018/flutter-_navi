// =============================================================================
// SessionSyncService — WebSocket & REST playback session synchronization
//
// Communicates with session.subimusic.me to maintain real-time playback state
// across multiple devices.
//
// SCOPE: Websocket lifecycle only. Exposes reactive streams (`stateStream`,
// `reconnectAttemptStream`). Zero audio playback or UI logic in this class —
// consumption and actions belong to PlayerProvider (Step 5).
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/hive_boxes.dart';
import '../utils/device_utils.dart';

// ---------------------------------------------------------------------------
// PlaybackState Model
// ---------------------------------------------------------------------------

/// Authoritative snapshot of playback state as tracked by the session server.
@immutable
class PlaybackState {
  final String? activeDevice;
  final String? activeDeviceName;
  final String? trackId;
  final String? trackTitle;
  final String? artist;
  final String? album;
  final int positionMs;
  final bool isPlaying;
  final List<String> queue;
  final DateTime? updatedAt;

  /// True when connection is offline / disconnected and passive devices
  /// should cease enforcing active device restrictions.
  final bool syncUnknown;

  const PlaybackState({
    this.activeDevice,
    this.activeDeviceName,
    this.trackId,
    this.trackTitle,
    this.artist,
    this.album,
    this.positionMs = 0,
    this.isPlaying = false,
    this.queue = const [],
    this.updatedAt,
    this.syncUnknown = false,
  });

  /// Default initial state before any server synchronization has occurred.
  const PlaybackState.initial()
      : activeDevice = null,
        activeDeviceName = null,
        trackId = null,
        trackTitle = null,
        artist = null,
        album = null,
        positionMs = 0,
        isPlaying = false,
        queue = const [],
        updatedAt = null,
        syncUnknown = false;

  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    List<String> parseQueue(dynamic val) {
      if (val is List) {
        return val.map((e) => e.toString()).toList();
      }
      return const [];
    }

    return PlaybackState(
      activeDevice: json['active_device'] as String? ??
          json['activeDevice'] as String?,
      activeDeviceName: json['active_device_name'] as String? ??
          json['activeDeviceName'] as String?,
      trackId: json['track_id'] as String? ?? json['trackId'] as String?,
      trackTitle:
          json['track_title'] as String? ?? json['trackTitle'] as String?,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      positionMs: (json['position_ms'] as num?)?.toInt() ??
          (json['positionMs'] as num?)?.toInt() ??
          0,
      isPlaying:
          json['is_playing'] as bool? ?? json['isPlaying'] as bool? ?? false,
      queue: parseQueue(json['queue']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
      syncUnknown: json['sync_unknown'] as bool? ??
          json['syncUnknown'] as bool? ??
          false,
    );
  }

  Map<String, dynamic> toJson() => {
        'active_device': activeDevice,
        'active_device_name': activeDeviceName,
        'track_id': trackId,
        'track_title': trackTitle,
        'artist': artist,
        'album': album,
        'position_ms': positionMs,
        'is_playing': isPlaying,
        'queue': queue,
        'updated_at': ?updatedAt?.toIso8601String(),
        'sync_unknown': syncUnknown,
      };

  PlaybackState copyWith({
    String? activeDevice,
    String? activeDeviceName,
    String? trackId,
    String? trackTitle,
    String? artist,
    String? album,
    int? positionMs,
    bool? isPlaying,
    List<String>? queue,
    DateTime? updatedAt,
    bool? syncUnknown,
  }) {
    return PlaybackState(
      activeDevice: activeDevice ?? this.activeDevice,
      activeDeviceName: activeDeviceName ?? this.activeDeviceName,
      trackId: trackId ?? this.trackId,
      trackTitle: trackTitle ?? this.trackTitle,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      positionMs: positionMs ?? this.positionMs,
      isPlaying: isPlaying ?? this.isPlaying,
      queue: queue ?? this.queue,
      updatedAt: updatedAt ?? this.updatedAt,
      syncUnknown: syncUnknown ?? this.syncUnknown,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackState &&
          runtimeType == other.runtimeType &&
          activeDevice == other.activeDevice &&
          activeDeviceName == other.activeDeviceName &&
          trackId == other.trackId &&
          trackTitle == other.trackTitle &&
          artist == other.artist &&
          album == other.album &&
          positionMs == other.positionMs &&
          isPlaying == other.isPlaying &&
          const ListEquality<String>().equals(queue, other.queue) &&
          updatedAt == other.updatedAt &&
          syncUnknown == other.syncUnknown;

  @override
  int get hashCode => Object.hash(
        activeDevice,
        activeDeviceName,
        trackId,
        trackTitle,
        artist,
        album,
        positionMs,
        isPlaying,
        Object.hashAll(queue),
        updatedAt,
        syncUnknown,
      );

  @override
  String toString() =>
      'PlaybackState(activeDevice: $activeDevice, trackId: $trackId, isPlaying: $isPlaying, pos: ${positionMs}ms, syncUnknown: $syncUnknown)';
}

// ---------------------------------------------------------------------------
// Type Definitions for Dependency Injection
// ---------------------------------------------------------------------------

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);
typedef JwtSupplier = FutureOr<String?> Function({bool forceRefresh});

// ---------------------------------------------------------------------------
// SessionSyncService
// ---------------------------------------------------------------------------

class SessionSyncService {
  static const String defaultWsBaseUrl =
      'wss://session.subimusic.me/ws/session';
  static const String defaultHttpBaseUrl = 'https://session.subimusic.me';

  final _stateController = StreamController<PlaybackState>.broadcast();
  Stream<PlaybackState> get stateStream => _stateController.stream;

  final _reconnectAttemptController = StreamController<int>.broadcast();
  Stream<int> get reconnectAttemptStream => _reconnectAttemptController.stream;

  final http.Client _httpClient;
  final WebSocketChannelFactory _channelFactory;
  final JwtSupplier? _jwtSupplier;
  final String _wsBaseUrl;
  final String _httpBaseUrl;
  final Future<String> Function() _deviceIdProvider;
  final Random _random;

  WebSocketChannel? _channel;
  String? _deviceId;
  String? _jwt;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _manuallyDisconnected = false;
  bool _isConnecting = false;
  PlaybackState _lastState = const PlaybackState.initial();

  SessionSyncService({
    String? jwt,
    JwtSupplier? jwtSupplier,
    http.Client? httpClient,
    WebSocketChannelFactory? channelFactory,
    String? wsBaseUrl,
    String? httpBaseUrl,
    Future<String> Function()? deviceIdProvider,
    Random? random,
  })  : _jwt = jwt,
        _jwtSupplier = jwtSupplier,
        _httpClient = httpClient ?? http.Client(),
        _channelFactory = channelFactory ?? WebSocketChannel.connect,
        _wsBaseUrl = wsBaseUrl ?? defaultWsBaseUrl,
        _httpBaseUrl = httpBaseUrl ?? defaultHttpBaseUrl,
        _deviceIdProvider = deviceIdProvider ?? getOrCreateDeviceId,
        _random = random ?? Random();

  /// Current cached state snapshot.
  PlaybackState get currentState => _lastState;

  /// Current reconnect attempt counter.
  int get reconnectAttempt => _reconnectAttempt;

  /// True when the WebSocket is currently open and not manually disconnected.
  bool get isConnected => _channel != null && !_manuallyDisconnected;

  /// Current persistent device ID.
  String? get deviceId => _deviceId;

  // ---------------------------------------------------------------------------
  // 1. Connect Flow
  // ---------------------------------------------------------------------------

  /// Initiates connection to the session synchronization server.
  Future<void> connect() async {
    if (_isConnecting) return;
    _isConnecting = true;
    _manuallyDisconnected = false;

    try {
      _deviceId ??= await _deviceIdProvider();
      _jwt ??= await _resolveJwt(forceRefresh: false);

      if (_jwt == null || _jwt!.isEmpty) {
        debugPrint('[SessionSync] ⚠️ No JWT token available — cannot connect');
        _scheduleReconnect(isAuthFailure: true);
        return;
      }

      final uri = Uri.parse('$_wsBaseUrl?token=$_jwt&device_id=$_deviceId');

      _channel = _channelFactory(uri);
      await _channel!.ready;

      _reconnectAttempt = 0;
      _reconnectAttemptController.add(0);
      _startPingTimer();

      _channel!.stream.listen(
        _onMessage,
        onDone: () => _onDisconnected(_channel?.closeCode),
        onError: (e) {
          debugPrint('[SessionSync] ❌ WebSocket error: $e');
          _onDisconnected(_channel?.closeCode);
        },
      );

      // 5. Initial REST resync on (re)connect
      try {
        final restState = await fetchCurrentState();
        _emitState(restState);
      } catch (e) {
        debugPrint('[SessionSync] ℹ️ REST initial sync note: $e');
        // WS initial push is the fallback if REST fails; don't block connect on it
      }
    } catch (e) {
      debugPrint('[SessionSync] ❌ Connection failed: $e');
      final is4001 =
          e.toString().contains('4001') || _channel?.closeCode == 4001;
      _scheduleReconnect(isAuthFailure: is4001);
    } finally {
      _isConnecting = false;
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Message Handling
  // ---------------------------------------------------------------------------

  void _onMessage(dynamic raw) {
    try {
      final Map<String, dynamic> json = raw is String
          ? (jsonDecode(raw) as Map<String, dynamic>)
          : (raw as Map<String, dynamic>);

      if (json['type'] == 'pong') return; // Heartbeat ack, no state change

      final state = PlaybackState.fromJson(json);
      _emitState(state);
    } catch (e) {
      debugPrint('[SessionSync] ❌ Error parsing message: $e (raw: $raw)');
    }
  }

  void _emitState(PlaybackState state) {
    _lastState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Ping / Heartbeat
  // ---------------------------------------------------------------------------

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _send({'type': 'ping'});
    });
  }

  // ---------------------------------------------------------------------------
  // 4. Disconnect Handling + Reconnect / Backoff
  // ---------------------------------------------------------------------------

  void _onDisconnected([int? closeCode]) {
    _pingTimer?.cancel();
    _channel = null;

    if (_manuallyDisconnected) return;

    final is4001 = closeCode == 4001;
    if (is4001) {
      debugPrint(
        '[SessionSync] 🔒 Server closed socket with 4001 (Unauthorized) — invalidating token',
      );
      _jwt = null;
    }

    // Passive devices stop enforcing active_device while offline —
    // emit a "sync unknown" marker so UI can fall back to standalone mode.
    _emitState(const PlaybackState.initial().copyWith(syncUnknown: true));

    _scheduleReconnect(isAuthFailure: is4001);
  }

  void _scheduleReconnect({bool isAuthFailure = false}) {
    if (_manuallyDisconnected) return;

    _reconnectTimer?.cancel();

    if (isAuthFailure) {
      _jwt = null;
      _reconnectAttempt++;
      _reconnectAttemptController.add(_reconnectAttempt);

      // Re-fetch the JWT via jwtSupplier before retrying instead of backing off forever
      _reconnectTimer = Timer(const Duration(milliseconds: 500), () async {
        if (!_manuallyDisconnected) {
          final newToken = await _resolveJwt(forceRefresh: true);
          if (newToken != null && newToken.isNotEmpty) {
            connect();
          } else {
            debugPrint(
              '[SessionSync] ❌ Re-auth failed — no valid token retrieved',
            );
          }
        }
      });
      return;
    }

    _reconnectAttempt++;
    final baseSeconds = min(pow(2, _reconnectAttempt - 1).toInt(), 60);
    final jitter = baseSeconds * 0.2 * (_random.nextDouble() * 2 - 1); // ±20%
    final delayMs = max(100, ((baseSeconds + jitter) * 1000).round());
    final delay = Duration(milliseconds: delayMs);

    _reconnectTimer = Timer(delay, () {
      if (!_manuallyDisconnected) {
        connect();
      }
    });

    _reconnectAttemptController.add(_reconnectAttempt);
  }

  // ---------------------------------------------------------------------------
  // 5. REST Authoritative State Fetch
  // ---------------------------------------------------------------------------

  /// Fetches the authoritative playback state from `GET /playback/state`.
  Future<PlaybackState> fetchCurrentState() async {
    _jwt ??= await _resolveJwt(forceRefresh: false);
    final uri = Uri.parse('$_httpBaseUrl/playback/state');

    var resp = await _httpClient.get(
      uri,
      headers: {
        if (_jwt != null && _jwt!.isNotEmpty) 'Authorization': 'Bearer $_jwt',
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode == 401) {
      debugPrint(
        '[SessionSync] 🔒 REST /playback/state returned 401 — refreshing token & retrying',
      );
      _jwt = null;
      final refreshedToken = await _resolveJwt(forceRefresh: true);
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        resp = await _httpClient.get(
          uri,
          headers: {
            'Authorization': 'Bearer $refreshedToken',
            'Accept': 'application/json',
          },
        );
      }
    }

    if (resp.statusCode == 200) {
      final dynamic data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) {
        return PlaybackState.fromJson(data);
      }
    }

    throw HttpException(
      'Failed to fetch playback state: HTTP ${resp.statusCode}',
      uri: uri,
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Outbound Methods
  // ---------------------------------------------------------------------------

  /// Pushes a playback state delta / update frame to the session server.
  void pushStateUpdate({
    String? trackId,
    int? positionMs,
    bool? isPlaying,
    List<String>? queue,
  }) {
    _send({
      'type': 'state_update',
      'track_id': ?trackId,
      'position_ms': ?positionMs,
      'is_playing': ?isPlaying,
      'queue': ?queue,
    });
  }

  /// Sends a playback handoff / transfer request to switch active device.
  void transferPlayback(String deviceId) {
    _send({
      'type': 'transfer_playback',
      'device_id': deviceId,
    });
  }

  void _send(Map<String, dynamic> msg) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(msg));
    } catch (e) {
      debugPrint('[SessionSync] ❌ Failed to send message: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 7. Manual Disconnect & Disposal
  // ---------------------------------------------------------------------------

  /// Manually disconnects the session (e.g. app exit, logout).
  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  /// Disposes stream controllers and cleanly tears down connections.
  void dispose() {
    disconnect();
    _stateController.close();
    _reconnectAttemptController.close();
  }

  // ---------------------------------------------------------------------------
  // Helper: JWT Resolution
  // ---------------------------------------------------------------------------

  Future<String?> _resolveJwt({bool forceRefresh = false}) async {
    if (!forceRefresh && _jwt != null && _jwt!.isNotEmpty) {
      return _jwt;
    }
    if (_jwtSupplier != null) {
      _jwt = await _jwtSupplier(forceRefresh: forceRefresh);
      return _jwt;
    }
    // Fallback: build standard Basic token from stored credentials if available
    try {
      final rawUser = HiveBoxes.auth.get(HiveBoxes.kUsername)?.toString() ?? '';
      final rawPass = HiveBoxes.auth.get(HiveBoxes.kPassword)?.toString() ?? '';
      if (rawUser.isNotEmpty && rawPass.isNotEmpty) {
        _jwt = base64Encode(utf8.encode('$rawUser:$rawPass'));
        return _jwt;
      }
    } catch (_) {}
    return null;
  }
}
