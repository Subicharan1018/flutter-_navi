import 'package:flutter/widgets.dart';

/// Fades and lifts [child] in the first time it scrolls into view, then never
/// again. Nothing animates while it is offscreen or after it has played, so a
/// long page costs nothing once settled. [index] staggers siblings that
/// arrive together.
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  const Reveal({super.key, required this.child, this.index = 0});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  ScrollPosition? _position;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _show(animate: false);
      return;
    }
    final next = Scrollable.maybeOf(context)?.position;
    if (next != _position) {
      _position?.removeListener(_check);
      _position = next;
      next?.addListener(_check);
    }
    if (_position == null) {
      _show(animate: false);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  void _check() {
    if (_shown || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final screen = MediaQuery.sizeOf(context).height;
    if (top < screen - 48) _show();
  }

  void _show({bool animate = true}) {
    _position?.removeListener(_check);
    _position = null;
    if (!animate) {
      _shown = true;
      _c.value = 1;
      return;
    }
    setState(() => _shown = true);
    Future<void>.delayed(Duration(milliseconds: 70 * widget.index.clamp(0, 6)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        // Charts inside keep their tickers muted until this has scrolled in.
        child: TickerMode(enabled: _shown, child: widget.child),
        builder: (context, child) => _t.value >= 1
            ? child!
            : Opacity(
                opacity: _t.value,
                child: Transform.translate(offset: Offset(0, 18 * (1 - _t.value)), child: child),
              ),
      );
}
