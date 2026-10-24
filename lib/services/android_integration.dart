import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/hive_boxes.dart';
import '../utils/platform_utils.dart';

/// Android-only glue: home-screen widget state and the one-time
/// POST_NOTIFICATIONS prompt. Every call is best-effort — a missing platform
/// channel or a denied permission must never affect playback.
class AndroidIntegration {
  AndroidIntegration._();

  static const _channel = MethodChannel('com.navivibe/android');
  static const _kAskedNotifications = 'notification_permission_asked';

  /// Pure: what the widget shows for the given state.
  @visibleForTesting
  static Map<String, Object> widgetPayload(MediaItem? item, bool playing) => {
    'title': item?.title ?? 'NaviVibe',
    'artist': item?.artist ?? 'Nothing playing',
    'playing': playing,
  };

  static void init(AudioHandler handler) {
    if (!PlatformUtils.isAndroid) return;
    MediaItem? item;
    var playing = false;
    var askedThisRun = false;
    String? lastKey;

    void push() {
      final payload = widgetPayload(item, playing);
      final key = '${payload['title']}|${payload['artist']}|$playing';
      if (key == lastKey) return;
      lastKey = key;
      _invoke('updateWidget', payload);
    }

    handler.mediaItem.listen((m) {
      item = m;
      push();
    });
    handler.playbackState.listen((s) {
      playing = s.playing;
      push();
      if (playing && !askedThisRun) {
        askedThisRun = true;
        unawaited(_requestNotificationsOnce());
      }
    });
  }

  /// Asks once, on the first play, so the prompt arrives with a reason.
  /// If denied, playback continues; only the media notification is hidden.
  static Future<void> _requestNotificationsOnce() async {
    try {
      if (HiveBoxes.prefs.get(_kAskedNotifications) == true) return;
      await HiveBoxes.prefs.put(_kAskedNotifications, true);
      await _invoke('requestNotificationPermission');
    } catch (_) {}
  }

  static Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('[AndroidIntegration] $method failed: $e');
    }
  }
}
