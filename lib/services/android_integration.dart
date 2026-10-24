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

  /// Pure: what the widgets show for the given state. [active] is false when
  /// nothing is loaded (cold start / stopped), so the widget's play button
  /// opens the app instead of poking a service with nothing to play.
  @visibleForTesting
  static Map<String, Object> widgetPayload(
    MediaItem? item,
    bool playing, {
    bool active = true,
  }) => {
    'title': item?.title ?? 'NaviVibe',
    'artist': item?.artist ?? 'Nothing playing',
    'playing': playing,
    'active': item != null && active,
    // The original artwork URL / file; the car-facing artUri is a content:// proxy.
    'art': (item?.extras?['artSrc'] as String?) ?? item?.artUri?.toString() ?? '',
  };

  static void init(AudioHandler handler) {
    if (!PlatformUtils.isAndroid) return;
    MediaItem? item;
    var playing = false;
    var active = false;
    var askedThisRun = false;
    String? lastKey;

    // Pushed only when something the widget shows actually changed, so an
    // idle playing app costs the widgets nothing (position ticks are ignored).
    void push() {
      final payload = widgetPayload(item, playing, active: active);
      final key = payload.values.join('|');
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
      active = s.processingState != AudioProcessingState.idle;
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
