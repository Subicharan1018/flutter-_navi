import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../providers/library_provider.dart';
import '../../providers/navivibe_replay_provider.dart';
import '../../utils/format.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/ui/media.dart';
import '../stats/widgets/stat_card.dart';
import 'year_shape.dart' show busiestMonth;

const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _caps = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

/// The year as a reel of twelve month posters you swipe through, starting on
/// the busiest month. Each poster is type and one cover: the month in large
/// capitals, the top song's cover, minutes and top artist. The poster in the
/// middle is full strength and its neighbours recede; a selection tick marks
/// each month you pass. Tap the middle one to open it, a neighbour to bring
/// it in.
class YearReel extends StatefulWidget {
  final List<ReplayMonthlyCard> cards;
  final ValueChanged<ReplayMonthlyCard> onOpen;
  const YearReel({super.key, required this.cards, required this.onOpen});

  @override
  State<YearReel> createState() => _YearReelState();
}

class _YearReelState extends State<YearReel> {
  late final int _start = (busiestMonth(widget.cards)?.month ?? 1) - 1;
  late final PageController _page = PageController(initialPage: _start, viewportFraction: 0.74);
  late int _current = _start;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  ReplayMonthlyCard? _card(int m) {
    for (final c in widget.cards) {
      if (c.month == m) return c;
    }
    return null;
  }

  void _tap(int i) {
    final c = _card(i + 1);
    if (i == _current) {
      if (c != null && c.totalPlays > 0) widget.onOpen(c);
    } else if (context.motionFullNow) {
      _page.animateToPage(i, duration: Motion.standard, curve: Curves.easeOutCubic);
    } else {
      _page.jumpToPage(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Your Year'),
        SizedBox(
          height: 292,
          child: PageView.builder(
            controller: _page,
            itemCount: 12,
            padEnds: false,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _current = i);
            },
            itemBuilder: (context, i) => AnimatedBuilder(
              animation: _page,
              builder: (context, child) {
                final at = _page.hasClients && _page.position.haveDimensions ? (_page.page ?? _start.toDouble()) : _start.toDouble();
                final near = (1 - (at - i).abs()).clamp(0.0, 1.0);
                return Opacity(
                  opacity: 0.38 + 0.62 * near,
                  child: Transform.scale(scale: 0.88 + 0.12 * near, alignment: Alignment.centerLeft, child: child),
                );
              },
              child: RepaintBoundary(child: _Poster(card: _card(i + 1), month: i + 1, onTap: () => _tap(i))),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, 0),
          child: Text('Swipe through the year. Tap a month to open it.', style: t.caption1.copyWith(color: t.textMuted)),
        ),
      ],
    );
  }
}

class _Poster extends ConsumerWidget {
  final ReplayMonthlyCard? card;
  final int month;
  final VoidCallback onTap;
  const _Poster({required this.card, required this.month, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final c = card;
    final active = c != null && c.totalPlays > 0;
    final cover = !active || c.topTrack == null
        ? null
        : ref.watch(songCoverUrlProvider('${c.topTrack!.title}|${c.topTrack!.artist}')).asData?.value;
    return CupertinoClickable(
      onTap: onTap,
      scaleFactor: 0.98,
      semanticLabel: c == null ? _caps[month - 1] : '${c.monthName}, ${listeningTime(c.totalMinutes.round())}',
      child: Padding(
        padding: const EdgeInsets.only(left: Space.gutter, right: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _caps[month - 1],
              style: t.textStyle(60, FontWeight.w800, active ? t.textPrimary : t.textMuted).copyWith(height: 1, letterSpacing: -2),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final s = box.maxHeight - 52;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      active
                          ? CoverArt(url: cover, size: s, radius: Radii.cover)
                          : SizedBox.square(
                              dimension: s,
                              child: DecoratedBox(decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.cover))),
                            ),
                      const SizedBox(height: Space.sm),
                      Text(
                        active ? listeningTime(c.totalMinutes.round()) : 'No listening',
                        style: figureStyle(t, 20).copyWith(color: active ? t.textPrimary : t.textMuted),
                      ),
                      Text(
                        active ? (c.topArtist?.artist ?? '${c.totalPlays} plays') : ' ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.footnote,
                      ),
                    ],
                  );
                },
              ),
            ),
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
