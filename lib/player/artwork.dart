import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/album_palette.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';

/// A cover reduced to what the player surfaces need: a 64px texture for the
/// artwork field shader and the derived [AlbumPalette].
class ArtworkData {
  final String key;
  final ui.Image image;
  final AlbumPalette palette;

  const ArtworkData({required this.key, required this.image, required this.palette});
}

/// Cache key shared with every `CachedNetworkImage` showing this cover, so the
/// thumbnail decode reuses the bytes the list/mini player already downloaded.
String coverCacheKey(Song song) =>
    'cover_${song.coverArt.isNotEmpty ? song.coverArt : song.id}';

/// Test seam: when set, every player surface resolves covers through this
/// instead of the network cache (golden tests point it at local files).
@visibleForTesting
ImageProvider Function(String url, String cacheKey)? debugCoverImageOverride;

/// The one way player surfaces load a cover: disk-cached network image,
/// decoded at [cacheWidth] px wide so a 3000px cover never sits in RAM at
/// full size.
ImageProvider coverImage(String url, String cacheKey, {int? cacheWidth}) {
  final base = debugCoverImageOverride?.call(url, cacheKey) ??
      CachedNetworkImageProvider(url, cacheKey: cacheKey);
  return cacheWidth == null ? base : ResizeImage(base, width: cacheWidth, policy: ResizeImagePolicy.fit);
}

/// A cover with a quiet placeholder, a short fade on first decode, and no
/// flicker when the song changes (gapless).
class CoverImage extends StatelessWidget {
  final String url;
  final String cacheKey;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final Color placeholderColor;

  const CoverImage({
    super.key,
    required this.url,
    required this.cacheKey,
    this.width,
    this.height,
    this.cacheWidth,
    this.placeholderColor = const Color(0x22FFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final cw = cacheWidth ?? (width != null ? (width! * dpr).round() : null);
    return Image(
      image: coverImage(url, cacheKey, cacheWidth: cw),
      width: width,
      height: height,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 180),
          child: Container(color: placeholderColor, width: width, height: height, child: child),
        );
      },
      errorBuilder: (context, _, _) => Container(
        width: width,
        height: height,
        color: placeholderColor,
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          color: const Color(0x99FFFFFF),
          size: ((width ?? 48) * 0.36).clamp(14.0, 96.0),
        ),
      ),
    );
  }
}

/// Decodes covers once at 64×64, extracts their palette off the UI isolate,
/// and keeps the most recent results (LRU). Everything that colours itself by
/// the album goes through here, so a cover is never decoded twice.
class ArtworkRepository {
  ArtworkRepository._();
  static final ArtworkRepository instance = ArtworkRepository._();

  static const int _capacity = 40;
  static const int _texSize = 64;

  final LinkedHashMap<String, ArtworkData> _cache = LinkedHashMap();
  final Map<String, Future<ArtworkData?>> _inFlight = {};

  ArtworkData? peek(String key) {
    final hit = _cache.remove(key);
    if (hit != null) _cache[key] = hit; // promote
    return hit;
  }

  Future<ArtworkData?> load(String key, String url) {
    final hit = peek(key);
    if (hit != null) return SynchronousFuture(hit);
    return _inFlight[key] ??= _load(key, url).whenComplete(() => _inFlight.remove(key));
  }

  Future<ArtworkData?> _load(String key, String url) async {
    try {
      final provider = ResizeImage(
        debugCoverImageOverride?.call(url, key) ?? CachedNetworkImageProvider(url, cacheKey: key),
        width: _texSize,
        height: _texSize,
        policy: ResizeImagePolicy.exact,
      );
      final image = await _resolve(provider);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      final ints = await compute(extractAlbumPalette, bytes.buffer.asUint8List());
      final data = ArtworkData(key: key, image: image, palette: albumPaletteFromInts(ints));
      _cache[key] = data;
      while (_cache.length > _capacity) {
        final evicted = _cache.remove(_cache.keys.first);
        evicted?.image.dispose();
      }
      return data;
    } catch (e) {
      debugPrint('[Artwork] $key failed: $e');
      return null;
    }
  }

  Future<ui.Image> _resolve(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        // Clone: the stream may dispose its handle once we stop listening.
        if (!completer.isCompleted) completer.complete(info.image.clone());
        info.dispose();
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 20));
  }
}

/// The artwork of the song that is playing now. Holds on to the previous
/// song's artwork until the next one is decoded, so surfaces never flash to
/// the fallback between tracks.
class NowPlayingArtworkNotifier extends Notifier<ArtworkData?> {
  String? _requestedKey;

  @override
  ArtworkData? build() {
    ref.listen<Song?>(
      playerProvider.select((s) => s.currentSong),
      (_, song) => _sync(song),
      fireImmediately: true,
    );
    return null;
  }

  void _sync(Song? song) {
    if (song == null) return;
    final key = coverCacheKey(song);
    if (key == _requestedKey) return;
    _requestedKey = key;
    final cached = ArtworkRepository.instance.peek(key);
    if (cached != null) {
      // build() may still be running on the first sync — defer the write.
      scheduleMicrotask(() {
        if (_requestedKey == key) state = cached;
      });
      return;
    }
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    ArtworkRepository.instance.load(key, url).then((data) {
      if (data != null && _requestedKey == key) state = data;
    });
  }
}

final nowPlayingArtworkProvider =
    NotifierProvider<NowPlayingArtworkNotifier, ArtworkData?>(NowPlayingArtworkNotifier.new);

/// The palette the whole app is tinted with right now.
final albumPaletteProvider = Provider<AlbumPalette>(
  (ref) => ref.watch(nowPlayingArtworkProvider.select((a) => a?.palette)) ?? AlbumPalette.fallback,
);

/// Palette for any cover (album pages, playlist headers), keyed by the
/// Subsonic coverArt id. Loads lazily, shares the repository cache.
final coverPaletteProvider = FutureProvider.family<AlbumPalette, String>((ref, coverArt) async {
  final url = ref.read(subsonicServiceProvider).getCoverArtUrl(coverArt);
  final data = await ArtworkRepository.instance.load('cover_$coverArt', url);
  return data?.palette ?? AlbumPalette.fallback;
});
