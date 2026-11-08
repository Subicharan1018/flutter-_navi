import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../providers/download_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../models/download_state.dart';
import '../../../services/session_sync_service.dart';
import '../../../providers/session_sync_provider.dart';
import '../../ai_shuffle/logic/shuffle_providers.dart' show shuffleApiServiceProvider;
import '../../online_fetch/data/fetch_queue_models.dart';
import '../../online_fetch/data/online_fetch_api.dart';
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../../social/data/social_models.dart' show SocialSettings;
import '../../social/logic/social_providers.dart';
import 'download_speed.dart';
import 'status_model.dart';

/// Row ids, in the order the screen lists them.
class StatusIds {
  static const navidrome = 'navidrome';
  static const shuffle = 'shuffle';
  static const sync = 'sync';
  static const social = 'social';
  static const fetcher = 'fetcher';
  static const library = 'library';
  static const downloads = 'downloads';
  static const offline = 'offline';

  static const titles = <String, String>{
    navidrome: 'Navidrome',
    shuffle: 'Smart Shuffle server',
    sync: 'Session sync',
    social: 'Social & Jam',
    fetcher: 'Online fetch',
    library: 'Library sync',
    downloads: 'Downloads',
    offline: 'Offline mode',
  };
}

typedef Probe = Future<ProbeResult> Function();

/// "1.4.0 (23)": version and build.
final statusAppVersionProvider = FutureProvider.autoDispose<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

final statusClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// One probe per row. Each is short-timeout and runs only when asked (screen
/// open, refresh, Retry). Tests override this whole map.
final statusProbesProvider = Provider<Map<String, Probe>>((ref) {
  bool signedIn() {
    final s = ref.read(settingsProvider);
    return s.serverUrl.isNotEmpty && s.username.isNotEmpty && s.password.isNotEmpty;
  }

  const signInFirst = ProbeResult.off('Sign in first');

  return {
    StatusIds.navidrome: () async {
      if (!signedIn()) return signInFirst;
      final host = hostOf(ref.read(settingsProvider).serverUrl);
      return timedProbe(() => ref.read(subsonicServiceProvider).verifyCredentials(), describe: (_) => host);
    },
    StatusIds.shuffle: () async {
      if (!signedIn()) return signInFirst;
      return timedProbe(
        () => ref.read(shuffleApiServiceProvider).getHealth(),
        describe: (_) => 'port 5500',
      );
    },
    StatusIds.sync: () async {
      if (!signedIn()) return signInFirst;
      final live = ref.exists(sessionSyncServiceProvider)
          ? ref.read(sessionSyncServiceProvider).connection
          : null;
      return timedProbe(() async {
        final r = await http.get(Uri.parse('${SessionSyncService.defaultHttpBaseUrl}/health'));
        if (r.statusCode != 200) throw ProbeFailure('Server error (${r.statusCode})');
        return null;
      }, describe: (_) => 'port 5501${live == null ? '' : ' · live link ${live.name}'}');
    },
    StatusIds.social: () async {
      if (!signedIn()) return signInFirst;
      return timedProbe(
        () => ref.read(socialApiProvider).settings(),
        describe: (s) => (s as SocialSettings).enabled ? 'Turned on' : 'Turned off in Settings',
      );
    },
    StatusIds.fetcher: () async {
      if (!ref.read(onlineFetchAvailableProvider)) return const ProbeResult.off('Not in this build');
      if (!signedIn()) return signInFirst;
      return timedProbe(() async {
        try {
          return await ref.read(onlineFetchApiProvider).queue();
        } on OnlineFetchException catch (e) {
          throw ProbeFailure(e.message);
        }
      }, describe: (q) {
        final items = (q as FetchQueue).items;
        int n(QueueStatus s) => items.where((i) => i.status == s).length;
        return queueSummary(queued: n(QueueStatus.queued), running: n(QueueStatus.running), failed: n(QueueStatus.failed));
      });
    },
    StatusIds.library: () async {
      final sync = ref.read(librarySyncProvider);
      final at = librarySyncedAt();
      final now = ref.read(statusClockProvider)();
      int count = 0;
      try {
        final row = await ref.read(appDatabaseProvider).customSelect('SELECT COUNT(*) AS c FROM song_metadata').getSingle();
        count = row.read<int>('c');
      } catch (_) {}
      return describeLibrary(syncing: sync.syncing, synced: sync.synced, error: sync.error, lastSyncAt: at, songCount: count, now: now);
    },
    StatusIds.downloads: () async => describeDownloads(
          ref.read(downloadStateProvider).values.toList(),
          DownloadSpeedMeter.instance.bytesPerSecond(),
          bytesOnDisk: await _diskBytes(ref),
        ),
    StatusIds.offline: () async => describeOffline(
          networkOffline: ref.read(isOfflineProvider),
          offlineMode: ref.read(offlineServiceProvider).isOfflineMode,
        ),
  };
});

