import 'package:flutter/material.dart' show Tooltip;
import '../../widgets/ui/horizontal_shelf.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../../utils/platform_utils.dart';
import '../art/navi_icons.dart';
import '../cover_art.dart';

/// Apple Music section title: Title 2, and when it leads somewhere, a chevron
/// right after the words (iOS 17+) rather than a separate "See All" link.
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.onTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final text = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(title, style: t.title2, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (onTap != null) ...[
          const SizedBox(width: Space.xs),
          NaviIcon(NaviGlyph.chevron, size: 20, color: t.textMuted),
        ],
      ],
    );
    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(pageGutter(context), Space.xxl, pageGutter(context), Space.md),
      child: Semantics(
        header: true,
        button: onTap != null,
        child: onTap == null
            ? text
            : CupertinoClickable(onTap: onTap, scaleFactor: 0.98, child: text),
      ),
    );
  }
}

/// Square artwork with a title and a secondary line underneath — the one card
/// shape used for albums, playlists, mixes and artists across the app.
class MediaCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? artUrl;
  final Widget? art;
  final double size;
  final bool circular;
  final NaviGlyph placeholderIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Desktop: a Play button over the cover while the pointer is on the card.
  final VoidCallback? onPlay;

  const MediaCard({
    super.key,
    required this.title,
    this.subtitle,
    this.artUrl,
    this.art,
    required this.size,
    this.circular = false,
    this.placeholderIcon = NaviGlyph.note,
    required this.onTap,
    this.onLongPress,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final size = ShelfSize.of(context) ?? this.size; // a desktop shelf sets the tile size
    Widget cover(bool hovered) {
      final image = art ??
          CoverArt(
            url: artUrl,
            size: size,
            radius: Radii.cover,
            circular: circular,
            placeholderIcon: placeholderIcon,
          );
      if (onPlay == null || !PlatformUtils.isDesktop) return image;
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [image, CardPlayButton(visible: hovered, onPlay: onPlay!, label: 'Play $title')],
        ),
      );
    }

    return CupertinoClickable(
      onTap: onTap,
      onLongPress: onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onLongPress!();
            },
      scaleFactor: 0.97,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      child: HoverBuilder(
        builder: (context, hovered) => SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: circular ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              cover(hovered),
              const SizedBox(height: Space.sm - 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: circular ? TextAlign.center : TextAlign.start,
                style: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w500),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: circular ? TextAlign.center : TextAlign.start,
                  style: t.footnote,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal row of [MediaCard]s under a [SectionHeader]. Renders nothing
/// when empty — an empty shelf is noise.
class MediaShelf extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final int itemCount;
  final double? cardSize;
  final Widget Function(BuildContext, int) itemBuilder;
  final bool hasSubtitle;

  const MediaShelf({
    super.key,
    required this.title,
    this.onSeeAll,
    required this.itemCount,
    required this.itemBuilder,
    this.cardSize,
    this.hasSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();
    // Desktop: equal tiles that fill the row exactly (about 170-190 wide), the rest
    // a page away behind the arrows, so no shelf ends short of the right edge.
    if (PlatformUtils.isDesktop) {
      return LayoutBuilder(
        builder: (context, c) {
          const gap = Space.md;
          final avail = c.maxWidth - pageGutter(context) * 2;
          final target = cardSize ?? ArtSize.of(context).tile;
          final fit = ((avail + gap) / (target + gap)).floor().clamp(2, 12);
          final fewest = ((avail + gap) / (220 + gap)).ceil().clamp(2, 12);
          // A shelf with just under a row's worth of items stretches them to fill it (up to ~220 wide).
          // A shelf with fewer still would end a third of the way short of the right edge,
          // so its last slot is a "See all" tile and the tiles grow (to 220) to take the row.
          final short = itemCount < fewest && onSeeAll != null;
          final n = short ? itemCount + 1 : (itemCount >= fit ? fit : (itemCount >= fewest ? itemCount : fit));
          final size = short ? ((avail - gap * (n - 1)) / n).clamp(target, 220.0) : (avail - gap * (n - 1)) / n;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: title, onTap: onSeeAll),
              HorizontalShelf(
                height: size + captionExtent(context, subtitle: hasSubtitle),
                itemCount: short ? itemCount + 1 : itemCount,
                itemBuilder: (context, i) => short && i == itemCount
                    ? _SeeAllTile(size: size, label: title, onTap: onSeeAll!)
                    : ShelfSize(size: size, child: itemBuilder(context, i)),
              ),
            ],
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, onTap: onSeeAll),
        HorizontalShelf(
          height: (cardSize ?? ArtSize.of(context).tile) + captionExtent(context, subtitle: hasSubtitle),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ],
    );
  }
}

