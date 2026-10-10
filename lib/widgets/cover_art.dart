import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../player/artwork.dart' show testCoverOverride;

/// Square cover art, decoded at its display size, with a quiet themed
/// placeholder (never a coloured gradient) while loading or when the server
/// has no image. Use this instead of hand-rolling CachedNetworkImage +
/// placeholder + errorWidget in each screen.
class CoverArt extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  final IconData placeholderIcon;
  final bool circular;

  const CoverArt({
    super.key,
    required this.url,
    required this.size,
    this.radius = 4,
    this.placeholderIcon = Icons.music_note_rounded,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholder = ColoredBox(
      color: t.bgElevated,
      child: Center(
        child: Icon(placeholderIcon, size: size * 0.38, color: t.textMuted),
      ),
    );
    final override = url == null || url!.isEmpty ? null : testCoverOverride(url!);
    final image = url == null || url!.isEmpty
        ? placeholder
        : override != null
            ? Image(
                image: ResizeImage(override, width: px, height: px),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              )
            : CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            memCacheWidth: px,
            memCacheHeight: px,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(circular ? size / 2 : radius),
        child: image,
      ),
    );
  }
}
