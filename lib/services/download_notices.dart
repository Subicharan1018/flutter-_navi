import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/hive_boxes.dart';
import '../models/song.dart';
import 'app_notifier.dart';
import 'download_queue.dart';

/// Notification ids: one slot for "finished", one for "failed", one for imports.
const downloadDoneNoticeId = 10;
const downloadFailedNoticeId = 11;
const importDoneNoticeId = 12;

class DownloadNotice {
  final int id;
  final String title;
  final String body;
  const DownloadNotice(this.id, this.title, this.body);
}

String _songs(int n) => n == 1 ? '1 song' : '$n songs';

/// What to tell the person when a stretch of downloads ends: one summary for
/// everything that arrived, and one for everything that did not.
List<DownloadNotice> downloadNotices(DownloadBatchResult r) => [
      if (r.succeeded == 1 && r.lastTitle != null && r.lastTitle!.isNotEmpty)
        DownloadNotice(downloadDoneNoticeId, 'Download finished', '${r.lastTitle} is ready offline.')
      else if (r.succeeded > 0)
        DownloadNotice(downloadDoneNoticeId, 'Downloads finished', '${_songs(r.succeeded)} downloaded.'),
      if (r.failed > 0)
        DownloadNotice(
          downloadFailedNoticeId,
          'Some downloads didn’t finish',
          '${_songs(r.failed)} couldn’t be downloaded. Open NaviVibe to try again.',
        ),
    ];

/// Posts [downloadNotices] (the notifier itself stays quiet while the app is on screen).
Future<void> postDownloadNotices(DownloadBatchResult r) async {
  for (final n in downloadNotices(r)) {
    await AppNotifier.show(NotifyChannel.downloads, id: n.id, title: n.title, body: n.body);
  }
}

/// The songs still to download, kept so a killed app can carry on.
/// Device data only; errors are swallowed (bookkeeping never breaks a download).
class PendingDownloadStore {
  const PendingDownloadStore();
  static const _key = 'pending_downloads_v1';

  Future<void> write(List<Song> songs) async {
    try {
      if (songs.isEmpty) {
        await HiveBoxes.prefs.delete(_key);
      } else {
        await HiveBoxes.prefs.put(_key, jsonEncode([for (final s in songs) s.toMap()]));
      }
    } catch (e) {
      if (e is! Error) debugPrint('[Downloads] pending list not saved: $e'); // an unopened box (tests) is not news
    }
  }

  List<Song> read() {
    try {
      final raw = HiveBoxes.prefs.get(_key);
      if (raw is! String) return const [];
      return [for (final m in jsonDecode(raw) as List) Song.fromJson(Map<String, dynamic>.from(m as Map))];
    } catch (_) {
      return const [];
    }
  }
}
