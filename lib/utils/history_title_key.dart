// Title comparison for listening history ("Monica (From "Coolie") (Tamil)")
// against library songs ("Monica").
//
// Only film and language tags are dropped. Anything else in a title, such as
// Unplugged, Remix, Live, Reprise or Slowed, stays in the key, so a distinct
// version never merges with the plain song.

const _languages =
    'tamil|telugu|hindi|malayalam|kannada|punjabi|bengali|marathi|english';

final _bracketTag = RegExp(
  '\\s*[\\(\\[]\\s*(?:(?:from|film|movie|featuring|feat|ft)\\b[^\\)\\]]*|(?:$_languages)(?:\\s+version)?)\\s*[\\)\\]]',
  caseSensitive: false,
);
// "Song - From "X"" or "Song - Tamil" at the end of a title.
final _dashTag = RegExp(
  '\\s+[-–—]\\s*(?:(?:from|film|movie)\\b.*|(?:$_languages))\\s*\$',
  caseSensitive: false,
);
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
// Compiled once: this runs for every library song when a resolver is built.
final _doubleQuotes = RegExp('[“”„‟«»]');
final _singleQuotes = RegExp('[‘’‚‛]');

/// Lower-case letters and digits of [title] with film/language tags removed.
String historyTitleKey(String title) {
  var t = title.replaceAll(_doubleQuotes, '"').replaceAll(_singleQuotes, "'");
  // Tags can stack: "(From "X") (Tamil)". Repeat until nothing changes.
  for (var prev = ''; prev != t;) {
    prev = t;
    t = t.replaceAll(_bracketTag, '').replaceAll(_dashTag, '');
  }
  return t.toLowerCase().replaceAll(_nonWord, '');
}
