import 'dart:convert';
import 'dart:math' as math;

/// The rules that decide which heard songs are kept offline. Pure functions
/// and plain data: nothing here touches the network, the disk or a clock, so
/// every rule is testable, and docs/auto-download.md can describe them 1:1.

// ── Tunables (documented in docs/auto-download.md) ──────────────────────────

/// Completed plays inside [recentDays] that make a song a candidate.
const int kAutoMinPlays = 3;
const int kAutoRecentDays = 14;

/// "Top played": the most played songs of the last [topDays] days, as long as
/// they were heard at least [topMinPlays] times.
const int kAutoTopDays = 30;
const int kAutoTopCount = 20;
const int kAutoTopMinPlays = 4;

/// A removed song is not picked again for this long. "Not this" is forever.
const Duration kAutoRemovedCooldown = Duration(days: 30);

/// Below this battery level nothing downloads unless the phone is charging.
const int kAutoLowBattery = 20;

/// At most this share of the free space may go to auto downloads.
const double kAutoFreeShare = 0.10;

const int kAutoDefaultBudgetMb = 2048;
const List<int> kAutoBudgetChoicesMb = [512, 1024, 2048, 5120, 10240];

// ── Settings ────────────────────────────────────────────────────────────────

class AutoDownloadSettings {
  const AutoDownloadSettings({
    this.enabled = false,
    this.wifiOnly = true,
    this.chargingOnly = true,
    this.budgetMb = kAutoDefaultBudgetMb,
  });

  final bool enabled;
  final bool wifiOnly;
  final bool chargingOnly;
  final int budgetMb;

  AutoDownloadSettings copyWith({bool? enabled, bool? wifiOnly, bool? chargingOnly, int? budgetMb}) =>
      AutoDownloadSettings(
        enabled: enabled ?? this.enabled,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        chargingOnly: chargingOnly ?? this.chargingOnly,
        budgetMb: budgetMb ?? this.budgetMb,
      );

  @override
  bool operator ==(Object other) =>
      other is AutoDownloadSettings &&
      other.enabled == enabled &&
      other.wifiOnly == wifiOnly &&
      other.chargingOnly == chargingOnly &&
      other.budgetMb == budgetMb;

  @override
  int get hashCode => Object.hash(enabled, wifiOnly, chargingOnly, budgetMb);
}

// ── Scoring ─────────────────────────────────────────────────────────────────

/// What the play history says about one song.
class PlayStat {
  const PlayStat({
    required this.songId,
    required this.recentPlays,
    required this.topWindowPlays,
    required this.lastPlayed,
    this.liked = false,
  });

  final String songId;

  /// Completed plays in the last [kAutoRecentDays] days.
  final int recentPlays;

  /// Completed plays in the last [kAutoTopDays] days.
  final int topWindowPlays;

  final DateTime lastPlayed;
  final bool liked;
}

class AutoCandidate {
  const AutoCandidate(this.songId, this.score, this.reason);
  final String songId;
  final int score;
  final String reason;
}

/// How much a song is worth keeping, 0 when it is no candidate at all.
///
///   10 per recent play + up to 14 for how recently it was last heard
///   + 15 if liked + 8 if in the top played.
///
/// Used both to rank what to download and to pick what to give up first.
int scoreOf(PlayStat s, DateTime now, {required bool inTop}) {
  final days = now.difference(s.lastPlayed).inHours / 24;
  final recency = math.max(0, kAutoRecentDays - days.floor());
  return s.recentPlays * 10 + recency + (s.liked ? 15 : 0) + (inTop ? 8 : 0);
}

/// The ids in the top played set: most completed plays in the last
/// [kAutoTopDays] days, at least [kAutoTopMinPlays] of them.
Set<String> topPlayedIds(Iterable<PlayStat> stats) {
  final sorted = [for (final s in stats) if (s.topWindowPlays >= kAutoTopMinPlays) s]
    ..sort((a, b) {
      final c = b.topWindowPlays.compareTo(a.topWindowPlays);
      return c != 0 ? c : b.lastPlayed.compareTo(a.lastPlayed);
    });
  return {for (final s in sorted.take(kAutoTopCount)) s.songId};
}

