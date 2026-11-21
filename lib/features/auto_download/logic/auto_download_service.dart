import 'package:flutter/foundation.dart';

import '../../../models/song.dart';
import 'auto_download_policy.dart';

/// Everything the service needs from the app, as plain functions, so it runs
/// the same in tests (no network, no disk) as on a device. The real wiring
/// reuses [OfflineService] through the downloads provider: there is no second
/// downloader.
class AutoDownloadDeps {
  const AutoDownloadDeps({
    required this.settings,
    required this.env,
    required this.stats,
    required this.downloadedIds,
    required this.freeBytes,
    required this.fetchSong,
    required this.download,
    required this.sizeOf,
    required this.delete,
    required this.ledger,
    required this.saveLedger,
    required this.now,
  });

  final AutoDownloadSettings Function() settings;
  final Future<AutoEnv> Function() env;

  /// Completed plays by song, from the listening history.
  final Future<List<PlayStat>> Function() stats;

  /// Everything on the device already (downloads), plus local-library songs.
  final Set<String> Function() downloadedIds;
  final Future<int?> Function() freeBytes;
  final Future<Song?> Function(String id) fetchSong;

  /// Downloads through the normal downloader; true when the file is there.
  final Future<bool> Function(Song song) download;

  /// Bytes the finished download takes on disk (0 when unknown).
  final Future<int> Function(String id) sizeOf;
  final Future<void> Function(String id) delete;
  final AutoLedger ledger;
  final Future<void> Function() saveLedger;
  final DateTime Function() now;
}

/// Keeps the songs you keep coming back to available offline. Rules are in
/// auto_download_policy.dart; this class only sequences them.
///
/// Safe by construction: [runOnce] never throws, downloads one song at a time,
/// re-checks the device before each one, and only ever deletes what it
/// downloaded itself.
class AutoDownloadService {
  AutoDownloadService(this._d);
  final AutoDownloadDeps _d;
  bool _running = false;

  /// Most songs fetched in one pass; the next pass (minutes later) continues.
  static const int maxPerRun = 4;

  bool get isRunning => _running;

  /// One pass: forget auto downloads that are gone, trim to the budget, then
  /// fetch the best candidates while the device allows it. Returns the ids it
  /// downloaded.
  Future<List<String>> runOnce() async {
    if (_running) return const [];
    _running = true;
    final got = <String>[];
    try {
      final settings = _d.settings();
      if (!settings.enabled) return got;
      final now = _d.now();

      await _forgetMissing(now);
      final stats = await _d.stats();
      final byId = {for (final s in stats) s.songId: s};
      final top = topPlayedIds(stats);
      int valueOf(AutoEntry e) {
        final s = byId[e.songId];
        return s == null ? 0 : scoreOf(s, now, inTop: top.contains(e.songId));
      }

      var budget = effectiveBudgetBytes(
        chosenMb: settings.budgetMb,
        freeBytes: await _d.freeBytes(),
        usedBytes: _d.ledger.usedBytes,
      );
      await _evict(trimToBudget(entries: _d.ledger.entries.values.toList(), scoreOfEntry: valueOf, budgetBytes: budget));

      final skip = <String>{
        ..._d.downloadedIds(),
        ..._d.ledger.entries.keys,
        for (final id in _d.ledger.blocked.keys)
          if (_d.ledger.isBlocked(id, now)) id,
      };
      final candidates = rankCandidates(stats, now, skip: skip);

      for (final c in candidates) {
        if (got.length >= maxPerRun) break;
        // The device can change between files (unplugged, off Wi-Fi, a song
        // started buffering): ask again every time.
        final why = whyNotNow(_d.settings(), await _d.env(), desktop: _isDesktop);
        if (why != null) {
          debugPrint('[AutoDownload] paused: $why');
          break;
        }
        final song = await _d.fetchSong(c.songId);
        if (song == null) continue;

        final need = _estimateBytes(song);
        final plan = planEviction(
          entries: _d.ledger.entries.values.toList(),
          scoreOfEntry: valueOf,
          budgetBytes: budget,
          needBytes: need,
          newScore: c.score,
        );
        if (plan == null) continue; // would push out something worth more
        await _evict(plan);

        final ok = await _d.download(song);
        if (!ok) continue;
        final bytes = await _d.sizeOf(song.id);
        _d.ledger.entries[song.id] = AutoEntry(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          bytes: bytes > 0 ? bytes : need,
          downloadedAt: _d.now(),
          reason: c.reason,
        );
        await _d.saveLedger();
        got.add(song.id);
        // The real size can differ from the estimate; keep within budget.
        budget = effectiveBudgetBytes(
          chosenMb: settings.budgetMb,
          freeBytes: await _d.freeBytes(),
          usedBytes: _d.ledger.usedBytes,
        );
        await _evict(trimToBudget(
          entries: [for (final e in _d.ledger.entries.values) if (e.songId != song.id) e],
          scoreOfEntry: valueOf,
          budgetBytes: budget - (_d.ledger.entries[song.id]?.bytes ?? 0),
        ));
      }
    } catch (e) {
      debugPrint('[AutoDownload] pass failed: $e'); // bookkeeping never breaks playback
    } finally {
      _running = false;
    }
    return got;
  }

  /// "Remove": deletes the file and skips the song for a month.
  Future<void> remove(String id) => _drop(id, forever: false);

  /// "Not this": deletes the file and never picks the song again.
  Future<void> neverAgain(String id) => _drop(id, forever: true);

  Future<void> _drop(String id, {required bool forever}) async {
    try {
      if (_d.ledger.entries.containsKey(id)) await _d.delete(id);
    } catch (e) {
      debugPrint('[AutoDownload] remove $id: $e');
    }
    _d.ledger.entries.remove(id);
    _d.ledger.blockFor(id, _d.now(), forever: forever);
    await _d.saveLedger();
  }

  Future<void> _evict(List<AutoEntry> victims) async {
    for (final v in victims) {
      try {
        await _d.delete(v.songId);
      } catch (e) {
        debugPrint('[AutoDownload] evict ${v.songId}: $e');
      }
      _d.ledger.entries.remove(v.songId);
    }
    if (victims.isNotEmpty) await _d.saveLedger();
  }

  /// An entry whose file the listener deleted by hand is dropped (and not
  /// fetched again for a month); one that became a plain download stays put.
  Future<void> _forgetMissing(DateTime now) async {
    final have = _d.downloadedIds();
    final gone = [for (final id in _d.ledger.entries.keys) if (!have.contains(id)) id];
    for (final id in gone) {
      _d.ledger.entries.remove(id);
      _d.ledger.blockFor(id, now);
    }
    if (gone.isNotEmpty) await _d.saveLedger();
  }

  static bool get _isDesktop => defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Size of the original file, estimated from the bit rate the server told us.
  static int _estimateBytes(Song s) {
    final kbps = s.bitRate > 0 ? s.bitRate : (s.suffix.toLowerCase() == 'flac' ? 900 : 256);
    final seconds = s.duration > 0 ? s.duration : 240;
    return kbps * 125 * seconds;
  }
}
