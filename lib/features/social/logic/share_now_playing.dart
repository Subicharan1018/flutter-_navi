import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../utils/platform_utils.dart';
import '../../../models/song.dart';

/// The text card for "Share now playing": title, artist, album, a
/// `naviv://song/<id>` link when the song has an id, and a plain-text fallback
/// that reads fine where a link means nothing.
class NowPlayingCard {
  final String title;
  final String artist;
  final String album;
  final String? link;
  const NowPlayingCard({required this.title, this.artist = '', this.album = '', this.link});

  /// The song model fills missing tags with these; they mean "no value".
  static String _known(String v) => v == 'Unknown Artist' || v == 'Unknown Album' ? '' : v;

  factory NowPlayingCard.of(Song s) => NowPlayingCard(
        title: s.title,
        artist: _known(s.artist),
        album: _known(s.album),
        link: s.id.isEmpty ? null : 'naviv://song/${Uri.encodeComponent(s.id)}',
      );

  /// "Listening to Title by Artist", then the album, with no link.
  String get plainText {
    final by = artist.isEmpty ? '' : ' by $artist';
    return [
      'Listening to $title$by',
      if (album.isNotEmpty) 'From $album',
      'Shared from NaviVibe',
    ].join('\n');
  }

  /// [plainText] plus the deep link when there is one.
  String get text => link == null ? plainText : '$plainText\n$link';

  String get subject => artist.isEmpty ? title : '$title · $artist';
}

/// Android and other phones: the OS share sheet. Windows and Linux: the
/// clipboard. Returns the message to confirm with (null when the sheet itself
/// is the confirmation).
Future<String?> shareNowPlaying(Song song, {bool? desktop, Future<void> Function(String)? copy}) async {
  final card = NowPlayingCard.of(song);
  if (desktop ?? PlatformUtils.isDesktop) {
    await (copy ?? (t) => Clipboard.setData(ClipboardData(text: t)))(card.text);
    return 'Copied. Paste it into a message.';
  }
  await SharePlus.instance.share(ShareParams(text: card.text, subject: card.subject));
  return null;
}
