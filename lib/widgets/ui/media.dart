import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
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
  });

  /// Library destination row: green glyph instead of artwork.
  factory CollectionRow.destination({
    Key? key,
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final t = ThemeTokens.of(context);
    return CollectionRow(
      key: key,
      title: title,
      leading: SizedBox(width: 28, child: Icon(icon, size: 24, color: t.accent)),
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
        child: Row(
          children: [
            leading,
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
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.body.copyWith(color: titleColor ?? t.textPrimary),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
                          ],
                        ],
                      ),
                    ),
                    if (showChevron) Icon(CupertinoIcons.chevron_forward, size: 16, color: t.textMuted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Apple Music's pair of tinted buttons under album and playlist headers.
class PlayShuffleButtons extends StatelessWidget {
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final bool playing;

  const PlayShuffleButtons({super.key, required this.onPlay, required this.onShuffle, this.playing = false});

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: TintedButton(icon: icon, label: label, onTap: onTap),
        );
    return Row(
      children: [
        button(
          playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
          playing ? 'Pause' : 'Play',
          onPlay,
        ),
        const SizedBox(width: Space.md + 2),
        button(CupertinoIcons.shuffle, 'Shuffle', onShuffle),
      ],
    );
  }
}

/// iOS tinted button: grey fill, accent glyph and label.
class TintedButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  const TintedButton({super.key, this.icon, required this.label, this.onTap, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final fg = onTap == null ? t.textMuted : (destructive ? t.danger : t.accent);
    return CupertinoClickable(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      scaleFactor: 0.97,
      semanticLabel: label,
      child: Container(
        height: 50,
        decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.control)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: Space.sm),
            ],
            Text(label, style: t.headline.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