/// Songs worth keeping offline, best first.
///
/// A song is a candidate when it has [kAutoMinPlays] completed plays in the
/// last [kAutoRecentDays] days, or one play and a like, or it is in the top
/// played. [skip] holds what must not be picked: already downloaded, local,
/// already auto-downloaded, or blocked by the listener.
List<AutoCandidate> rankCandidates(
  Iterable<PlayStat> stats,
  DateTime now, {
  Set<String> skip = const {},
}) {
  final top = topPlayedIds(stats);
  final out = <AutoCandidate>[];
  for (final s in stats) {
    if (skip.contains(s.songId)) continue;
    final inTop = top.contains(s.songId);
    String? reason;
    if (s.recentPlays >= kAutoMinPlays) {
      reason = 'Played ${s.recentPlays} times lately';
    } else if (s.recentPlays >= 1 && s.liked) {
      reason = 'Played and liked';
    } else if (inTop) {
      reason = 'One of your most played';
    }
    if (reason == null) continue;
    out.add(AutoCandidate(s.songId, scoreOf(s, now, inTop: inTop), reason));
  }
  out.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.songId.compareTo(b.songId);
  });
  return out;
}

// ── Budget and eviction ─────────────────────────────────────────────────────

/// The room auto downloads may use: what the listener chose, but never more
/// than [kAutoFreeShare] of the space that is free for them (free space plus
/// what they already hold). [freeBytes] null: the platform did not say, only
/// the chosen budget applies.
int effectiveBudgetBytes({required int chosenMb, int? freeBytes, required int usedBytes}) {
  final chosen = chosenMb * 1024 * 1024;
  if (freeBytes == null) return chosen;
  final share = ((freeBytes + usedBytes) * kAutoFreeShare).floor();
  return math.min(chosen, share);
}

/// One song the auto downloader keeps.
class AutoEntry {
  const AutoEntry({
    required this.songId,
    required this.title,
    required this.artist,
    required this.bytes,
    required this.downloadedAt,
    required this.reason,
  });

  final String songId;
  final String title;
  final String artist;
  final int bytes;
  final DateTime downloadedAt;
  final String reason;

  Map<String, dynamic> toJson() => {
        'id': songId,
        't': title,
        'a': artist,
        'b': bytes,
        'at': downloadedAt.millisecondsSinceEpoch,
        'r': reason,
      };

  static AutoEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], at = j['at'], b = j['b'];
    if (id is! String || id.isEmpty || at is! int || b is! int) return null;
    return AutoEntry(
      songId: id,
      title: j['t']?.toString() ?? '',
      artist: j['a']?.toString() ?? '',
      bytes: b,
      downloadedAt: DateTime.fromMillisecondsSinceEpoch(at),
      reason: j['r']?.toString() ?? '',
    );
  }
}

/// What to delete to make room for [needBytes], or null when it cannot be done
/// without giving up songs that matter more than the new one.
///
/// Only [entries] (auto downloads) are ever offered; songs the listener
/// downloaded are not in this list. Least valuable go first: lowest score,
/// then oldest. An entry scoring at least as high as [newScore] is never
/// evicted for it, so the budget does not churn between two equal songs.
List<AutoEntry>? planEviction({
  required List<AutoEntry> entries,
  required int Function(AutoEntry) scoreOfEntry,
  required int budgetBytes,
  required int needBytes,
  required int newScore,
}) {
  var used = entries.fold<int>(0, (a, e) => a + e.bytes);
  if (used + needBytes <= budgetBytes) return const [];
  if (needBytes > budgetBytes) return null;
  final order = [...entries]..sort((a, b) {
      final c = scoreOfEntry(a).compareTo(scoreOfEntry(b));
      return c != 0 ? c : a.downloadedAt.compareTo(b.downloadedAt);
    });
  final victims = <AutoEntry>[];
  for (final e in order) {
    if (used + needBytes <= budgetBytes) break;
    if (scoreOfEntry(e) >= newScore) return null;
    victims.add(e);
    used -= e.bytes;
  }
  return used + needBytes <= budgetBytes ? victims : null;
}

