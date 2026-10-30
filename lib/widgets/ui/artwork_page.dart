import '../../core/layout/window_size.dart';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../player/artwork.dart' show coverPaletteProvider;
import '../art/navi_icons.dart';
import '../shell/dock_glass.dart';
import 'dock_ground.dart';

/// Apple Music's iOS 26.4 collection page: the artwork runs edge to edge at
/// the top and dissolves into a ground colour sampled from it; title, artist
/// and the transport sit over that seam; the track list continues on the
/// same colour. Everything inside is themed with [AppThemeTokens.tinted], so
/// shared rows and buttons turn white-on-colour without knowing about it.
///
/// Pull down and the artwork stretches; scroll up and it drifts at half
/// speed under the content. A compact bar fades in once the artwork is gone.
/// On wide windows the artwork sits beside the title instead.
class ArtworkPage extends ConsumerStatefulWidget {
  /// Subsonic cover id the colour is sampled from (null → neutral ground).
  final String? paletteCoverId;

  /// The artwork itself, drawn at whatever square size the layout asks for.
  final Widget Function(double size) art;

  final String title;
  final String? subtitle;
  final VoidCallback? onSubtitleTap;
  final String? detail;
  final String? description;

  /// Transport row (usually [PlayShuffleButtons]).
  final Widget? buttons;

  /// Round buttons for the top-right corner (More, Add Songs…).
  final List<Widget> actions;
  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;

  /// Artists get a left-aligned display title, as in Apple Music.
  final bool artistStyle;

  const ArtworkPage({
    super.key,
    required this.paletteCoverId,
    required this.art,
    required this.title,
    this.subtitle,
    this.onSubtitleTap,
    this.detail,
    this.description,
    this.buttons,
    this.actions = const [],
    required this.slivers,
    this.onRefresh,
    this.artistStyle = false,
  });

  static const double _wideBreakpoint = 720;

  @override
  ConsumerState<ArtworkPage> createState() => _ArtworkPageState();
}

