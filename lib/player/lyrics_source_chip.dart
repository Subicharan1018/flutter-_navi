import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../lyrics/controllers/lyrics_sources_provider.dart';
import 'now_playing_style.dart';

/// The name a lyrics source is credited by, or null when there's nothing to
/// credit (no source recorded).
String? lyricsSourceLabel(String? source) {
  switch (source) {
    case null:
    case '':
      return null;
    case 'server':
      return 'Your server';
    case 'device':
      return 'This device';
    case 'lrclib':
      return 'LRCLIB';
  }
  return LyricsSource.fromWire(source)?.label;
}

/// "lrc.red · WORD": where the lyrics on screen came from and how they are
/// timed. It is also the credit lrc.red's terms require wherever its data shows.
class LyricsSourceChip extends StatelessWidget {
  final NowPlayingStyle style;
  final String label;

  /// `WORD`, `SYNC` or `TEXT`.
  final String kind;
  const LyricsSourceChip({super.key, required this.style, required this.label, required this.kind});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Lyrics from $label, ${kind == 'WORD' ? 'timed word by word' : kind == 'SYNC' ? 'timed by line' : 'not timed'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: style.pillIdle, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: naviText(13, FontWeight.w700, style.textPrimary)),
            const SizedBox(width: 8),
            Text(kind, style: naviText(11, FontWeight.w700, style.textMuted)),
          ],
        ),
      ),
    );
  }
}
