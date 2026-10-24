import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../core/motion.dart';
import '../../../../core/theme.dart';
import '../../data/social_models.dart';
import '../social_widgets.dart';

/// The Jam as a room: a thin ring with the people seated on it and the song at
/// its centre. Empty seats stay as hollow dots so the room reads as open. The
/// host's seat is ringed in white. While music plays the ring breathes; with
/// reduced motion it holds still.
class RoomRing extends StatefulWidget {
  final List<JamMember> members;
  final double size;
  final bool playing;

  /// What sits at the centre (the cover of the song playing).
  final Widget center;

  /// Seats drawn in total; more people than seats simply add seats.
  final int minSeats;

  const RoomRing({
    super.key,
    required this.members,
    required this.size,
    required this.playing,
    required this.center,
    this.minSeats = 6,
  });

  @override
  State<RoomRing> createState() => _RoomRingState();
}

class _RoomRingState extends State<RoomRing> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  bool _wantsMotion = false;

  void _sync() {
    final run = _wantsMotion && widget.playing;
    if (run && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!run && _breath.isAnimating) {
      _breath.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wantsMotion = context.motionFull;
    _sync();
  }

  @override
  void didUpdateWidget(RoomRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final size = widget.size;
    final seats = math.max(widget.minSeats, widget.members.length);
    final avatar = (size * 0.17).clamp(22.0, 52.0);
    final radius = size / 2 - avatar / 2 - 2;
    final centerSize = (radius - avatar / 2 - 5) * 2; // never touches a seat

    Offset seat(int i) {
      final a = -math.pi / 2 + i * 2 * math.pi / seats;
      return Offset(size / 2 + radius * math.cos(a), size / 2 + radius * math.sin(a));
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _breath,
                builder: (context, _) => CustomPaint(
                  painter: _RingPainter(
                    color: t.textPrimary,
                    radius: radius,
                    breath: _breath.value,
                    seats: [for (var i = widget.members.length; i < seats; i++) seat(i)],
                    seatRadius: avatar * 0.14,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: (size - centerSize) / 2,
            top: (size - centerSize) / 2,
            width: centerSize,
            height: centerSize,
            child: ClipOval(child: widget.center),
          ),
          for (final (i, m) in widget.members.indexed)
            Positioned(
              left: seat(i).dx - avatar / 2,
              top: seat(i).dy - avatar / 2,
              width: avatar,
              height: avatar,
              child: Semantics(
                label: m.isHost ? '${m.username}, host' : m.username,
                excludeSemantics: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: m.isHost ? Border.all(color: t.textPrimary, width: 2) : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(m.isHost ? 3 : 0),
                    child: PersonAvatar(m.username, size: avatar),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double breath;
  final List<Offset> seats;
  final double seatRadius;

  const _RingPainter({
    required this.color,
    required this.radius,
    required this.breath,
    required this.seats,
    required this.seatRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // The breathing halo: a second ring easing out and fading.
    if (breath > 0) {
      canvas.drawCircle(
        c,
        radius + 3 + breath * 9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.22 * (1 - breath)),
      );
    }
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.28),
    );
    final hollow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.35);
    for (final s in seats) {
      canvas.drawCircle(s, seatRadius * 2.4, hollow);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.breath != breath || old.color != color || old.radius != radius || old.seats.length != seats.length;
}
