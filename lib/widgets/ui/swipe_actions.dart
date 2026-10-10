import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// iOS-style swipe actions on a row: swipe right for the [leading] action,
/// left for the [trailing] one. The row never leaves the list — the action
/// runs and the row springs back. Solid colour backgrounds, as iOS draws them.
class SwipeActions extends StatelessWidget {
  final Key rowKey;
  final Widget child;
  final SwipeAction? leading;
  final SwipeAction? trailing;

  const SwipeActions({super.key, required this.rowKey, required this.child, this.leading, this.trailing});

  /// The standard pair for songs: Play Next (right) / Play Last (left).
  factory SwipeActions.queue({
    Key? key,
    required Key rowKey,
    required Widget child,
    required BuildContext context,
    required VoidCallback onPlayNext,
    required VoidCallback onPlayLast,
  }) {
    final t = ThemeTokens.of(context);
    return SwipeActions(
      key: key,
      rowKey: rowKey,
      leading: SwipeAction(label: 'Play Next', icon: CupertinoIcons.text_insert, color: t.accent, onTrigger: onPlayNext),
      trailing: SwipeAction(label: 'Play Last', icon: CupertinoIcons.text_append, color: t.warning, onTrigger: onPlayLast),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (leading == null && trailing == null) return child;
    return Dismissible(
      key: rowKey,
      direction: leading != null && trailing != null
          ? DismissDirection.horizontal
          : (leading != null ? DismissDirection.startToEnd : DismissDirection.endToStart),
      dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.3},
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        (direction == DismissDirection.startToEnd ? leading : trailing)?.onTrigger();
        return false;
      },
      background: leading == null ? const SizedBox.shrink() : _Background(action: leading!, alignStart: true),
      secondaryBackground: trailing == null ? null : _Background(action: trailing!, alignStart: false),
      child: child,
    );
  }
}

class SwipeAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTrigger;
  const SwipeAction({required this.label, required this.icon, required this.color, required this.onTrigger});
}

class _Background extends StatelessWidget {
  final SwipeAction action;
  final bool alignStart;
  const _Background({required this.action, required this.alignStart});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final fg = action.color.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    return Container(
      color: action.color,
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(action.icon, color: fg, size: 22),
          const SizedBox(height: Space.xs),
          Text(action.label, style: t.caption1.copyWith(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