/// Entries to drop when the budget itself shrank (lower setting, less free
/// space): least valuable first until what is left fits.
List<AutoEntry> trimToBudget({
  required List<AutoEntry> entries,
  required int Function(AutoEntry) scoreOfEntry,
  required int budgetBytes,
}) {
  var used = entries.fold<int>(0, (a, e) => a + e.bytes);
  if (used <= budgetBytes) return const [];
  final order = [...entries]..sort((a, b) {
      final c = scoreOfEntry(a).compareTo(scoreOfEntry(b));
      return c != 0 ? c : a.downloadedAt.compareTo(b.downloadedAt);
    });
  final out = <AutoEntry>[];
  for (final e in order) {
    if (used <= budgetBytes) break;
    out.add(e);
    used -= e.bytes;
  }
  return out;
}

// ── When it may run ─────────────────────────────────────────────────────────

enum AutoNet { wifi, mobile, none, unknown }

/// The device right now.
class AutoEnv {
  const AutoEnv({
    required this.net,
    this.charging,
    this.batteryPercent,
    this.playbackBusy = false,
  });

  final AutoNet net;

  /// Null when the platform cannot tell (a desktop without a battery).
  final bool? charging;
  final int? batteryPercent;

  /// The player is loading or buffering: leave the connection to it.
  final bool playbackBusy;
}

/// Null when a download may start now, otherwise why not (for the log and
/// tests). Checked before every file, not once per run.
///
/// [desktop]: an unknown charging state counts as plugged in (a desktop has
/// no battery to protect); on a phone it counts as not charging.
String? whyNotNow(AutoDownloadSettings s, AutoEnv env, {required bool desktop}) {
  if (!s.enabled) return 'off';
  switch (env.net) {
    case AutoNet.none:
      return 'offline';
    case AutoNet.unknown:
      return 'network unknown'; // cannot prove it is not metered
    case AutoNet.mobile:
      if (s.wifiOnly) return 'mobile data';
    case AutoNet.wifi:
      break;
  }
  final charging = env.charging ?? desktop;
  if (s.chargingOnly && !charging) return 'not charging';
  final level = env.batteryPercent;
  if (!charging && level != null && level <= kAutoLowBattery) return 'low battery';
  if (env.playbackBusy) return 'playback busy';
  return null;
}

// ── The ledger ──────────────────────────────────────────────────────────────

/// What the auto downloader has put on the device, and what it was told never
/// (or not for a while) to fetch. Stored as one json string.
class AutoLedger {
  AutoLedger({Map<String, AutoEntry>? entries, Map<String, int>? blocked})
      : entries = entries ?? {},
        blocked = blocked ?? {};

  final Map<String, AutoEntry> entries;

  /// song id → ms since epoch until which it is skipped; 0 = for good.
  final Map<String, int> blocked;

  bool isBlocked(String id, DateTime now) {
    final until = blocked[id];
    if (until == null) return false;
    if (until == 0) return true;
    return now.millisecondsSinceEpoch < until;
  }

  void blockFor(String id, DateTime now, {bool forever = false}) {
    blocked[id] = forever ? 0 : now.add(kAutoRemovedCooldown).millisecondsSinceEpoch;
  }

  int get usedBytes => entries.values.fold(0, (a, e) => a + e.bytes);

  String encode() => jsonEncode({
        'v': 1,
        'entries': [for (final e in entries.values) e.toJson()],
        'blocked': blocked,
      });

  /// Never throws: anything unreadable gives an empty ledger.
  static AutoLedger decode(String? raw) {
    if (raw == null || raw.isEmpty) return AutoLedger();
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['v'] != 1) return AutoLedger();
      final entries = <String, AutoEntry>{};
      for (final e in (j['entries'] as List? ?? const [])) {
        final entry = AutoEntry.fromJson(e);
        if (entry != null) entries[entry.songId] = entry;
      }
      final blocked = <String, int>{};
      (j['blocked'] as Map? ?? const {}).forEach((k, v) {
        if (k is String && v is int) blocked[k] = v;
      });
      return AutoLedger(entries: entries, blocked: blocked);
    } catch (_) {
      return AutoLedger();
    }
  }
}
