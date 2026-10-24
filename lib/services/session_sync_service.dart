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
  final String? coverArtId;
  final double durationS;
  final int positionMs;
  final bool isPlaying;
  final List<String> queue;
  final int queueIndex;
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
    this.coverArtId,
    this.durationS = 0,
    this.positionMs = 0,
    this.isPlaying = false,
    this.queue = const [],
    this.queueIndex = 0,
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
        coverArtId = null,
        durationS = 0,
        positionMs = 0,
        isPlaying = false,
        queue = const [],
        queueIndex = 0,
        updatedAt = null,
        syncUnknown = false;

  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is num) {
        // The server stamps unix seconds (a float); older callers sent milliseconds.
        final ms = val < 100000000000 ? (val * 1000).round() : val.round();
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
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
      coverArtId: json['cover_art_id'] as String? ?? json['coverArtId'] as String?,
      durationS: (json['duration_s'] as num?)?.toDouble() ?? 0,
      queueIndex: (json['queue_index'] as num?)?.toInt() ?? 0,
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
        'cover_art_id': coverArtId,
        'duration_s': durationS,
        'queue_index': queueIndex,
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
    String? coverArtId,
    double? durationS,
    int? positionMs,
    bool? isPlaying,
    List<String>? queue,
    int? queueIndex,
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
      coverArtId: coverArtId ?? this.coverArtId,
      durationS: durationS ?? this.durationS,
      positionMs: positionMs ?? this.positionMs,
      isPlaying: isPlaying ?? this.isPlaying,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
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
          coverArtId == other.coverArtId &&
          durationS == other.durationS &&
          queueIndex == other.queueIndex &&
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
        coverArtId,
        durationS,
        queueIndex,
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

// ---------------------------------------------------------------------------
// Devices, remote commands, connection status
// ---------------------------------------------------------------------------

enum SyncDeviceType {
  phone,
  tablet,
  desktop,
  web,
  tv,
  speaker,
  unknown;

  static SyncDeviceType parse(Object? raw) =>
      SyncDeviceType.values.firstWhere((t) => t.name == raw, orElse: () => SyncDeviceType.unknown);
}

/// One of this account's devices that is connected right now.
@immutable
class SyncDevice {
  final String id;
  final String name;
  final SyncDeviceType type;
  final bool active;

  const SyncDevice({required this.id, required this.name, this.type = SyncDeviceType.unknown, this.active = false});

  factory SyncDevice.fromJson(Map<String, dynamic> j) => SyncDevice(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Unknown device',
        type: SyncDeviceType.parse(j['type']),
        active: j['active'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncDevice && other.id == id && other.name == name && other.type == type && other.active == active;

  @override
  int get hashCode => Object.hash(id, name, type, active);
}

/// What a controller asked the active device to do.
@immutable
class RemoteCommand {
  final String action;
  final int? positionMs;
  final double? volume;
  final String? trackId;
  final int? index;
  final List<String> queue;
  final String fromDevice;
  final String fromName;

  const RemoteCommand({
    required this.action,
    this.positionMs,
    this.volume,
    this.trackId,
    this.index,
    this.queue = const [],
    this.fromDevice = '',
    this.fromName = '',
  });

  factory RemoteCommand.fromJson(Map<String, dynamic> j) => RemoteCommand(
        action: j['action']?.toString() ?? '',
        positionMs: (j['position_ms'] as num?)?.toInt(),
        volume: (j['volume'] as num?)?.toDouble(),
        trackId: j['track_id']?.toString(),
        index: (j['index'] as num?)?.toInt(),
        queue: [for (final q in (j['queue'] as List? ?? const [])) q.toString()],
        fromDevice: j['from_device']?.toString() ?? '',
        fromName: j['from_name']?.toString() ?? '',
      );
}

/// The server's answer to a command or transfer this device sent.
@immutable
class CommandResult {
  final bool ok;
  final String action;
  final String? reason;
  const CommandResult({required this.ok, required this.action, this.reason});

  /// A line for the person: what went wrong and what to do.
  String get message => switch (reason) {
        'no_active_device' => 'Nothing is playing on your devices. Start music on one first.',
        'device_offline' => 'That device went offline.',
        'device_too_old' => 'That device needs the latest NaviVibe to be controlled.',
        _ => 'That didn’t work. Try again.',
      };
}

enum SyncConnection { connecting, online, offline }

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

  final _devicesController = StreamController<List<SyncDevice>>.broadcast();
  Stream<List<SyncDevice>> get devicesStream => _devicesController.stream;
  List<SyncDevice> _devices = const [];
  List<SyncDevice> get currentDevices => _devices;

  final _commandController = StreamController<RemoteCommand>.broadcast();
  Stream<RemoteCommand> get commandStream => _commandController.stream;

  final _resultController = StreamController<CommandResult>.broadcast();
  Stream<CommandResult> get resultStream => _resultController.stream;

  final _connectionController = StreamController<SyncConnection>.broadcast();
  Stream<SyncConnection> get connectionStream => _connectionController.stream;
  SyncConnection _connection = SyncConnection.connecting;
  SyncConnection get connection => _connection;

  void _setConnection(SyncConnection c) {
    if (_connection == c) return;
    _connection = c;
    if (!_connectionController.isClosed) _connectionController.add(c);
  }

  final _reconnectAttemptController = StreamController<int>.broadcast();
  Stream<int> get reconnectAttemptStream => _reconnectAttemptController.stream;

  final http.Client _httpClient;
  final WebSocketChannelFactory _channelFactory;
  final JwtSupplier? _jwtSupplier;
  final String _wsBaseUrl;
  final String _httpBaseUrl;
  final Future<String> Function() _deviceIdProvider;
  final Random _random;
  final String? _deviceName;
  final SyncDeviceType _deviceType;

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
    String? deviceName,
    SyncDeviceType deviceType = SyncDeviceType.unknown,
  })  : _deviceName = deviceName,
        _deviceType = deviceType,
        _jwt = jwt,
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

  /// How this device introduces itself in the "Playing on" list.
  String? get deviceName => _deviceName;

  // ---------------------------------------------------------------------------
  // 1. Connect Flow
  // ---------------------------------------------------------------------------

  /// Initiates connection to the session synchronization server.
  Future<void> connect() async {
    if (_isConnecting || _channel != null) return;
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

      _setConnection(SyncConnection.connecting);
      final uri = Uri.parse(_wsBaseUrl).replace(queryParameters: {
        'token': _jwt!,
        'device_id': _deviceId!,
        if (_deviceName != null && _deviceName.isNotEmpty) 'device_name': _deviceName,
        if (_deviceType != SyncDeviceType.unknown) 'device_type': _deviceType.name,
        'proto': '2',
      });

      _channel = _channelFactory(uri);
      await _channel!.ready;

      _reconnectAttempt = 0;
      _reconnectAttemptController.add(0);
      _setConnection(SyncConnection.online);
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

      switch (json['type']) {
        case 'pong':
          return; // Heartbeat ack, no state change
        case 'devices':
          _devices = [
            for (final d in (json['payload'] as List? ?? const []))
              if (d is Map) SyncDevice.fromJson(Map<String, dynamic>.from(d)),
          ];
          if (!_devicesController.isClosed) _devicesController.add(_devices);
          return;
        case 'command':
          if (!_commandController.isClosed) _commandController.add(RemoteCommand.fromJson(json));
          return;
        case 'command_result':
          if (!_resultController.isClosed) {
            _resultController.add(CommandResult(
              ok: json['ok'] == true,
              action: json['action']?.toString() ?? '',
              reason: json['reason']?.toString(),
            ));
          }
          return;
      }

      // `state` carries its fields flat and again under "payload"; read the
      // payload when there is one.
      final body = json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : json;
      _emitState(PlaybackState.fromJson(body));
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
    _devices = const [];
    if (!_devicesController.isClosed) _devicesController.add(_devices);
    _setConnection(SyncConnection.offline);

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
    String? trackTitle,
    String? artist,
    String? album,
    String? coverArtId,
    double? durationS,
    int? queueIndex,
  }) {
    _send({
      'type': 'state_update',
      'track_id': ?trackId,
      'position_ms': ?positionMs,
      'is_playing': ?isPlaying,
      'queue': ?queue,
      'track_title': ?trackTitle,
      'artist': ?artist,
      'album': ?album,
      'cover_art_id': ?coverArtId,
      'duration_s': ?durationS,
      'queue_index': ?queueIndex,
    });
  }

  /// Sends a playback handoff / transfer request to switch active device.
  /// The server hands the playhead over with it.
  void transferPlayback(String deviceId, {String? deviceName}) {
    _send({
      'type': 'transfer_playback',
      'device_id': deviceId,
      'device_name': ?deviceName,
    });
  }

  /// Stops being the active device (the server keeps the position).
  void releasePlayback() => _send({'type': 'release_playback'});

  /// Remote control: asks the active device (or [target]) to do [action].
  /// Answered on [resultStream].
  void sendCommand(
    String action, {
    int? positionMs,
    double? volume,
    String? trackId,
    int? index,
    List<String>? queue,
    String? target,
  }) {
    _send({
      'type': 'command',
      'action': action,
      'position_ms': ?positionMs,
      'volume': ?volume,
      'track_id': ?trackId,
      'index': ?index,
      'queue': ?queue,
      'target': ?target,
    });
  }

  /// Asks for the device list (it is also pushed whenever it changes).
  void requestDevices() => _send({'type': 'get_devices'});

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
    _setConnection(SyncConnection.offline);
  }

  /// Disposes stream controllers and cleanly tears down connections.
  void dispose() {
    disconnect();
    _stateController.close();
    _reconnectAttemptController.close();
    _devicesController.close();
    _commandController.close();
    _resultController.close();
    _connectionController.close();
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
