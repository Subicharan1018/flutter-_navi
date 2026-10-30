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

  /// Protocol 3: bumped by the server on every change / every change of host.
  final int? epoch;
  final int? version;

  /// Server clock (ms since epoch) at which [positionMs] was true.
  final int? positionAtServerMs;

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
    this.epoch,
    this.version,
    this.positionAtServerMs,
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
        syncUnknown = false,
        epoch = null,
        version = null,
        positionAtServerMs = null;

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
      epoch: (json['epoch'] as num?)?.toInt(),
      version: (json['version'] as num?)?.toInt(),
      positionAtServerMs: (json['position_at_server_ms'] as num?)?.toInt(),
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
    int? epoch,
    int? version,
    int? positionAtServerMs,
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
      epoch: epoch ?? this.epoch,
      version: version ?? this.version,
      positionAtServerMs: positionAtServerMs ?? this.positionAtServerMs,
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
          epoch == other.epoch &&
          version == other.version &&
          positionAtServerMs == other.positionAtServerMs &&
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
        epoch,
        version,
        positionAtServerMs,
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

  /// The host: the device that holds playback.
  final bool active;

  /// Seconds since the server last heard from it (null: not reported).
  final double? lastSeenS;

  const SyncDevice({
    required this.id,
    required this.name,
    this.type = SyncDeviceType.unknown,
    this.active = false,
    this.lastSeenS,
  });

  factory SyncDevice.fromJson(Map<String, dynamic> j) => SyncDevice(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Unknown device',
        type: SyncDeviceType.parse(j['type']),
        active: j['active'] == true || j['host'] == true,
        lastSeenS: (j['last_seen_s'] as num?)?.toDouble(),
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
        'claim_cooldown' => 'Another device just took over. Try again in a moment.',
        'device_offline' => 'That device went offline.',
        'device_too_old' => 'That device needs the latest NaviVibe to be controlled.',
        _ => 'That didn’t work. Try again.',
      };
}

enum SyncConnection { connecting, online, offline }

/// The server asks this device to get ready to become the host: load [trackId] at
/// [positionMs] (paused), then answer with `sendReady(transferId)`. Until it does,
/// the current host keeps playing, so there is no gap.
@immutable
class PrepareTransfer {
  final String transferId;
  final int epoch;
  final String? trackId;
  final int positionMs;
  final List<String> queue;
  final int queueIndex;
  final bool play;

  const PrepareTransfer({
    required this.transferId,
    required this.epoch,
    this.trackId,
    this.positionMs = 0,
    this.queue = const [],
    this.queueIndex = 0,
    this.play = true,
  });

  factory PrepareTransfer.fromJson(Map<String, dynamic> j) => PrepareTransfer(
        transferId: j['transfer_id']?.toString() ?? '',
        epoch: (j['epoch'] as num?)?.toInt() ?? 0,
        trackId: j['track_id']?.toString(),
        positionMs: (j['position_ms'] as num?)?.toInt() ?? 0,
        queue: [for (final q in (j['queue'] as List? ?? const [])) q.toString()],
        queueIndex: (j['queue_index'] as num?)?.toInt() ?? 0,
        play: j['play'] != false,
      );
}

/// NTP-style estimate of `serverTime - deviceTime` from ping round trips. It keeps
/// the lowest-RTT of the last eight samples (the least asymmetric one) and eases
/// toward it, so one slow reply never drags the clock.
class ClockEstimator {
  final List<({int rtt, int offset})> _samples = [];
  int? _offset;

  /// [t0]: device ms when the ping left; [t1]: device ms when the pong arrived;
  /// [serverT]: server ms when it answered.
  void add(int t0, int t1, int serverT) {
    final rtt = t1 - t0;
    if (rtt < 0 || serverT <= 0) return;
    // offset = serverT - (t0 + t1) / 2: the server stamped the middle of the trip.
    final offset = serverT - ((t0 + t1) ~/ 2);
    _samples.add((rtt: rtt, offset: offset));
    if (_samples.length > 8) _samples.removeAt(0);
    final best = _samples.reduce((a, b) => a.rtt <= b.rtt ? a : b);
    final prev = _offset;
    _offset = prev == null || (best.offset - prev).abs() > 1000 ? best.offset : ((prev * 7 + best.offset * 3) / 10).round();
  }

