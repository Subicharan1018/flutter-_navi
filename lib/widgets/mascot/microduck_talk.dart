/// What Microduck knows about the song that is playing, gathered from data
/// the app already has. Everything is optional.
class MicroduckFacts {
  final String songId;
  final String title;
  final String composer;
  final String? film;
  final int year;
  final int playCount;
  final bool starred;
  final int? bpm;

  const MicroduckFacts({
    required this.songId,
    required this.title,
    this.composer = '',
    this.film,
    this.year = 0,
    this.playCount = 0,
    this.starred = false,
    this.bpm,
  });
}

/// "1st", "2nd", "3rd", "42nd", "11th".
String ordinal(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

/// Microduck speaks up on about one song in three, so it stays a treat.
bool microduckFeelsChatty(String songId, DateTime now) => _hash('$songId|${now.day}') % 3 == 0;

/// A short remark about the song, from templates and local facts only (no
/// model calls), or null when there is nothing worth saying. The same song on
/// the same day gets the same remark.
String? microduckComment(MicroduckFacts f, DateTime now) {
  final lines = <String>[
    if (f.playCount >= 5) 'Your ${ordinal(f.playCount + 1)} play of this one!',
    if (f.starred) 'You starred this one. Good taste.',
    if (f.composer.isNotEmpty) 'Music by ${f.composer}.',
    if (f.film != null && f.film!.isNotEmpty) 'From “${f.film}”.',
    if (f.year > 0) 'A ${f.year} one.',
    if (f.bpm != null) '${f.bpm} bpm. I can work with that.',
    if (now.hour < 5) 'Up late? Same.',
  ];
  if (lines.isEmpty) return null;
  // A play count is the most personal thing it knows: say that when it can.
  if (f.playCount >= 5) return lines.first;
  return lines[_hash('${f.songId}|${now.day}|line') % lines.length];
}

/// A plain-language answer to "what is this song?" from the same facts.
String describeSong({required String title, required String artist, required MicroduckFacts facts}) {
  final parts = <String>[
    '“$title” by $artist.',
    if (facts.film != null && facts.film!.isNotEmpty) 'From “${facts.film}”.',
    if (facts.composer.isNotEmpty) 'Composed by ${facts.composer}.',
    if (facts.year > 0) 'Released in ${facts.year}.',
    if (facts.playCount > 0) 'You have played it ${facts.playCount} ${facts.playCount == 1 ? 'time' : 'times'}.',
    if (facts.bpm != null) 'It runs at ${facts.bpm} bpm.',
  ];
  return parts.join(' ');
}

int _hash(String s) {
  var h = 17;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}
