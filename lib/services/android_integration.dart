import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils/platform_utils.dart';
import 'notification_pills.dart';
import 'open_intent.dart';

/// Android-only glue: home-screen widget state and the one-time
/// POST_NOTIFICATIONS prompt. Every call is best-effort — a missing platform
/// channel or a denied permission must never affect playback.
class AndroidIntegration {
  AndroidIntegration._();

  static const _channel = MethodChannel('com.navivibe/android');
  static var _askedThisRun = false;

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
      if (call.method == 'downloadStopRequested') onDownloadStopRequested?.call();
      if (call.method == 'audioRouteChanged') onAudioRouteChanged?.call();
    });
    unawaited(() async {
      try {
        await handle(await _channel.invokeMethod<Object?>('getInitialIntent'));
      } catch (e) {
        debugPrint('[AndroidIntegration] getInitialIntent failed: $e');
      }
    }());
  }

  static Future<void> _requestNotificationsOnce() => requestNotificationPermission();

  /// Asks for the notification permission at most once per app run, until it
  /// is granted. A prompt that never appeared (the app was in the background)
  /// or was dismissed gets another chance on the next launch; a remembered
  /// "already asked" would lose the now-playing notification for good. Android
  /// itself stops showing the prompt after two denials, so this cannot nag, and
  /// Settings links to the system page ([openNotificationSettings]).
  static Future<void> requestNotificationPermission() async {
    if (!PlatformUtils.isAndroid || _askedThisRun) return;
    _askedThisRun = true;
    await _invoke('requestNotificationPermission');
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

  /// The "Stop" button on the ongoing download notification was pressed.
  static void Function()? onDownloadStopRequested;

  /// The set of connected outputs changed (headphones, Bluetooth, car).
  static void Function()? onAudioRouteChanged;

  /// Starts or updates the foreground service that keeps downloads running in
  /// the background. False when Android refused (the app can't start one from
  /// the background) or off Android.
  static Future<bool> startDownloadService({
    required String title,
    required String text,
    required int done,
    required int total,
    bool live = true,
  }) async {
    if (!PlatformUtils.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('startDownloadService', {
            'title': title,
            'text': text,
            'done': done,
            'total': total,
            'live': live,
          }) ??
          false;
    } catch (e) {
      debugPrint('[AndroidIntegration] startDownloadService failed: $e');
      return false;
    }
  }

  static Future<void> stopDownloadService() async {
    if (!PlatformUtils.isAndroid) return;
    await _invoke('stopDownloadService');
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

  /// Connected audio outputs, raw (see `outputRoute`). Empty off Android.
  static Future<List<AudioDevice>> audioOutputs() async {
    if (!PlatformUtils.isAndroid) return const [];
    try {
      return AudioDevice.parseList(await _channel.invokeMethod<Object?>('audioOutputs'));
    } catch (_) {
      return const [];
    }
  }

  /// Posts or updates an ongoing progress notification (a Live Update on
  /// Android 16+). [id] picks the slot; [whenMs] with [countDown] draws a
  /// system countdown; [timeoutMs] removes it if the app dies. False when blocked.
  static Future<bool> livePost({
    required int id,
    required String title,
    required String text,
    int value = 0,
    int max = 0,
    bool indeterminate = false,
    String? chip,
    int whenMs = 0,
    bool countDown = false,
    int timeoutMs = 0,
  }) async {
    if (!PlatformUtils.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('livePost', {
            'id': id,
            'title': title,
            'text': text,
            'value': value,
            'max': max,
            'indeterminate': indeterminate,
            'chip': chip,
            'whenMs': whenMs,
            'countDown': countDown,
            'timeoutMs': timeoutMs,
          }) ??
          false;
    } catch (e) {
      debugPrint('[AndroidIntegration] livePost failed: $e');
      return false;
    }
  }

  static Future<void> liveEnd(int id) async {
    if (!PlatformUtils.isAndroid) return;
    await _invoke('liveEnd', {'id': id});
  }

  /// A finished notice whose tap plays [ids] (comma separated song ids).
  static Future<bool> notifyPlayable({required int id, required String title, required String text, required String ids}) async {
    if (!PlatformUtils.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('notifyPlayable', {'id': id, 'title': title, 'text': text, 'ids': ids}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('[AndroidIntegration] $method failed: $e');
    }
  }
}
