import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/focus/navi_focus.dart';
import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../player/artwork.dart';
import '../../../player/playback_progress.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../screens/now_playing_screen.dart';
import '../../../player/player_controls.dart' show formatClock;
import '../../art/navi_icons.dart';
import '../shortcuts_help.dart';
import 'now_playing_panel.dart';

// =============================================================================
// player_bar.dart — the Windows player bar: three zones, desktop-sized.
//
// Left: the song (cover, title, artist, favorite). Middle: transport (shuffle,
// previous, play, next, repeat) with the time on either side of the seek bar,
// which previews the time under the pointer. Right: Lyrics, Queue, About, a
// volume control (mute button, wheel to change) and the full-screen player.
// =============================================================================

class DesktopPlayerBar extends ConsumerWidget {
  final PanelKind? panel;
  final ValueChanged<PanelKind> onTogglePanel;

  /// A very narrow window: no panel buttons, a shorter volume bar.
  final bool compact;
  const DesktopPlayerBar({super.key, required this.panel, required this.onTogglePanel, this.compact = false});

  static const double height = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final starred = ref.watch(playerProvider.select((s) => s.starredIds.contains(song.id)));
    final shuffle = ref.watch(playerProvider.select((s) => s.shuffleMode));
    final repeat = ref.watch(playerProvider.select((s) => s.repeatMode));
    final n = ref.read(playerProvider.notifier);
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(
        color: t.bgSurface,
        border: Border(top: BorderSide(color: t.separatorOpaque, width: 0.5)),
      ),
      child: Row(
        children: [
          // ── Left: the song ──────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Tooltip(
                  message: 'Open the full-screen player',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => openNowPlaying(context),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.thumb),
                        child: CoverImage(
                          url: url,
                          cacheKey: coverCacheKey(song),
                          width: 48,
                          height: 48,
                          cacheWidth: 144,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
                      ),
                      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption1),
                    ],
                  ),
                ),
                BarIconButton(
                  icon: NaviGlyph.star,
                  filled: starred,
                  tooltip: starred ? 'Remove from Favorites (L)' : 'Favorite (L)',
                  active: starred,
                  onTap: () => n.toggleStar(song.id),
                ),
              ],
            ),
          ),
          // ── Middle: transport and seek ──────────────────────────────────
          Expanded(
            flex: 5,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        BarIconButton(icon: NaviGlyph.shuffle, tooltip: 'Shuffle (S)', active: shuffle, onTap: n.toggleShuffle),
                        BarIconButton(icon: NaviGlyph.previous, tooltip: 'Previous (Ctrl+←)', size: 18, onTap: n.playPrev),
                        const SizedBox(width: Space.xs),
                        _PlayButton(playing: playing, onTap: n.togglePlay),
                        const SizedBox(width: Space.xs),
                        BarIconButton(icon: NaviGlyph.next, tooltip: 'Next (Ctrl+→)', size: 18, onTap: n.playNext),
                        BarIconButton(
                          icon: repeat == LoopMode.one ? NaviGlyph.repeatOne : NaviGlyph.repeat,
                          tooltip: switch (repeat) {
                            LoopMode.off => 'Repeat (R)',
                            LoopMode.all => 'Repeat queue (R)',
                            LoopMode.one => 'Repeat this song (R)',
                          },
                          active: repeat != LoopMode.off,
                          onTap: n.cycleRepeat,
                        ),
                      ],
                    ),
                    DesktopSeekBar(song: song),
                  ],
                ),
              ),
            ),
          ),
          // ── Right: panels, volume ───────────────────────────────────────
          Expanded(
            flex: 3,
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 300;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!compact) ...[
                      BarIconButton(
                        icon: NaviGlyph.lyrics,
                        tooltip: 'Lyrics',
                        active: panel == PanelKind.lyrics,
                        onTap: () => onTogglePanel(PanelKind.lyrics),
                      ),
                      BarIconButton(
                        icon: NaviGlyph.queue,
                        tooltip: 'Queue',
                        active: panel == PanelKind.queue,
                        onTap: () => onTogglePanel(PanelKind.queue),
                      ),
                      if (!narrow)
                        BarIconButton(
                          icon: NaviGlyph.info,
                          tooltip: 'About this song',
                          active: panel == PanelKind.about,
                          onTap: () => onTogglePanel(PanelKind.about),
                        ),
                    ],
                    if (c.maxWidth >= 200)
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: compact || narrow ? 110 : 140),
                          child: DesktopVolume(player: n.player),
                        ),
                      ),
                    if (!narrow) const KeyboardHelpButton(),
                    BarIconButton(
                      icon: NaviGlyph.expand,
                      tooltip: 'Full-screen player',
                      size: 15,
                      onTap: () => openNowPlaying(context),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A bar glyph: 32 wide, a wash on hover, a tooltip, white when [active].
class BarIconButton extends StatefulWidget {
  final NaviGlyph icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool filled;
  final double size;
  const BarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.filled = false,
    this.size = 16,
  });

  @override
  State<BarIconButton> createState() => _BarIconButtonState();
}

