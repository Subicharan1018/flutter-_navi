import 'package:flutter/widgets.dart';

import '../../../../core/theme.dart';
import '../../../../widgets/art/navi_icons.dart';

/// One full-screen card of a story. [builder] gets the card's own clock: 0→1
/// over [duration] from the moment the card appears (and 1 from the start
/// when the system asks for reduced motion, so the finished picture shows).
class StoryPage {
  final Duration duration;
  final Widget Function(BuildContext context, Animation<double> progress) builder;
  const StoryPage({required this.builder, this.duration = const Duration(seconds: 6)});
}

/// Instagram-style stories: progress segments across the top, tap the right
/// side to advance and the left to go back, press and hold to pause. A card
/// runs on one controller and hands its clock to the page, so everything on a
/// card is staggered from a single ticker. The last card stays up.
///
/// With reduced motion nothing auto-advances and no card animates: you move
/// on by tapping, and each card is already in its finished state.
class StoryPager extends StatefulWidget {
  final List<StoryPage> pages;
  final VoidCallback? onClose;
  final int initialPage;

  const StoryPager({super.key, required this.pages, this.onClose, this.initialPage = 0});

  @override
  State<StoryPager> createState() => _StoryPagerState();
}

class _StoryPagerState extends State<StoryPager> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this)..addStatusListener(_onStatus);
  late int _index = widget.initialPage.clamp(0, widget.pages.length - 1);
  bool _reduced = false;
  bool _started = false;

  bool get _last => _index == widget.pages.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_started && reduced == _reduced) return;
    _reduced = reduced;
    _started = true;
    _play();
  }

  void _play() {
    final page = widget.pages[_index];
    _c.duration = page.duration;
    if (_reduced) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && !_reduced && !_last) _go(_index + 1);
  }

  void _go(int to) {
    if (to < 0) return _play(); // back on the first card restarts it
    if (to >= widget.pages.length) return;
    setState(() => _index = to);
    _play();
  }

  void _hold(bool on) {
    if (_reduced) return;
    if (on) {
      _c.stop();
    } else if (_c.value < 1) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final clock = _reduced ? const AlwaysStoppedAnimation<double>(1) : _c;
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Pages cross-fade; the switch is skipped entirely under reduced motion.
          AnimatedSwitcher(
            duration: _reduced ? Duration.zero : Motion.standard,
            child: KeyedSubtree(
              key: ValueKey(_index),
              child: RepaintBoundary(child: widget.pages[_index].builder(context, clock)),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (d) => _go(d.localPosition.dx < c.maxWidth / 3 ? _index - 1 : _index + 1),
                onLongPressStart: (_) => _hold(true),
                onLongPressEnd: (_) => _hold(false),
                onLongPressCancel: () => _hold(false),
              ),
            ),
          ),
          Positioned(
            top: top + Space.sm,
            left: Space.md,
            right: Space.md,
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Card ${_index + 1} of ${widget.pages.length}',
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: 3,
                        child: CustomPaint(
                          painter: _Segments(count: widget.pages.length, index: _index, clock: clock),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: Space.sm),
                  CupertinoClickable(
                    onTap: widget.onClose,
                    semanticLabel: 'Close',
                    child: SizedBox.square(
                      dimension: 44,
                      child: Center(child: NaviIcon(NaviGlyph.close, size: 20, color: const Color(0xFFFFFFFF))),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Segments extends CustomPainter {
  final int count;
  final int index;
  final Animation<double> clock;
  _Segments({required this.count, required this.index, required this.clock}) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 4.0;
    final w = (size.width - gap * (count - 1)) / count;
    final track = Paint()..color = const Color(0x40FFFFFF);
    final fill = Paint()..color = const Color(0xFFFFFFFF);
    for (var i = 0; i < count; i++) {
      final x = i * (w + gap);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, w, size.height), Radius.circular(size.height / 2));
      canvas.drawRRect(r, track);
      final f = i < index ? 1.0 : (i == index ? clock.value : 0.0);
      if (f > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, w * f, size.height), Radius.circular(size.height / 2)),
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Segments old) => old.count != count || old.index != index || old.clock != clock;
}
