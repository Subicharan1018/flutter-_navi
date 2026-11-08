import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme.dart';
import '../../player/artwork.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/mini_player.dart';
import '../art/navi_icons.dart';
import 'desktop/player_bar.dart';

// =============================================================================
// mini_player_view.dart — what the window shows in mini player mode.
//
// A black ground (no cards): the cover, title and artist, a return-to-full
// button, the seek bar and previous / play / next. Dragging the cover or the
// text moves the window, since the mini window has no title bar of its own.
// =============================================================================

/// Shows [child] (the whole app) normally and the mini player while
/// [MiniPlayer.active]. The app stays mounted underneath so nothing resets.
class MiniPlayerHost extends StatelessWidget {
  final Widget child;
  final MiniPlayer? controller;
  const MiniPlayerHost({super.key, required this.child, this.controller});

  @override
  Widget build(BuildContext context) {
    final mini = controller ?? MiniPlayer.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: mini.active,
      child: child,
      builder: (context, active, app) => Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: active, child: TickerMode(enabled: !active, child: app!)),
          if (active) MiniPlayerView(onReturn: mini.exit),
        ],
      ),
    );
  }
}

class MiniPlayerView extends ConsumerWidget {
  final VoidCallback onReturn;
  const MiniPlayerView({super.key, required this.onReturn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final n = ref.read(playerProvider.notifier);
    final art = ArtSize.desktop.thumb;
    final url = song == null ? '' : ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);

    return ColoredBox(
      color: t.bgBase,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Drag(
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.thumb),
                          child: song == null
                              ? SizedBox(width: art, height: art, child: ColoredBox(color: t.textMuted.withValues(alpha: 0.2)))
                              : CoverImage(
                                  url: url,
                                  cacheKey: coverCacheKey(song),
                                  width: art,
                                  height: art,
                                  cacheWidth: (art * MediaQuery.devicePixelRatioOf(context)).round(),
                                ),
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song?.title ?? 'Nothing playing',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
                              ),
                              if (song != null) Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption1),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                BarIconButton(icon: NaviGlyph.expand, tooltip: 'Back to full player', onTap: onReturn),
              ],
            ),
            const SizedBox(height: Space.sm),
            if (song != null) DesktopSeekBar(song: song) else const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BarIconButton(icon: NaviGlyph.previous, tooltip: 'Previous', size: 20, onTap: n.playPrev),
                const SizedBox(width: Space.xs),
                BarPlayButton(playing: playing, onTap: n.togglePlay),
                const SizedBox(width: Space.xs),
                BarIconButton(icon: NaviGlyph.next, tooltip: 'Next', size: 20, onTap: n.playNext),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Drags the window, wrapped here so tests can run without window_manager.
class _Drag extends StatelessWidget {
  final Widget child;
  const _Drag({required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) {
          try {
            windowManager.startDragging();
          } catch (_) {}
        },
        child: child,
      );
}
