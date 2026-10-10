import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/download_state.dart';
import '../../models/song.dart';
import '../../providers/download_provider.dart';
import '../../utils/format.dart';
import 'media.dart';

/// "12 songs, 48 minutes" under the last track, as Apple Music closes lists.
class CollectionSummary extends StatelessWidget {
  final List<Song> songs;
  final String? extra;
  const CollectionSummary({super.key, required this.songs, this.extra});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final seconds = songs.fold<int>(0, (sum, s) => sum + s.duration);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
      child: Text(
        [?extra, '${songCount(songs.length)}, ${formatLongDuration(seconds)}'].join('\n'),
        style: t.footnote,
      ),
    );
  }
}

/// Download state of a set of songs, derived once per rebuild.
class CollectionDownloadProgress {
  final int done;
  final int active;
  final int total;
  const CollectionDownloadProgress(this.done, this.active, this.total);

  bool get allDone => total > 0 && done == total;
  bool get running => active > 0;
  double get fraction => total == 0 ? 0 : (done + active / 2) / total;

  factory CollectionDownloadProgress.of(List<Song> songs, Map<String, SongDownloadState> dl) {
    var done = 0, active = 0;
    for (final s in songs) {
      final st = dl[s.id]?.status;
      if (st == SongDownloadStatus.downloaded) {
        done++;
      } else if (st == SongDownloadStatus.queued || st == SongDownloadStatus.downloading) {
        active++;
      }
    }
    return CollectionDownloadProgress(done, active, songs.length);
  }
}

/// Round download control for the transport row: arrow → progress ring →
/// filled check once every song is on the device.
class CollectionDownloadButton extends ConsumerWidget {
  final List<Song> songs;
  const CollectionDownloadButton({super.key, required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final p = CollectionDownloadProgress.of(songs, ref.watch(downloadStateProvider));
    if (p.running) {
      return CircleIconButton(
        icon: CupertinoIcons.arrow_down,
        label: 'Downloading ${p.done} of ${p.total}',
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            value: p.fraction > 0 ? p.fraction : null,
            strokeWidth: 2.4,
            color: t.textPrimary,
            backgroundColor: t.fill,
          ),
        ),
      );
    }
    if (p.allDone) {
      return const CircleIconButton(icon: CupertinoIcons.checkmark_alt, label: 'Downloaded');
    }
    return CircleIconButton(
      icon: CupertinoIcons.arrow_down,
      label: 'Download',
      onTap: p.total == 0 ? null : () => ref.read(downloadStateProvider.notifier).downloadPlaylist(songs),
    );
  }
}
