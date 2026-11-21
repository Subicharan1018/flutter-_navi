import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/art/navi_icons.dart';
import '../../widgets/ui/grouped_list.dart';
import '../controllers/lyrics_sources_provider.dart';

/// Settings ▸ Lyrics: which online sources the app may ask for lyrics, in the
/// order they're tried. The server fetches them and keeps a copy per song for
/// this account; nothing here stores a login, cookie or key.
class LyricsSourcesSection extends ConsumerWidget {
  const LyricsSourcesSection({super.key});

  static const _notes = {
    LyricsSource.lrcRed: 'Timed line by line, and word by word on many songs.',
    LyricsSource.betterLyrics: 'Word by word. Community-run: some songs are missing.',
    LyricsSource.ytMusic:
        'Timed by line where YouTube Music has it, plain text otherwise. Unofficial: it can stop working '
        'without notice, and may not follow YouTube’s terms of service. Only lyrics text is read.',
    LyricsSource.paxsenix:
        'Unofficial. Uses undocumented Spotify endpoints and may break Spotify’s terms of service, '
        'so it is off unless you switch it on. Only works if the server has been set up for it.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(lyricsSourcesProvider);
    final ctl = ref.read(lyricsSourcesProvider.notifier);
    return GroupedSection(
      header: 'Lyrics sources',
      footer: 'Lyrics saved in your music files always come first, then these, then LRCLIB. '
          'Your server fetches them and keeps a copy for you; the app stores no logins for any source.',
      children: [
        for (final s in LyricsSource.values)
          GroupedSwitchRow(
            title: s.label,
            subtitle: _notes[s],
            icon: NaviGlyph.lyrics,
            value: on.contains(s),
            onChanged: (v) => ctl.set(s, v),
          ),
      ],
    );
  }
}
