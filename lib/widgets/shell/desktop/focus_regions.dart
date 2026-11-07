import 'package:flutter/widgets.dart';

// =============================================================================
// focus_regions.dart — F6 / Shift+F6: jump between the parts of the window.
//
// The rail, the page, the Now Playing panel and the player bar each wrap
// themselves in a [FocusRegion]. F6 moves focus to the first control of the next
// region that is on screen (Shift+F6 the previous one), the way Windows apps
// let a keyboard user skip a whole pane instead of tabbing through it.
// =============================================================================

class FocusRegion extends StatefulWidget {
  /// Where it sits in the F6 cycle (low first).
  final int order;
  final String name;
  final Widget child;
  const FocusRegion({super.key, required this.order, required this.name, required this.child});

  /// The names of the regions currently on screen, in F6 order (for tests and
  /// the shortcuts overlay).
  static List<String> get names => (_live.toList()..sort((a, b) => a.widget.order.compareTo(b.widget.order))).map((s) => s.widget.name).toList();

  static final List<_FocusRegionState> _live = [];

  /// Moves focus to the next (or [reverse] previous) region; false if there is none.
  static bool cycle({bool reverse = false}) {
    final regions = _live.where((s) => s.mounted).toList()..sort((a, b) => a.widget.order.compareTo(b.widget.order));
    if (regions.isEmpty) return false;
    final current = regions.indexWhere((s) => s._node.hasFocus);
    final n = regions.length;
    for (var step = 1; step <= n; step++) {
      final i = current < 0 ? (reverse ? n - step : step - 1) : (current + (reverse ? -step : step)) % n;
      if (regions[(i + n) % n]._focusFirst()) return true;
    }
    return false;
  }

  @override
  State<FocusRegion> createState() => _FocusRegionState();
}

class _FocusRegionState extends State<FocusRegion> {
  final _node = FocusNode(debugLabel: 'region', canRequestFocus: false, skipTraversal: true);

  @override
  void initState() {
    super.initState();
    FocusRegion._live.add(this);
  }

  @override
  void dispose() {
    FocusRegion._live.remove(this);
    _node.dispose();
    super.dispose();
  }

  bool _focusFirst() {
    for (final n in _node.traversalDescendants) {
      if (n.canRequestFocus && !n.skipTraversal && n.context != null) {
        n.requestFocus();
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _node, child: widget.child);
}
