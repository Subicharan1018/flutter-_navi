import '../../../models/song.dart';

/// What a chat message is asking for. Routing is plain keyword rules, not a
/// model: anything it does not recognise is a "describe a mix" request and goes
/// to `/intent`.
enum ChatIntent {
  nowPlaying,
  composer,
  recognize,
  translate,
  neverArtist,
  neverSong,
  weekly,
  discover,
  flow,
  moreLikeThis,
  mix,
}

ChatIntent routeChat(String text) {
  final t = text.toLowerCase().trim();
  bool has(Iterable<String> words) => words.any(t.contains);

  if (has(const ['never recommend', 'never play', 'stop recommending', 'don’t recommend', "don't recommend", 'never suggest'])) {
    return has(const ['artist', 'singer', 'composer', 'musician']) ? ChatIntent.neverArtist : ChatIntent.neverSong;
  }
  if (has(const ['recogni', 'shazam', 'identify', 'name that', 'listen to the room'])) return ChatIntent.recognize;
  if (has(const ['translate', 'translation', 'meaning of', 'what does this mean'])) return ChatIntent.translate;
  if (has(const ['composer', 'music director', 'who made', 'who wrote', 'who composed', 'who sang', 'who is the singer'])) {
    return ChatIntent.composer;
  }
  if (has(const ['what is this song', "what's this song", 'what is playing', "what's playing", 'what song is this', 'what is this'])) {
    return ChatIntent.nowPlaying;
  }
  if (has(const ['weekly'])) return ChatIntent.weekly;
  if (has(const ['discover', 'something new', 'new music', 'new songs', 'new in my library'])) return ChatIntent.discover;
  if (has(const ['surprise', 'flow', 'endless', 'keep them coming'])) return ChatIntent.flow;
  if (has(const ['more like this', 'similar', 'like this one', 'like this song'])) return ChatIntent.moreLikeThis;
  return ChatIntent.mix;
}

/// The sentence sent to `/intent` for [text]: "more like this" becomes the
/// current song, anything else goes as typed.
String mixQuery(String text, Song? current) {
  if (routeChat(text) == ChatIntent.moreLikeThis) {
    return current == null ? 'something I like' : 'songs like ${current.title} by ${current.artist}';
  }
  return text;
}

/// A suggestion under the chat box: [label] is shown, [text] is what is sent.
class ChatChip {
  final String label;
  final String text;
  const ChatChip(this.label, [String? text]) : text = text ?? label;
}

/// Suggestions that fit the moment: the song that is playing, the time of day,
/// the artist you have been hearing, and the standing favourites. At most six.
List<ChatChip> suggestChips({Song? current, required DateTime now, bool signedIn = true}) {
  final hour = now.hour;
  final mood = hour < 5 || hour >= 22
      ? const ChatChip('Something calm for the night', 'calm songs for the night')
      : hour < 11
          ? const ChatChip('Gentle morning songs', 'gentle songs for the morning')
          : hour < 17
              ? const ChatChip('Focus music', 'songs to focus to')
              : const ChatChip('Evening unwind', 'relaxing songs for the evening');
  final artist = current == null ? '' : _firstName(current.artist);
  return [
    if (current != null) ...[
      const ChatChip('More like this'),
      const ChatChip('What is this song?'),
      if (current.composer.isNotEmpty) const ChatChip('Who is the composer?'),
      if (artist.isNotEmpty) ChatChip('More from $artist', 'songs by $artist'),
    ],
    mood,
    if (signedIn) ...[
      const ChatChip('Surprise me'),
      const ChatChip('My weekly mix'),
      const ChatChip('Something new'),
    ],
  ].take(6).toList();
}

String _firstName(String raw) {
  for (final part in raw.split(RegExp(r'[;,•&/]'))) {
    if (part.trim().isNotEmpty) return part.trim();
  }
  return '';
}
