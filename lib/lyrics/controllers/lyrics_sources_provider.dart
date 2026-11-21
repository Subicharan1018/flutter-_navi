import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hive_boxes.dart';

/// Where online lyrics can come from, in the order they are tried. Each one is
/// fetched by the shuffle server (the web app's CSP only allows that host, and
/// no third party ever sees the signed-in user); the app only picks which
/// sources to ask for.
enum LyricsSource {
  /// Line and word timing. Credit and link required wherever it shows.
  lrcRed('lrcred', 'lrc.red', 'https://lrc.red', defaultOn: true),

  /// Word timing; community-run, no keys issued, so a song may simply be missing.
  betterLyrics('betterlyrics', 'BetterLyrics', 'https://betterlyrics.org', defaultOn: true),

  /// Line-timed lyrics (or plain text) from YouTube Music, read by the server.
  /// Unofficial, so it is the last of the on-by-default sources.
  ytMusic('ytmusic', 'YouTube Music', 'https://music.youtube.com', defaultOn: true),

  /// Unofficial wrapper around undocumented Spotify endpoints: may break
  /// Spotify's terms of service, so it stays off until switched on here.
  paxsenix('paxsenix', 'Spotify (unofficial)', null, defaultOn: false);

  /// The name the server's `sources` query uses.
  final String wire;

  /// What the source chip and Settings show.
  final String label;
  final String? homepage;
  final bool defaultOn;
  const LyricsSource(this.wire, this.label, this.homepage, {required this.defaultOn});

  String get prefKey => 'lyrics_source_$wire';

  static LyricsSource? fromWire(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// Which sources are switched on. Plain device preferences: no credentials,
/// cookies or tokens are ever stored for any of them.
class LyricsSourcesNotifier extends Notifier<Set<LyricsSource>> {
  @override
  Set<LyricsSource> build() {
    final enabled = <LyricsSource>{};
    for (final s in LyricsSource.values) {
      bool? stored;
      try {
        final v = HiveBoxes.prefs.get(s.prefKey);
        if (v is bool) stored = v;
      } catch (_) {}
      if (stored ?? s.defaultOn) enabled.add(s);
    }
    return enabled;
  }

  Future<void> set(LyricsSource source, bool on) async {
    state = on ? {...state, source} : ({...state}..remove(source));
    try {
      await HiveBoxes.prefs.put(source.prefKey, on);
    } catch (_) {}
  }

  /// The enabled sources in the order they're tried.
  List<LyricsSource> get ordered => [
    for (final s in LyricsSource.values)
      if (state.contains(s)) s,
  ];
}

final lyricsSourcesProvider = NotifierProvider<LyricsSourcesNotifier, Set<LyricsSource>>(LyricsSourcesNotifier.new);