class _BarIconButtonState extends State<BarIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final color = widget.active ? t.accent : (_hover ? t.textPrimary : t.textSecondary);
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: NaviPressable(
            onTap: widget.onTap,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  NaviIcon(widget.icon, size: widget.size, color: color, filled: widget.filled),
                  // A dot under an active toggle, so on/off is not colour alone.
                  if (widget.active && widget.icon != NaviGlyph.star)
                    Positioned(
                      bottom: 1,
                      child: Container(width: 3, height: 3, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatefulWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayButton({required this.playing, required this.onTap});

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: widget.playing ? 'Pause' : 'Play',
      child: Tooltip(
        message: widget.playing ? 'Pause (Space)' : 'Play (Space)',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: NaviPressable(
            onTap: widget.onTap,
            radius: 17,
            child: AnimatedScale(
              scale: _hover ? 1.06 : 1,
              duration: const Duration(milliseconds: 100),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: NaviIcon(widget.playing ? NaviGlyph.pause : NaviGlyph.play, size: 16, filled: true, color: t.onAccent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Seek ─────────────────────────────────────────────────────────────────────

/// Elapsed · bar · total. The bar thickens on hover and a bubble above it names
/// the time under the pointer; click or drag to seek.
class DesktopSeekBar extends ConsumerStatefulWidget {
  final Song song;
  const DesktopSeekBar({super.key, required this.song});

  @override
  ConsumerState<DesktopSeekBar> createState() => _DesktopSeekBarState();
}

class _DesktopSeekBarState extends ConsumerState<DesktopSeekBar> {
  double? _drag;
  double? _hover; // 0..1 along the bar

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final player = ref.read(playerProvider.notifier).player;
    final label = t.caption1.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return RepaintBoundary(
      child: PlaybackProgressBuilder(
        player: player,
        song: widget.song,
        builder: (context, progress) {
          final total = progress.total.inMilliseconds;
          final f = (_drag ?? progress.fraction).clamp(0.0, 1.0);
          final shown = _hover ?? _drag;
          return Row(
            children: [
              SizedBox(width: 40, child: Text(formatClock(Duration(milliseconds: (f * total).round())), textAlign: TextAlign.right, style: label)),
              const SizedBox(width: Space.sm),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    double at(Offset local) => (local.dx / c.maxWidth).clamp(0.0, 1.0);
                    final hovering = _hover != null || _drag != null;
                    return Semantics(
                      slider: true,
                      label: 'Playback position',
                      value: formatClock(Duration(milliseconds: (f * total).round())),
                      increasedValue: formatClock(Duration(milliseconds: (total * (f + 0.02).clamp(0.0, 1.0)).round())),
                      decreasedValue: formatClock(Duration(milliseconds: (total * (f - 0.02).clamp(0.0, 1.0)).round())),
                      onIncrease: () => progress.seekTo(player, Duration(milliseconds: (total * (f + 0.02)).round().clamp(0, total))),
                      onDecrease: () => progress.seekTo(player, Duration(milliseconds: (total * (f - 0.02)).round().clamp(0, total))),
                      child: _RingedRegion(
                        cursor: SystemMouseCursors.click,
                        onHover: (e) => setState(() => _hover = at(e.localPosition)),
                        onExit: (_) => setState(() => _hover = null),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => progress.seekTo(player, Duration(milliseconds: (at(d.localPosition) * total).round())),
                          onHorizontalDragStart: (d) => setState(() => _drag = at(d.localPosition)),
                          onHorizontalDragUpdate: (d) => setState(() => _drag = at(d.localPosition)),
                          onHorizontalDragEnd: (_) {
                            final v = _drag;
                            if (v != null) progress.seekTo(player, Duration(milliseconds: (v * total).round()));
                            setState(() => _drag = null);
                          },
                          child: SizedBox(
                            height: 28,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(
                                  height: hovering ? 6 : 4,
                                  decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(3)),
                                ),
                                FractionallySizedBox(
                                  widthFactor: f,
                                  child: Container(
                                    height: hovering ? 6 : 4,
                                    decoration: BoxDecoration(color: hovering ? t.textPrimary : t.textSecondary, borderRadius: BorderRadius.circular(3)),
                                  ),
                                ),
                                if (hovering)
                                  Positioned(
                                    left: (f * c.maxWidth) - 6,
                                    child: Container(width: 12, height: 12, decoration: BoxDecoration(color: t.textPrimary, shape: BoxShape.circle)),
                                  ),
                                if (shown != null)
                                  Positioned(
                                    key: const Key('seek-preview'),
                                    left: (shown * c.maxWidth - 24).clamp(0.0, (c.maxWidth - 48).clamp(0.0, double.infinity)),
                                    top: -30,
                                    child: IgnorePointer(
                                      child: Container(
                                        width: 48,
                                        padding: const EdgeInsets.symmetric(vertical: 3),
                                        decoration: BoxDecoration(
                                          color: t.bgElevated,
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(color: t.outline, width: 0.5),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          formatClock(Duration(milliseconds: (shown * total).round())),
                                          style: label.copyWith(color: t.textPrimary),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: Space.sm),
              SizedBox(width: 40, child: Text(formatClock(progress.total), style: label)),
            ],
          );
        },
      ),
    );
  }
}

// ── Volume ───────────────────────────────────────────────────────────────────

/// A mute button and a slider. The wheel over either changes the volume by 5%
/// a notch; the button remembers the level it muted from.
class DesktopVolume extends StatefulWidget {
  final AudioPlayer player;
  const DesktopVolume({super.key, required this.player});

  @override
  State<DesktopVolume> createState() => _DesktopVolumeState();
}

class _DesktopVolumeState extends State<DesktopVolume> {
  late double _v = widget.player.volume;
  StreamSubscription<double>? _sub;
  double _beforeMute = 0.7;
  bool _hover = false;
  bool _drag = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.player.volumeStream.listen((v) {
      if (mounted && (v - _v).abs() > 0.004) setState(() => _v = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _set(double v) {
    v = v.clamp(0.0, 1.0);
    setState(() => _v = v);
    widget.player.setVolume(v);
  }

  void _toggleMute() {
    if (_v > 0) {
      _beforeMute = _v;
      _set(0);
    } else {
      _set(_beforeMute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final muted = _v <= 0.001;
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
          _set(_v + (e.scrollDelta.dy < 0 ? 0.05 : -0.05));
        }
      },
      child: Row(
        children: [
          BarIconButton(
            icon: muted ? NaviGlyph.speakerOff : (_v < 0.5 ? NaviGlyph.speakerLow : NaviGlyph.speaker),
            tooltip: muted ? 'Unmute (M)' : 'Mute (M)',
            onTap: _toggleMute,
            size: 18,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                double at(Offset p) => (p.dx / c.maxWidth).clamp(0.0, 1.0);
                final lit = _hover || _drag;
                return Semantics(
                  slider: true,
                  label: 'Volume',
                  value: '${(_v * 100).round()}%',
                  increasedValue: '${((_v + 0.05).clamp(0.0, 1.0) * 100).round()}%',
                  decreasedValue: '${((_v - 0.05).clamp(0.0, 1.0) * 100).round()}%',
                  onIncrease: () => _set(_v + 0.05),
                  onDecrease: () => _set(_v - 0.05),
                  child: _RingedRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hover = true),
                    onExit: (_) => setState(() => _hover = false),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _set(at(d.localPosition)),
                      onHorizontalDragStart: (_) => setState(() => _drag = true),
                      onHorizontalDragUpdate: (d) => _set(at(d.localPosition)),
                      onHorizontalDragEnd: (_) => setState(() => _drag = false),
                      child: SizedBox(
                        height: 28,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(height: 4, decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(2))),
                            FractionallySizedBox(
                              widthFactor: _v,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(color: lit ? t.textPrimary : t.textSecondary, borderRadius: BorderRadius.circular(2)),
                              ),
                            ),
                            if (lit)
                              Positioned(
                                left: _v * c.maxWidth - 6,
                                child: Container(width: 12, height: 12, decoration: BoxDecoration(color: t.textPrimary, shape: BoxShape.circle)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A slider's pointer region that is also a keyboard stop: the focus ring draws
/// around it, and the arrow keys (the app's seek and volume shortcuts) reach it.
class _RingedRegion extends StatelessWidget {
  final MouseCursor cursor;
  final void Function(PointerHoverEvent)? onHover;
  final void Function(PointerEnterEvent)? onEnter;
  final void Function(PointerExitEvent)? onExit;
  final Widget child;
  const _RingedRegion({required this.cursor, this.onHover, this.onEnter, this.onExit, required this.child});

  @override
  Widget build(BuildContext context) => NaviFocusRing(
        onTap: () {},
        radius: 4,
        child: MouseRegion(cursor: cursor, onHover: onHover, onEnter: onEnter, onExit: onExit, child: child),
      );
}