/// The last slot of a short desktop shelf: a quiet tile that opens the full list.
class _SeeAllTile extends StatelessWidget {
  final double size;
  final String label;
  final VoidCallback onTap;
  const _SeeAllTile({required this.size, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    // Cover-sized, top-aligned with the covers beside it (the shelf row is taller
    // than a cover: it holds the captions too).
    return Align(
      alignment: Alignment.topLeft,
      child: NaviFocusable(
          radius: Radii.cover,
          // The tile paints its own fill, so no second hover tint; NaviFocusable
          // already speaks as a button with this label.
          hoverTint: false,
          semanticLabel: 'See all $label',
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.cover)),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('See all', style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
                    const SizedBox(width: Space.xs),
                    NaviIcon(NaviGlyph.chevron, size: 14, color: t.textPrimary),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

/// Two-column (three on wide screens) grid of [MediaCard]s, Apple's
/// "Recently Added" layout.
class MediaGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index, double cardSize) itemBuilder;

  const MediaGrid({super.key, required this.itemCount, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: pageGutter(context)),
      sliver: SliverLayoutBuilder(
        builder: (context, c) {
          final target = ArtSize.of(context).tile;
          final phoneColumns = gridColumns(c.crossAxisExtent, target);
          final (columns, card) = PlatformUtils.isDesktop
              ? desktopTiles(c.crossAxisExtent, target, Space.lg)
              : (phoneColumns, (c.crossAxisExtent - Space.lg * (phoneColumns - 1)) / phoneColumns);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: Space.lg,
              mainAxisSpacing: Space.xl,
              mainAxisExtent: card + 44,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => itemBuilder(context, i, card),
              childCount: itemCount,
            ),
          );
        },
      ),
    );
  }
}

