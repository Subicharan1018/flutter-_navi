import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../player/artwork.dart' show testCoverOverride;
import 'art/navi_icons.dart';

/// The cover sizes a list or tile asks the server for. A few fixed steps, not
/// the exact pixel count, so the same cover is fetched (and cached) once per
/// step instead of once per layout, and a slow connection downloads a 128 px
/// image for a 46 px row instead of the full-size original.
const kCoverSteps = [96, 160, 256, 384, 512, 768, 1024];

/// [url] (a Subsonic `getCoverArt` link) asking for [px] pixels, rounded up to
/// the next of [kCoverSteps]. Links that already carry a size, and anything
/// that is not a cover-art link, come back unchanged.
String sizedCoverUrl(String url, int px) {
  if (!url.contains('getCoverArt')) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.queryParameters.containsKey('size')) return url;
  final step = kCoverSteps.firstWhere((s) => s >= px, orElse: () => kCoverSteps.last);
  return uri.replace(queryParameters: {...uri.queryParameters, 'size': '$step'}).toString();
}

/// Square cover art, decoded at its display size, with a quiet themed
/// placeholder (never a coloured gradient) while loading or when the server
/// has no image. Use this instead of hand-rolling CachedNetworkImage +
/// placeholder + errorWidget in each screen.
class CoverArt extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  final NaviGlyph placeholderIcon;
  final bool circular;

  /// Shown instead of the placeholder when [url] fails (e.g. an artist with
  /// no portrait falls back to one of their album covers).
  final String? fallbackUrl;

  const CoverArt({
    super.key,
    required this.url,
    required this.size,
    this.radius = 4,
    this.placeholderIcon = NaviGlyph.note,
    this.circular = false,
    this.fallbackUrl,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    // The note is for "this has no cover". While a cover loads, a plain panel:
    // the note never sits under (or fades out over) art that is arriving.
    final loading = ColoredBox(color: t.bgElevated);
    final placeholder = ColoredBox(
      color: t.bgElevated,
      child: Center(
        child: NaviIcon(placeholderIcon, size: size * 0.38, color: t.textMuted),
      ),
    );
    final failed = fallbackUrl == null
        ? placeholder
        : CoverArt(url: fallbackUrl, size: size, radius: 0, placeholderIcon: placeholderIcon);
    final override = url == null || url!.isEmpty ? null : testCoverOverride(url!);
    final isFile = url != null && url!.startsWith('file:');
    final image = url == null || url!.isEmpty
        ? failed
        : isFile
            ? Image.file(
                File.fromUri(Uri.parse(url!)),
                fit: BoxFit.cover,
                // Width only: giving both sizes decodes to exactly px × px and
                // squashes any cover that is not square.
                cacheWidth: px,
                errorBuilder: (_, _, _) => failed,
              )
            : override != null
            ? Image(
                image: ResizeImage(override, width: px, height: px, policy: ResizeImagePolicy.fit),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => failed,
              )
            : CachedNetworkImage(
                imageUrl: sizedCoverUrl(url!, px),
                fit: BoxFit.cover,
                // Width only (see above): both would stretch a non-square cover.
                memCacheWidth: px,
                fadeInDuration: const Duration(milliseconds: 180),
                fadeOutDuration: Duration.zero,
                placeholderFadeInDuration: Duration.zero,
                placeholder: (_, _) => loading,
                errorWidget: (_, _, _) => failed,
              );
    // Always size × size: Align lets a tight, non-square parent (a stretched
    // row, a tile of another shape) have its box while the art keeps its square.
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(circular ? size / 2 : radius),
          child: image,
        ),
      ),
    );
  }
}
