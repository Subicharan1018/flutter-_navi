import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/theme.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/desktop_dialogs.dart';
import 'artwork.dart';
import 'now_playing_style.dart';

/// Queue and history in one scroll: history lives ABOVE the anchor (scroll
/// up to see what played), "Playing Next" sits at the top of the viewport
/// with Shuffle / Repeat / Autoplay pills. Rows reorder by their handle and
/// leave with a swipe.
class QueuePane extends ConsumerStatefulWidget {
  final NowPlayingStyle style;

  /// Show the current song as the first row (desktop side panel). Now
  /// Playing already shows it in its header.
  final bool showCurrent;

  /// Called after a row tap jumps playback (e.g. to collapse a sheet).
  final VoidCallback? onJumped;

  const QueuePane({super.key, required this.style, this.showCurrent = false, this.onJumped});

  @override
  ConsumerState<QueuePane> createState() => _QueuePaneState();
}

class _QueuePaneState extends ConsumerState<QueuePane> {
  final _anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final st = widget.style;
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final current = ref.watch(playerProvider.select((s) => s.currentIndex));
    final history = ref.watch(playerProvider.select((s) => s.history));
    final notifier = ref.read(playerProvider.notifier);
    final service = ref.read(subsonicServiceProvider);

    final upNext = current + 1 < queue.length ? queue.sublist(current + 1) : const <Song>[];
    final currentSong = current < queue.length ? queue[current] : null;

    return CustomScrollView(
      center: _anchor,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        // ── History (laid out upward from the anchor) ─────────────────────
        if (history.isNotEmpty)
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'History',
              style: st,
              trailing: _TextAction(
                label: 'Clear',
                style: st,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  notifier.clearHistory();
                },
              ),
            ),
          ),
        if (history.isNotEmpty)
          SliverList.builder(
            itemCount: history.length,
            itemBuilder: (context, i) {
              // i == 0 is directly above the anchor → most recent first.
              final song = history[history.length - 1 - i];
              return Opacity(
                opacity: 0.62,
                child: _QueueRow(
                  song: song,
                  url: service.getCoverArtUrl(song.coverArt),
                  style: st,
                  onTap: () {
                    final idx = queue.lastIndexWhere((s) => s.id == song.id);
                    idx >= 0 ? notifier.jumpTo(idx) : notifier.setQueue([song], 0);
                    widget.onJumped?.call();
                  },
                ),
              );
            },
          ),

        // ── Anchor: Playing Next header + mode pills ──────────────────────
        SliverToBoxAdapter(
          key: _anchor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showCurrent && currentSong != null) ...[
                _SectionHeader(title: 'Now Playing', style: st),
                _QueueRow(
                  song: currentSong,
                  url: service.getCoverArtUrl(currentSong.coverArt),
                  style: st,
                  isCurrent: true,
                ),
              ],
              _SectionHeader(
                title: 'Playing Next',
                style: st,
                subtitle: upNext.isEmpty
                    ? null
                    : '${upNext.length} ${upNext.length == 1 ? 'song' : 'songs'}',
              ),
              const _ModePills(),
              const SizedBox(height: 6),
            ],
          ),
        ),

        // ── Up next ────────────────────────────────────────────────────────
        if (upNext.isEmpty)
          SliverToBoxAdapter(child: _EmptyNext(style: st))
        else
          SliverReorderableList(
            itemCount: upNext.length,
            proxyDecorator: (child, index, anim) => AnimatedBuilder(
              animation: anim,
              builder: (context, c) => Material(
                color: Colors.transparent,
                elevation: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: st.rowLifted.withValues(alpha: 0.92 * anim.value),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35 * anim.value),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: c,
                ),
              ),
              child: child,
            ),
            // onReorderItem already reports the post-removal index that
            // reorderQueue expects.
            onReorderItem: (oldIdx, newIdx) {
              if (newIdx == oldIdx) return;
              HapticFeedback.selectionClick();
              notifier.reorderQueue(current + 1 + oldIdx, current + 1 + newIdx);
            },
            itemBuilder: (context, i) {
              final song = upNext[i];
              final qIdx = current + 1 + i;
              return _Swipeable(
                // Absolute index keeps keys unique when a song repeats.
                key: ValueKey('q_${song.id}_$qIdx'),
                style: st,
                onRemove: () => notifier.removeFromQueue(qIdx),
                child: _QueueRow(
                  song: song,
                  url: service.getCoverArtUrl(song.coverArt),
                  style: st,
                  onTap: () {
                    notifier.jumpTo(qIdx);
                    widget.onJumped?.call();
                  },
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Semantics(
                      label: 'Reorder ${song.title}',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.drag_handle_rounded, color: st.textMuted, size: 22),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }
}

// ── Mode pills ────────────────────────────────────────────────────────────────

class _ModePills extends ConsumerWidget {
  const _ModePills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = NowPlayingStyle.of(context);
    final shuffle = ref.watch(playerProvider.select((s) => s.shuffleMode));
    final repeat = ref.watch(playerProvider.select((s) => s.repeatMode));
    final autoplay = ref.watch(playerProvider.select((s) => s.autoplayMode));
    final n = ref.read(playerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _Pill(
              icon: Icons.shuffle_rounded,
              label: 'Shuffle',
              active: shuffle,
              style: st,
              onTap: n.toggleShuffle,
              onLongPress: () => _showShuffleModes(context, ref),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Pill(
              icon: repeat == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              label: switch (repeat) {
                LoopMode.one => 'Repeat 1',
                LoopMode.all => 'Repeat',
                LoopMode.off => 'Repeat',
              },
              active: repeat != LoopMode.off,
              style: st,
              onTap: n.cycleRepeat,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Pill(
              icon: Icons.all_inclusive_rounded,
              label: 'Autoplay',
              active: autoplay,
              style: st,
              onTap: n.toggleAutoplay,
            ),
          ),
        ],
      ),
    );
  }
}

