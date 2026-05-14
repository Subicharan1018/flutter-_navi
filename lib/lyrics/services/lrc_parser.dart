// Source: lyrics.dart (project root — downloaded GitHub code)
// This is a thin adapter over SyncedLyrics.fromLrc / fromPlainText so that
// the rest of the app interacts with a single named service class instead of
// the factory constructors directly.

import '../models/lyric_line.dart';

class LrcParser {
  const LrcParser._();

  /// Returns true if [text] looks like LRC format — i.e. it contains at
  /// least one `[mm:ss.xx]` or `[mm:ss:xx]` timestamp tag.
  static bool isLrcFormat(String text) {
    return RegExp(r'\[\d{1,2}:\d{2}[.:]\d{2,3}\]').hasMatch(text);
  }

  /// Parses an LRC-formatted string into [SyncedLyrics].
  /// Delegates to [SyncedLyrics.fromLrc] from the integrated GitHub code.
  static SyncedLyrics parseLrc(String lrc) =>
      SyncedLyrics.fromLrc(lrc);

  /// Wraps plain text (one line per newline) into a [SyncedLyrics] with
  /// all timestamps set to [Duration.zero].
  /// Delegates to [SyncedLyrics.fromPlainText] from the integrated GitHub code.
  static SyncedLyrics parsePlain(String text) =>
      SyncedLyrics.fromPlainText(text);
}