class _ArtworkPageState extends ConsumerState<ArtworkPage> {
  final _offset = ValueNotifier<double>(0);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) _offset.value = n.metrics.pixels;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.paletteCoverId == null || widget.paletteCoverId!.isEmpty
        ? AlbumPalette.fallback
        : ref.watch(coverPaletteProvider(widget.paletteCoverId!)).asData?.value ?? AlbumPalette.fallback;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= ArtworkPage._wideBreakpoint;

    // The ground eases to the sampled colour when it arrives instead of
    // snapping, so the page appears to "develop" like a photo.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: palette.ground),
      duration: Motion.slow,
      curve: Motion.ease,
      builder: (context, ground, _) {
        final tokens = AppThemeTokens.tinted(palette, ground ?? palette.ground);
        return ThemeTokens(
          tokens: tokens,
          // The dock band takes this page's colour, so the page runs
          // unbroken to the bottom edge under the mini player and tabs.
          child: DockGroundScope(
            color: tokens.bgBase,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Scaffold(
              backgroundColor: tokens.bgBase,
              body: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: Stack(
                  children: [
                    CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: wide
                              ? _WideHeader(page: widget)
                              : _PhoneHeader(page: widget, width: size.width, offset: _offset),
                        ),
                        if (widget.onRefresh != null && wide) CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
                        for (final s in widget.slivers)
                          wide
                              ? SliverPadding(
                                  padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
                                  sliver: s,
                                )
                              : s,
                        SliverToBoxAdapter(
                          child: SizedBox(height: dockClearance(context)),
                        ),
                      ],
                    ),
                    _TopBar(
                      title: widget.title,
                      actions: widget.actions,
                      offset: _offset,
                      revealAt: wide ? 220 : size.width - 80,
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Headers
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneHeader extends StatelessWidget {
  final ArtworkPage page;
  final double width;
  final ValueNotifier<double> offset;
  const _PhoneHeader({required this.page, required this.width, required this.offset});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final ground = t.bgBase;
    final align = page.artistStyle ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = page.artistStyle ? TextAlign.start : TextAlign.center;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRect(
          // Clip only below: the drifting artwork must not show under the
          // track list, but the overscroll stretch extends above the box.
          clipper: _BelowClipper(width),
          child: SizedBox(
          width: width,
          height: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Stretch on overscroll, half-speed drift on scroll.
              ValueListenableBuilder<double>(
                valueListenable: offset,
                child: page.art(width),
                builder: (context, o, art) {
                  // Overscroll moves this box down by `pull`; pin the art to
                  // the screen top and grow it so it fills the gap.
                  final pull = math.max(0.0, -o);
                  return Positioned(
                    left: 0,
                    right: 0,
                    top: o < 0 ? o : o * 0.5,
                    height: width,
                    child: Transform.scale(
                      scale: (width + pull) / width,
                      alignment: Alignment.topCenter,
                      child: art,
                    ),
                  );
                },
              ),
              // The seam: artwork dissolves into the ground colour, reaching
              // solid ground before the title block so text never sits on
              // bright artwork, whatever the cover.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.38, 0.66, 0.84, 1],
                      colors: [
                        ground.withValues(alpha: 0),
                        ground.withValues(alpha: 0),
                        ground.withValues(alpha: 0.85),
                        ground,
                        ground,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: Space.xl,
                right: Space.xl,
                bottom: Space.lg,
                child: Column(
                  crossAxisAlignment: align,
                  children: [
                    Text(
                      page.title,
                      textAlign: textAlign,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: page.artistStyle ? t.largeTitle.copyWith(fontSize: 36) : t.title1,
                    ),
                    if (page.subtitle != null && page.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: Space.xxs),
                      CupertinoClickable(
                        onTap: page.onSubtitleTap,
                        scaleFactor: 0.97,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                page.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.title3.copyWith(fontWeight: FontWeight.w500, color: t.accent),
                              ),
                            ),
                            if (page.onSubtitleTap != null)
                              NaviIcon(NaviGlyph.chevron, size: 15, color: t.textSecondary),
                          ],
                        ),
                      ),
                    ],
                    if (page.detail != null && page.detail!.isNotEmpty) ...[
                      const SizedBox(height: Space.xs),
                      Text(page.detail!, textAlign: textAlign, style: t.footnote),
                    ],
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
        if (page.buttons != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, 0),
            child: Center(child: page.buttons),
          ),
        if (page.description != null && page.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, 0),
            child: Text(page.description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.subheadline),
          ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

class _BelowClipper extends CustomClipper<Rect> {
  final double bottom;
  const _BelowClipper(this.bottom);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-1e4, -1e4, 1e4, bottom);

  @override
  bool shouldReclip(_BelowClipper old) => old.bottom != bottom;
}

class _WideHeader extends StatelessWidget {
  final ArtworkPage page;
  const _WideHeader({required this.page});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    const art = 260.0;
    return Container(
      // A soft wash of the artwork colour behind the header on wide windows.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(Colors.white.withValues(alpha: 0.06), t.bgBase), t.bgBase],
        ),
      ),
      padding: EdgeInsets.fromLTRB(Space.xxxl, MediaQuery.paddingOf(context).top + 72, Space.xxxl, Space.xxl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: page.artistStyle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: page.artistStyle ? null : BorderRadius.circular(Radii.hero),
              boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 36, offset: Offset(0, 14))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(page.artistStyle ? art / 2 : Radii.hero),
              child: page.art(art),
            ),
          ),
          const SizedBox(width: Space.xxxl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(page.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.largeTitle),
                if (page.subtitle != null && page.subtitle!.isNotEmpty)
                  CupertinoClickable(
                    onTap: page.onSubtitleTap,
                    scaleFactor: 0.98,
                    child: Text(page.subtitle!, style: t.title3.copyWith(fontWeight: FontWeight.w500)),
                  ),
                if (page.detail != null && page.detail!.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Text(page.detail!, style: t.footnote),
                ],
                if (page.description != null && page.description!.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(page.description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.subheadline),
                  ),
                ],
                if (page.buttons != null) ...[
                  const SizedBox(height: Space.xl),
                  Align(alignment: Alignment.centerLeft, child: page.buttons),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

/// Back + actions float over the artwork as round buttons; past [revealAt]
/// the bar fills with the ground colour and shows the title.
class _TopBar extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final ValueNotifier<double> offset;
  final double revealAt;
  const _TopBar({required this.title, required this.actions, required this.offset, required this.revealAt});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    // Windows and tablets show the breadcrumb bar's back arrow; one is enough.
    final canPop = Navigator.of(context).canPop() && ShellKind.ofContext(context) == ShellKind.phone;
    return ValueListenableBuilder<double>(
      valueListenable: offset,
      builder: (context, o, _) {
        final reveal = ((o - revealAt) / 40).clamp(0.0, 1.0);
        return Container(
          height: top + 52,
          padding: EdgeInsets.only(top: top, left: Space.sm, right: Space.sm),
          decoration: BoxDecoration(
            color: t.bgBase.withValues(alpha: reveal),
            border: Border(bottom: BorderSide(color: t.outline.withValues(alpha: t.outline.a * reveal), width: 0.5)),
          ),
          child: Row(
            children: [
              if (canPop)
                BarCircleButton(
                  icon: NaviGlyph.chevronLeft,
                  label: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              Expanded(
                child: Opacity(
                  opacity: reveal,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.headline,
                  ),
                ),
              ),
              ...actions,
              if (actions.isEmpty && canPop) const SizedBox(width: BarCircleButton.size),
            ],
          ),
        );
      },
    );
  }
}

/// The round buttons that float over artwork in the top bar: a solid disc
/// one step lighter than the page ground, white glyph.
class BarCircleButton extends StatelessWidget {
  static const double size = 36;

  final NaviGlyph icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? child;

  const BarCircleButton({super.key, required this.icon, required this.label, this.onTap, this.child});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    // 36pt disc inside a 44pt touch target.
    return CupertinoClickable(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      scaleFactor: 0.9,
      semanticLabel: label,
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: t.bgElevated,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            alignment: Alignment.center,
            child: child ?? NaviIcon(icon, size: 18, color: onTap == null ? t.textMuted : t.textPrimary),
          ),
        ),
      ),
    );
  }
}
