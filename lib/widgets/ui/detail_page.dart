import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Frame for album, playlist and other collection pages: a compact iOS bar
/// with a back chevron and trailing actions whose title fades in once the
/// hero's own title has scrolled away. Only the bar rebuilds while scrolling.
class DetailPage extends StatefulWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> slivers;

  /// Scroll offset after which the bar shows [title] and a hairline.
  final double revealAt;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  const DetailPage({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.revealAt = 260,
    this.onRefresh,
    this.controller,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _revealed = ValueNotifier(false);

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      _revealed.value = n.metrics.pixels > widget.revealAt;
    }
    return false;
  }

  @override
  void dispose() {
    _revealed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: t.bgBase,
        body: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            controller: widget.controller,
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _BarDelegate(
                  height: top + _BarDelegate.barHeight,
                  topPadding: top,
                  title: widget.title,
                  actions: widget.actions,
                  revealed: _revealed,
                ),
              ),
              if (widget.onRefresh != null) CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
              // Wide windows inset the whole page so lists line up under
              // the hero instead of running to the window edge.
              for (final s in widget.slivers)
                MediaQuery.sizeOf(context).width >= 720
                    ? SliverPadding(padding: const EdgeInsets.symmetric(horizontal: Space.lg), sliver: s)
                    : s,
              SliverToBoxAdapter(
                child: SizedBox(height: Space.playerClearance + MediaQuery.paddingOf(context).bottom),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarDelegate extends SliverPersistentHeaderDelegate {
  static const double barHeight = 44;

  final double height;
  final double topPadding;
  final String title;
  final List<Widget> actions;
  final ValueNotifier<bool> revealed;

  _BarDelegate({
    required this.height,
    required this.topPadding,
    required this.title,
    required this.actions,
    required this.revealed,
  });

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = ThemeTokens.of(context);
    final canPop = Navigator.of(context).canPop();
    return ValueListenableBuilder<bool>(
      valueListenable: revealed,
      builder: (context, shown, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: EdgeInsets.only(top: topPadding),
        decoration: BoxDecoration(
          color: t.bgBase,
          border: Border(bottom: BorderSide(color: shown ? t.outline : t.bgBase, width: 0.5)),
        ),
        child: NavigationToolbar(
          leading: canPop
              ? CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Icon(CupertinoIcons.chevron_back, color: t.accent, semanticLabel: 'Back'),
                )
              : null,
          middle: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: Motion.fast,
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.headline),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
          middleSpacing: Space.sm,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_BarDelegate old) =>
      old.height != height || old.title != title || old.actions != actions || old.revealed != revealed;
}

/// A glyph button for the [DetailPage] bar.
class BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? child;

  const BarButton({super.key, required this.icon, required this.label, this.onTap, this.child});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Tooltip(
      message: label,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        minimumSize: const Size(40, 44),
        onPressed: onTap,
        child: child ?? Icon(icon, size: 22, color: onTap == null ? t.textMuted : t.accent, semanticLabel: label),
      ),
    );
  }
}
