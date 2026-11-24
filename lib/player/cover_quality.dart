import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/local_library/logic/local_index.dart' show pendingLocalCoverId;
import '../models/song.dart';
import '../services/subsonic_service.dart';
import 'artwork.dart';

/// The largest cover Now Playing asks the server for. Full-bleed art is a
/// phone's width wide at up to ~3.4x (a 1240 px panel), so 1440 px is sharp
/// without fetching the 3000 px original some albums carry. At 1080 a wide
/// phone upscaled the picture by 15% and it read as soft.
const int kNowPlayingCoverPx = 1440;

/// The small cover shown at once while the sharp one downloads, so the picture
/// is never blank and the sharp one fades in over it instead of replacing a
/// grey box. It is a size the lists already fetch, so it is usually cached.
const int kNowPlayingPreviewPx = 512;

/// A source narrower than this stays in the square-cover layout: stretched
/// across a phone it would be a soft blur.
const int kFullBleedMinSourcePx = 500;

/// The cover Now Playing shows: where it comes from and its cache key.
@immutable
class NowPlayingCoverRequest {
  final String url;
  final String cacheKey;

  /// Decode width in px (display width x devicePixelRatio, never above what
  /// the server is asked for).
  final int width;

  /// A small copy of the same cover shown underneath until [url] has decoded
  /// (null when the cover is already on the device or has no small size).
  final String? previewUrl;

  const NowPlayingCoverRequest(this.url, this.cacheKey, this.width, {this.previewUrl});

  @override
  bool operator ==(Object other) =>
      other is NowPlayingCoverRequest &&
      other.url == url &&
      other.cacheKey == cacheKey &&
      other.width == width &&
      other.previewUrl == previewUrl;

  @override
  int get hashCode => Object.hash(url, cacheKey, width, previewUrl);

  /// True when nothing can be shown yet (no cover id, or a device cover the
  /// index has not loaded).
  bool get missing => url.isEmpty || pendingLocalCoverId(url) != null;
}

/// A copy saved on the device (a download, a local song) wins, so Now Playing
/// works offline; otherwise the server resizes to [kNowPlayingCoverPx]. The
/// server copy has its own cache key: the list thumbnails share
/// [coverCacheKey], and reusing it would serve a small cached picture here.
NowPlayingCoverRequest nowPlayingCoverRequest(SubsonicService service, Song song, double logicalWidth, double dpr) {
  final width = (logicalWidth * dpr).round().clamp(1, kNowPlayingCoverPx);
  final saved = service.getCoverArtUrl(song.coverArt);
  if (saved.startsWith('file:') || saved.isEmpty || pendingLocalCoverId(saved) != null) {
    return NowPlayingCoverRequest(saved, coverCacheKey(song), width);
  }
  return NowPlayingCoverRequest(
    service.getCoverArtUrl(song.coverArt, size: kNowPlayingCoverPx),
    '${coverCacheKey(song)}_$kNowPlayingCoverPx',
    width,
    previewUrl: service.getCoverArtUrl(song.coverArt, size: kNowPlayingPreviewPx),
  );
}

/// The decoded pixel width of a cover (0 when it cannot be loaded). Resolves
/// the same [coverImage] the screen shows, so the decode is shared through the
/// image cache and nothing is fetched twice.
final coverSourcePxProvider = FutureProvider.autoDispose.family<int, NowPlayingCoverRequest>((ref, r) async {
  if (r.missing) return 0;
  final done = Completer<int>();
  final stream = coverImage(r.url, r.cacheKey, cacheWidth: r.width).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) done.complete(info.image.width);
      info.dispose();
    },
    onError: (_, _) {
      if (!done.isCompleted) done.complete(0);
    },
  );
  stream.addListener(listener);
  // A cover that never arrives counts as unusable; the timer dies with the
  // provider, so closing Now Playing never leaves it pending.
  final giveUp = Timer(const Duration(seconds: 20), () {
    if (!done.isCompleted) done.complete(0);
  });
  ref.onDispose(() {
    giveUp.cancel();
    stream.removeListener(listener);
  });
  return done.future;
});

/// Whether this cover is good enough to fill the screen. Optimistic while it
/// loads (most covers are), so the layout does not jump to the square cover
/// and back on every track.
bool coverFitsFullBleed(AsyncValue<int> source, NowPlayingCoverRequest r) {
  if (r.missing) return false;
  return switch (source) {
    AsyncData(:final value) => value >= kFullBleedMinSourcePx,
    AsyncError() => false,
    _ => true,
  };
}
