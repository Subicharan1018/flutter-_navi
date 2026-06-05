import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/song.dart';
import '../providers/settings_provider.dart'; // subsonicServiceProvider + settingsProvider

// =============================================================================
// ListeningLogService
//
// Posts a slim JSON payload to POST <webdav_base_url>/listening-log whenever a
// song is played past the scrobble threshold. Reuses the WebDAV http.Client
// and Basic-auth credentials already configured in SubsonicService — no new
// HTTP client is created.
//
// Failed POSTs are stored in SharedPreferences under 'listening_log_queue' and
// retried on next app foreground (via ListeningLogService.flushQueue()).
// =============================================================================

const _kQueueKey = 'listening_log_queue';
const _kMaxQueueSize = 500;
const _kMaxRetries = 3;

/// Wraps a queued entry with its retry count.
/// Format: "<retries>|<json_payload>"
class _QueueEntry {
  final int retries;
  final String payload;

  _QueueEntry(this.retries, this.payload);

  factory _QueueEntry.fromString(String raw) {
    final sep = raw.indexOf('|');
    if (sep < 0) return _QueueEntry(0, raw);
    final retries = int.tryParse(raw.substring(0, sep)) ?? 0;
    return _QueueEntry(retries, raw.substring(sep + 1));
  }

  String serialize() => '$retries|$payload';

  _QueueEntry withIncrementedRetries() => _QueueEntry(retries + 1, payload);
}

enum _PostResult { ok, authError, networkError }

class ListeningLogService {
  final http.Client _client;
  final String? _baseUrl;
  final String? _webdavUser;
  final String? _webdavPass;
  final String _logPath;

  String _sessionId = const Uuid().v4();
  DateTime _lastPlayTime = DateTime.now();

  ListeningLogService({
    required http.Client client,
    String? baseUrl,
    String? webdavUser,
    String? webdavPass,
    String logPath = '/feedback',
  }) : _client = client,
       _baseUrl = baseUrl,
       _webdavUser = webdavUser,
       _webdavPass = webdavPass,
       _logPath = logPath;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Posts a listening log entry to the FastAPI server.
  ///
  /// Call this fire-and-forget (via [unawaited]) from the scrobble path.
  /// If [_baseUrl] is not configured the call is a silent no-op.
  /// On network failure the payload is persisted to the retry queue.
  ///
  /// Posts a listening log entry to the FastAPI server.
  ///
  /// Call this fire-and-forget (via [unawaited]) from the scrobble path.
  /// If [_baseUrl] is not configured the call is a silent no-op.
  /// On network failure the payload is persisted to the retry queue.
  /// Auth failures (401) are logged but NOT queued — they indicate wrong creds.
  Future<void> logPlay({required Song song}) async {
    if (_baseUrl == null || _baseUrl.isEmpty) {
      debugPrint('[ListeningLog] ⏭ No server URL configured — skipping');
      return;
    }

    final now = DateTime.now().toUtc();
    final gap = now.difference(_lastPlayTime);
    if (gap.inMinutes >= 30) {
      _sessionId = const Uuid().v4();
    }
    _lastPlayTime = now;

    final payload = _buildPayload(
      song: song,
      now: now,
      sessionId: _sessionId,
    );

    final result = await _post(payload);
    if (result == _PostResult.networkError) {
      await _queueFailedLog(payload);
    }
    // Auth failures (401) are not queued — they will never succeed with the
    // same credentials. They surface as a debugPrint warning instead.
  }

  /// Retries all queued payloads. Call this on app foreground.
  ///
  /// Each entry is retried up to [_kMaxRetries] times. Successfully posted
  /// entries are removed from the queue. Entries that have exhausted their
  /// retries are also removed (dropped silently).
  Future<void> flushQueue() async {
    if (_baseUrl == null || _baseUrl.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kQueueKey) ?? [];
    if (raw.isEmpty) return;

    debugPrint('[ListeningLog] 🔄 Flushing ${raw.length} queued entries');

    final remaining = <String>[];
    for (final rawEntry in raw) {
      final entry = _QueueEntry.fromString(rawEntry);
      if (entry.retries >= _kMaxRetries) {
        debugPrint(
          '[ListeningLog] 🗑 Dropping entry after $_kMaxRetries retries',
        );
        continue; // drop exhausted entry
      }

      final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
      final result = await _post(payload);
      if (result == _PostResult.ok) {
        debugPrint('[ListeningLog] ✅ Flushed queued entry');
        // don't add to remaining — it's done
      } else if (result == _PostResult.authError) {
        debugPrint('[ListeningLog] ⚠️ Dropping queued entry — auth failed (401)');
        // Drop auth failures: they'll never succeed with the same credentials.
      } else {
        remaining.add(entry.withIncrementedRetries().serialize());
      }
    }

    await prefs.setStringList(_kQueueKey, remaining);
    debugPrint(
      '[ListeningLog] Queue after flush: ${remaining.length} remaining',
    );
  }

