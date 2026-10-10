import 'dart:math' show min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/download_state.dart';
import '../../models/song.dart';
import '../../providers/download_provider.dart';
import '../../utils/format.dart';
import '../cover_art.dart';
import 'detail_page.dart';
import 'media.dart';

/// Apple Music's album/playlist header. On phones: centred artwork, title,
/// the artist (or owner) in the accent, a quiet detail line, Play/Shuffle.
/// On wide windows the same pieces sit beside the artwork.
class CollectionHero extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSubtitleTap;
  final String? detail;
  final String? description;
  final String? artUrl;
  final Widget? art;
  final IconData placeholderIcon;
  final bool circularArt;
  final bool playing;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  const CollectionHero({
    super.key,
    required this.title,
    this.subtitle,
    this.onSubtitleTap,
    this.detail,
    this.description,
    this.artUrl,
    this.art,
    this.placeholderIcon = CupertinoIcons.music_albums,
    this.circularArt = false,
    this.playing = false,
    this.onPlay,
    this.onShuffle,
  });

  /// Offset at which the hero title has scrolled under the bar; pass to
  /// [DetailPage.revealAt].
  static double revealOffset(BuildContext context) =>
      _wide(context) ? 200 : _artSize(context) + Space.xxl;

  static bool _wide(BuildContext context) => MediaQuery.sizeOf(context).width >= 720;
  static double _artSize(BuildContext context) => min(MediaQuery.sizeOf(context).width - 2 * 64, 300);

  Widget _art(double size) => DecoratedBox(
        decoration: BoxDecoration(
          shape: circularArt ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circularArt ? null : BorderRadius.circular(Radii.hero),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 12))],
        ),
        child: art ??
            CoverArt(
              url: artUrl,
              size: size,
              radius: Radii.hero,
              circular: circularArt,
              placeholderIcon: placeholderIcon,
            ),
      );

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final wide = _wide(context);
    final align = wide ? TextAlign.start : TextAlign.center;

    final sub = subtitle == null || subtitle!.isEmpty
        ? null
        : CupertinoClickable(
            onTap: onSubtitleTap,
            scaleFactor: 0.98,
            child: Text(
              subtitle!,
              textAlign: align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.title3.copyWith(color: t.accent, fontWeight: FontWeight.w400),
            ),
          );

    final text = <Widget>[
      Text(
        title,
        textAlign: align,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: wide ? t.title1 : t.title2,
      ),
      if (sub != null) ...[const SizedBox(height: Space.xxs), sub],
      if (detail != null && detail!.isNotEmpty) ...[
        const SizedBox(height: Space.xs),
        Text(detail!, textAlign: align, style: t.footnote),
      ],
    ];

    final buttons = PlayShuffleButtons(onPlay: onPlay, onShuffle: onShuffle, playing: playing);
    final about = description == null || description!.isEmpty
        ? null
        : Text(description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.subheadline);

    if (wide) {
      return Padding(
        // DetailPage already insets wide pages by Space.lg.
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xxl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _art(240),
            const SizedBox(width: Space.xxxl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...text,
                  if (about != null) ...[const SizedBox(height: Space.md), about],
                  const SizedBox(height: Space.xl),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: buttons),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.lg),
      child: Column(
        children: [
          _art(_artSize(context)),
          const SizedBox(height: Space.xl),
          ...text,
          const SizedBox(height: Space.lg),
          buttons,
          if (about != null) ...[
            const SizedBox(height: Space.lg),
            Align(alignment: Alignment.centerLeft, child: about),
          ],
        ],
      ),
    );
  }
}

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

/// Bar button that downloads a whole collection, then shows its progress
/// ring and finally a filled glyph once everything is on the device.
class CollectionDownloadButton extends ConsumerWidget {
  final List<Song> songs;
  const CollectionDownloadButton({super.key, required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final p = CollectionDownloadProgress.of(songs, ref.watch(downloadStateProvider));
    if (p.running) {
      return BarButton(
        icon: CupertinoIcons.arrow_down_circle,
        label: 'Downloading ${p.done} of ${p.total}',
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: p.fraction > 0 ? p.fraction : null,
            strokeWidth: 2.2,
            color: t.accent,
            backgroundColor: t.fill,
          ),
        ),
      );
    }
    return BarButton(
      icon: p.allDone ? CupertinoIcons.arrow_down_circle_fill : CupertinoIcons.arrow_down_circle,
      label: p.allDone ? 'Downloaded' : 'Download',
      onTap: p.allDone || p.total == 0
          ? null
          : () => ref.read(downloadStateProvider.notifier).downloadPlaylist(songs),
    );
  }
}