void _showShuffleModes(BuildContext context, WidgetRef ref) {
  HapticFeedback.mediumImpact();
  showPlatformSheet(
    context: context,
    title: 'Shuffle',
    builder: (ctx) => _ShuffleModeSheet(parentRef: ref),
  );
}

class _ShuffleModeSheet extends ConsumerWidget {
  final WidgetRef parentRef;
  const _ShuffleModeSheet({required this.parentRef});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final current = ref.watch(settingsProvider.select((s) => s.shuffleAlgorithm));
    final shuffleOn = ref.watch(playerProvider.select((s) => s.shuffleMode));
    final modes = <(ShuffleAlgorithm, IconData, String, String)>[
      (ShuffleAlgorithm.standard, Icons.shuffle_rounded, 'Random', 'Every song equally likely.'),
      (ShuffleAlgorithm.spotify, Icons.auto_awesome_rounded, 'Balanced',
          'Spreads out songs by the same artist.'),
      (ShuffleAlgorithm.youtube, Icons.trending_up_rounded, 'Favourites first',
          'Leans toward starred and most-played songs.'),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text('Shuffle style', style: naviText(20, FontWeight.w700, t.textPrimary)),
            ),
            for (final (algo, icon, title, sub) in modes)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(icon, color: algo == current ? t.accent : t.textSecondary),
                title: Text(title),
                subtitle: Text(sub),
                trailing: algo == current ? Icon(Icons.check_rounded, color: t.accent) : null,
                onTap: () async {
                  ref.read(settingsProvider.notifier).setShuffleAlgorithm(algo);
                  if (shuffleOn) await ref.read(playerProvider.notifier).applyShuffleAlgorithm();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            if (shuffleOn) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reshuffle what plays next'),
                  onPressed: () async {
                    Navigator.pop(context);
                    final all = await ref.read(allSongsProvider.future);
                    await ref.read(playerProvider.notifier).reshuffleActiveQueue(all);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final NowPlayingStyle style;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _Pill({
    required this.icon,
    required this.label,
    required this.active,
    required this.style,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? style.pillOnActive : style.textPrimary;
    return CupertinoClickable(
      semanticLabel: '$label ${active ? 'on' : 'off'}',
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 40,
        decoration: BoxDecoration(
          color: active ? style.pillActive : style.pillIdle,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: naviText(13.5, FontWeight.w600, fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rows ──────────────────────────────────────────────────────────────────────

class _QueueRow extends StatelessWidget {
  final Song song;
  final String url;
  final NowPlayingStyle style;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool isCurrent;

  const _QueueRow({
    required this.song,
    required this.url,
    required this.style,
    this.onTap,
    this.trailing,
    this.isCurrent = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, trailing == null ? 16 : 4, 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CoverImage(
                url: url,
                cacheKey: coverCacheKey(song),
                width: 48,
                height: 48,
                cacheWidth: 144,
                placeholderColor: style.rowLifted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: naviText(
                      15,
                      FontWeight.w600,
                      isCurrent ? style.accent : style.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: naviText(13, FontWeight.w400, style.textSecondary),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _Swipeable extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  final NowPlayingStyle style;

  const _Swipeable({super.key, required this.child, required this.onRemove, required this.style});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismiss_${(key as ValueKey).value}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        onRemove();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: const Color(0xFFE5484D),
        child: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final NowPlayingStyle style;

  const _SectionHeader({required this.title, required this.style, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: naviText(19, FontWeight.w700, style.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(subtitle!, style: naviText(13, FontWeight.w500, style.textMuted)),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final NowPlayingStyle style;
  const _TextAction({required this.label, required this.onTap, required this.style});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(foregroundColor: style.textSecondary, minimumSize: const Size(48, 40)),
      child: Text(label, style: naviText(14, FontWeight.w600, style.textSecondary)),
    );
  }
}

class _EmptyNext extends ConsumerWidget {
  final NowPlayingStyle style;
  const _EmptyNext({required this.style});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoplay = ref.watch(playerProvider.select((s) => s.autoplayMode));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
      child: Text(
        autoplay
            ? 'Nothing queued. Autoplay will keep the music going with songs like this one.'
            : 'Nothing queued. Turn on Autoplay to keep the music going when this song ends.',
        style: naviText(14, FontWeight.w500, style.textSecondary).copyWith(height: 1.45),
      ),
    );
  }
}
