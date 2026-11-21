import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, ComparableExpr;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import '../../../core/hive_boxes.dart';
import '../../../models/download_state.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/platform_utils.dart';
import '../../local_library/logic/download_location.dart' show freeSpaceBytes;
import '../../local_library/logic/local_models.dart' show isLocalSongId;
import 'auto_download_policy.dart';
import 'auto_download_service.dart';

const _kEnabled = 'auto_download_enabled';
const _kWifiOnly = 'auto_download_wifi_only';
const _kChargingOnly = 'auto_download_charging_only';
const _kBudgetMb = 'auto_download_budget_mb';
const _kLedger = 'auto_download_ledger_v1';

/// Settings > Downloads & Storage > Auto Downloads. Off until the listener
/// turns it on: it uses storage and data.
class AutoDownloadSettingsNotifier extends Notifier<AutoDownloadSettings> {
  @override
  AutoDownloadSettings build() {
    try {
      final p = HiveBoxes.prefs;
      return AutoDownloadSettings(
        enabled: p.get(_kEnabled, defaultValue: false) == true,
        wifiOnly: p.get(_kWifiOnly, defaultValue: true) != false,
        chargingOnly: p.get(_kChargingOnly, defaultValue: true) != false,
        budgetMb: (p.get(_kBudgetMb, defaultValue: kAutoDefaultBudgetMb) as num).toInt(),
      );
    } catch (_) {
      return const AutoDownloadSettings();
    }
  }

  void _save(AutoDownloadSettings s) {
    state = s;
    try {
      HiveBoxes.prefs
        ..put(_kEnabled, s.enabled)
        ..put(_kWifiOnly, s.wifiOnly)
        ..put(_kChargingOnly, s.chargingOnly)
        ..put(_kBudgetMb, s.budgetMb);
    } catch (_) {}
  }

  void setEnabled(bool v) => _save(state.copyWith(enabled: v));
  void setWifiOnly(bool v) => _save(state.copyWith(wifiOnly: v));
  void setChargingOnly(bool v) => _save(state.copyWith(chargingOnly: v));
  void setBudgetMb(int v) => _save(state.copyWith(budgetMb: v));
}

final autoDownloadSettingsProvider =
    NotifierProvider<AutoDownloadSettingsNotifier, AutoDownloadSettings>(AutoDownloadSettingsNotifier.new);

/// The songs it downloaded (see [AutoLedger]); one live copy for the app.
final autoLedgerProvider = Provider<AutoLedger>((ref) {
  try {
    final raw = HiveBoxes.prefs.get(_kLedger);
    return AutoLedger.decode(raw is String ? raw : null);
  } catch (_) {
    return AutoLedger();
  }
});

/// Bumps whenever the ledger changes, so "What it downloaded" repaints.
final autoLedgerRevisionProvider = NotifierProvider<_Revision, int>(_Revision.new);

class _Revision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

/// The device as it is right now (network, power, whether the player is busy).
Future<AutoEnv> readAutoEnv(Ref ref) async {
  var net = AutoNet.unknown;
  try {
    final r = await ref.read(connectivityProvider).checkConnectivity();
    if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) {
      net = AutoNet.wifi;
    } else if (r.contains(ConnectivityResult.mobile)) {
      net = AutoNet.mobile;
    } else if (r.isEmpty || r.contains(ConnectivityResult.none)) {
      net = AutoNet.none;
    }
  } catch (_) {}

  bool? charging;
  int? level;
  try {
    final b = Battery();
    final st = await b.batteryState;
    charging = switch (st) {
      BatteryState.charging || BatteryState.full || BatteryState.connectedNotCharging => true,
      BatteryState.discharging => false,
      BatteryState.unknown => null,
    };
    level = await b.batteryLevel;
  } catch (_) {} // a desktop without a battery

  var busy = false;
  try {
    final ps = ref.read(playerProvider.notifier).player.processingState;
    busy = ps == ProcessingState.loading || ps == ProcessingState.buffering;
  } catch (_) {}
  return AutoEnv(net: net, charging: charging, batteryPercent: level, playbackBusy: busy);
}