Future<int?> _diskBytes(Ref ref) async {
  try {
    return await ref.read(offlineServiceProvider).getDownloadedSize();
  } catch (_) {
    return null;
  }
}

/// Library sync row from its parts (pure, so it can be tested).
ProbeResult describeLibrary({
  required bool syncing,
  required int synced,
  required Object? error,
  required DateTime? lastSyncAt,
  required int songCount,
  required DateTime now,
}) {
  final size = '$songCount songs';
  if (syncing) return ProbeResult(HealthLevel.ok, 'Syncing · $synced fetched · $size');
  if (error != null) {
    return ProbeResult(HealthLevel.down, 'Last run failed: ${describeProbeError(error)} · $size');
  }
  if (lastSyncAt == null) return ProbeResult(HealthLevel.slow, 'Not synced yet · $size');
  return ProbeResult(HealthLevel.ok, 'Last run ${formatAgo(lastSyncAt, now)} · $size');
}

/// Download queue row (pure).
ProbeResult describeDownloads(List<SongDownloadState> all, double bytesPerSecond, {int? bytesOnDisk}) {
  final queued = all.where((d) => d.status == SongDownloadStatus.queued).length;
  final running = all.where((d) => d.status == SongDownloadStatus.downloading).length;
  final failed = all.where((d) => d.status == SongDownloadStatus.failed).toList();
  final parts = [
    queueSummary(queued: queued, running: running, failed: failed.length),
    if (running > 0) formatSpeed(bytesPerSecond) else 'idle',
    if (bytesOnDisk != null) '${formatBytes(bytesOnDisk)} on device',
  ];
  var detail = parts.join(' · ');
  if (failed.isNotEmpty) {
    final why = failed.map((f) => f.errorMessage).whereType<String>().toSet().take(2).join('; ');
    if (why.isNotEmpty) detail += '\nFailed: $why';
  }
  return ProbeResult(failed.isEmpty ? HealthLevel.ok : HealthLevel.slow, detail);
}

/// Offline row (pure).
ProbeResult describeOffline({required bool networkOffline, required bool offlineMode}) {
  if (networkOffline) return const ProbeResult(HealthLevel.down, 'No network connection');
  if (offlineMode) return const ProbeResult(HealthLevel.slow, 'Offline mode is on — playing downloads only');
  return const ProbeResult(HealthLevel.ok, 'Online');
}

/// The status screen's rows. Runs every probe at once on creation and on
/// [refreshAll]; [retry] runs one. No timers: nothing polls in the background.
class StatusController extends Notifier<List<HealthRow>> {
  @override
  List<HealthRow> build() {
    final rows = [
      for (final id in StatusIds.titles.keys) HealthRow(id: id, title: StatusIds.titles[id]!),
    ];
    scheduleMicrotask(refreshAll);
    return rows;
  }

  Future<void> refreshAll() async {
    final ids = ref.read(statusProbesProvider).keys.toList();
    await Future.wait([for (final id in ids) retry(id, repair: false)]);
  }

  /// Runs one row's probe. A manual retry of the library row also restarts
  /// the sync (unless one is running) before reporting on it.
  Future<void> retry(String id, {bool repair = true}) async {
    final probe = ref.read(statusProbesProvider)[id];
    if (probe == null) return;
    _put(id, (r) => r.checking());
    if (repair && id == StatusIds.library && !ref.read(librarySyncProvider).syncing) {
      try {
        ref.invalidate(allSongsProvider);
        await ref.read(allSongsProvider.future).timeout(const Duration(seconds: 60));
      } catch (_) {}
    }
    ProbeResult result;
    try {
      result = await probe();
    } catch (e) {
      result = ProbeResult(HealthLevel.down, describeProbeError(e));
    }
    if (!ref.mounted) return;
    final at = ref.read(statusClockProvider)();
    _put(id, (r) => r.withResult(result, at));
  }

  void _put(String id, HealthRow Function(HealthRow) f) {
    state = [for (final r in state) r.id == id ? f(r) : r];
  }
}

final statusControllerProvider =
    NotifierProvider.autoDispose<StatusController, List<HealthRow>>(StatusController.new);

/// Platform name for the report.
String statusPlatform() {
  if (kIsWeb) return 'web';
  return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
}
