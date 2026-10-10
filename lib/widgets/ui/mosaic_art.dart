import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';
import '../cover_art.dart';

/// Artwork for app-made collections (mixes, Favorites): a 2×2 mosaic of the
/// covers inside it, the way Apple Music draws playlists without their own
/// art. Falls back to one cover, then to a glyph on a neutral square.
class MosaicArt extends StatelessWidget {
  final List<String?> urls;
  final double size;
  final double radius;
  final IconData placeholderIcon;

  const MosaicArt({
    super.key,
    required this.urls,
    required this.size,
    this.radius = Radii.cover,
    this.placeholderIcon = CupertinoIcons.music_note_list,
  });

  @override
  Widget build(BuildContext context) {
    final distinct = <String>{
      for (final u in urls)
        if (u != null && u.isNotEmpty) u,
    }.toList();

    if (distinct.length < 4) {
      return CoverArt(
        url: distinct.firstOrNull,
        size: size,
        radius: radius,
        placeholderIcon: placeholderIcon,
      );
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Wrap(
          children: [
            for (final u in distinct.take(4)) CoverArt(url: u, size: half, radius: 0),
          ],
        ),
      ),
    );
  }
}
