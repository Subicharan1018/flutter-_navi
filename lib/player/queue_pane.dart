import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/theme.dart';
import '../models/composer.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/platform_utils.dart';
import '../utils/queue_actions.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/table/song_table.dart' show SongDrag;
import '../widgets/desktop_dialogs.dart';
import '../widgets/options_menu.dart' show showSongActions;
import '../widgets/ui/action_sheet.dart';
import 'artwork.dart';
import 'edge_fade.dart';
import 'mode_buttons.dart' show smartShuffleOnProvider;
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

  const QueuePane({
    super.key,
    required this.style,
    this.showCurrent = false,
    this.onJumped,
  });

  @override
  ConsumerState<QueuePane> createState() => _QueuePaneState();
}

class _QueuePaneState extends ConsumerState<QueuePane> {
  final _anchor = GlobalKey();

  /// A History row dropped into the queue: a copy goes in at [at]; History
  /// itself is untouched.
  void _insertDropped(List<Song> songs, int at) {
    HapticFeedback.mediumImpact();
    ref.read(playerProvider.notifier).insertAllNext(songs, atIndex: at);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.style;
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final current = ref.watch(playerProvider.select((s) => s.currentIndex));
    final history = ref.watch(playerProvider.select((s) => s.history));
    final notifier = ref.read(playerProvider.notifier);
    final service = ref.read(subsonicServiceProvider);

    final upNext = current + 1 < queue.length
        ? queue.sublist(current + 1)
        : const <Song>[];
    final currentSong = current < queue.length ? queue[current] : null;

    return EdgeFade(
      top: 0.03,
      bottom: 0.08,
      child: CustomScrollView(
        center: _anchor,
        // Windows: the wheel stops at the ends, like every other list.
        physics: PlatformUtils.isDesktop
            ? const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
            : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
                return _HistoryDraggable(
                  song: song,
                  style: st,
                  child: Opacity(
                    opacity: 0.62,
                    child: _QueueRow(
                      song: song,
                      url: service.getCoverArtUrl(song.coverArt),
                      style: st,
                      songMenu: false,
                      onTap: () {
                        final idx =
                            queue.lastIndexWhere((s) => s.id == song.id);
                        idx >= 0
                            ? notifier.jumpTo(idx)
                            : notifier.setQueue([song], 0);
                        widget.onJumped?.call();
                      },
                      trailing: IconButton(
                        tooltip: 'More',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _showHistoryMenu(context, ref, song),
                        icon: NaviIcon(
                          NaviGlyph.more,
                          size: 18,
                          color: st.textMuted,
                        ),
                      ),
                    ),
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
            SliverToBoxAdapter(
              child: _DropSlot(
                queueIndex: queue.isEmpty ? 0 : current + 1,
                style: st,
                // Nothing below to drop beside: always land at the end.
                alwaysAbove: true,
                onDrop: _insertDropped,
                child: _EmptyNext(style: st),
              ),
            )
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
                          color: Colors.black.withValues(
                            alpha: 0.35 * anim.value,
                          ),
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
                notifier.reorderQueue(
                  current + 1 + oldIdx,
                  current + 1 + newIdx,
                );
              },
              itemBuilder: (context, i) {
                final song = upNext[i];
                final qIdx = current + 1 + i;
                if (PlatformUtils.isDesktop) {
                  // Desktop: grab the row anywhere to move it; the x removes it;
                  // there is no swiping.
                  return ReorderableDragStartListener(
                    key: ValueKey('q_${song.id}_$qIdx'),
                    index: i,
                    child: _DropSlot(
                      queueIndex: qIdx,
                      style: st,
                      onDrop: _insertDropped,
                      child: _QueueRow(
                        song: song,
                        url: service.getCoverArtUrl(song.coverArt),
                        style: st,
                        onTap: () {
                          notifier.jumpTo(qIdx);
                          widget.onJumped?.call();
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Remove from queue',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => notifier.removeFromQueue(qIdx),
                              icon: NaviIcon(NaviGlyph.close, size: 14, color: st.textMuted),
                            ),
                            NaviIcon(NaviGlyph.grip, color: st.textMuted, size: 18),
                            const SizedBox(width: Space.sm),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return _Swipeable(
                  // Absolute index keeps keys unique when a song repeats.
                  key: ValueKey('q_${song.id}_$qIdx'),
                  style: st,
                  onRemove: () => notifier.removeFromQueue(qIdx),
                  child: _DropSlot(
                    queueIndex: qIdx,
                    style: st,
                    onDrop: _insertDropped,
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
                            child: NaviIcon(
                              NaviGlyph.grip,
                              color: st.textMuted,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
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
    final smartShuffle = ref.watch(smartShuffleOnProvider);
    final repeat = ref.watch(playerProvider.select((s) => s.repeatMode));
    final autoplay = ref.watch(playerProvider.select((s) => s.autoplayMode));
    final smartBusy = ref.watch(smartReshuffleBusyProvider);
    final n = ref.read(playerProvider.notifier);

    // iOS 26's queue controls: four equal icon buttons. Shuffle is the local
    // random toggle; the last button is Smart Reshuffle — an action that asks
    // the server for a fresh Up Next, so it never shows as "on".
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _Pill(
              glyph: smartShuffle ? NaviGlyph.smartShuffle : NaviGlyph.shuffle,
              label: smartShuffle ? 'Smart Shuffle' : 'Shuffle',
              active: shuffle,
              style: st,
              onTap: n.toggleShuffle,
              onLongPress: () => _showShuffleModes(context, ref),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Pill(
              glyph: NaviGlyph.repeat,
              badge: repeat == LoopMode.one ? '1' : null,
              label: switch (repeat) {
                LoopMode.one => 'Repeat this song',
                LoopMode.all => 'Repeat queue',
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
              glyph: NaviGlyph.infinite,
              label: 'Autoplay',
              active: autoplay,
              style: st,
              onTap: n.toggleAutoplay,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Pill(
              glyph: NaviGlyph.smartShuffle,
              label: 'Smart Reshuffle',
              active: false,
              toggle: false,
              busy: smartBusy,
              style: st,
              onTap: () => runSmartReshuffle(context, ref),
              onLongPress: () => _showShuffleModes(context, ref),
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

  /// The styles offered here; the full list lives in Settings. Whatever is
  /// selected is always shown, so the checkmark is never missing.
  static const _quick = [
    ShuffleAlgorithm.standard,
    ShuffleAlgorithm.spotify,
    ShuffleAlgorithm.youtube,
    ShuffleAlgorithm.smartLocal,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final current = ref.watch(
      settingsProvider.select((s) => s.shuffleAlgorithm),
    );
    final shuffleOn = ref.watch(playerProvider.select((s) => s.shuffleMode));
    final modes = [..._quick, if (!_quick.contains(current)) current];
    // The sheet closes before an action runs; act through the page's ref.
    final player = parentRef.read(playerProvider.notifier);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetGroup(
            children: [
              SheetAction(
                label: shuffleOn ? 'Shuffle Up Next Again' : 'Shuffle Up Next',
                detail: 'Random order',
                icon: NaviGlyph.shuffle,
                onTap: player.applyShuffleAlgorithm,
              ),
              SheetAction(
                label: 'Smart Reshuffle',
                detail: 'Fresh picks for right now',
                icon: NaviGlyph.smartShuffle,
                onTap: () => runSmartReshuffle(context, parentRef),
              ),
            ],
          ),
          SheetGroup(
            children: [
              for (final algo in modes)
                SheetAction(
                  label: algo.label,
                  detail: algo.summary,
                  trailing: SizedBox(
                    width: 22,
                    child: algo == current
                        ? NaviIcon(NaviGlyph.check, size: 20, color: t.accent)
                        : null,
                  ),
                  onTap: () async {
                    parentRef
                        .read(settingsProvider.notifier)
                        .setShuffleAlgorithm(algo);
                    if (shuffleOn) await player.applyShuffleAlgorithm();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  /// One of NaviVibe's own glyphs.
  final NaviGlyph glyph;

  /// Small mark on the glyph (the "1" of repeat-one).
  final String? badge;
  final String label;
  final bool active;
  final NowPlayingStyle style;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// False for one-shot actions (no on/off state to announce).
  final bool toggle;

  /// Shows a spinner and ignores taps while the action runs.
  final bool busy;

  const _Pill({
    required this.glyph,
    this.badge,
    required this.label,
    required this.active,
    required this.style,
    required this.onTap,
    this.onLongPress,
    this.toggle = true,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    // A bare icon, not a boxed tile (DESIGN.md: no card containers). On: full
    // strength with a dot under it; off: dimmed with no dot. The whole
    // equal-width cell stays tappable.
    final on = active && toggle;
    final fg = on
        ? style.textPrimary
        : style.textPrimary.withValues(alpha: 0.6);
    return CupertinoClickable(
      semanticLabel: busy
          ? '$label, working'
          : (toggle ? '$label ${active ? 'on' : 'off'}' : label),
      onTap: () {
        if (busy) return;
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: onLongPress,
      child: SizedBox(
        height: 48,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: busy
                ? SizedBox(
                    key: const ValueKey('busy'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Column(
                    key: ValueKey(badge),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          NaviIcon(glyph, size: 22, color: fg),
                          if (badge != null)
                            Positioned(
                              right: -5,
                              top: -4,
                              child: Text(
                                badge!,
                                style: naviText(10, FontWeight.w800, fg),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? fg : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Runs a Smart Reshuffle and tells the listener when it couldn't be smart.
/// Safe to call repeatedly: taps while one is running join it.
Future<void> runSmartReshuffle(BuildContext context, WidgetRef ref) async {
  final outcome = await ref.read(playerProvider.notifier).smartReshuffle();
  if (!context.mounted) return;
  switch (outcome) {
    case ReshuffleOutcome.random:
      showToast(context, 'Smart Shuffle is unavailable — shuffled randomly');
    case ReshuffleOutcome.nothingToShuffle:
      showToast(context, 'Nothing else to shuffle');
    case ReshuffleOutcome.smart:
    case ReshuffleOutcome.superseded:
      break;
  }
}

// ── History → queue drag ──────────────────────────────────────────────────────

void _showHistoryMenu(BuildContext context, WidgetRef ref, Song song) {
  showPlatformSheet(
    context: context,
    title: song.title,
    menu: true,
    builder: (_) => SheetGroup(
      children: [
        SheetAction(
          label: 'Play Next',
          icon: NaviGlyph.playNext,
          onTap: () => queueSongs(context, ref, [song], next: true),
        ),
        SheetAction(
          label: 'Add to Queue',
          icon: NaviGlyph.queue,
          onTap: () => queueSongs(context, ref, [song], next: false),
        ),
      ],
    ),
  );
}

/// Makes a History row draggable into the queue: a mouse drag on desktop and
/// web, a long-press on touch (a plain drag there scrolls the list).
class _HistoryDraggable extends StatelessWidget {
  final Song song;
  final NowPlayingStyle style;
  final Widget child;
  const _HistoryDraggable({
    required this.song,
    required this.style,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final data = SongDrag([song], const [], null);
    final feedback = Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(left: 12, top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: style.rowLifted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: naviText(14, FontWeight.w600, style.textPrimary),
        ),
      ),
    );
    final dragging = Opacity(opacity: 0.4, child: child);
    if (PlatformUtils.isDesktop) {
      return Draggable<SongDrag>(
        data: data,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        maxSimultaneousDrags: 1,
        feedback: feedback,
        childWhenDragging: dragging,
        child: child,
      );
    }
    return LongPressDraggable<SongDrag>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      maxSimultaneousDrags: 1,
      onDragStarted: HapticFeedback.mediumImpact,
      feedback: feedback,
      childWhenDragging: dragging,
      child: child,
    );
  }
}

/// Drop target around one Up Next row. Shows a line above or below the row
/// (by which half the pointer is over) and reports where the songs land.
class _DropSlot extends StatefulWidget {
  /// Absolute queue index of the row this wraps.
  final int queueIndex;
  final NowPlayingStyle style;
  final Widget child;
  final void Function(List<Song> songs, int at) onDrop;

  /// Always land before [queueIndex], with the line on top.
  final bool alwaysAbove;

  const _DropSlot({
    required this.queueIndex,
    required this.style,
    required this.child,
    required this.onDrop,
    this.alwaysAbove = false,
  });

  @override
  State<_DropSlot> createState() => _DropSlotState();
}

class _DropSlotState extends State<_DropSlot> {
  /// null: nothing hovering. true: line under the row. false: line above.
  bool? _below;

  @override
  Widget build(BuildContext context) {
    return DragTarget<SongDrag>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (d) {
        if (widget.alwaysAbove) {
          if (_below != false) setState(() => _below = false);
          return;
        }
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final below = box.globalToLocal(d.offset).dy > box.size.height / 2;
        if (_below != below) {
          if (_below != null) HapticFeedback.selectionClick();
          setState(() => _below = below);
        }
      },
      onLeave: (_) => setState(() => _below = null),
      onAcceptWithDetails: (d) {
        final below = _below ?? false;
        setState(() => _below = null);
        widget.onDrop(d.data.songs, widget.queueIndex + (below ? 1 : 0));
      },
      builder: (context, _, _) {
        final below = _below;
        if (below == null) return widget.child;
        return Stack(
          children: [
            widget.child,
            Positioned(
              left: 16,
              right: 16,
              top: below ? null : 0,
              bottom: below ? 0 : null,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('queue_drop_line'),
                  height: 2,
                  color: widget.style.accent,
                ),
              ),
            ),
          ],
        );
      },
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

  /// Long-press (touch) or right-click opens the song menu (with "Not this mood"
  /// while Flow plays a mood). Off for History rows, where a long-press drags.
  final bool songMenu;

  const _QueueRow({
    required this.song,
    required this.url,
    required this.style,
    this.onTap,
    this.trailing,
    this.isCurrent = false,
    this.songMenu = true,
  });

  void _openMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showSongActions(context, song);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: songMenu ? () => _openMenu(context) : null,
      onSecondaryTap: songMenu ? () => _openMenu(context) : null,
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
                    songCreditLine(composer: song.composer, artist: song.artist),
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

  const _Swipeable({
    super.key,
    required this.child,
    required this.onRemove,
    required this.style,
  });

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
        color: AppThemeTokens
            .systemRed, // destructive: the one hue kept in monochrome
        child: const NaviIcon(NaviGlyph.minusCircle, color: Colors.white),
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

  const _SectionHeader({
    required this.title,
    required this.style,
    this.subtitle,
    this.trailing,
  });

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
            Text(
              subtitle!,
              style: naviText(13, FontWeight.w500, style.textMuted),
            ),
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
  const _TextAction({
    required this.label,
    required this.onTap,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: style.textSecondary,
        minimumSize: const Size(48, 40),
      ),
      child: Text(
        label,
        style: naviText(14, FontWeight.w600, style.textSecondary),
      ),
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
        style: naviText(
          14,
          FontWeight.w500,
          style.textSecondary,
        ).copyWith(height: 1.45),
      ),
    );
  }
}
