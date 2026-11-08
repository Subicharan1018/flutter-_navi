import 'package:flutter/widgets.dart';

/// A [SliverLayoutBuilder] that only asks for a new layout when the width
/// changes (or this widget is rebuilt by its parent).
///
/// `SliverLayoutBuilder` calls its builder whenever the sliver's constraints
/// change, and a scroll changes them (`scrollOffset`, `remainingPaintExtent`) on
/// every frame. A grid or table built inside one is therefore rebuilt in full,
/// every visible card or row, on every frame of a scroll. This hands the same
/// widget back instead, which Flutter skips.
///
/// Read anything that can change (theme, `MediaQuery`, art size) in the parent's
/// `build` and capture it in [builder]'s closure, not through the `context` the
/// builder receives: the parent rebuilding is what refreshes the layout.
class SliverWidthBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, double width) builder;
  const SliverWidthBuilder({super.key, required this.builder});

  @override
  State<SliverWidthBuilder> createState() => _SliverWidthBuilderState();
}

class _SliverWidthBuilderState extends State<SliverWidthBuilder> {
  Widget? _tree;
  double _width = -1;

  @override
  Widget build(BuildContext context) {
    _tree = null; // this widget was rebuilt: its layout is stale
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final cached = _tree;
        if (cached != null && _width == constraints.crossAxisExtent) return cached;
        _width = constraints.crossAxisExtent;
        return _tree = widget.builder(context, _width);
      },
    );
  }
}
