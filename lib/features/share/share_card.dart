import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';
import '../../widgets/art/navi_icons.dart';

enum ShareKind {
  song('Song', NaviGlyph.note),
  album('Album', NaviGlyph.library),
  playlist('Playlist', NaviGlyph.playlist);

  final String label;
  final NaviGlyph icon;
  const ShareKind(this.label, this.icon);
}

/// The picture sent with a share: cover art, title and artist on black.
/// Always the dark monochrome look, whatever theme the app is in, so it reads
/// the same on the friend's screen. Rendered to a PNG by the share sheet.
class ShareCard extends StatelessWidget {
  static const double width = 360;
  static const double height = 450;

  final ShareKind kind;
  final String title;
  final String subtitle;
  final ImageProvider? cover;

  const ShareCard({super.key, required this.kind, required this.title, required this.subtitle, this.cover});

  static const _ground = Color(0xFF000000);
  static const _label = Color(0xFFFFFFFF);
  static const _secondary = Color(0xFF9E9EA4);
  static const _tile = Color(0xFF1C1C1E);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    // A picture, not UI: the phone's text size must not change it.
    return MediaQuery.withNoTextScaling(
      child: Container(
        width: width,
        height: height,
        color: _ground,
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // The text keeps its room; a long title shrinks the square cover.
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.cover + 4),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: cover == null
                      ? ColoredBox(color: _tile, child: NaviIcon(kind.icon, size: 72, color: _secondary))
                      : Image(image: cover!, fit: BoxFit.cover),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.title2.copyWith(color: _label)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.callout.copyWith(color: _secondary)),
                  ],
                  const SizedBox(height: Space.md),
                  Row(
                    children: [
                      NaviIcon(kind.icon, size: 13, color: _secondary),
                      const SizedBox(width: 6),
                      Text('${kind.label} on NaviVibe', style: t.caption1.copyWith(color: _secondary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
