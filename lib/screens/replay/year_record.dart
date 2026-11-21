import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../providers/library_provider.dart';
import '../../providers/navivibe_replay_provider.dart';
import '../../utils/format.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/motion/number_roll.dart';
import '../../widgets/ui/media.dart';
import '../stats/widgets/stat_card.dart';
import 'year_shape.dart' show busiestMonth;

const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// Your year as a record. January is the outer band and December the inner
/// one, like tracks on a side. Each month's band is cut with grooves: the
/// more you listened, the more grooves, an empty month is bare vinyl. The
/// label is your No. 1 song's cover and turns slowly. A tonearm rests on the
/// selected month; drag across the record to move it (one tick per month),
/// then open the month under the needle.
///
/// Reduced motion: the label holds still and the needle jumps.
class YearRecord extends ConsumerStatefulWidget {
  final List<ReplayMonthlyCard> cards;

  /// The year's No. 1 song, whose cover is the label.
  final ReplayTrack? label;
  final ValueChanged<ReplayMonthlyCard> onOpen;
  const YearRecord({super.key, required this.cards, required this.onOpen, this.label});

  @override
  ConsumerState<YearRecord> createState() => _YearRecordState();
}

class _YearRecordState extends ConsumerState<YearRecord> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 14));
  late final ValueNotifier<int> _sel = ValueNotifier(busiestMonth(widget.cards)?.month ?? 1);
  bool _spinning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final full = context.motionFull;
    if (full && !_spinning) {
      _spinning = true;
      _spin.repeat();
    } else if (!full && _spinning) {
      _spinning = false;
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _sel.dispose();
    super.dispose();
  }

  ReplayMonthlyCard? _card(int m) {
    for (final c in widget.cards) {
      if (c.month == m) return c;
    }
    return null;
  }

  void _pick(Offset p, double side) {
    final g = _Geometry(side);
    final d = (p - Offset(side / 2, side / 2)).distance;
    if (d < g.labelR) return;
    final m = g.monthAt(d);
    if (m == _sel.value) return;
    HapticFeedback.selectionClick();
    _sel.value = m;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final peak = busiestMonth(widget.cards)?.totalMinutes ?? 0;
    final shares = [
      for (var m = 1; m <= 12; m++) peak == 0 || _card(m) == null ? 0.0 : _card(m)!.totalMinutes / peak,
    ];
    final labelUrl = widget.label == null
        ? null
        : ref.watch(songCoverUrlProvider('${widget.label!.title}|${widget.label!.artist}')).asData?.value;
    final full = context.motionFull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Your Year'),
        Center(
          child: LayoutBuilder(
            builder: (context, box) {
              final side = math.min(box.maxWidth - Space.gutter * 2, 340.0);
              final g = _Geometry(side);
              return SizedBox.square(
                dimension: side,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => _pick(d.localPosition, side),
                  onPanUpdate: (d) => _pick(d.localPosition, side),
                  onTapDown: (d) => _pick(d.localPosition, side),
                  child: Stack(
                    children: [
                      // The vinyl never redraws unless the selection changes.
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: ValueListenableBuilder<int>(
                            valueListenable: _sel,
                            builder: (context, sel, _) => CustomPaint(
                              painter: _VinylPainter(
                                shares: shares,
                                selected: sel,
                                disc: Color.lerp(t.bgBase, t.accent, 0.07)!,
                                groove: Color.lerp(t.bgBase, t.accent, 0.34)!,
                                lit: t.accent,
                                bare: Color.lerp(t.bgBase, t.accent, 0.14)!,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _spin,
                              builder: (context, child) => Transform.rotate(angle: _spin.value * 2 * math.pi, child: child),
                              child: CoverArt(url: labelUrl, size: g.labelR * 2, radius: g.labelR, circular: true),
                            ),
                          ),
                        ),
                      ),
                      // Spindle hole.
                      Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: t.bgBase, shape: BoxShape.circle))),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ValueListenableBuilder<int>(
                            valueListenable: _sel,
                            builder: (context, sel, _) => TweenAnimationBuilder<double>(
                              tween: Tween(end: g.slotMid(sel)),
                              duration: full ? const Duration(milliseconds: 320) : Duration.zero,
                              curve: Curves.easeOutCubic,
                              builder: (context, r, _) => CustomPaint(painter: _NeedlePainter(r, t.accent, t.bgBase)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: ValueListenableBuilder<int>(
            valueListenable: _sel,
            builder: (context, m, _) => _Readout(card: _card(m), month: m, onOpen: widget.onOpen),
          ),
        ),
      ],
    );
  }
}

/// Where things sit on a record [side] wide.
class _Geometry {
  final double side;
  const _Geometry(this.side);

  double get r => side / 2;
  double get labelR => r * 0.27;
  double get _inner => labelR + r * 0.05;
  double get _outer => r * 0.965;
  double get slot => (_outer - _inner) / 12;

  /// Outer edge of month [m]'s band (1 = January, outermost).
  double slotOuter(int m) => _outer - (m - 1) * slot;
  double slotMid(int m) => slotOuter(m) - slot / 2;

  int monthAt(double distance) => (((_outer - distance) / slot).floor()).clamp(0, 11) + 1;
}

class _VinylPainter extends CustomPainter {
  final List<double> shares;
  final int selected;
  final Color disc;
  final Color groove;
  final Color lit;
  final Color bare;
  const _VinylPainter({
    required this.shares,
    required this.selected,
    required this.disc,
    required this.groove,
    required this.lit,
    required this.bare,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(size.width);
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, g.r, Paint()..color = disc);
    canvas.drawCircle(
      c,
      g.r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = groove.withValues(alpha: 0.6),
    );
    for (var m = 1; m <= 12; m++) {
      final share = shares[m - 1];
      final on = m == selected;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 1.4 : 1;
      if (share <= 0) {
        // An empty month is one faint seam, not grooves.
        paint.color = bare;
        canvas.drawCircle(c, g.slotMid(m), paint);
        continue;
      }
      paint.color = on ? lit : groove;
      final n = math.max(1, (share * 6).ceil());
      final pad = 2.0;
      final span = g.slot - pad * 2;
      for (var k = 0; k < n; k++) {
        final rad = g.slotOuter(m) - pad - (n == 1 ? span / 2 : span * k / (n - 1));
        canvas.drawCircle(c, rad, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_VinylPainter old) =>
      old.selected != selected || old.shares != shares || old.disc != disc || old.lit != lit || old.groove != groove;
}

/// The tonearm: a line from the top-right corner to the needle on the record.
class _NeedlePainter extends CustomPainter {
  final double radius;
  final Color ink;
  final Color ground;
  const _NeedlePainter(this.radius, this.ink, this.ground);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const angle = -math.pi / 3.2; // up and to the right
    final tip = c + Offset(math.cos(angle), math.sin(angle)) * radius;
    final pivot = Offset(size.width, 0);
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..color = ink
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, 6, Paint()..color = ink);
    canvas.drawCircle(pivot, 2.5, Paint()..color = ground);
    canvas.drawCircle(tip, 4, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => old.radius != radius || old.ink != ink;
}

class _Readout extends StatelessWidget {
  final ReplayMonthlyCard? card;
  final int month;
  final ValueChanged<ReplayMonthlyCard> onOpen;
  const _Readout({required this.card, required this.month, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final c = card;
    final active = c != null && c.totalPlays > 0;
    return CupertinoClickable(
      onTap: active ? () => onOpen(c) : null,
      scaleFactor: 0.99,
      semanticLabel: active ? 'Open ${c.monthName}, ${listeningTime(c.totalMinutes.round())}' : '${monthNames[month - 1]}, no listening',
      child: SizedBox(
        height: 84,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(monthNames[month - 1], style: t.headline),
                  if (active)
                    NumberRoll(
                      value: c.totalMinutes.round(),
                      format: listeningTime,
                      duration: const Duration(milliseconds: 420),
                      style: figureStyle(t, 34),
                    )
                  else
                    Text('No listening', style: figureStyle(t, 34).copyWith(color: t.textMuted)),
                  Text(
                    active ? (c.topArtist?.artist ?? '${c.totalPlays} plays') : ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.footnote,
                  ),
                ],
              ),
            ),
            if (active) Text('Open', style: t.subheadline.copyWith(color: t.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Fades [child] in and lifts it 24 px into place (ease-out, 360 ms),
/// staggered 60 ms by [index], the first time it appears. Static under
/// reduced motion.
class RiseIn extends StatelessWidget {
  final int index;
  final Widget child;
  const RiseIn({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!context.motionFull) return child;
    final delay = 60 * index.clamp(0, 6);
    final total = 360 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, k, child) => Opacity(
        opacity: k,
        child: Transform.translate(offset: Offset(0, 24 * (1 - k)), child: child),
      ),
    );
  }
}