  bool get ready => _offset != null;
  int get offsetMs => _offset ?? 0;
  int get rttMs => _samples.isEmpty ? 0 : _samples.map((s) => s.rtt).reduce(min);
  int serverNowMs(int deviceNowMs) => deviceNowMs + offsetMs;
  void reset() {
    _samples.clear();
    _offset = null;
  }
}

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
  String? _deviceName;
  final Future<String> Function()? _deviceNameProvider;
  final SyncDeviceType _deviceType;

  WebSocketChannel? _channel;
  String? _deviceId;
  String? _jwt;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _pongWatch;
  Timer? _stableTimer;
  Timer? _quickPings;

  /// Offset between this device's clock and the server's.
  final ClockEstimator clock = ClockEstimator();

  /// What the server says is true now, by this device's reckoning.
  int serverNowMs() => clock.serverNowMs(DateTime.now().millisecondsSinceEpoch);

  /// True once the server has shown it speaks protocol 3 (its states carry an epoch).
  bool _server3 = false;
  bool get serverSpeaksV3 => _server3;

  int? _seenEpoch;
  int? _seenVersion;

  final _prepareController = StreamController<PrepareTransfer>.broadcast();
  Stream<PrepareTransfer> get prepareStream => _prepareController.stream;

  /// Commands sent as `cmd` frames and not yet acknowledged: resent with the same
  /// id after a reconnect, so a dropped socket never loses or doubles an action.
  final Map<String, ({Map<String, dynamic> frame, DateTime at, String action})> _unacked = {};
  static const _retryWindow = Duration(seconds: 15);

  /// 0.5 s · 2^(attempt-1), capped at 30 s, with full jitter (never under 200 ms).
  static int reconnectDelayMs(int attempt, Random random) {
    final ceiling = min(0.5 * pow(2, attempt - 1), 30.0);
    return max(200, (ceiling * 1000 * random.nextDouble()).round());
  }

  int _failedConnects = 0;

  /// Bumped whenever the account or the connection is torn down, so a connect that
  /// was in flight can tell it is stale.
  int _generation = 0;
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
    Future<String> Function()? deviceNameProvider,
    SyncDeviceType deviceType = SyncDeviceType.unknown,
  })  : _deviceName = deviceName,
        _deviceNameProvider = deviceNameProvider,
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
      if (_deviceName == null && _deviceNameProvider != null) {
        try {
          _deviceName = await _deviceNameProvider();
        } catch (_) {}
      }

      if (_jwt == null || _jwt!.isEmpty) {
        debugPrint('[SessionSync] ⚠️ No JWT token available — cannot connect');
        _scheduleReconnect(isAuthFailure: true);
        return;
      }

      _setConnection(SyncConnection.connecting);
      final uri = Uri.parse(_wsBaseUrl).replace(queryParameters: {
        'token': _jwt!,
        'device_id': _deviceId!,
        if (_deviceName != null && _deviceName!.isNotEmpty) 'device_name': _deviceName!,
        if (_deviceType != SyncDeviceType.unknown) 'device_type': _deviceType.name,
        'proto': '3',
      });

      final generation = _generation;
      final channel = _channelFactory(uri);
      _channel = channel;
      await channel.ready;
      if (generation != _generation) {
        // The account changed (or we were told to disconnect) while this socket was opening:
        // it belongs to someone who is no longer signed in.
        try {
          unawaited(Future.sync(() => channel.sink.close()).catchError((_) {}));
        } catch (_) {}
        if (identical(_channel, channel)) _channel = null;
        return;
      }

      _stableTimer?.cancel();
      _stableTimer = Timer(const Duration(seconds: 30), () {
        _reconnectAttempt = 0;
        if (!_reconnectAttemptController.isClosed) _reconnectAttemptController.add(0);
      });
      _seenEpoch = null;
      _seenVersion = null;
      _failedConnects = 0;
      _setConnection(SyncConnection.online);
      debugPrint('[SessionSync] ✅ connected as ${_deviceName ?? 'device'} (${_deviceType.name}) id=${(_deviceId ?? '').length > 6 ? _deviceId!.substring(0, 6) : _deviceId}');
      _flushPending();
      _resendUnacked();
      _startPingTimer();

      // Each socket reports only for itself: a socket we already replaced must not
      // tear down its successor (that left an orphan connected under the old account).
      channel.stream.listen(
        (m) {
          if (identical(_channel, channel)) _onMessage(m);
        },
        onDone: () {
          if (identical(_channel, channel)) _onDisconnected(channel.closeCode);
        },
        onError: (e) {
          debugPrint('[SessionSync] ❌ WebSocket error: $e');
          if (identical(_channel, channel)) _onDisconnected(channel.closeCode);
        },
      );

      // 5. Initial REST resync on (re)connect
      try {
        final restState = await fetchCurrentState();
        // The socket already delivered a snapshot with an epoch and version: the REST copy can
        // only be older or equal, and replacing the newer one with it would lose the epoch.
        if (_seenVersion == null) _emitState(restState);
      } catch (e) {
        debugPrint('[SessionSync] ℹ️ REST initial sync note: $e');
        // WS initial push is the fallback if REST fails; don't block connect on it
      }
    } catch (e) {
      debugPrint('[SessionSync] ❌ Connection failed (${e.runtimeType}): $e');
      final is4001 =
          e.toString().contains('4001') || _channel?.closeCode == 4001;
      // A socket that never opened must not count as connected: connect()
      // refuses to start while a channel exists, so leaving it here would stop
      // every later retry.
      final broken = _channel;
      _channel = null;
      try {
        unawaited(Future.sync(() => broken?.sink.close()).catchError((_) {}));
      } catch (_) {}
      _pingTimer?.cancel();
      _setConnection(SyncConnection.offline);
      // A server that keeps refusing the upgrade usually means the credentials changed; ask the
      // supplier again instead of retrying a token that no longer works.
      if (++_failedConnects >= 2) _jwt = null;
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
          _pongWatch?.cancel();
          final t0 = (json['t0'] as num?)?.toInt();
          final serverT = (json['server_t'] as num?)?.toInt();
          if (t0 != null && serverT != null) {
            clock.add(t0, DateTime.now().millisecondsSinceEpoch, serverT);
          }
          return; // Heartbeat ack, no state change
        case 'ack':
          final id = json['cmdId']?.toString() ?? '';
          final entry = _unacked[id];
          final status = json['status']?.toString() ?? '';
          if (status != 'ok' || json['pending'] != true) _unacked.remove(id);
          if (!_resultController.isClosed && entry != null) {
            final good = status == 'ok' || status == 'duplicate';
            _resultController.add(CommandResult(ok: good, action: entry.action, reason: good ? null : (json['reason']?.toString() ?? status)));
          }
          return;
        case 'exec':
          if (json['action'] == 'prepare' && !_prepareController.isClosed) {
            _prepareController.add(PrepareTransfer.fromJson(json));
          }
          return;
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
      final incoming = PlaybackState.fromJson(body);
      if (incoming.epoch != null) {
        _server3 = true;
        // The server alone orders states. Within one connection an older one is dropped
        // (a delayed frame must never roll the picture back).
        final e = incoming.epoch!;
        final v = incoming.version ?? 0;
        if (_seenEpoch != null && (e < _seenEpoch! || (e == _seenEpoch! && v < (_seenVersion ?? 0)))) return;
        _seenEpoch = e;
        _seenVersion = v;
      }
      _emitState(incoming);
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
    _quickPings?.cancel();
    _ping();
    // A few quick pings at the start so the clock estimate settles; then every 25 s,
    // inside the ~100 s idle limit Cloudflare puts on a quiet socket.
    var quick = 0;
    _quickPings = Timer.periodic(const Duration(seconds: 2), (t) {
      if (++quick >= 3) t.cancel();
      _ping();
    });
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) => _ping());
  }

  void _ping() {
    if (_channel == null) return;
    _send({'type': 'ping', 't0': DateTime.now().millisecondsSinceEpoch});
    // The server answers every ping. No answer in 10 s means the socket is half-open
    // (the phone slept, the Wi-Fi changed): start over rather than wait for a close
    // that never comes.
    _pongWatch?.cancel();
    _pongWatch = Timer(const Duration(seconds: 10), () {
      debugPrint('[SessionSync] ⚠️ no pong within 10 s, reconnecting');
      final dead = _channel;
      try {
        unawaited(Future.sync(() => dead?.sink.close()).catchError((_) {}));
      } catch (_) {}
      _onDisconnected();
    });
  }

  // ---------------------------------------------------------------------------
  // 4. Disconnect Handling + Reconnect / Backoff
  // ---------------------------------------------------------------------------

  void _onDisconnected([int? closeCode]) {
    debugPrint('[SessionSync] ⚠️ disconnected (close code ${closeCode ?? 'none'})');
    _pingTimer?.cancel();
    _pongWatch?.cancel();
    _quickPings?.cancel();
    _stableTimer?.cancel();
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

    if (isAuthFailure && _reconnectAttempt < 3) {
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
    if (isAuthFailure) _jwt = null; // ask for the credentials again on the next try
    // 0.5 s · 2^n, capped at 30 s, with full jitter: a crowd of devices that lost the
    // server together does not come back together.
    final delay = Duration(milliseconds: reconnectDelayMs(_reconnectAttempt, _random));

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
  ///
  /// [force] says a person asked for it: without it the server ignores a claim
  /// that comes seconds after another device's (two devices fighting over the
  /// host seat).
  void transferPlayback(String deviceId, {String? deviceName, bool force = false}) {
    if (_server3) {
      // Compare-and-swap on the epoch we last saw: if someone moved playback first, the
      // server answers "stale" and we adopt its state instead of fighting it.
      _cmd('transfer', {'toDeviceId': deviceId, 'force': force, 'baseEpoch': ?_seenEpoch}, action: 'transfer');
      return;
    }
    _send({
      'type': 'transfer_playback',
      'device_id': deviceId,
      'device_name': ?deviceName,
      if (force) 'force': true,
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
    if (_server3) {
      _cmd(
        switch (action) { 'set_queue' => 'setQueue', 'play_track' => 'playTrack', _ => action },
        {
          'position_ms': ?positionMs,
          'volume': ?volume,
          'track_id': ?trackId,
          'index': ?index,
          'queue': ?queue,
          'target': ?target,
        },
        action: action,
      );
      return;
    }
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

  /// A protocol-3 command: carries an id, is acknowledged, and is resent after a
  /// reconnect (once, thanks to the id) if the answer never came.
  void _cmd(String type, Map<String, dynamic> args, {required String action}) {
    final id = generateUuid();
    final frame = {'type': 'cmd', 'cmdId': id, 'cmdType': type, 'args': args, if (_seenVersion != null) 'baseVersion': _seenVersion};
    _unacked[id] = (frame: frame, at: DateTime.now(), action: action);
    if (_channel == null && action != 'transfer') {
      _unacked.remove(id); // "now" commands are not "later" commands
      return;
    }
    _send(frame);
  }

  void _resendUnacked() {
    final now = DateTime.now();
    _unacked.removeWhere((_, e) => now.difference(e.at) > _retryWindow);
    for (final e in _unacked.values) {
      _send(e.frame);
    }
  }

  /// The prepared device says it has loaded the song; the server may hand it playback.
  void sendReady(String transferId) => _send({'type': 'ready', 'transfer_id': transferId});

  /// Asks for the device list (it is also pushed whenever it changes).
  void requestDevices() => _send({'type': 'get_devices'});

  /// Frames asked for while the socket was still opening (the first play after
  /// launch claims playback before the link is up). Kept briefly, newest wins
  /// per kind, and sent the moment the socket opens.
  final Map<String, Map<String, dynamic>> _pending = {};

  void _send(Map<String, dynamic> msg) {
    if (_channel == null) {
      final type = msg['type']?.toString() ?? '';
      if (type == 'ping' || _manuallyDisconnected) return;
      if (type == 'command') {
        // A command is for right now; if the link is down it is not "later".
        return;
      }
      _pending[type] = msg;
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(msg));
    } catch (e) {
      debugPrint('[SessionSync] ❌ Failed to send message: $e');
    }
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    // A transfer goes first so the updates that follow come from the active device.
    final order = [
      if (_pending.containsKey('transfer_playback')) 'transfer_playback',
      ..._pending.keys.where((k) => k != 'transfer_playback'),
    ];
    final frames = [for (final k in order) _pending[k]!];
    _pending.clear();
    for (final m in frames) {
      _send(m);
    }
  }

  // ---------------------------------------------------------------------------
  // 7. Manual Disconnect & Disposal
  // ---------------------------------------------------------------------------

  /// Manually disconnects the session (e.g. app exit, logout).
  void disconnect() {
    _pongWatch?.cancel();
    _quickPings?.cancel();
    _stableTimer?.cancel();
    _generation++;
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _setConnection(SyncConnection.offline);
  }

  /// Another account is signing in (or this one signed out): drop the socket, the
  /// cached token, everything the old account's devices told us, and anything
  /// queued for it. The next [connect] authenticates from scratch.
  void resetAccount() {
    disconnect();
    _jwt = null;
    _pending.clear();
    _unacked.clear();
    clock.reset();
    _server3 = false;
    _devices = const [];
    if (!_devicesController.isClosed) _devicesController.add(_devices);
    _emitState(const PlaybackState.initial());
    _isConnecting = false;
    _reconnectAttempt = 0;
  }

  /// Disposes stream controllers and cleanly tears down connections.
  void dispose() {
    disconnect();
    _stateController.close();
    _prepareController.close();
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
