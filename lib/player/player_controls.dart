import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../core/theme.dart';
import '../models/song.dart';

// =============================================================================
// Shared playback controls. Every control here takes its colours as
// parameters: on Now Playing they are white-on-artwork, in the desktop bar
// they use the app tokens.
// =============================================================================

String formatClock(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Honest format label from the file the server reports. Never claims
/// "Lossless" for a lossy file.
String? qualityLabel(Song song) {
  final suffix = song.suffix.toLowerCase();
  const lossless = {'flac', 'alac', 'wav', 'aiff', 'aif', 'ape', 'wv', 'dsf'};
  if (lossless.contains(suffix)) return 'Lossless · ${suffix.toUpperCase()}';
  if (suffix.isEmpty && song.bitRate == 0) return null;
  final parts = [
    if (suffix.isNotEmpty) suffix.toUpperCase(),
    if (song.bitRate > 0) '${song.bitRate} kbps',
  ];
  return parts.join(' · ');
}

// ─────────────────────────────────────────────────────────────────────────────
// Position — a flash-free, throttled position source.
// just_audio briefly emits 0 while switching sources; a naive StreamBuilder
// shows a one-frame jump to 0:00. This keeps the last real position until the
// song actually changes.
// ─────────────────────────────────────────────────────────────────────────────

class PlaybackPosition extends StatefulWidget {
  final AudioPlayer player;
  final String songId;
  final Widget Function(BuildContext context, Duration position) builder;

  /// Minimum change before rebuilding (sub-second resolution isn't visible
  /// on a 300px bar; 250 ms keeps the playhead visibly fluid).
  final Duration resolution;

  const PlaybackPosition({
    super.key,
    required this.player,
    required this.songId,
    required this.builder,
    this.resolution = const Duration(milliseconds: 250),
  });

  @override
  State<PlaybackPosition> createState() => _PlaybackPositionState();
}

class _PlaybackPositionState extends State<PlaybackPosition> {
  StreamSubscription<Duration>? _sub;
  Duration _pos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pos = widget.player.position;
    _sub = widget.player.positionStream.listen(_onPos);
  }

  void _onPos(Duration p) {
    if (!mounted) return;
    if (p == Duration.zero && _pos > const Duration(seconds: 1)) return;
    if ((p - _pos).abs() >= widget.resolution || p < _pos) {
      setState(() => _pos = p);
    }
  }

  @override
  void didUpdateWidget(PlaybackPosition old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      _sub?.cancel();
      _sub = widget.player.positionStream.listen(_onPos);
    }
    if (old.songId != widget.songId) _pos = Duration.zero;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _pos);
}

// ─────────────────────────────────────────────────────────────────────────────
// Elastic track — the shared bar behind the scrubber and the volume control.
// Idle it is thin; touched, it swells (response on pointer-down) and tracks
// the finger 1:1; released, it settles back.
// ─────────────────────────────────────────────────────────────────────────────

class ElasticTrack extends StatefulWidget {
  final double value; // 0..1
  final ValueChanged<double>? onChanged; // continuous, while dragging
  final ValueChanged<double>? onChangeEnd; // committed
  final ValueChanged<bool>? onActiveChanged;
  final Color activeColor;
  final Color inactiveColor;
  final double idleHeight;
  final double activeHeight;
  final String semanticLabel;
  final String Function(double)? semanticValue;

  const ElasticTrack({
    super.key,
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    required this.semanticLabel,
    this.onChanged,
    this.onChangeEnd,
    this.onActiveChanged,
    this.idleHeight = 6,
    this.activeHeight = 12,
    this.semanticValue,
  });

  @override
  State<ElasticTrack> createState() => _ElasticTrackState();
}

