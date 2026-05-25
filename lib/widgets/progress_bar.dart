import 'dart:ui';
import 'package:flutter/material.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
class _PDS {
  // Glass surface
  static const glassWhite = Color(0x14FFFFFF); // ~8% white
  static const glassBorder = Color(0x26FFFFFF); // ~15% white
  static const glassBorderH = Color(0x40FFFFFF); // ~25% white — hover

  // Neon gradient stops
  static const neonPurple = Color(0xFF9D4EDD); // vivid purple
  static const neonViolet = Color(0xFFBF5CF3); // mid violet
  static const neonPink = Color(0xFFFF2D78); // electric pink

  // Track
  static const trackBg = Color(0x1AFFFFFF); // inactive
  static const thumbShadow = Color(0x66BF5CF3);

  // Text
  static const timeColor = Color(0xAAFFFFFF);
  static const timeShadow = Color(0x44000000);
}

// ── Neon gradient painter for the active track ────────────────────────────────
class _NeonTrackPainter extends CustomPainter {
  final double progress; // 0.0 – 1.0

  const _NeonTrackPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final r = h / 2;
    final fill = w * progress;

    if (fill <= 0) return;

    // ── Glow layer (blurred, wider) ───────────────────────────────────────
    final glowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          _PDS.neonPurple.withValues(alpha: 0.55),
          _PDS.neonPink.withValues(alpha: 0.45),
        ],
      ).createShader(Rect.fromLTWH(0, 0, fill, h))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-3, -4, fill + 6, h + 8),
        const Radius.circular(12),
      ),
      glowPaint,
    );

    // ── Solid neon track ──────────────────────────────────────────────────
    final trackPaint = Paint()
      ..shader = LinearGradient(
        colors: [_PDS.neonPurple, _PDS.neonViolet, _PDS.neonPink],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, fill, h));

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fill, h), Radius.circular(r)),
      trackPaint,
    );

    // ── Leading-edge micro-flare ──────────────────────────────────────────
    if (fill > r) {
      final flarePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      canvas.drawCircle(Offset(fill - r, r), r * 0.6, flarePaint);
    }
  }

  @override
  bool shouldRepaint(_NeonTrackPainter old) => old.progress != progress;
}

// ── Custom thumb shape — reads pulse scale from ValueNotifier ─────────────────
class _GlassThumbShape extends SliderComponentShape {
  final ValueNotifier<double> pulseScale;

  const _GlassThumbShape(this.pulseScale);

  static const _radius = 11.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final scale = pulseScale.value;
    final r = _radius * scale;

    // Drop shadow + glow
    canvas.drawCircle(
      center,
      r + 3,
      Paint()
        ..color = _PDS.thumbShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Outer glass ring
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = _PDS.glassBorderH
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Inner frosted fill
    canvas.drawCircle(center, r - 1, Paint()..color = const Color(0xCCFFFFFF));

    // Specular highlight
    canvas.drawCircle(
      center.translate(-3, -3),
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }
}

// ── Progress bar ──────────────────────────────────────────────────────────────
class ProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const ProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  // ValueNotifier so _GlassThumbShape can read scale without rebuilding tree.
  final ValueNotifier<double> _pulseScale = ValueNotifier(1.0);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.4,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _pulseAnim.addListener(() {
      _pulseScale.value = _pulseAnim.value;
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _pulseScale.dispose();
    super.dispose();
  }

  void _triggerPulse() {
    _pulseCtrl.forward().then((_) => _pulseCtrl.reverse());
  }

  void _handleSeek(Duration d) {
    widget.onSeek(d);
    _triggerPulse();
  }

  @override
  Widget build(BuildContext context) {
    // ── Logic untouched ───────────────────────────────────────────────────
    String formatDuration(Duration d) {
      final minutes = d.inMinutes;
      final seconds = d.inSeconds % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }

    final maxMs = widget.duration.inMilliseconds > 0
        ? widget.duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = widget.position.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final progress = maxMs > 1.0 ? posMs / maxMs : 0.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: _PDS.glassWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _PDS.glassBorder, width: 0.8),
          ),
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Neon track behind the slider ──────────────────────────
              Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Inactive (dim) track
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: _PDS.trackBg,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Active neon track (painted beneath slider)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 4,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return CustomPaint(
                            size: Size(constraints.maxWidth, 4),
                            painter: _NeonTrackPainter(progress: progress),
                          );
                        },
                      ),
                    ),
                  ),

                  // Transparent slider on top (handles gesture only)
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: _GlassThumbShape(_pulseScale),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: Colors.transparent,
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMs,
                      value: posMs,
                      onChanged: (val) {
                        _handleSeek(Duration(milliseconds: val.round()));
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Time labels ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _TimeLabel(text: formatDuration(widget.position)),
                    _TimeLabel(
                      text:
                          '-${formatDuration(widget.duration - widget.position)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Time label with subtle shadow ─────────────────────────────────────────────
class _TimeLabel extends StatelessWidget {
  final String text;
  const _TimeLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: _PDS.timeColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        shadows: const [Shadow(color: _PDS.timeShadow, blurRadius: 4)],
      ),
    );
  }
}
