// =============================================================================
// session_sync_provider.dart — Riverpod providers for SessionSyncService
//
// Exposes the singleton SessionSyncService and its reactive streams to the app.
// Note: Intentionally non-autoDispose so socket connectivity persists across
// screen navigation (e.g. NowPlaying, Library, Settings).
// =============================================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_sync_service.dart';
import 'settings_provider.dart';

/// Central singleton provider for SessionSyncService.
///
/// Reads credentials from settingsProvider on demand and automatically disposes
/// when the ProviderContainer is destroyed.
final sessionSyncServiceProvider = Provider<SessionSyncService>((ref) {
  final service = SessionSyncService(
    jwtSupplier: ({bool forceRefresh = false}) {
      final settings = ref.read(settingsProvider);
      if (settings.username.isNotEmpty && settings.password.isNotEmpty) {
        return base64Encode(
          utf8.encode('${settings.username}:${settings.password}'),
        );
      }
      return null;
    },
  );

  ref.onDispose(service.dispose);
  return service;
});

/// Stream provider for real-time playback state updates from the session server.
final sessionPlaybackStateProvider = StreamProvider<PlaybackState>((ref) {
  final service = ref.watch(sessionSyncServiceProvider);
  return service.stateStream;
});

/// Stream provider tracking WebSocket reconnection attempt counts.
final sessionReconnectAttemptProvider = StreamProvider<int>((ref) {
  final service = ref.watch(sessionSyncServiceProvider);
  return service.reconnectAttemptStream;
});
