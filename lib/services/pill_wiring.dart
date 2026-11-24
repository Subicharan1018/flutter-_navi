import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/online_fetch/logic/online_fetch_providers.dart';
import '../features/social/logic/jam_controller.dart';
import '../player/sleep_timer.dart';
import '../utils/platform_utils.dart';
import 'android_integration.dart';
import 'app_notifier.dart';
import 'navi_audio_handler.dart';
import 'notification_pills.dart';
import 'output_route.dart';
import 'pill_prefs.dart';

// Notification ids: 9 is the download service, 10–12 finished downloads.
const _fetchSlot = 20;
const _sleepSlot = 21;
const _jamSlot = 22;
const _fetchedSlot = 30;
const weeklyReadySlot = 31;

/// Re-reads the Settings switches (call after changing one).
VoidCallback applyPillPrefs = () {};

/// One ongoing notification: posted only while the app is hidden (on screen
/// it would repeat what the person sees), throttled, and removed as soon as
/// the work it shows is over.
class _LiveSlot {
  _LiveSlot(this.id, Duration gap) : _gate = UpdateGate(gap);

  final int id;
  final UpdateGate _gate;
  bool _shown = false;

  void show({
    required String key,
    required String title,
    required String text,
    LiveProgress? progress,
    String? chip,
    int whenMs = 0,
    bool countDown = false,
    int timeoutMs = 0,
  }) {
    if (!_gate.allow(key)) return;
    _shown = true;
    final p = progress;
    unawaited(AndroidIntegration.livePost(
      id: id,
      title: title,
      text: text,
      value: p?.value ?? 0,
      max: p?.max ?? 0,
      indeterminate: p?.indeterminate ?? false,
      chip: chip ?? p?.chip,
      whenMs: whenMs,
      countDown: countDown,
      timeoutMs: timeoutMs,
    ));
  }

  void end() {
    if (!_shown) return;
    _shown = false;
    _gate.reset();
    unawaited(AndroidIntegration.liveEnd(id));
  }
}

bool _wanted(Pill pill) => pill.on && AppNotifier.enabledPref && !AppNotifier.inForeground();

/// Connects the output device line, the media notification's buttons, the
/// Live Updates (fetches, sleep timer, Jam) and the finished-fetch notice to
/// the providers that know about them. Android only.
void wireNotificationPills(ProviderContainer container, NaviAudioHandler handler) {
  if (!PlatformUtils.isAndroid) return;

  void applyOutput() {
    final r = container.read(outputRouteProvider);
    handler.setSubtext(Pill.output.on ? routeSubtext(r) : '');
  }

  container.listen(outputRouteProvider, (_, _) => applyOutput(), fireImmediately: true);

  final fetch = _LiveSlot(_fetchSlot, const Duration(seconds: 3));
  final sleep = _LiveSlot(_sleepSlot, const Duration(seconds: 1));
  final jam = _LiveSlot(_jamSlot, const Duration(seconds: 5));

  void syncFetch() {
    final d = container.read(fetchJobsProvider);
    if (!d.isActive || !_wanted(Pill.fetches)) return fetch.end();
    final n = d.activeCount;
    final p = fractionProgress(d.progress);
    fetch.show(
      key: '${p.value}/$n',
      title: n == 1 ? 'Fetching a song' : 'Fetching songs',
      text: n == 1 ? 'Adding it to your library' : '$n on their way to your library',
      progress: p,
      timeoutMs: const Duration(hours: 1).inMilliseconds,
    );
  }

  void syncSleep() {
    final s = container.read(sleepTimerProvider);
    if (!s.active || !_wanted(Pill.sleep)) return sleep.end();
    final ends = s.endsAt;
    if (ends == null) {
      return sleep.show(key: 'song', title: 'Sleep timer', text: 'Music stops after this song', chip: 'Sleep');
    }
    final left = ends.difference(DateTime.now());
    sleep.show(
      key: 'at${ends.millisecondsSinceEpoch}',
      title: 'Sleep timer',
      text: 'Music stops when it reaches zero',
      whenMs: ends.millisecondsSinceEpoch,
      countDown: true,
      timeoutMs: left.inMilliseconds + 2000,
    );
  }

  void syncJam() {
    final j = container.read(jamControllerProvider).jam;
    if (j == null || !_wanted(Pill.jam)) return jam.end();
    jam.show(
      key: '${j.code}${j.members.length}',
      title: 'In a Jam',
      text: jamLine(code: j.code, people: j.members.length),
      chip: j.code,
      timeoutMs: const Duration(hours: 3).inMilliseconds,
    );
  }

  void syncAll() {
    syncFetch();
    syncSleep();
    syncJam();
  }

  container.listen(fetchJobsProvider.select((d) => (d.activeCount, d.progress?.toStringAsFixed(2))), (_, _) => syncFetch());
  container.listen(sleepTimerProvider, (_, _) => syncSleep());
  container.listen(jamControllerProvider.select((s) => (s.jam?.code, s.jam?.members.length)), (_, _) => syncJam());
  // Hidden → post what is running; back on screen → take it down.
  AppLifecycleListener(onStateChange: (_) => syncAll());

  container.listen(fetchFinishedProvider, (_, f) {
    if (f == null || f.songIds.isEmpty || !_wanted(Pill.fetched)) return;
    // Single songs read "Title — Artist"; a group's detail starts with its name.
    final dash = f.detail.indexOf(' — ');
    final name = dash > 0 ? f.detail.substring(0, dash) : f.detail.split(' · ').first;
    final artist = dash > 0 ? f.detail.substring(dash + 3) : '';
    final n = fetchedNotice(f.songIds, name.isEmpty ? 'Your download' : name, artist);
    if (n == null) return;
    unawaited(AndroidIntegration.notifyPlayable(id: _fetchedSlot, title: n.title, text: n.body, ids: joinPlayIds(n.playIds)));
  });

  applyPillPrefs = () {
    handler.buttonPreset = buttonPreset;
    handler.refreshControls();
    applyOutput();
    syncAll();
    if (Pill.output.on) unawaited(container.read(outputRouteProvider.notifier).refresh());
  };
  applyPillPrefs();
}

/// "Weekly Exploration is ready", once the list that was being made is done.
Future<void> announceWeeklyReady(int songs) async {
  if (!Pill.weekly.on || songs <= 0) return;
  await AppNotifier.show(
    NotifyChannel.updates,
    id: weeklyReadySlot,
    title: 'Weekly Exploration is ready',
    body: songs == 1 ? 'One new song to try.' : '$songs new songs to try.',
  );
}
