// ignore_for_file: experimental_member_use
import 'package:just_audio/just_audio.dart';

import 'play_cache.dart';

/// A song whose first bytes are already in the play cache: playback starts
/// from them at once while the rest downloads (one request, shared with the
/// cache, which ends up with the whole file like any other song).
///
/// Used for the song a skip lands on, in place of a [LockCachingAudioSource]
/// that would first have to wait for the server's first bytes.
class HeadStartSource extends StreamAudioSource {
  HeadStartSource({
    required this.cache,
    required this.songId,
    required this.quality,
    required this.url,
    required this.total,
    required this.mime,
    super.tag,
  });

  final PlayCache cache;
  final String songId;
  final String quality;
  final Uri url;
  final int total;
  final String mime;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = (start ?? 0).clamp(0, total);
    final e = (end ?? total).clamp(s, total);
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: e - s,
      offset: s,
      contentType: mime,
      stream: cache.readThrough(songId, quality, url, start: s, end: e, total: total),
    );
  }
}