  // ---------------------------------------------------------------------------
  // Payload builder
  // ---------------------------------------------------------------------------

  /// Builds the JSON payload for POST /listening-log.
  ///
  /// Schema matches the FastAPI server contract:
  /// - title, artist (required)
  /// - album, duration_s, source, song_id, album_id, artist_id, cover_art,
  ///   played_at (optional)
  ///
  /// Keys removed vs. old schema: duration_ms, played_ms, week, month, device_id.
  Map<String, dynamic> _buildPayload({
    required Song song,
    required DateTime now,
    required String sessionId,
  }) {
    // Matches POST /feedback schema (api_refernce.md).
    // Only fields the server actually uses are sent.
    return {
      'title': song.title,
      'composer': song.composer.isNotEmpty ? song.composer : song.artist,
      'listen_ratio': 1.0,
      'end_reason': 'natural',
      'session_id': sessionId,
      'session_depth': 1,
    };
  }

  // ISO week helpers removed — no longer needed after payload schema update.

  // ---------------------------------------------------------------------------
  // HTTP POST
  // ---------------------------------------------------------------------------

  Future<_PostResult> _post(Map<String, dynamic> payload) async {
    try {
      final uri = Uri.parse(
        '${_baseUrl!.replaceAll(RegExp(r'/+$'), '')}$_logPath',
      );

      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      };

      if (_webdavUser != null &&
          _webdavUser.isNotEmpty &&
          _webdavPass != null &&
          _webdavPass.isNotEmpty) {
        final auth = base64Encode(utf8.encode('$_webdavUser:$_webdavPass'));
        headers['Authorization'] = 'Basic $auth';
      }

      final response = await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));

      debugPrint('[ListeningLog] POST $uri → ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _PostResult.ok;
      }
      if (response.statusCode == 401) {
        debugPrint('[ListeningLog] ⚠️ 401 — check Navidrome credentials in Settings');
        return _PostResult.authError;
      }
      return _PostResult.networkError;
    } catch (e) {
      debugPrint('[ListeningLog] ❌ POST failed: $e');
      return _PostResult.networkError;
    }
  }

  // ---------------------------------------------------------------------------
  // Retry queue
  // ---------------------------------------------------------------------------

  Future<void> _queueFailedLog(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var queue = prefs.getStringList(_kQueueKey) ?? [];

      final entry = _QueueEntry(0, jsonEncode(payload));

      // Enforce max queue size: drop oldest entries first.
      if (queue.length >= _kMaxQueueSize) {
        final excess = queue.length - _kMaxQueueSize + 1;
        queue = queue.sublist(excess);
        debugPrint(
          '[ListeningLog] ⚠ Queue full — dropped $excess oldest entries',
        );
      }

      queue.add(entry.serialize());
      await prefs.setStringList(_kQueueKey, queue);
      debugPrint(
        '[ListeningLog] 📦 Queued failed log (queue size: ${queue.length})',
      );
    } catch (e) {
      debugPrint('[ListeningLog] ❌ Failed to queue log: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final listeningLogServiceProvider = Provider<ListeningLogService>((ref) {
  final settings = ref.watch(settingsProvider);
  final subsonic = ref.watch(subsonicServiceProvider);

  return ListeningLogService(
    client: subsonic.client,
    baseUrl: settings.loggingApiUrl.isEmpty ? null : settings.loggingApiUrl,
    // The shuffle server uses Navidrome Basic Auth (username:password),
    // NOT the WebDAV credentials. Use the primary Navidrome creds here.
    webdavUser: settings.username.isEmpty ? null : settings.username,
    webdavPass: settings.password.isEmpty ? null : settings.password,
  );
});
