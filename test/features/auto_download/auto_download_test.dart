import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/auto_download/logic/auto_download_policy.dart';
import 'package:navivibe/features/auto_download/logic/auto_download_service.dart';
import 'package:navivibe/models/song.dart';

final now = DateTime(2026, 11, 20, 12);

PlayStat stat(String id, {int recent = 0, int window = 0, int daysAgo = 1, bool liked = false}) => PlayStat(
      songId: id,
      recentPlays: recent,
      topWindowPlays: window == 0 ? recent : window,
      lastPlayed: now.subtract(Duration(days: daysAgo)),
      liked: liked,
    );

const mb = 1024 * 1024;

Song song(String id) => Song(
    id: id, title: id, artist: 'X', album: 'Y', coverArt: id, duration: 200, track: 1, year: 2020, bitRate: 320, suffix: 'mp3');

void main() {
  group('scoring', () {
    test('3 plays in 14 days is a candidate; 2 plays is not', () {
      final c = rankCandidates([stat('a', recent: 3), stat('b', recent: 2)], now);
      expect(c.map((e) => e.songId), ['a']);
    });

    test('one play plus a like qualifies; one play alone does not', () {
      final c = rankCandidates([stat('a', recent: 1, liked: true), stat('b', recent: 1)], now);
      expect(c.map((e) => e.songId), ['a']);
      expect(c.single.reason, 'Played and liked');
    });

    test('top played qualifies even with few recent plays', () {
      final c = rankCandidates([stat('a', recent: 0, window: 6, daysAgo: 20)], now);
      expect(c.single.reason, 'One of your most played');
    });

    test('top played needs at least 4 plays', () {
      expect(rankCandidates([stat('a', window: 3, daysAgo: 20)], now), isEmpty);
    });

    test('ranks by plays, then recency', () {
      final c = rankCandidates([
        stat('few', recent: 3, daysAgo: 1),
        stat('many', recent: 6, daysAgo: 10),
        stat('fresh', recent: 3, daysAgo: 0),
      ], now);
      expect(c.map((e) => e.songId), ['many', 'fresh', 'few']);
    });

    test('skips ids that must not be picked', () {
      final c = rankCandidates([stat('a', recent: 5), stat('b', recent: 5)], now, skip: {'a'});
      expect(c.map((e) => e.songId), ['b']);
    });
  });

  group('budget', () {
    test('is the smaller of the chosen size and 10% of free space', () {
      expect(effectiveBudgetBytes(chosenMb: 2048, freeBytes: 100 * 1024 * mb, usedBytes: 0), 2048 * mb);
      expect(effectiveBudgetBytes(chosenMb: 2048, freeBytes: 5 * 1024 * mb, usedBytes: 0), (5 * 1024 * mb * 0.1).floor());
      expect(effectiveBudgetBytes(chosenMb: 2048, freeBytes: null, usedBytes: 0), 2048 * mb);
    });

    test('space already used by auto downloads counts as available to them', () {
      expect(effectiveBudgetBytes(chosenMb: 4096, freeBytes: 8 * 1024 * mb, usedBytes: 2 * 1024 * mb),
          ((8 + 2) * 1024 * mb * 0.1).floor());
    });
  });

  group('eviction', () {
    AutoEntry e(String id, int bytes, int day) => AutoEntry(
        songId: id, title: id, artist: '', bytes: bytes, downloadedAt: DateTime(2026, 11, day), reason: '');

    test('nothing to evict when it fits', () {
      expect(planEviction(entries: [e('a', 10, 1)], scoreOfEntry: (_) => 5, budgetBytes: 100, needBytes: 50, newScore: 9), isEmpty);
    });

    test('least valuable then oldest go first', () {
      final scores = {'a': 30, 'b': 5, 'c': 5};
      final plan = planEviction(
        entries: [e('a', 40, 1), e('b', 40, 3), e('c', 40, 2)],
        scoreOfEntry: (x) => scores[x.songId]!,
        budgetBytes: 120,
        needBytes: 40,
        newScore: 50,
      )!;
      expect(plan.map((x) => x.songId), ['c']);
    });

    test('never evicts something worth as much as the new song', () {
      final plan = planEviction(
        entries: [e('a', 80, 1)],
        scoreOfEntry: (_) => 40,
        budgetBytes: 100,
        needBytes: 50,
        newScore: 40,
      );
      expect(plan, isNull);
    });

    test('a song bigger than the whole budget cannot be placed', () {
      expect(planEviction(entries: const [], scoreOfEntry: (_) => 0, budgetBytes: 10, needBytes: 50, newScore: 9), isNull);
    });

    test('trimToBudget drops the least played first until it fits', () {
      final scores = {'a': 1, 'b': 9};
      final out = trimToBudget(
        entries: [e('a', 60, 1), e('b', 60, 2)],
        scoreOfEntry: (x) => scores[x.songId]!,
        budgetBytes: 70,
      );
      expect(out.map((x) => x.songId), ['a']);
    });
  });

  group('when it may run', () {
    const on = AutoDownloadSettings(enabled: true);
    const wifi = AutoEnv(net: AutoNet.wifi, charging: true, batteryPercent: 80);

    test('runs on Wi-Fi while charging', () {
      expect(whyNotNow(on, wifi, desktop: false), isNull);
    });

    test('never on mobile data with Wi-Fi only on', () {
      expect(whyNotNow(on, const AutoEnv(net: AutoNet.mobile, charging: true, batteryPercent: 80), desktop: false), 'mobile data');
    });

    test('mobile data is allowed only when Wi-Fi only is off', () {
      final s = on.copyWith(wifiOnly: false);
      expect(whyNotNow(s, const AutoEnv(net: AutoNet.mobile, charging: true, batteryPercent: 80), desktop: false), isNull);
    });

    test('an unknown network is treated as unsafe', () {
      expect(whyNotNow(on, const AutoEnv(net: AutoNet.unknown, charging: true), desktop: false), isNotNull);
    });

    test('waits for the charger, low battery and a busy player', () {
      expect(whyNotNow(on, const AutoEnv(net: AutoNet.wifi, charging: false, batteryPercent: 80), desktop: false), 'not charging');
      final noCharger = on.copyWith(chargingOnly: false);
      expect(whyNotNow(noCharger, const AutoEnv(net: AutoNet.wifi, charging: false, batteryPercent: 15), desktop: false), 'low battery');
      expect(whyNotNow(noCharger, const AutoEnv(net: AutoNet.wifi, charging: false, batteryPercent: 60), desktop: false), isNull);
      expect(whyNotNow(on, const AutoEnv(net: AutoNet.wifi, charging: true, playbackBusy: true), desktop: false), 'playback busy');
    });

    test('a desktop without a battery counts as plugged in; a phone does not', () {
      const unknown = AutoEnv(net: AutoNet.wifi);
      expect(whyNotNow(on, unknown, desktop: true), isNull);
      expect(whyNotNow(on, unknown, desktop: false), 'not charging');
    });

    test('off does nothing', () {
      expect(whyNotNow(const AutoDownloadSettings(), wifi, desktop: false), 'off');
    });
  });

  group('ledger', () {
    test('round trips and survives corruption', () {
      final l = AutoLedger()
        ..entries['a'] = AutoEntry(songId: 'a', title: 'A', artist: 'X', bytes: 5, downloadedAt: now, reason: 'r')
        ..blockFor('b', now, forever: true)
        ..blockFor('c', now);
      final back = AutoLedger.decode(l.encode());
      expect(back.entries['a']!.title, 'A');
      expect(back.isBlocked('b', now.add(const Duration(days: 999))), isTrue);
      expect(back.isBlocked('c', now.add(const Duration(days: 10))), isTrue);
      expect(back.isBlocked('c', now.add(const Duration(days: 31))), isFalse);
      expect(AutoLedger.decode('garbage').entries, isEmpty);
      expect(AutoLedger.decode(null).entries, isEmpty);
    });
  });

  group('service', () {
    late AutoLedger ledger;
    late Set<String> onDevice;
    late List<String> downloads;
    late List<String> deleted;

    AutoDownloadService build({
      required List<PlayStat> stats,
      AutoDownloadSettings settings = const AutoDownloadSettings(enabled: true),
      AutoEnv env = const AutoEnv(net: AutoNet.wifi, charging: true, batteryPercent: 90),
      Set<String> userDownloads = const {},
      int? freeBytes,
      int bytesPerSong = 8 * mb,
    }) {
      onDevice = {...userDownloads};
      return AutoDownloadService(AutoDownloadDeps(
        settings: () => settings,
        env: () async => env,
        stats: () async => stats,
        downloadedIds: () => onDevice,
        freeBytes: () async => freeBytes,
        fetchSong: (id) async => song(id),
        download: (s) async {
          downloads.add(s.id);
          onDevice.add(s.id);
          return true;
        },
        sizeOf: (id) async => bytesPerSong,
        delete: (id) async {
          deleted.add(id);
          onDevice.remove(id);
        },
        ledger: ledger,
        saveLedger: () async {},
        now: () => now,
      ));
    }

    setUp(() {
      ledger = AutoLedger();
      downloads = [];
      deleted = [];
    });

    test('downloads the best candidates and records them', () async {
      final svc = build(stats: [stat('a', recent: 5), stat('b', recent: 3), stat('c', recent: 1)]);
      final got = await svc.runOnce();
      expect(got, ['a', 'b']);
      expect(ledger.entries.keys, containsAll(['a', 'b']));
      expect(ledger.entries['a']!.bytes, 8 * mb);
    });

    test('never runs on mobile data while Wi-Fi only is on', () async {
      final svc = build(
        stats: [stat('a', recent: 5)],
        env: const AutoEnv(net: AutoNet.mobile, charging: true, batteryPercent: 90),
      );
      expect(await svc.runOnce(), isEmpty);
      expect(downloads, isEmpty);
    });

    test('does nothing while off, offline, or not charging', () async {
      expect(await build(stats: [stat('a', recent: 5)], settings: const AutoDownloadSettings()).runOnce(), isEmpty);
      expect(await build(stats: [stat('a', recent: 5)], env: const AutoEnv(net: AutoNet.none)).runOnce(), isEmpty);
      expect(
          await build(stats: [stat('a', recent: 5)], env: const AutoEnv(net: AutoNet.wifi, charging: false, batteryPercent: 90))
              .runOnce(),
          isEmpty);
      expect(downloads, isEmpty);
    });

    test('skips songs the listener already downloaded', () async {
      final svc = build(stats: [stat('a', recent: 5)], userDownloads: {'a'});
      expect(await svc.runOnce(), isEmpty);
    });

    test('stays within the storage budget and never touches the listeners own downloads', () async {
      // 10% of (400 MB free + what it holds) leaves room for about two 20 MB songs.
      final svc = build(
        stats: [stat('mine', recent: 9), stat('a', recent: 5), stat('b', recent: 4), stat('c', recent: 3)],
        userDownloads: {'mine'},
        freeBytes: 400 * mb,
        bytesPerSong: 20 * mb,
      );
      await svc.runOnce();
      final room = ((400 * mb + 3 * 20 * mb) * 0.1).floor();
      expect(ledger.usedBytes, lessThanOrEqualTo(room));
      expect(onDevice, contains('mine'));
      expect(deleted, isNot(contains('mine')));
      expect(ledger.entries.containsKey('mine'), isFalse);
    });

    test('evicts its own least valuable song for a better one, never a user download', () async {
      final svc = build(
        stats: [stat('best', recent: 9)],
        settings: const AutoDownloadSettings(enabled: true, budgetMb: 512),
        userDownloads: {'mine'},
        bytesPerSong: 20 * mb,
      );
      ledger.entries['old'] = AutoEntry(songId: 'old', title: 'old', artist: '', bytes: 500 * mb, downloadedAt: now, reason: '');
      onDevice.add('old');
      final got = await svc.runOnce();
      expect(got, ['best']);
      expect(deleted, ['old']);
      expect(onDevice, containsAll(['mine', 'best']));
    });

    test('Not This deletes the file and the song is never picked again', () async {
      final svc = build(stats: [stat('a', recent: 5)]);
      await svc.runOnce();
      expect(downloads, ['a']);
      await svc.neverAgain('a');
      expect(deleted, ['a']);
      expect(ledger.entries, isEmpty);
      downloads.clear();
      expect(await svc.runOnce(), isEmpty);
    });

    test('a song the listener deleted by hand is not fetched again for a month', () async {
      final svc = build(stats: [stat('a', recent: 5)]);
      await svc.runOnce();
      onDevice.remove('a'); // deleted in Downloads
      downloads.clear();
      expect(await svc.runOnce(), isEmpty);
      expect(ledger.entries, isEmpty);
    });

    test('a failing step never throws out of runOnce', () async {
      final svc = AutoDownloadService(AutoDownloadDeps(
        settings: () => const AutoDownloadSettings(enabled: true),
        env: () async => throw StateError('boom'),
        stats: () async => [stat('a', recent: 5)],
        downloadedIds: () => {},
        freeBytes: () async => null,
        fetchSong: (id) async => song(id),
        download: (s) async => true,
        sizeOf: (id) async => 0,
        delete: (id) async {},
        ledger: AutoLedger(),
        saveLedger: () async {},
        now: () => now,
      ));
      expect(await svc.runOnce(), isEmpty);
    });
  });
}