class _ElasticTrackState extends State<ElasticTrack> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 320),
  );
  double? _dragValue;

  double get _shown => (_dragValue ?? widget.value).clamp(0.0, 1.0);

  void _start(Offset local, double width) {
    _press.forward();
    widget.onActiveChanged?.call(true);
    _update(local, width);
  }

  void _update(Offset local, double width) {
    final v = (local.dx / width).clamp(0.0, 1.0);
    setState(() => _dragValue = v);
    widget.onChanged?.call(v);
  }

  void _end() {
    final v = _dragValue;
    _press.reverse();
    widget.onActiveChanged?.call(false);
    if (v != null) {
      widget.onChangeEnd?.call(v);
      HapticFeedback.selectionClick();
    }
    setState(() => _dragValue = null);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChangeEnd != null || widget.onChanged != null;
    String describe(double v) => widget.semanticValue?.call(v) ?? '${(v * 100).round()}%';
    final up = (_shown + 0.05).clamp(0.0, 1.0);
    final down = (_shown - 0.05).clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: describe(_shown),
      increasedValue: enabled ? describe(up) : null,
      decreasedValue: enabled ? describe(down) : null,
      onIncrease: enabled ? () => widget.onChangeEnd?.call(up) : null,
      onDecrease: enabled ? () => widget.onChangeEnd?.call(down) : null,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (d) => _start(d.localPosition, w) : null,
            onTapUp: enabled ? (_) => _end() : null,
            onHorizontalDragStart: enabled ? (d) => _start(d.localPosition, w) : null,
            onHorizontalDragUpdate: enabled ? (d) => _update(d.localPosition, w) : null,
            onHorizontalDragEnd: enabled ? (_) => _end() : null,
            onHorizontalDragCancel: enabled ? _end : null,
            child: SizedBox(
              width: w,
              height: 32, // 32dp hit band around a 6dp bar
              child: AnimatedBuilder(
                animation: _press,
                builder: (context, _) {
                  final t = Curves.easeOutCubic.transform(_press.value);
                  final h = widget.idleHeight + (widget.activeHeight - widget.idleHeight) * t;
                  return CustomPaint(
                    painter: _TrackPainter(
                      value: _shown,
                      height: h,
                      active: widget.activeColor,
                      inactive: widget.inactiveColor,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  final double value;
  final double height;
  final Color active;
  final Color inactive;

  _TrackPainter({required this.value, required this.height, required this.active, required this.inactive});

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - height) / 2;
    final r = Radius.circular(height / 2);
    final full = RRect.fromRectAndRadius(Rect.fromLTWH(0, top, size.width, height), r);
    canvas.drawRRect(full, Paint()..color = inactive);
    if (value <= 0) return;
    canvas.save();
    canvas.clipRRect(full);
    canvas.drawRect(Rect.fromLTWH(0, top, size.width * value, height), Paint()..color = active);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrackPainter o) =>
      o.value != value || o.height != height || o.active != active || o.inactive != inactive;
}

// ─────────────────────────────────────────────────────────────────────────────
// Scrubber — elastic track + elapsed / format / remaining.
// ─────────────────────────────────────────────────────────────────────────────

class Scrubber extends StatefulWidget {
  final AudioPlayer player;
  final Song song;
  final Color color; // fill + bright labels
  final Color trackColor;
  final Color labelColor;
  final bool showQuality;

  const Scrubber({
    super.key,
    required this.player,
    required this.song,
    this.color = Colors.white,
    this.trackColor = const Color(0x40FFFFFF),
    this.labelColor = const Color(0x99FFFFFF),
    this.showQuality = true,
  });

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  final ValueNotifier<double?> _scrub = ValueNotifier(null);

  @override
  void dispose() {
    _scrub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = Duration(seconds: widget.song.duration);
    final totalMs = total.inMilliseconds;
    final quality = widget.showQuality ? qualityLabel(widget.song) : null;
    return RepaintBoundary(
      child: PlaybackPosition(
        player: widget.player,
        songId: widget.song.id,
        builder: (context, pos) {
          return ValueListenableBuilder<double?>(
            valueListenable: _scrub,
            builder: (context, scrub, _) {
              final frac = scrub ?? (totalMs > 0 ? pos.inMilliseconds / totalMs : 0.0);
              final shownPos = Duration(milliseconds: (frac * totalMs).round());
              final active = scrub != null;
              final labelStyle = naviText(
                12,
                FontWeight.w600,
                active ? widget.color : widget.labelColor,
                tabular: true,
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElasticTrack(
                    value: frac,
                    activeColor: active ? widget.color : widget.color.withValues(alpha: 0.82),
                    inactiveColor: widget.trackColor,
                    semanticLabel: 'Playback position',
                    semanticValue: (v) =>
                        '${formatClock(Duration(milliseconds: (v * totalMs).round()))} of ${formatClock(total)}',
                    onChanged: (v) => _scrub.value = v,
                    onChangeEnd: (v) {
                      widget.player.seek(Duration(milliseconds: (v * totalMs).round()));
                      _scrub.value = null;
                    },
                  ),
                  Row(
                    children: [
                      Text(formatClock(shownPos), style: labelStyle),
                      Expanded(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: active || quality == null ? 0 : 1,
                          child: Text(
                            quality ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: naviText(10.5, FontWeight.w600, widget.labelColor).copyWith(
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                      Text('-${formatClock(total - shownPos)}', style: labelStyle),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glyph button — a bare icon with Apple's pressed state: a soft disc blooms
// behind the glyph and the glyph dips, on pointer-down.
// ─────────────────────────────────────────────────────────────────────────────

class GlyphButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double size; // hit + disc diameter
  final String semanticLabel;
  final Color pressColor;
  final bool selected;
  final Color? selectedColor;

  const GlyphButton({
    super.key,
    required this.child,
    required this.semanticLabel,
    this.onTap,
    this.onLongPress,
    this.size = 56,
    this.pressColor = const Color(0x24FFFFFF),
    this.selected = false,
    this.selectedColor,
  });

  @override
  State<GlyphButton> createState() => _GlyphButtonState();
}

class _GlyphButtonState extends State<GlyphButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 300),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _c.forward() : null,
        onTapUp: enabled ? (_) => _c.reverse() : null,
        onTapCancel: enabled ? () => _c.reverse() : null,
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = Curves.easeOut.transform(_c.value);
              return Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: widget.size * (widget.selected ? 0.78 : 0.62 + 0.38 * t),
                    height: widget.size * (widget.selected ? 0.78 : 0.62 + 0.38 * t),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selected
                          ? (widget.selectedColor ?? const Color(0x2EFFFFFF))
                          : widget.pressColor.withValues(alpha: widget.pressColor.a * t),
                    ),
                  ),
                  Transform.scale(scale: 1 - 0.08 * t, child: child),
                ],
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport — rewind · play/pause · forward. Play/pause morphs between its
// two glyphs instead of swapping icons.
// ─────────────────────────────────────────────────────────────────────────────

class TransportControls extends StatefulWidget {
  final bool playing;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Color color;
  final double scale; // 1.0 = phone Now Playing

  /// Optional mode buttons either side (shuffle / repeat on Now Playing).
  final Widget? leading;
  final Widget? trailing;

  const TransportControls({
    super.key,
    required this.playing,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    this.color = Colors.white,
    this.scale = 1,
    this.leading,
    this.trailing,
  });

  @override
  State<TransportControls> createState() => _TransportControlsState();
}

class _TransportControlsState extends State<TransportControls> with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(TransportControls old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      widget.playing ? _morph.forward() : _morph.reverse();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    // With shuffle/repeat either side, tighten the transport hit areas (not
    // the glyphs) so all five fit a 360 dp phone: 48+60+76+60+48 = 292.
    final flanked = widget.leading != null || widget.trailing != null;
    final skipBox = (flanked ? 60.0 : 72.0) * s;
    final playBox = (flanked ? 76.0 : 84.0) * s;
    return Row(
      mainAxisAlignment:
          flanked ? MainAxisAlignment.spaceBetween : MainAxisAlignment.spaceEvenly,
      children: [
        ?widget.leading,
        GlyphButton(
          size: skipBox,
          semanticLabel: 'Previous',
          onTap: widget.onPrevious,
          child: Icon(Icons.fast_rewind_rounded, size: 44 * s, color: widget.color),
        ),
        GlyphButton(
          size: playBox,
          semanticLabel: widget.playing ? 'Pause' : 'Play',
          onTap: widget.onPlayPause,
          child: AnimatedIcon(
            icon: AnimatedIcons.play_pause,
            progress: _morph,
            size: 58 * s,
            color: widget.color,
          ),
        ),
        GlyphButton(
          size: skipBox,
          semanticLabel: 'Next',
          onTap: widget.onNext,
          child: Icon(Icons.fast_forward_rounded, size: 44 * s, color: widget.color),
        ),
        ?widget.trailing,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Volume — speaker glyphs either side of an elastic track; stays in sync with
// hardware buttons / ducking through the player's volume stream.
// ─────────────────────────────────────────────────────────────────────────────

class VolumeBar extends StatefulWidget {
  final AudioPlayer player;
  final Color color;
  final Color trackColor;
  final Color iconColor;

  const VolumeBar({
    super.key,
    required this.player,
    this.color = Colors.white,
    this.trackColor = const Color(0x40FFFFFF),
    this.iconColor = const Color(0x99FFFFFF),
  });

  @override
  State<VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<VolumeBar> {
  late double _v = widget.player.volume;
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.player.volumeStream.listen((v) {
      if (mounted && (v - _v).abs() > 0.005) setState(() => _v = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _set(double v) {
    setState(() => _v = v);
    widget.player.setVolume(v);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => _set(0),
          child: Icon(Icons.volume_mute_rounded, size: 20, color: widget.iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElasticTrack(
            value: _v,
            activeColor: widget.color,
            inactiveColor: widget.trackColor,
            semanticLabel: 'Volume',
            onChanged: _set,
            onChangeEnd: _set,
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => _set(1),
          child: Icon(Icons.volume_up_rounded, size: 20, color: widget.iconColor),
        ),
      ],
    );
  }
}

/// Secondary action on the artwork (favourite, more): a plain glyph with a
/// full-size hit area — no translucent disc behind it.
class GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final Color? iconColor;
  final double diameter;

  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.iconColor,
    this.diameter = 34,
  });

  @override
  Widget build(BuildContext context) {
    return GlyphButton(
      size: 48,
      semanticLabel: semanticLabel,
      onTap: onTap,
      pressColor: const Color(0x00FFFFFF),
      child: Icon(icon, size: diameter * 0.7, color: iconColor ?? Colors.white),
    );
  }
}
