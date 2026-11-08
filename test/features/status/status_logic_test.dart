import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/status/logic/download_speed.dart';
import 'package:navivibe/features/status/logic/status_model.dart';
import 'package:navivibe/features/status/logic/status_providers.dart';
import 'package:navivibe/models/download_state.dart';

void main() {
  group('timedProbe', () {
    test('a quick reply is OK with its latency', () async {
      final r = await timedProbe(() async => 'x', describe: (_) => 'host');
      expect(r.level, HealthLevel.ok);
      expect(r.latency, isNotNull);
      expect(r.detail, endsWith('host'));
    });

    test('a failure is Down with a sentence, not a stack', () async {
      final r = await timedProbe(() async => throw DioException(
            requestOptions: RequestOptions(),
            response: Response(requestOptions: RequestOptions(), statusCode: 503),
          ));
      expect(r.level, HealthLevel.down);
      expect(r.detail, 'Server error (503)');
    });

    test('no answer in time is Down', () async {
      final r = await timedProbe(
        () => Future<Object?>.delayed(const Duration(seconds: 5)),
        timeout: const Duration(milliseconds: 20),
      );
      expect(r.level, HealthLevel.down);
      expect(r.detail, 'No answer in time');
    });

    test('latency above the threshold is Slow', () {
      expect(levelForLatency(const Duration(milliseconds: 200)), HealthLevel.ok);
      expect(levelForLatency(kSlowAfter + const Duration(milliseconds: 1)), HealthLevel.slow);
    });

    test('a ProbeFailure message passes through', () async {
      final r = await timedProbe(() async => throw const ProbeFailure('Not allowed'));
      expect(r.detail, 'Not allowed');
    });
  });

  group('redaction and report', () {
    test('strips credentials from urls, params and auth headers', () {
      const dirty = 'GET https://bob:hunter2@host/rest/ping?u=bob&t=abc123&s=salt&p=hunter2 Bearer eyJhbGci.x.y';
      final clean = redact(dirty);
      for (final secret in ['hunter2', 'abc123', 'salt', 'eyJhbGci']) {
        expect(clean, isNot(contains(secret)));
      }
    });

    test('diagnostics list every row and never carry secrets', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final report = buildDiagnostics(
        rows: [
          HealthRow(id: 'a', title: 'Navidrome', level: HealthLevel.ok, detail: '40 ms', checkedAt: now),
          HealthRow(id: 'b', title: 'Online fetch', level: HealthLevel.down, detail: 'url ?p=hunter2&t=tok', checkedAt: now),
          const HealthRow(id: 'c', title: 'Social & Jam'),
        ],
        appVersion: '1.0.0 (7)',
        platform: 'windows',
        now: now,
        extra: {'Server': hostOf('https://music.example.com:4533/x')},
      );
      expect(report, contains('App: 1.0.0 (7)'));
      expect(report, contains('Server: music.example.com:4533'));
      expect(report, contains('Navidrome: OK — 40 ms (checked just now)'));
      expect(report, contains('Social & Jam: Checking…'));
      expect(report, isNot(contains('hunter2')));
      expect(report, isNot(contains('tok')));
    });

    test('formatAgo', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      expect(formatAgo(null, now), 'Not checked');
      expect(formatAgo(now.subtract(const Duration(seconds: 30)), now), '30 s ago');
      expect(formatAgo(now.subtract(const Duration(minutes: 3)), now), '3 min ago');
      expect(formatAgo(now.subtract(const Duration(hours: 5)), now), '5 h ago');
    });
  });

  group('row descriptions', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    test('library: syncing, failed, never, done', () {
      expect(describeLibrary(syncing: true, synced: 500, error: null, lastSyncAt: null, songCount: 500, now: now).detail,
          contains('Syncing'));
      final failed = describeLibrary(syncing: false, synced: 0, error: Exception('SocketException'), lastSyncAt: now, songCount: 3, now: now);
      expect(failed.level, HealthLevel.down);
      expect(describeLibrary(syncing: false, synced: 0, error: null, lastSyncAt: null, songCount: 0, now: now).level, HealthLevel.slow);
      final ok = describeLibrary(syncing: false, synced: 0, error: null, lastSyncAt: now.subtract(const Duration(hours: 2)), songCount: 1200, now: now);
      expect(ok.level, HealthLevel.ok);
      expect(ok.detail, 'Last run 2 h ago · 1200 songs');
    });

    test('downloads: counts, speed and failed reasons', () {
      const dl = [
        SongDownloadState(songId: '1', status: SongDownloadStatus.queued),
        SongDownloadState(songId: '2', status: SongDownloadStatus.downloading, progress: .4),
        SongDownloadState(songId: '3', status: SongDownloadStatus.failed, errorMessage: 'No internet connection'),
        SongDownloadState(songId: '4', status: SongDownloadStatus.downloaded),
      ];
      final r = describeDownloads(dl, 2 * 1024 * 1024, bytesOnDisk: 5 * 1024 * 1024);
      expect(r.level, HealthLevel.slow);
      expect(r.detail, contains('1 queued · 1 running · 1 failed'));
      expect(r.detail, contains('2.0 MB/s'));
      expect(r.detail, contains('Failed: No internet connection'));
      expect(describeDownloads(const [], 0).detail, contains('idle'));
      expect(describeDownloads(const [], 0).level, HealthLevel.ok);
    });

    test('offline', () {
      expect(describeOffline(networkOffline: true, offlineMode: false).level, HealthLevel.down);
      expect(describeOffline(networkOffline: false, offlineMode: true).detail, contains('Offline mode is on'));
      expect(describeOffline(networkOffline: false, offlineMode: false).level, HealthLevel.ok);
    });
  });

  group('DownloadSpeedMeter', () {
    test('averages recent bytes and decays to zero', () {
      final m = DownloadSpeedMeter.forTesting();
      final t0 = DateTime.utc(2026, 1, 1);
      m.startFile();
      m.record(1000, now: t0);
      m.record(3000000, now: t0.add(const Duration(seconds: 2)));
      expect(m.bytesPerSecond(now: t0.add(const Duration(seconds: 2))), closeTo(1500000, 1000));
      expect(m.bytesPerSecond(now: t0.add(const Duration(seconds: 30))), 0);
    });

    test('a new file counts from zero', () {
      final m = DownloadSpeedMeter.forTesting();
      final t0 = DateTime.utc(2026, 1, 1);
      m.record(5000, now: t0);
      m.startFile();
      m.record(2000, now: t0.add(const Duration(seconds: 1)));
      expect(m.bytesPerSecond(now: t0.add(const Duration(seconds: 1))), closeTo(7000, 1));
    });
  });

  group('StatusController', () {
    ProviderContainer make(Map<String, Probe> probes, DateTime Function() clock) {
      final c = ProviderContainer(overrides: [
        statusProbesProvider.overrideWithValue(probes),
        statusClockProvider.overrideWithValue(clock),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('runs every probe on open; one failing row does not affect others', () async {
      final at = DateTime.utc(2026, 1, 1);
      final c = make({
        StatusIds.navidrome: () async => const ProbeResult(HealthLevel.ok, '30 ms'),
        StatusIds.shuffle: () async => throw Exception('boom'),
      }, () => at);
      c.listen(statusControllerProvider, (_, _) {});
      expect(c.read(statusControllerProvider).first.level, HealthLevel.checking);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final rows = {for (final r in c.read(statusControllerProvider)) r.id: r};
      expect(rows[StatusIds.navidrome]!.level, HealthLevel.ok);
      expect(rows[StatusIds.navidrome]!.checkedAt, at);
      expect(rows[StatusIds.shuffle]!.level, HealthLevel.down);
      // No probe registered: stays unchecked rather than inventing a result.
      expect(rows[StatusIds.sync]!.checkedAt, isNull);
    });

    test('retry re-runs only that row', () async {
      var n = 0, other = 0;
      var t = DateTime.utc(2026, 1, 1);
      final c = make({
        StatusIds.navidrome: () async => ProbeResult(n++ == 0 ? HealthLevel.down : HealthLevel.ok, 'try $n'),
        StatusIds.shuffle: () async {
          other++;
          return const ProbeResult(HealthLevel.ok, '');
        },
      }, () => t);
      c.listen(statusControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      HealthRow row(String id) => c.read(statusControllerProvider).firstWhere((r) => r.id == id);
      expect(row(StatusIds.navidrome).level, HealthLevel.down);
      t = t.add(const Duration(minutes: 1));
      await c.read(statusControllerProvider.notifier).retry(StatusIds.navidrome);
      expect(row(StatusIds.navidrome).level, HealthLevel.ok);
      expect(row(StatusIds.navidrome).checkedAt, t);
      expect(other, 1);
    });
  });
}
