import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../art/navi_icons.dart';
import '../cover_art.dart';

/// Apple Music section title: Title 2, and when it leads somewhere, a chevron
/// right after the words (iOS 17+) rather than a separate "See All" link.
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, Space.md),
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
          Icon(CupertinoIcons.chevron_forward, size: 20, color: t.textMuted),
        ],
      ],
    );
    return Padding(
      padding: padding,
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
  final IconData placeholderIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const MediaCard({
    super.key,
    required this.title,
    this.subtitle,
    this.artUrl,
    this.art,
    required this.size,
    this.circular = false,
    this.placeholderIcon = CupertinoIcons.music_note,
    required this.onTap,
    this.onLongPress,
  });

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
      scaleFactor: 0.97,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: circular ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            art ??
                CoverArt(
                  url: artUrl,
                  size: size,
                  radius: Radii.cover,
                  circular: circular,
                  placeholderIcon: placeholderIcon,
                ),
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
    );
  }
}

/// Horizontal row of [MediaCard]s under a [SectionHeader]. Renders nothing
/// when empty — an empty shelf is noise.
class MediaShelf extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final int itemCount;
  final double cardSize;
  final Widget Function(BuildContext, int) itemBuilder;
  final bool hasSubtitle;

  const MediaShelf({
    super.key,
    required this.title,
    this.onSeeAll,
    required this.itemCount,
    required this.itemBuilder,
    this.cardSize = 150,
    this.hasSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, onTap: onSeeAll),
        SizedBox(
          height: cardSize + (hasSubtitle ? 44 : 26),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      sliver: SliverLayoutBuilder(
        builder: (context, c) {
          final columns = c.crossAxisExtent >= 900 ? 5 : c.crossAxisExtent >= 600 ? 3 : 2;
          final card = (c.crossAxisExtent - Space.lg * (columns - 1)) / columns;
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
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool showSeparator = true,
  }) {
    final t = ThemeTokens.of(context);
    return CollectionRow(
      key: key,
      title: title,
      titleStyle: t.title3.copyWith(fontWeight: FontWeight.w400),
      leading: SizedBox(width: 30, child: Icon(icon, size: 24, color: t.accent)),
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
        padding: const EdgeInsets.only(left: Space.gutter),
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
                  padding: const EdgeInsets.only(right: Space.gutter, top: Space.sm, bottom: Space.sm),
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
                        Icon(CupertinoIcons.chevron_forward, size: 16, color: t.textMuted),
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

  const PlayShuffleButtons({
    super.key,
    required this.onPlay,
    required this.onShuffle,
    this.playing = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final enabled = onPlay != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleIconButton(icon: CupertinoIcons.shuffle, label: 'Shuffle', onTap: onShuffle),
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
                Icon(
                  playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
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

  final IconData icon;
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
          child: child ?? Icon(icon, size: 19, color: onTap == null ? t.textMuted : (color ?? t.textPrimary)),
        ),
    );
  }
}

/// iOS tinted capsule: soft fill, accent glyph and label. Used for single
/// secondary actions ("Try Again", "Add Songs").
class TintedButton extends StatelessWidget {
  final IconData? icon;

  /// One of NaviVibe's own glyphs, shown instead of [icon].
  final NaviGlyph? glyph;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  /// The primary action of a pair: solid accent with dark text.
  final bool filled;
  final double height;

  const TintedButton({
    super.key,
    this.icon,
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
    final bg = filled && onTap != null ? t.accent : t.fill;
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
            ] else if (icon != null) ...[
              Icon(icon, size: 17, color: fg),
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