/// A list row for a collection (playlist, album, library destination): art or
/// glyph, title, optional subtitle, chevron. Hairline separator inset past
/// the art, as in Apple Music's Library.
class CollectionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget leading;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showChevron;
  final bool showSeparator;
  final Color? titleColor;
  final TextStyle? titleStyle;

  /// A small marker after the title (e.g. a "Smart" badge).
  final Widget? badge;

  /// Replaces the chevron at the row's end.
  final Widget? trailing;

  const CollectionRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.leading,
    required this.onTap,
    this.onLongPress,
    this.showChevron = true,
    this.showSeparator = true,
    this.titleColor,
    this.titleStyle,
    this.badge,
    this.trailing,
  });

  /// Library destination row: accent glyph instead of artwork.
  factory CollectionRow.destination({
    Key? key,
    required BuildContext context,
    required NaviGlyph icon,
    required String title,
    required VoidCallback onTap,
    bool showSeparator = true,
  }) {
    final t = ThemeTokens.of(context);
    return CollectionRow(
      key: key,
      title: title,
      titleStyle: t.title3.copyWith(fontWeight: FontWeight.w400),
      leading: SizedBox(width: 30, child: NaviIcon(icon, size: 24, color: t.accent)),
      showSeparator: showSeparator,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      onLongPress: onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onLongPress!();
            },
      scaleFactor: 0.99,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      child: Padding(
        padding: EdgeInsets.only(left: pageGutter(context)),
        // Artwork sits inset in its row (never touching the next row's), and
        // the hairline stays on the row's bottom edge whichever side is taller.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Padding(padding: const EdgeInsets.symmetric(vertical: Space.sm), child: leading),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: EdgeInsets.only(right: pageGutter(context), top: Space.sm, bottom: Space.sm),
                  decoration: BoxDecoration(
                    border: showSeparator ? Border(bottom: BorderSide(color: t.outline, width: 0.5)) : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: (titleStyle ?? t.body).copyWith(color: titleColor ?? t.textPrimary),
                                  ),
                                ),
                                if (badge != null) ...[const SizedBox(width: Space.sm), badge!],
                              ],
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null)
                        trailing!
                      else if (showChevron)
                        NaviIcon(NaviGlyph.chevron, size: 16, color: t.textMuted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS 26.4 Apple Music transport under a collection header: a round
/// Shuffle on the left, the Play capsule in the middle, an optional round
/// action ([trailing], e.g. download) on the right. Centred, thumb-reachable.
class PlayShuffleButtons extends StatelessWidget {
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final bool playing;
  final Widget? trailing;

  /// Windows: one quiet line after the buttons saying what Play will play.
  final String? scope;

  const PlayShuffleButtons({
    super.key,
    required this.onPlay,
    required this.onShuffle,
    this.playing = false,
    this.trailing,
    this.scope,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final enabled = onPlay != null;
    if (PlatformUtils.isDesktop) {
      // Desktop: a round Play, then Shuffle and the rest as quiet icons, left-aligned
      // directly above the table.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoClickable(
            onTap: enabled ? onPlay : null,
            focusRadius: 28,
            semanticLabel: playing ? 'Pause' : 'Play',
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: enabled ? t.accentFill : t.fill, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: NaviIcon(
                playing ? NaviGlyph.pause : NaviGlyph.play,
                size: 22,
                filled: true,
                color: enabled ? t.onAccent : t.textMuted,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          CircleIconButton(icon: NaviGlyph.shuffle, label: 'Shuffle', onTap: onShuffle),
          if (trailing != null) ...[const SizedBox(width: Space.xs), trailing!],
          if (scope != null) ...[
            const SizedBox(width: Space.lg),
            Text(scope!, style: t.footnote.copyWith(color: t.textSecondary)),
          ],
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleIconButton(icon: NaviGlyph.shuffle, label: 'Shuffle', onTap: onShuffle),
        const SizedBox(width: Space.xl),
        CupertinoClickable(
          onTap: enabled
              ? () {
                  HapticFeedback.mediumImpact();
                  onPlay!();
                }
              : null,
          scaleFactor: 0.95,
          semanticLabel: playing ? 'Pause' : 'Play',
          child: AnimatedContainer(
            duration: Motion.fast,
            height: 50,
            constraints: const BoxConstraints(minWidth: 148),
            padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
            decoration: BoxDecoration(
              color: enabled ? t.accent : t.fill,
              borderRadius: BorderRadius.circular(Radii.capsule),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NaviIcon(
                  playing ? NaviGlyph.pause : NaviGlyph.play,
                  size: 18,
                  color: enabled ? t.onAccent : t.textMuted,
                ),
                const SizedBox(width: Space.sm),
                Text(
                  playing ? 'Pause' : 'Play',
                  style: t.headline.copyWith(color: enabled ? t.onAccent : t.textMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Space.xl),
        trailing ?? const SizedBox(width: CircleIconButton.size),
      ],
    );
  }
}

/// A round glyph button on a soft fill (Shuffle, Download, More).
class CircleIconButton extends StatelessWidget {
  static const double size = 44;

  final NaviGlyph icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? child;
  final Color? color;

  const CircleIconButton({super.key, required this.icon, required this.label, this.onTap, this.child, this.color});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        scaleFactor: 0.9,
        semanticLabel: label,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: t.fill, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: child ?? NaviIcon(icon, size: 19, color: onTap == null ? t.textMuted : (color ?? t.textPrimary)),
        ),
    );
  }
}

/// iOS tinted capsule: soft fill, accent glyph and label. Used for single
/// secondary actions ("Try Again", "Add Songs").
class TintedButton extends StatelessWidget {
  final NaviGlyph? glyph;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  /// The primary action of a pair: solid accent with dark text.
  final bool filled;
  final double height;

  const TintedButton({
    super.key,
    this.glyph,
    required this.label,
    this.onTap,
    this.destructive = false,
    this.filled = false,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final fg = onTap == null
        ? t.textMuted
        : (filled ? t.onAccent : (destructive ? t.danger : t.accent));
    final bg = filled && onTap != null ? t.accentFill : t.fill;
    return CupertinoClickable(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      scaleFactor: 0.96,
      semanticLabel: label,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.capsule)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (glyph != null) ...[
              NaviIcon(glyph!, size: 18, color: fg),
              const SizedBox(width: Space.sm),
            ],
            // Shrinks with an ellipsis when it shares a row (paired capsules).
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.headline.copyWith(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Room under a card's artwork for its title (and subtitle) line, growing with
/// the person's text size so a larger font never overflows a fixed-height shelf.
double captionExtent(BuildContext context, {bool subtitle = true}) {
  final k = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);
  return (subtitle ? 44.0 : 26.0) * k;
}

/// Reports whether the pointer is over its child, for hover-only controls.
class HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  const HoverBuilder({super.key, required this.builder});

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: widget.builder(context, _hover),
      );
}

/// The round Play button that fades in over a cover when the pointer is on its card.
class CardPlayButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onPlay;
  final String label;
  const CardPlayButton({super.key, required this.visible, required this.onPlay, required this.label});

  @override
  Widget build(BuildContext context) => Positioned(
        right: Space.sm,
        bottom: Space.sm,
        child: HoverPlayDisc(visible: visible, onPlay: onPlay, label: label, size: 44, glyph: 20),
      );
}

/// A round Play button that shows while the pointer is on its card or while it
/// has keyboard focus (so it can be reached without a mouse). Labelled, with a
/// tooltip and the white focus ring.
class HoverPlayDisc extends StatefulWidget {
  final bool visible;
  final VoidCallback onPlay;
  final String label;
  final double size;
  final double glyph;
  const HoverPlayDisc({super.key, required this.visible, required this.onPlay, required this.label, this.size = 44, this.glyph = 20});

  @override
  State<HoverPlayDisc> createState() => _HoverPlayDiscState();
}

class _HoverPlayDiscState extends State<HoverPlayDisc> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final shown = widget.visible || _focused;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: shown ? 1 : 0,
      child: IgnorePointer(
        ignoring: !shown,
        child: Semantics(
          button: true,
          label: widget.label,
          child: Tooltip(
            message: widget.label,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: NaviFocusRing(
                onTap: widget.onPlay,
                radius: widget.size / 2,
                onFocusChange: (f) => setState(() => _focused = f),
                child: GestureDetector(
                  onTap: widget.onPlay,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(color: t.accentFill, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: NaviIcon(NaviGlyph.play, size: widget.glyph, filled: true, color: t.onAccent),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
