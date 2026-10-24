import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';

enum ShareKind {
  song('Song', CupertinoIcons.music_note),
  album('Album', CupertinoIcons.music_albums),
  playlist('Playlist', CupertinoIcons.music_note_list);

  final String label;
  final IconData icon;
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
    const art = width - 64;
    return Container(
      width: width,
      height: height,
      color: _ground,
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.cover + 4),
            child: SizedBox(
              width: art,
              height: art,
              child: cover == null
                  ? ColoredBox(color: _tile, child: Icon(kind.icon, size: 72, color: _secondary))
                  : Image(image: cover!, fit: BoxFit.cover),
            ),
          ),
          const Spacer(),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.title2.copyWith(color: _label)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.callout.copyWith(color: _secondary)),
          ],
          const SizedBox(height: Space.md),
          Row(
            children: [
              Icon(kind.icon, size: 13, color: _secondary),
              const SizedBox(width: 6),
              Text('${kind.label} on NaviVibe', style: t.caption1.copyWith(color: _secondary)),
            ],
          ),
        ],
      ),
    );
  }
}
