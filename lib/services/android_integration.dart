import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/hive_boxes.dart';
import '../utils/platform_utils.dart';
import 'open_intent.dart';

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

  /// Opened as a music player: a voice request ("play X on NaviVibe") or an
  /// audio file ("Open with"). Covers the intent that launched the app (read
  /// once) and any that arrive while it runs.
  static void listenForOpenIntents(Future<void> Function(OpenIntent) onIntent) {
    if (!PlatformUtils.isAndroid) return;
    Future<void> handle(Object? raw) async {
      final intent = OpenIntent.parse(raw);
      if (intent == null) return;
      try {
        await onIntent(intent);
      } catch (e) {
        debugPrint('[AndroidIntegration] open intent failed: $e');
      }
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onIntent') await handle(call.arguments);
    });
    unawaited(() async {
      try {
        await handle(await _channel.invokeMethod<Object?>('getInitialIntent'));
      } catch (e) {
        debugPrint('[AndroidIntegration] getInitialIntent failed: $e');
      }
    }());
  }

  /// Asks for the notification permission once, ever. Android 13+ shows the
  /// system prompt; after two denials it never shows again, which is why
  /// Settings links to the system page ([openNotificationSettings]).
  static Future<void> _requestNotificationsOnce() => requestNotificationPermission();

  static Future<void> requestNotificationPermission() async {
    if (!PlatformUtils.isAndroid) return;
    try {
      if (HiveBoxes.prefs.get(_kAskedNotifications) == true) return;
      await HiveBoxes.prefs.put(_kAskedNotifications, true);
      await _invoke('requestNotificationPermission');
    } catch (_) {}
  }

  /// Posts a notification; false when blocked (denied permission or channel off).
  static Future<bool> notify({
    required String channel,
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('notify', {
            'channel': channel,
            'id': id,
            'title': title,
            'body': body,
          }) ??
          false;
    } catch (e) {
      debugPrint('[AndroidIntegration] notify failed: $e');
      return false;
    }
  }

  /// Whether the system lets the app post notifications at all.
  static Future<bool> notificationsEnabled() async {
    if (!PlatformUtils.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openNotificationSettings() => _invoke('openNotificationSettings');

  static Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('[AndroidIntegration] $method failed: $e');
    }
  }
}
