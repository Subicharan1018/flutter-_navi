import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navivibe/models/download_state.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/offline_service.dart';
import 'package:navivibe/providers/download_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/app_notifier.dart';
import 'package:navivibe/services/download_keep_alive.dart';
import 'package:navivibe/services/download_notices.dart';
import 'package:navivibe/services/subsonic_service.dart';

import '../../helpers/test_utils.dart';

class _Offline extends Mock implements OfflineService {
  final Set<String> have;
  final Completer<void>? gate;
  final List<String> cancelled = [];
  _Offline({this.have = const {}, this.gate});

  @override
  List<String> getDownloadedSongIds() => have.toList();
  @override
  Future<bool> isSongDownloadedAsync(String songId) async => have.contains(songId);
  @override
  void cancelDownload(String songId) {
    cancelled.add(songId);
    if (gate != null && !gate!.isCompleted) gate!.complete();
  }

  @override
  Future<bool> downloadSong(Song song, SubsonicService s, {void Function(double progress)? onProgress}) async {
    if (gate != null) {
      await gate!.future;
      return !cancelled.contains(song.id);
    }
    onProgress?.call(1);
    return true;
  }
}

class _Store implements PendingDownloadStore {
  List<Song> saved;
  _Store(this.saved);
  @override
  List<Song> read() => saved;
  @override
  Future<void> write(List<Song> songs) async => saved = songs;
}

class _Conn extends Mock implements Connectivity {}

class _Sub extends Mock implements SubsonicService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Conn conn;
  late List<String> keepAlive;

  setUp(() {
    conn = _Conn();
    when(() => conn.checkConnectivity()).thenAnswer((_) async => [ConnectivityResult.wifi]);
    keepAlive = [];
  });

  ProviderContainer container(_Offline offline, _Store store) {
    final c = ProviderContainer(overrides: [
      offlineServiceProvider.overrideWithValue(offline),
      subsonicServiceProvider.overrideWithValue(_Sub()),
      connectivityProvider.overrideWithValue(conn),
      downloadRetryBackoffProvider.overrideWithValue(const [Duration.zero]),
      pendingDownloadStoreProvider.overrideWithValue(store),
      downloadKeepAliveProvider.overrideWithValue(DownloadKeepAlive(
        start: (t, x, d, n) async {
          keepAlive.add('$d/$n');
          return true;
        },
        stop: () async => keepAlive.add('stop'),
        minGap: Duration.zero,
      )),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('a batch keeps the service alive while it runs and stops it at the end; the saved list ends empty', () async {
    final store = _Store([]);
    final c = container(_Offline(), store);
    await c.read(downloadStateProvider.notifier).downloadPlaylist([makeSong(id: 'a'), makeSong(id: 'b'), makeSong(id: 'c')]);
    expect(keepAlive.last, 'stop');
    expect(keepAlive.first, '0/3');
    expect(store.saved, isEmpty);
    expect(c.read(downloadStateProvider).values.map((s) => s.status), everyElement(SongDownloadStatus.downloaded));
  });

  test('songs a killed app left unfinished are queued again; finished ones are not', () async {
    final store = _Store([makeSong(id: 'a'), makeSong(id: 'b')]);
    final c = container(_Offline(have: {'a'}), store);
    final n = c.read(downloadStateProvider.notifier);
    await pumpMicrotasks();
    await n.resumePending();
    expect(n.statusOf('b'), SongDownloadStatus.downloaded);
    expect(store.saved, isEmpty);
  });

  test('cancel all (the notification Stop button): running and waiting songs return to not downloaded', () async {
    final gate = Completer<void>();
    final offline = _Offline(gate: gate);
    final c = container(offline, _Store([]));
    final n = c.read(downloadStateProvider.notifier);
    final done = n.downloadPlaylist([for (final id in ['a', 'b', 'c', 'd']) makeSong(id: id)]);
    await pumpMicrotasks();
    expect(n.statusOf('d'), SongDownloadStatus.queued);
    n.cancelAll();
    await done;
    for (final id in ['a', 'b', 'c', 'd']) {
      expect(n.statusOf(id), SongDownloadStatus.notDownloaded, reason: id);
    }
    expect(offline.cancelled, containsAll(['a', 'b']));
  });

  test('nothing is announced while the app is on screen, and something is once it is not', () async {
    final saved = AppNotifier.inForeground;
    addTearDown(() => AppNotifier.inForeground = saved);
    AppNotifier.inForeground = () => true;
    expect(await AppNotifier.show(NotifyChannel.downloads, id: downloadDoneNoticeId, title: 't', body: 'b'), isFalse);
    expect(AppNotifier.shouldShow(foreground: false, enabled: true), isTrue);
  });
}
