import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyric_translation.dart';
import 'lyrics_translation_controller.dart' show lyricsServerApiProvider;

/// Shortest text worth searching lyrics for: one word is mostly noise.
const lyricsSearchMinLength = 3;

/// Songs whose lyrics contain [query]. Quiet by design: a short query, an
/// unreachable server or an old server without the route all give an empty
/// list, so the Search screen simply has no "Matches in Lyrics" section.
final lyricsSearchProvider = FutureProvider.autoDispose
    .family<List<LyricMatch>, String>((ref, query) async {
      final q = query.trim();
      if (q.length < lyricsSearchMinLength) return const [];
      try {
        return await ref.watch(lyricsServerApiProvider).searchLyrics(q);
      } catch (_) {
        return const [];
      }
    });
