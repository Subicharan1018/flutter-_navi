import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/theme.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/desktop_dialogs.dart';
import '../widgets/ui/action_sheet.dart';
import 'artwork.dart';
import 'edge_fade.dart';
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

    return EdgeFade(
      top: 0.03,
      bottom: 0.08,
      child: CustomScrollView(
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
                        child: Icon(CupertinoIcons.line_horizontal_3, color: st.textMuted, size: 22),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
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
              icon: CupertinoIcons.shuffle,
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
              icon: repeat == LoopMode.one ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat,
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
              icon: CupertinoIcons.infinite,
              label: 'Autoplay',
              active: autoplay,
              style: st,
              onTap: n.toggleAutoplay,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Pill(
              icon: CupertinoIcons.sparkles,
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
    final current = ref.watch(settingsProvider.select((s) => s.shuffleAlgorithm));
    final shuffleOn = ref.watch(playerProvider.select((s) => s.shuffleMode));
    final modes = [..._quick, if (!_quick.contains(current)) current];
    // The sheet closes before an action runs; act through the page's ref.
    final player = parentRef.read(playerProvider.notifier);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetGroup(children: [
            SheetAction(
              label: shuffleOn ? 'Shuffle Up Next Again' : 'Shuffle Up Next',
              detail: 'Random order',
              icon: CupertinoIcons.shuffle,
              onTap: player.applyShuffleAlgorithm,
            ),
            SheetAction(
              label: 'Smart Reshuffle',
              detail: 'Fresh picks for right now',
              icon: CupertinoIcons.sparkles,
              onTap: () => runSmartReshuffle(context, parentRef),
            ),
          ]),
          SheetGroup(children: [
            for (final algo in modes)
              SheetAction(
                label: algo.label,
                detail: algo.summary,
                trailing: SizedBox(
                  width: 22,
                  child: algo == current ? Icon(CupertinoIcons.checkmark_alt, size: 20, color: t.accent) : null,
                ),
                onTap: () async {
                  parentRef.read(settingsProvider.notifier).setShuffleAlgorithm(algo);
                  if (shuffleOn) await player.applyShuffleAlgorithm();
                },
              ),
          ]),
        ],
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

  /// False for one-shot actions (no on/off state to announce).
  final bool toggle;

  /// Shows a spinner and ignores taps while the action runs.
  final bool busy;

  const _Pill({
    required this.icon,
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
    final fg = active ? style.pillOnActive : style.textPrimary;
    return CupertinoClickable(
      semanticLabel: busy ? '$label, working' : (toggle ? '$label ${active ? 'on' : 'off'}' : label),
      onTap: () {
        if (busy) return;
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 44,
        decoration: BoxDecoration(
          color: active ? style.pillActive : style.pillIdle,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: busy
              ? SizedBox(
                  key: const ValueKey('busy'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Icon(icon, key: const ValueKey('icon'), size: 20, color: fg),
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
        child: const Icon(CupertinoIcons.minus_circle, color: Colors.white),
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
