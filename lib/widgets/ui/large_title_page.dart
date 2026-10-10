import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'dock_ground.dart';

/// The frame of every top-level page: Apple's large title that collapses into
/// a compact bar as you scroll, iOS pull-to-refresh, and bottom clearance so
/// the last row isn't hidden under the mini player and tab bar.
class LargeTitlePage extends StatelessWidget {
  final String title;
  final List<Widget> slivers;
  final Widget? leading;
  final Widget? trailing;

  /// Pinned under the title, e.g. the Search field. Fixed [headerHeight].
  final Widget? header;
  final double headerHeight;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  /// Set false for pages pushed above the tab bar that have no mini player.
  final bool clearPlayer;

  const LargeTitlePage({
    super.key,
    required this.title,
    required this.slivers,
    this.leading,
    this.trailing,
    this.header,
    this.headerHeight = 52,
    this.onRefresh,
    this.controller,
    this.clearPlayer = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final canPop = Navigator.of(context).canPop();
    return DockGroundScope(
      color: null,
      child: Scaffold(
      backgroundColor: t.bgBase,
      body: CustomScrollView(
        controller: controller,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(title),
            leading: leading,
            automaticallyImplyLeading: canPop,
            previousPageTitle: canPop ? 'Back' : null,
            trailing: trailing,
            // Opaque: no blur behind the collapsed bar.
            backgroundColor: t.bgBase,
            // No hairline while the large title shows; iOS adds one only
            // once content scrolls under the bar.
            border: null,
            // Tabs keep their own navigators; cross-route hero flights between
            // their bars would collide, so bars don't animate between routes.
            transitionBetweenRoutes: false,
          ),
          if (header != null)
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedHeader(height: headerHeight, color: t.bgBase, child: header!),
            ),
          if (onRefresh != null) CupertinoSliverRefreshControl(onRefresh: onRefresh),
          ...slivers,
          SliverToBoxAdapter(
            child: SizedBox(
              height: clearPlayer
                  ? Space.playerClearance + MediaQuery.paddingOf(context).bottom
                  : Space.xxxl,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  final double height;
  final Color color;
  final Widget child;
  _PinnedHeader({required this.height, required this.color, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(
        color: color,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xs),
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      );

  @override
  bool shouldRebuild(_PinnedHeader old) => old.height != height || old.color != color || old.child != child;
}

/// Page padding for content inside a [LargeTitlePage].
class PageSliver extends StatelessWidget {
  final Widget sliver;
  final double top;
  const PageSliver({super.key, required this.sliver, this.top = 0});

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0),
        sliver: sliver,
      );
}