/// Completed plays from the history: a play counts when it was not skipped
/// before half and lasted at least 20 seconds.
Future<List<PlayStat>> loadPlayStats(Ref ref, DateTime now) async {
  final db = ref.read(appDatabaseProvider);
  final since = now.subtract(const Duration(days: kAutoTopDays)).millisecondsSinceEpoch;
  final rows = await (db.select(db.playEvents)
        ..where((t) => t.tsStart.isBiggerOrEqualValue(since) & t.skipBefore50.equals(false) & t.playDurSec.isBiggerOrEqualValue(20)))
      .get();
  final recentCut = now.subtract(const Duration(days: kAutoRecentDays)).millisecondsSinceEpoch;
  final recent = <String, int>{}, window = <String, int>{}, last = <String, int>{};
  for (final r in rows) {
    if (isLocalSongId(r.songId)) continue;
    window[r.songId] = (window[r.songId] ?? 0) + 1;
    if (r.tsStart >= recentCut) recent[r.songId] = (recent[r.songId] ?? 0) + 1;
    if (r.tsStart > (last[r.songId] ?? 0)) last[r.songId] = r.tsStart;
  }
  if (window.isEmpty) return const [];
  final liked = <String>{};
  final ids = window.keys.toList();
  for (var i = 0; i < ids.length; i += 500) {
    final chunk = ids.sublist(i, (i + 500).clamp(0, ids.length));
    final meta = await (db.select(db.songMetadata)..where((t) => t.songId.isIn(chunk) & t.starred.equals(true))).get();
    liked.addAll(meta.map((m) => m.songId));
  }
  return [
    for (final id in ids)
      PlayStat(
        songId: id,
        recentPlays: recent[id] ?? 0,
        topWindowPlays: window[id] ?? 0,
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(last[id]!),
        liked: liked.contains(id),
      ),
  ];
}

final autoDownloadServiceProvider = Provider<AutoDownloadService>((ref) {
  final ledger = ref.watch(autoLedgerProvider);
  final offline = ref.read(offlineServiceProvider);
  return AutoDownloadService(AutoDownloadDeps(
    settings: () => ref.read(autoDownloadSettingsProvider),
    env: () => readAutoEnv(ref),
    stats: () => loadPlayStats(ref, DateTime.now()),
    downloadedIds: () => offline.getDownloadedSongIds().toSet(),
    freeBytes: () async {
      final dir = offline.downloadsDirectory;
      return dir == null ? null : freeSpaceBytes(dir);
    },
    fetchSong: (id) async {
      final songs = await ref.read(subsonicServiceProvider).getSongs([id]);
      return songs.isEmpty ? null : songs.first;
    },
    download: (song) async {
      final n = ref.read(downloadStateProvider.notifier);
      await n.downloadSong(song, notify: false);
      return n.statusOf(song.id) == SongDownloadStatus.downloaded;
    },
    sizeOf: (id) async {
      try {
        final path = await offline.getLocalPathAsync(id);
        return path == null ? 0 : await File(path).length();
      } catch (_) {
        return 0;
      }
    },
    delete: (id) => ref.read(downloadStateProvider.notifier).deleteSong(id),
    ledger: ledger,
    saveLedger: () async {
      try {
        await HiveBoxes.prefs.put(_kLedger, ledger.encode());
      } catch (_) {}
      ref.read(autoLedgerRevisionProvider.notifier).bump();
    },
    now: DateTime.now,
  ));
});

/// Starts the quiet background pass: a first look shortly after launch, then
/// every ten minutes. One timer, and each pass does nothing at all while the
/// setting is off.
final autoDownloadBootstrapProvider = Provider<void>((ref) {
  if (!PlatformUtils.supportsOfflineFiles) return;
  Timer? first;
  Timer? every;
  void pass() {
    if (!ref.read(autoDownloadSettingsProvider).enabled) return;
    unawaited(ref.read(offlineServiceProvider).initialize().then((_) => ref.read(autoDownloadServiceProvider).runOnce()));
  }

  first = Timer(const Duration(minutes: 2), pass);
  every = Timer.periodic(const Duration(minutes: 10), (_) => pass());
  // Turning it on starts a pass without waiting for the timer.
  ref.listen(autoDownloadSettingsProvider.select((s) => s.enabled), (prev, on) {
    if (on && prev != true) pass();
  });
  ref.onDispose(() {
    first?.cancel();
    every?.cancel();
  });
  if (kDebugMode) debugPrint('[AutoDownload] ready');
});
